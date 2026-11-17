---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

local USE_ITEM, CAST_SPELL = L["Use %s"], L["Cast %s"]

-- The tracker and screen prompt name the same item or spell in the client's language. `formatPlace`, when the
-- tracker asks for it, wraps the capital a party mage opens inside the same locale sentence.
---@param teleport SPFTeleportPlace
---@param formatPlace? fun(place: string): string
---@return string action, number? icon
function ns.TeleportAction(teleport, formatPlace)
	if teleport.partyMage then
		local icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(teleport.spell)
		local place = teleport.destination or UNKNOWN
		if formatPlace then
			place = formatPlace(place)
		end
		return L["Ask %s for a portal to %s"]:format(teleport.partyMage, place), icon
	end
	local name = teleport.item and C_Item.GetItemNameByID(teleport.item)
		or C_Spell.GetSpellName(teleport.spell)
		or UNKNOWN
	local icon = teleport.item and C_Item.GetItemIconByID(teleport.item) or (C_Spell.GetSpellTexture(teleport.spell))
	return (teleport.item and USE_ITEM or CAST_SPELL):format(name), icon
end

-- How a journey step reads. The tracker and the public API's EstimateDetail share these words, so a step names
-- the same place in SPF's list and in another addon's travel line.
local SCHEDULED = { boat = true, zeppelin = true, lift = true, tram = true }
local STEP = {
	walk = L["Walk to %s"],
	flight = L["Fly to %s"],
	boat = L["Boat to %s"],
	zeppelin = L["Zeppelin to %s"],
	lift = L["Lift to %s"],
	tram = L["Tram to %s"],
	portal = L["Portal to %s"],
	passage = L["Go through to %s"],
	teleport = L["Teleport to %s"],
}
-- Why a walk has no path, keyed by Path's failure reason; the journey and the corpse run word it the same way.
ns.WalkFailure = {
	unreachable = L["no walking path"],
	offmesh = L["no walking path"],
	outside = L["no walking path"],
	nodata = L["walking map unavailable"],
	error = L["walking search failed"],
}

-- A flight point by the name its flight map last gave it, or the shipped English one until a flight map has.
---@param id number
---@return string
function ns.TaxiName(id)
	local names = ns.charDB.taxiNames
	return names and names[id] or ns.TaxiNodes[id].name
end

-- A place with no kind is the destination point as clicked or picked from a quest.
---@param node SPFPoint|SPFPlace
---@param mode? SPFMode
---@return string
function ns.PlaceLabel(node, mode)
	if node.kind == "start" then
		return L["your position"]
	elseif node.kind == "dock" then
		return (mode == "boat" or mode == "zeppelin") and ns.DockLabel(node.id) or ns.DockTitle(node.id)
	elseif node.kind == "taxi" then
		return ns.TaxiName(node.id)
	elseif node.kind == "portal" then
		return node.label
	elseif node.kind == "teleport" or node.kind == "goal" or node.kind == nil then
		local location = not node.label and ns.Locate(node)
		return node.label or location and location.zone or UNKNOWN
	end
	error("unknown journey node kind " .. tostring(node.kind))
end

-- The place a leg ends.
---@param leg SPFLeg
---@return string
function ns.LegLabel(leg)
	return ns.PlaceLabel(leg.to, leg.mode)
end

-- What to do on a leg: "Boat to Menethil Harbor", or the mage and the capital for a party portal. `formatPlace`
-- wraps the place name in the caller's colour, inside the same locale sentence; the plain call leaves it as it is.
---@param leg SPFLeg
---@param formatPlace? fun(place: string): string
---@return string
function ns.LegStep(leg, formatPlace)
	local party = leg.partyPortal
	local place = party and (party.destination or ns.LegLabel(leg)) or ns.LegLabel(leg)
	if formatPlace then
		place = formatPlace(place)
	end
	if party then
		return string.format(L["Ask %s for a portal to %s"], party.partyMage, place)
	end
	return string.format(STEP[leg.mode], place)
end

-- Whole seconds as a countdown shows them, so totals add up to the times on screen.
local function Seconds(ms)
	return math.max(0, math.ceil(ms / 1000))
end

-- A leg's remaining milliseconds: the observed progress along a flight being flown, else the planned span.
-- Counting an air leg down from the path rather than the clock keeps its time steady on a slow or fast ride.
---@param leg SPFLeg
---@return number
function ns.LegSpan(leg)
	local observed = ns.TaxiTimes and ns.TaxiTimes.Remaining(leg)
	return observed or (leg.arrive - leg.depart)
end

-- Only a timed transport's departure and a teleport's cooldown make a step wait; a flight leaves at once. A
-- transport nobody has timed yet waits half its round trip on average; "about" marks that guess.
---@param leg SPFLeg
---@return string
function ns.LegTime(leg)
	local text = ns.FormatCountdown(ns.LegSpan(leg))
	if leg.wait and leg.wait > 0 then
		local lead = leg.mode == "teleport" and L["ready in %s"]
			or leg.estimated and SCHEDULED[leg.mode] and L["leaves in about %s"]
			or L["leaves in %s"]
		text = string.format(L["%s · %s"], string.format(lead, ns.FormatCountdown(leg.wait)), text)
	end
	return text
end

-- The steps from index on, waits included, in the milliseconds of the whole seconds each step shows. The header
-- adds up the steps rather than counting down to the planned arrival, which would run on while you stand still
-- until the next retime put it back.
---@param legs SPFLeg[]
---@param index integer
---@return integer
function ns.JourneyTime(legs, index)
	local seconds = 0
	for legIndex = index, #legs do
		local leg = legs[legIndex]
		seconds = seconds + Seconds(ns.LegSpan(leg)) + Seconds(leg.wait or 0)
	end
	return seconds * 1000
end

-- Whether a leg has reached its far end. A lift's landings share a spot on the map and the player's height is unknown
-- (UnitPosition's is a placeholder 0), so standing at the shaft cannot tell the top from the bottom. Such a leg is
-- over when you step away from the shaft after being there for at least the ride; stepping away sooner means you
-- did not ride, and the step points you back to the landing.
---@param leg SPFLeg
---@param progress {index: integer, departed?: boolean}
---@param near fun(node: SPFPoint|SPFPlace, reach?: number): boolean?
---@param reach? number the player's arrival distance for a last leg that ends the journey
---@return boolean
local function Landed(leg, progress, near, reach)
	local from, to = leg.from, leg.to
	local stacked = leg.route
		and from.map == to.map
		and from.z
		and to.z
		and from.z ~= to.z
		and (from.x - to.x) ^ 2 + (from.y - to.y) ^ 2 < 1
	if not stacked then
		return near(to, reach) == true
	end
	local now = ns.NowMs()
	if near(to, reach) then
		leg.reachedAt = leg.reachedAt or now
		return false
	end
	if leg.reachedAt and now - leg.reachedAt >= leg.arrive - leg.depart then
		return true
	end
	leg.reachedAt, progress.departed = nil, false
	return false
end

-- Advance legs that can be completed from the player's current position. Keeping this
-- state machine beside the step vocabulary keeps the journey driver focused on refreshes.
---@param near fun(node: SPFPoint|SPFPlace, reach?: number): boolean?
---@param reach? number the player's arrival distance at the final goal, which the last leg's far end shares
function ns.AdvanceJourneyProgress(legs, progress, goal, riding, flying, near, guide, reach)
	while progress.index <= #legs do
		local leg = legs[progress.index]
		local nextLeg = legs[progress.index + 1]
		if
			leg.mode == "walk"
			and nextLeg
			and ((nextLeg.route and riding == nextLeg.route) or (nextLeg.mode == "flight" and flying))
		then
			progress.index = progress.index + 1
			leg = nextLeg
		end
		local finalReach = progress.index == #legs and reach or nil
		local aboard = leg.aboard
			or leg.mode == "teleport"
			or (leg.route and riding == leg.route)
			or (leg.mode == "flight" and flying)
		if leg.mode ~= "walk" and not progress.departed then
			-- Arriving at a boat dock is only the boarding point.  The client
			-- reports no boarding event, so retain the unboarded state until the
			-- transport is actually ridden and remain recoverable if the player
			-- walks away.
			if leg.mode == "boat" and not aboard then
				guide.To(leg.from, nil, goal, leg)
				return true
			elseif aboard or near(leg.from) then
				progress.departed = true
			else
				guide.To(leg.from, nil, goal, leg)
				return true
			end
		end
		if leg.mode == "teleport" and not near(leg.to, finalReach) then
			guide.Cast(leg)
			return true
		end
		if not Landed(leg, progress, near, finalReach) or (leg.mode == "flight" and flying) then
			guide.To(leg.to, leg.walkPoints, goal, leg)
			return true
		end
		if goal.hold and leg.mode == "walk" and not nextLeg then
			guide.To(leg.to, leg.walkPoints, goal, leg)
			return true
		end
		progress.index, progress.departed = progress.index + 1, false
	end
	return goal.hold
end

---@param plan SPFPlan
---@param current integer
---@return SPFRow?
function ns.NewFlightPathReminderRow(plan, current)
	for index = current, #plan.legs do
		local leg = plan.legs[index]
		if leg.mode == "walk" and leg.to.undiscovered then
			return {
				key = "new-flight-path",
				text = string.format(L["Step %d: discover flight master %s before flying."], index, ns.LegLabel(leg)),
				grey = true,
			}
		end
	end
	if plan.unknownFlight then
		local walk, flight = false, false
		for index = current, #plan.legs do
			local mode = plan.legs[index].mode
			walk = walk or mode == "walk"
			flight = flight or mode == "flight"
		end
		if walk and not flight then
			return {
				key = "unknown-flight-path",
				text = L["A flight point you have not discovered yet would shorten this route: visit a flight master to learn it."],
				grey = true,
			}
		end
	end
	return nil
end

local function Whole(ms)
	return math.max(0, math.ceil(ms / 1000))
end

-- Where a leg starts and ends, as the planner's own leg points name them: the first and last point of the line it
-- draws, copied to uiMapID and 0-1 fractions. A leg with no such line, or an end this client cannot place, keeps that
-- field nil. Nothing is estimated here.
---@param leg SPFLeg
---@param place fun(point: SPFPoint): SPFAPIPlace?
---@return SPFAPIPlace?, SPFAPIPlace?
local function LegEnds(leg, place)
	local points = ns.PlanContext.LegPoints(leg)
	local first, last = points[1], points[#points]
	return first and place(first), last and place(last)
end

-- The planner's legs from the one under way on, as fresh copies: the tracker's plain action words, the mode's own
-- name and the leg's whole seconds including its wait, which is how JourneyTime adds the header up, and the leg's own
-- ends as the planner drew them. Every table is new, so a caller never reaches the plan.
---@param plan SPFPlan
---@param index integer
---@param place fun(point: SPFPoint): SPFAPIPlace?
---@return SPFAPIJourneyLeg[]
function ns.JourneyLegDetails(plan, index, place)
	local legs = {}
	for legIndex = index, #plan.legs do
		local leg = plan.legs[legIndex]
		local from, to = LegEnds(leg, place)
		legs[#legs + 1] = {
			mode = leg.mode,
			text = ns.StepText(leg),
			seconds = Whole(ns.LegSpan(leg)) + Whole(leg.wait or 0),
			from = from,
			to = to,
		}
	end
	return legs
end

-- A place with the goal's name: the title its caller gave the stop, else the name the tracker's header gives it. The
-- header's own line also counts the stops ("Stop 1 of 2: ..."), which a caller reads from index instead.
---@param project fun(point: SPFPoint): SPFAPIPlace?
---@param point SPFPoint
---@return SPFAPIJourneyGoal?
function ns.JourneyGoalDetails(project, point)
	local place = project(point)
	if not place then
		return nil
	end
	return { map = place.map, x = place.x, y = place.y, z = place.z, title = point.label or ns.JourneyTitle(point) }
end

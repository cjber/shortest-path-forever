---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- A map click with the journey key held: the fastest way there from here, by foot, flight, boat, zeppelin, tram and
-- portal,
-- with the boats' live waits. JourneySearch.lua finds the way; this follows it: the goal, the route and how far
-- along it you are, Guide and the frame driver. The tracker owns the list; closing the map leaves the journey running.
local REPLAN_EVERY = 5
local REPLAN_DUE = REPLAN_EVERY - 0.5 -- from here Itinerary.lua leaves the frames to the timed replan
local DRAW_EVERY = 0.5

local goal, result
local policyChanged
local nextPoint
local progress = { index = 1 }
local withoutHearth = false
---@class SPFJourneyDriver : Frame
---@field elapsed number
---@field replannedAt? number GetTime of the last timed replan
---@field speed? number run speed seen on the last frame
---@field progressElapsed number
---@field riding? number
---@field flying? boolean
---@field drawAt? number
---@field drawX? number
---@field drawY? number
---@field drawMap? number
---@type SPFJourneyDriver
local driver
local ARRIVAL = 15
local Search, Guide = ns.JourneySearch, ns.JourneyGuide
local RefreshTracker, StopGuide = Guide.RefreshTracker, Guide.Stop
-- A walk whose drawn line runs this many yards above or below the floor you are on (Floor.lua) is not the one you are
-- on: it is on another floor of the same spot. The walking search's own height tolerance.
local OTHER_FLOOR = 10
-- Water Walking, Levitate and the Elixir of Water Walking make water ground. A spell you know counts too: the step
-- asks you to cast it.
local WATER_AURAS = { 546, 1706, 11319 }
local WATER_SPELLS = { 546, 1706 }
local WALK_FAILURE = ns.WalkFailure

-- While you are a ghost, Corpse.lua's run borrows the route drawing, the tracker and Guide; the journey waits.
local function CorpseRun()
	return ns.Corpse ~= nil and ns.Corpse.Active()
end

---@return boolean
function ns.HasJourney()
	return goal ~= nil or CorpseRun()
end

-- The plan being followed and the step under way, whatever the tracker shows (paused or behind a corpse run).
---@return SPFPlan? plan, integer index
function ns.JourneyPlan()
	return result, progress.index
end

local CONTINENTS = {
	{ map = 0, uiMap = 1415, name = L["Eastern Kingdoms"] },
	{ map = 1, uiMap = 1414, name = L["Kalimdor"] },
}
local continentsNamed = false
local NONE = {}

local function Continents()
	if not continentsNamed then
		continentsNamed = true
		for _, continent in ipairs(CONTINENTS) do
			local info = C_Map.GetMapInfo(continent.uiMap)
			if info and info.name and info.name ~= "" then
				continent.name = info.name
			end
		end
	end
	return CONTINENTS
end

local function KnownCounts()
	local counts = {}
	for nodeID in pairs(ns.KnownTaxiNodes()) do
		local node = ns.TaxiNodes[nodeID]
		if node then
			counts[node.map] = (counts[node.map] or 0) + 1
		end
	end
	return counts
end

---@return {map: number, name: string, known: integer}[]
function ns.KnownFlightPointsByContinent()
	local counts, continents = KnownCounts(), {}
	for _, continent in ipairs(Continents()) do
		continents[#continents + 1] = { map = continent.map, name = continent.name, known = counts[continent.map] or 0 }
	end
	return continents
end

---@param plan SPFPlan
---@return {map: number, name: string}[]
local function UnsyncedContinents(plan)
	local maps = plan.unknownFlightMaps
	if not maps then
		return NONE
	end
	local counts, unsynced = KnownCounts(), NONE
	for _, continent in ipairs(Continents()) do
		if maps[continent.map] and not counts[continent.map] then
			unsynced = unsynced == NONE and {} or unsynced
			unsynced[#unsynced + 1] = continent
		end
	end
	return unsynced
end

---@param plan SPFPlan
---@return SPFRow[]
function ns.UnsyncedFlightPointRows(plan)
	local unsynced = UnsyncedContinents(plan)
	if unsynced == NONE then
		return NONE
	end
	local rows = {}
	for _, continent in ipairs(unsynced) do
		rows[#rows + 1] = {
			key = "no-flight-points-" .. continent.map,
			text = string.format(
				L["No flight points learned in %s: open a flight master's map once to sync them."],
				continent.name
			),
			warning = true,
		}
	end
	return rows
end

-- Where the journey goes, also while it waits behind a corpse run; nil with no journey.
---@return SPFPoint?
function ns.JourneyGoal()
	return goal
end

function ns.JourneyWithoutHearth()
	return withoutHearth
end

function ns.TravelPolicyChanged()
	policyChanged = true
	if ns.ItineraryChanged then
		ns.ItineraryChanged(true)
	end
	ns.WakeTravel()
end

-- Whether journeys may use the Hearthstone. The saved switch, flipped from the tracker's journey menu and the map's
-- innkeeper button (UI/HearthPin.lua); off, class teleports and bind items still apply (Transport/Teleports.lua).
---@return boolean
function ns.HearthstoneEnabled()
	return ns.db == nil or ns.db.useHearthstone ~= false
end

---@param enabled boolean
function ns.SetHearthstoneEnabled(enabled)
	if not ns.db then
		return
	end
	ns.db.useHearthstone = enabled == true
	-- Turning it back on forgives a Hearthstone step skipped by hand earlier in this journey.
	if ns.db.useHearthstone then
		withoutHearth = false
	end
	ns.TravelPolicyChanged()
	RefreshTracker()
	if ns.RefreshHearthPin then
		ns.RefreshHearthPin()
	end
end

function ns.ToggleHearthstone()
	ns.SetHearthstoneEnabled(not ns.HearthstoneEnabled())
end

-- Whether walks may cross water, and the spell to cast first when none is up.
local function WaterWalking()
	if ns.db.useWaterWalking == false then
		return false
	end
	for _, id in ipairs(WATER_AURAS) do
		if C_UnitAuras.GetPlayerAuraBySpellID(id) then
			return true
		end
	end
	for _, id in ipairs(WATER_SPELLS) do
		-- IsPlayerSpell is a deprecation fallback, defined only while the loadDeprecationFallbacks CVar is on.
		if C_SpellBook.IsSpellKnown(id) then
			return true, id
		end
	end
	return false
end

-- Read-only capability query shared by the public estimator and the guided planner.
ns.JourneyWaterWalking = WaterWalking

-- The player's world position, from UnitPosition or the map the client puts the player on. The client may withhold
-- UnitPosition from addons (its values are secret) while the map APIs still answer with the same place; the journey,
-- its route, the minimap and the arrow then keep working instead of silently waiting for a sample that never comes
-- (#553).
---@return number? x, number? y, number? z, number? map
function ns.PlayerPosition()
	local x, y, z, map = UnitPosition("player")
	if canaccessvalue(x) and canaccessvalue(y) and canaccessvalue(map) and x and y and map then
		return x, y, canaccessvalue(z) and z or nil, map
	end
	local uiMap = C_Map.GetBestMapForUnit("player")
	if not (uiMap and canaccessvalue(uiMap)) then
		return nil
	end
	local position = C_Map.GetPlayerMapPosition(uiMap, "player")
	if not (position and canaccessvalue(position)) then
		return nil
	end
	local mapX, mapY = position:GetXY()
	if not (canaccessvalue(mapX) and canaccessvalue(mapY)) or not (mapX and mapY) then
		return nil
	end
	local continent, world = C_Map.GetWorldPosFromMapPos(uiMap, CreateVector2D(mapX, mapY))
	if not (continent and world and canaccessvalue(continent) and canaccessvalue(world)) then
		return nil
	end
	x, y = world:GetXY()
	if not (canaccessvalue(x) and canaccessvalue(y)) or not (x and y) then
		return nil
	end
	return x, y, nil, continent
end

-- Planning, Guide and lines share this gate. UnitPosition's third value is no floor to plan from, so the player's
-- height is unknown here.
---@return number? x, number? y, nil z, number? map
function ns.JourneyPosition()
	local x, y, _, map = ns.PlayerPosition()
	return x, y, nil, map
end

local function Here()
	local x, y, _, map = ns.JourneyPosition()
	return x and { map = map, x = x, y = y }
end

local function Near(node, reach)
	local x, y, _, map = ns.JourneyPosition()
	if not (x and y and map == node.map and (x - node.x) ^ 2 + (y - node.y) ^ 2 <= (reach or ARRIVAL) ^ 2) then
		return false
	end
	-- The goal under or over you is not reached: crossing the Ruins of Lordaeron's hall above a stop in the Undercity
	-- never arrives there. Where the floor is unknown, the spot alone decides, as before. Only the goal: a dock's or
	-- a landing's height is the transport's, and boarding and landing have their own tests.
	local atGoal = goal and node.z and node.map == goal.map and node.x == goal.x and node.y == goal.y
	local height = atGoal and map and ns.Floor and ns.Floor.Height(map, x, y)
	return not (height and math.abs(height - node.z) > OTHER_FLOOR)
end

-- The client's own answer for the quests a held stop names: true inside any of their areas, false outside them
-- all, nil when the stop names none or the client has or shares no answer for any of them.
---@param point SPFPoint
---@return boolean?
local function InsideQuestArea(point)
	local insideQuestBlob = C_Minimap and C_Minimap.IsInsideQuestBlob
	if not (point.questIDs and insideQuestBlob) then
		return nil
	end
	local answer
	for _, questID in ipairs(point.questIDs) do
		local inside = insideQuestBlob(questID)
		if canaccessvalue(inside) then
			if inside == true then
				return true
			end
			answer = false
		end
	end
	return answer
end

-- Whether the player stands in a held stop's objective area. A stop that names the quests it stands for is
-- answered by the client's own blob state, which is what its minimap draws and the player sees; a client that
-- withholds or does not have it, and a stop the guide only has circles for, falls back to the shapes and radius.
---@param point SPFPoint?
---@return boolean
function ns.StopInside(point)
	if not (point and point.hold) then
		return false
	end
	local inside = InsideQuestArea(point)
	if inside ~= nil then
		return inside
	end
	local x, y, _, map = ns.JourneyPosition()
	if not (x and map == point.map) then
		return false
	end
	if point.shapes then
		for _, shape in ipairs(point.shapes) do
			if shape.map == map and (x - shape.x) ^ 2 + (y - shape.y) ^ 2 <= shape.radius ^ 2 then
				return true
			end
		end
		return false
	end
	return point.radius ~= nil and (x - point.x) ^ 2 + (y - point.y) ^ 2 <= point.radius ^ 2
end

---@type SPFRoutePolicy
local journeyPolicy = "normal"

---@param reason "arrived"|"cleared"
local function EndJourney(reason)
	Search.Reset()
	goal, result, nextPoint = nil, nil, nil
	journeyPolicy = "normal"
	withoutHearth = false
	if ns.JourneyChanged then
		ns.JourneyChanged(nil, reason)
	end
	progress.index, progress.departed = 1, false
	driver:Hide()
	if not CorpseRun() then
		StopGuide(reason)
		ns.SetJourneyRoute(nil)
	end
	RefreshTracker()
end

-- Menus and settings pass their own arguments to callbacks, so the player's clear takes none.
function ns.ClearJourney()
	EndJourney("cleared")
end

-- Completion may run inside a planner callback. Start at most one next stop on the driver's next step,
-- after that callback unwinds; coincident stops must never recurse through the whole route in one frame.
local function Arrive()
	local reached = goal
	if ns.JourneyStopObserved then
		local alive = ns.JourneyStopObserved("arrived", reached)
		-- An observer may cancel, replace or hand over the route: that journey, not this arrival, is what goes on.
		if alive == false or goal ~= reached then
			return
		end
	end
	nextPoint = ns.NextJourneyStop and ns.NextJourneyStop(goal)
	if not nextPoint then
		EndJourney("arrived")
	end
end

local function UpdateProgress()
	if not (goal and result) or nextPoint or CorpseRun() then
		return
	end
	local inside = goal.hold and ns.StopInside(goal)
	local changed, riding, flying = ns.JourneyProgressChanged(goal, result, progress, inside)
	if not changed then
		return
	end
	if inside then
		Guide.Pause()
		return
	end
	-- A dungeon's door is reached by going in (EnteredInstance), never by standing beside it: the stop it stands for
	-- is inside, and the next stop may be too.
	local reach
	if not goal.hold and not goal.entrance then
		-- The player's own arrival distance is for the journey's final destination. The stops before the last on a
		-- multi-stop route keep the fixed 15 yards.
		local final = not (ns.NextJourneyStop and ns.NextJourneyStop(goal))
		reach = final and ns.db.arrivalDistance or nil
		if Near(goal, reach) then
			Arrive()
			return
		end
	end
	if ns.AdvanceJourneyProgress(result.legs, progress, goal, riding, flying, Near, Guide, reach) or goal.entrance then
		return
	end
	Arrive()
end

-- Going in through the door of the instance a journey's stop is inside completes that stop.
local function EnteredInstance()
	if goal and goal.entrance and not nextPoint and select(8, GetInstanceInfo()) == goal.entrance then
		Arrive()
		if nextPoint then
			ns.StartJourney(nextPoint, journeyPolicy)
		end
	end
end

---@return boolean
function ns.IsJourneyGuided()
	return Guide.Active()
end

-- costError says why no walk could be measured, if one could not; loading says a first search is still working.
-- timing is the search's own clock since the journey started, to its first and latest route (JourneySearch.lua).
---@return boolean pending, integer settleRound, string? costError, boolean loading, table? timing, boolean replanning
function ns.JourneyStatus()
	local pending, settleRound, costError, loading = Search.Status()
	return pending > 0, settleRound, costError, loading, Search.timing, Search.Replanning()
end

local function StartGuide()
	Guide.Start()
	UpdateProgress()
	if ns.RefreshJourneyPin then
		ns.RefreshJourneyPin()
	end
end

function ns.ToggleJourneyGuide()
	if Guide.Active() then
		StopGuide()
	elseif CorpseRun() then
		Guide.Start()
		ns.Corpse.Steer()
	elseif goal then
		StartGuide()
	end
	RefreshTracker()
	-- The goal's pin is gold while Guide tracks it and bronze while the route waits unguided.
	if ns.RefreshJourneyPin then
		ns.RefreshJourneyPin()
	end
end

---@return number?
function ns.JourneyMapID()
	local place = CorpseRun() and ns.Corpse.Point() or goal
	local location = place and ns.Locate(place)
	return location and location.uiMap
end

-- The journey's name. `formatPlace` wraps the place this addon named inside the same locale sentence; a caller's
-- own title (`routeTitle`) keeps its words, since only a title this addon built knows where its place sits.
---@param point SPFPoint
---@param formatPlace? fun(place: string): string
---@return string
function ns.JourneyTitle(point, formatPlace)
	local function place(text)
		return formatPlace and formatPlace(text) or text
	end
	if point.routeTitleFormat and point.stopLabel then
		return string.format(point.routeTitleFormat, point.number, point.routeCount, place(point.stopLabel))
	end
	if point.routeTitle then
		return point.routeTitle
	end
	return string.format(L["Journey to %s"], place(ns.PlaceLabel(point)))
end

-- Shared by the tracker and the goal pin, including on a fullscreen map. `formatPlace` asks for the places in the
-- title and each step already wrapped in the tracker's colour; the plain text is left as it is.
---@param formatPlace? fun(place: string): string
---@return string? title, SPFRow[]? rows, SPFPlan? plan, number? index, boolean? loading
function ns.JourneyInfo(formatPlace)
	if CorpseRun() then
		return ns.Corpse.Info(formatPlace)
	end
	if not goal or Guide.Paused() then
		return nil
	end
	local title = ns.JourneyTitle(goal, formatPlace)
	local rows = {}
	local _, _, costError, loading = Search.Status()
	-- Only this goal's own steps: a new goal lists none until its plan lands, never the journey it replaced.
	if result then
		ns.StepRows(rows, result, progress.index, formatPlace, loading)
	elseif loading then
		rows[1] = { key = "searching", text = L["Finding the fastest way…"], grey = true }
	else
		rows[1] = { key = "unreachable", text = costError and WALK_FAILURE[costError] or L["No way there from here."] }
	end
	return title, rows, result, progress.index, loading
end

-- The height of a walk's segment from a to b at t along it, from whichever ends have one.
local function SegmentHeight(a, b, t)
	if a.z and b.z then
		return a.z + t * (b.z - a.z)
	end
	return a.z or b.z
end

-- Where here falls on a walk: the segment ending at points[index], how far along it (t), and the yards still to walk
-- from there, or nil when here is farther from the walk than reach. Measured walks share the saved tolerance for
-- replanning, rejoining and corpse runs. Unmeasured walks rejoin at the nearest point, and arrival keeps its own
-- distance check. A player with a known height can only match a segment on the same floor.
-- Segment lengths of a walk, built once per points table: OnWalk runs on every progress tick for the same
-- walk, and rebuilding them allocated a table and re-rooted every segment each time (WFA-13). Weak keys let
-- a replaced walk's lengths go with it. The cache keeps each point's coordinates too, so a points table edited
-- in place is measured again; comparing them costs no square roots and allocates nothing.
local walkLengths = setmetatable({}, { __mode = "k" })
local function OnWalk(points, here, reach)
	if not here then
		return nil
	end
	local cached = walkLengths[points]
	local fresh = cached ~= nil and cached.count == #points
	if fresh then
		local xs, ys = cached.xs, cached.ys
		for index = 1, #points do
			local point = points[index]
			if point.x ~= xs[index] or point.y ~= ys[index] then
				fresh = false
				break
			end
		end
	end
	local lengths, total
	if fresh then
		lengths, total = cached.lengths, cached.total
	else
		lengths, total = {}, 0
		local xs, ys = {}, {}
		for index = 1, #points do
			xs[index], ys[index] = points[index].x, points[index].y
		end
		for index = 2, #points do
			local a, b = points[index - 1], points[index]
			lengths[index] = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
			total = total + lengths[index]
		end
		walkLengths[points] = { lengths = lengths, total = total, count = #points, xs = xs, ys = ys }
	end
	reach = reach or ns.db.offPathTolerance
	local walked, best, found, along, after = 0, nil, nil, nil, nil
	for index = 2, #points do
		local a, b = points[index - 1], points[index]
		local dx, dy, length = b.x - a.x, b.y - a.y, lengths[index]
		local t = length > 0 and math.max(0, math.min(1, ((here.x - a.x) * dx + (here.y - a.y) * dy) / length ^ 2)) or 0
		local off = math.sqrt((a.x + t * dx - here.x) ^ 2 + (a.y + t * dy - here.y) ^ 2)
		local height = here.z and SegmentHeight(a, b, t)
		if
			here.map == a.map
			and off <= reach
			and (not best or off < best)
			and not (height and math.abs(height - here.z) > OTHER_FLOOR)
		then
			best, found, along, after = off, index, t, total - walked - t * length
		end
		walked = walked + length
	end
	return found, along, after, total, best
end

ns.OnWalk = OnWalk -- Corpse.lua trims its walk the same way.
-- The route last handed to the map, kept so a retime moves its arrival without redrawing it, and a first search's
-- rough route, drawn while nothing is followed yet until a followable route or a new search replaces it.
local drawn, rough
local function Refresh()
	local remaining
	if result then
		remaining = { now = result.now, arrive = result.arrive, legs = {} }
		for index = progress.index, #result.legs do
			remaining.legs[#remaining.legs + 1] = result.legs[index]
		end
		-- Draw the walk you are on from where you stand, not from where it was planned.
		local leg, here = remaining.legs[1], Here()
		if here then
			driver.drawAt, driver.drawX, driver.drawY, driver.drawMap = GetTime(), here.x, here.y, here.map
		end
		if leg and leg.mode == "walk" and here then
			local points = leg.walkPoints or ns.Planner.WalkPoints(leg.from, leg.to)
			-- A walk still being searched may be the one it replaces, which you have strayed from: join it where it is
			-- nearest.
			local found = OnWalk(points, here, not leg.measured and math.huge or nil)
			if found then
				local ahead = { here }
				for index = found, #points do
					ahead[#ahead + 1] = points[index]
				end
				remaining.legs[1] = setmetatable({ walkPoints = ahead }, { __index = leg })
			end
		end
	end
	if not CorpseRun() then
		drawn = remaining
		ns.SetJourneyRoute(goal, remaining or goal and rough)
	end
	RefreshTracker()
end

-- Advance only the current leg. A refused Hearthstone stays out of this journey's later plans,
-- which still start at the player's actual position.
---@param index integer?
---@return boolean
function ns.SkipJourneyStep(index)
	if not goal or not result or CorpseRun() or InCombatLockdown() then
		return false
	end
	local current = progress.index
	if index ~= nil and index ~= current then
		return false
	end
	if not result.legs[current] then
		return false
	end
	if result.legs[current].teleport and result.legs[current].teleport.bind then
		withoutHearth = true
	end
	progress.index = current + 1
	progress.departed = false
	if progress.index > #result.legs then
		Arrive()
	else
		UpdateProgress()
	end
	Refresh()
	-- The leg under way moved on without the goal changing: subscribers hear "leg" (Core/API.lua).
	if ns.JourneyLegChanged then
		ns.JourneyLegChanged()
	end
	return true
end

local SamePlace = Search.SamePlace

local announcedGoal, announced = nil, {}

local function AnnounceUnsyncedFlightPoints()
	if not (result and result.unknownFlightMaps and goal and ns.db.flightPathReminder) then
		return
	end
	if announcedGoal ~= goal then
		announcedGoal, announced = goal, {}
	end
	for _, continent in ipairs(UnsyncedContinents(result)) do
		if not announced[continent.map] then
			announced[continent.map] = true
			ns.Print(
				RED_FONT_COLOR:WrapTextInColorCode(
					string.format(
						L["A flight would be quicker. Open a flight master's map in %s once to sync your flight points."],
						continent.name
					)
				)
			)
		end
	end
end

-- Everything the search changes about what to follow arrives here, possibly while it is being started or stepped.
---@param route SPFPlan?
---@param news SPFSearchNews
local function Follow(route, news)
	if news == "searching" or news == "rough" then
		-- The rough line is display-only.
		rough = news == "rough" and route or nil
		return Refresh()
	end
	if news == "route" then
		result, rough = route, nil
		progress.index, progress.departed = 1, false
		Guide.Retarget()
		if not result then
			StopGuide()
		end
		-- The plan is ready or has been replaced: the legs Journey() reports, and where each starts and ends, may
		-- differ from the last answer, whether or not the goal changed.
		if ns.JourneyReplanned then
			ns.JourneyReplanned()
		end
	elseif news == "walks" then
		Guide.Retarget()
		-- A redrawn walk can move the leg's own ends, which Journey() copies.
		if ns.JourneyReplanned then
			ns.JourneyReplanned()
		end
	end
	-- A provisional route is followed while the proof runs; stop observers hear only the proved one.
	local settled = goal
	local observe = ns.JourneyStopObserved and not (result and result.provisional)
	if (observe and ns.JourneyStopObserved("settled", settled) == false) or goal ~= settled then
		return
	end
	UpdateProgress()
	AnnounceUnsyncedFlightPoints()
	if news == "times" then
		if drawn and result then
			drawn.now, drawn.arrive = result.now, result.arrive
		end
		return RefreshTracker()
	end
	return Refresh()
end

-- The timed replan in Update plans in the frame, and from just before it Itinerary.lua keeps off that frame (a frame's
-- GetTime is fixed). A corpse run holds the replan, so a route queued behind it plans its hops meanwhile.
---@return boolean
function ns.JourneyReplanning()
	return not CorpseRun() and (driver.elapsed >= REPLAN_DUE or driver.replannedAt == GetTime())
end

---@param self SPFJourneyDriver
---@param elapsed number
-- One throttled frame step; keeping its gates together preserves the search/draw cadence
local function Update(self, elapsed)
	if CorpseRun() then
		return
	end
	if InCombatLockdown() then
		self.progressElapsed = self.progressElapsed + elapsed
		if self.progressElapsed >= 0.1 then
			self.progressElapsed = 0
			-- Progress is the guide's own, not planning or drawing: a bend passed in combat still moves the arrow
			-- under way and tells guidance subscribers, which writes nothing.
			if ns.AdvanceGuide then
				ns.AdvanceGuide()
			end
			if goal and ns.StopInside(goal) then
				Guide.Pause()
			end
		end
		return
	end
	if not ns.db.journey then
		ns.ClearJourney()
		return
	end
	self.elapsed = self.elapsed + elapsed
	self.progressElapsed = self.progressElapsed + elapsed
	if self.progressElapsed < 0.1 then
		return
	end
	self.progressElapsed = 0
	local x, y, _, map = ns.JourneyPosition()
	if not x then
		return
	end
	-- The guide's bend under way advances from this existing progress tick too, so an arrow that is off still keeps
	-- the compass and the public guidance read current. A read advances it as well; there is no poll of its own.
	if ns.AdvanceGuide then
		ns.AdvanceGuide()
	end
	if ns.Floor and y and map then
		ns.Floor.Sample(map, x, y)
	end
	local changed = policyChanged
	policyChanged = nil
	Search.Poll(changed)
	local index = progress.index
	UpdateProgress()
	if nextPoint then
		ns.StartJourney(nextPoint, journeyPolicy)
		return
	end
	if not goal then
		return
	end
	local riding, flying = ns.CurrentRide(), UnitOnTaxi("player")
	local changedRide = riding ~= self.riding or flying ~= self.flying
	self.riding, self.flying = riding, flying
	-- Edge-triggered like the ride: comparing against the last planned speed would retrigger every frame
	-- while a search is still settling and no plan has run.
	local speed = ns.PlanContext.RunSpeed()
	local changedSpeed = speed ~= (self.speed or Search.Speed())
	self.speed = speed
	if self.elapsed >= REPLAN_EVERY or changedRide or changedSpeed then
		self.elapsed, self.replannedAt = 0, GetTime()
		Search.Replan(riding, flying, changedRide, changedSpeed)
	elseif index ~= progress.index then
		Refresh()
	end
	-- Trimming is presentation work, independent of the five-second planning/search cadence.
	if
		goal
		and result
		and GetTime() - (self.drawAt or 0) >= DRAW_EVERY
		and (x ~= self.drawX or y ~= self.drawY or map ~= self.drawMap)
	then
		Refresh()
	end
end

-- Whether the journey waiting out a corpse run was guided; one asked for while you are a ghost starts guided.
local waitingGuided = false
-- The run is starting: searches stop, and the journey keeps its goal, route and progress for later.
function ns.SuspendJourney()
	waitingGuided = goal ~= nil and Guide.Active()
	Search.Cancel()
end

-- You are alive again: the journey plans afresh from wherever that is, guided as it was.
function ns.ResumeJourney()
	if goal then
		ns.StartJourney(goal, journeyPolicy)
		-- A route submitted while dead used the corpse run's effective policy for its previews.
		if ns.ItineraryChanged then
			ns.ItineraryChanged()
		end
		-- The route you were on shows again at once, until the new plan replaces it.
		if result then
			Refresh()
		end
		if not waitingGuided then
			StopGuide()
		end
	else
		StopGuide()
		ns.SetJourneyRoute(nil)
	end
	RefreshTracker()
end

-- An owner sent the destination the journey already has; only the stop's words may have changed. A first search
-- still owing its answer is asked to read what it has, as sending the same route again always did, but nothing of the
-- journey is restarted.
function ns.RefreshJourneySearch()
	if goal and not result and not CorpseRun() and Search.Status() > 0 then
		Search.Start(goal, result, progress, Follow, nil, journeyPolicy)
	end
end

-- An owner moved the destination of a journey it already owns (a guide's next objective in the area, or the same
-- waypoint re-pointed). The owner, the stop and the progress stay, and so does the route already drawn, until the
-- search for the new place settles: tearing all of it down and starting again flashed the arrow, the line and the
-- tracker for every objective the guide moved to (#693).
---@param point SPFPoint
---@return boolean
function ns.RetargetJourney(point)
	if CorpseRun() or not goal or point.map ~= goal.map then
		return ns.StartJourney(point, journeyPolicy)
	end
	if Search.SamePlace(goal, point) then
		ns.RefreshJourneySearch()
		return true
	end
	goal, nextPoint = point, nil
	withoutHearth = false
	if ns.JourneyChanged then
		ns.JourneyChanged(point)
	end
	-- The hops after this stop start from where it now is.
	ns.ItineraryChanged()
	driver.elapsed, driver.progressElapsed = 0, 0
	if not InCombatLockdown() then
		driver:Show()
	end
	ns.WakeTravel()
	-- Replacing: the plan under way leads to the place this one leaves, so the next plan takes over whatever it costs.
	Search.Start(goal, result, progress, Follow, true, journeyPolicy)
	-- A guide that yielded to the player's own destination leads again for a destination the player did not choose.
	if Guide.Yielded() then
		StopGuide()
	end
	if not Guide.Active() then
		StartGuide()
	end
	Refresh()
	return true
end

---@param point SPFPoint
---@param policy? SPFRoutePolicy
---@return boolean
function ns.StartJourney(point, policy)
	policy = policy or "normal"
	point = ns.InstanceEntrance(point)
	if CorpseRun() then
		-- Queued behind the corpse run, which ResumeJourney plans from where you come back to life.
		if not (goal and SamePlace(goal, point) and journeyPolicy == policy) then
			result = nil
			withoutHearth = false
			Search.Clear(false, policy)
			progress.index, progress.departed = 1, false
		end
		journeyPolicy = policy
		goal, nextPoint, waitingGuided = point, nil, true
		if ns.JourneyChanged then
			ns.JourneyChanged(point)
		end
		RefreshTracker()
		return true
	end
	local previous = Search.Clear(goal and SamePlace(goal, point), policy) and result
	journeyPolicy = policy
	withoutHearth = false
	if previous then
		for _, leg in ipairs(previous.legs) do
			if leg.to.kind == "goal" then
				leg.to.label = point.label
			end
		end
	end
	local index, departed = progress.index, progress.departed
	if Guide.Active() then
		StopGuide()
	end
	goal, nextPoint = point, nil
	if ns.JourneyChanged then
		ns.JourneyChanged(point)
	end
	result = previous or nil
	progress.index, progress.departed = previous and index or 1, previous and departed or false
	driver.elapsed, driver.progressElapsed = 0, 0
	if not InCombatLockdown() then
		driver:Show()
	end
	ns.WakeTravel()
	Search.Start(goal, result, progress, Follow, nil, journeyPolicy)
	-- Every journey starts guided; the tracker header turns it off.
	if goal then
		StartGuide()
		RefreshTracker()
	end
	return true
end

ns.Init(function()
	local journeyDriver = CreateFrame("Frame", "ShortestPathForeverJourneyDriver", UIParent)
	---@cast journeyDriver SPFJourneyDriver
	driver = journeyDriver
	driver.elapsed, driver.progressElapsed = 0, 0
	driver:SetScript("OnUpdate", Update)
	driver:RegisterEvent("PLAYER_REGEN_DISABLED")
	driver:RegisterEvent("PLAYER_REGEN_ENABLED")
	driver:RegisterEvent("QUEST_TURNED_IN")
	driver:RegisterEvent("QUEST_REMOVED")
	driver:RegisterEvent("SUPER_TRACKING_CHANGED")
	driver:RegisterEvent("USER_WAYPOINT_UPDATED")
	driver:RegisterEvent("PLAYER_LOGIN")
	driver:RegisterEvent("PLAYER_ENTERING_WORLD")
	driver:SetScript("OnEvent", function(self, event, questID)
		if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
			Guide.ClearOrphan()
			EnteredInstance()
			if ns.FocusedTrackingReset then
				ns.FocusedTrackingReset()
			end
		elseif
			event == "PLAYER_REGEN_DISABLED"
			and not (goal and goal.hold and (goal.radius or goal.shapes or goal.questIDs))
		then
			self:Hide()
		elseif event == "PLAYER_REGEN_ENABLED" and goal then
			self:Show()
		end
		local questGone = event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED"
		if questGone then
			Guide.QuestGone(questID)
		end
		if questGone and goal and goal.questID == questID then
			ns.ClearJourney()
		elseif event == "SUPER_TRACKING_CHANGED" or event == "USER_WAYPOINT_UPDATED" then
			Guide.TrackingChanged(event)
			if ns.FocusedTrackingChanged then
				ns.FocusedTrackingChanged(event)
			end
		end
	end)
	driver:Hide()
end)

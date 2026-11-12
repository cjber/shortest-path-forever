---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L
local APIKit = assert(ForeverCore.APIKit)

-- This topology belongs exclusively to estimates: Planner.Plan mutates its cache between calls.
-- Never borrow the active journey's cache, path jobs, progress, waypoint or route drawing.
local plannerCache, knownSnapshot = {}, {}
-- legs are the planner's own, read only to build EstimateDetail's copies; they never leave this file.
---@type table<string, {at: number, seconds: number|false, legs?: SPFLeg[]}>
local estimates, order, slot = {}, {}, 1
local anchorSnapshot, context = {}, {}
local CACHE_LIMIT, CACHE_MS = 256, 5000
-- Teleports are cast from where you stand, now: only an estimate that starts within this many yards of you counts
-- them. Anywhere else is a later leg of the caller's route, when their cooldowns are unknown.
local HERE = 15
-- Yards from a stop to the spawn it stands for: QuestieDB keeps a spawn's spot to a hundredth of a percent of its zone
-- map, a yard or less, and the server's spawn sits within 2 yd of Questie's for five spawns in six.
local SPAWN_REACH = 8
local CONTEXT_KEYS = {
	"walkSpeed",
	"faction",
	"otherFaction",
	"waterWalking",
	"docks",
	"routes",
	"taxiNodes",
	"taxiPaths",
	"portals",
	"teleports",
	"partyPortals",
	"landmasses",
	"baked",
	"hearthMinimumSavings",
}

local function Number(value)
	return canaccessvalue(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function Point(map, x, y)
	if
		not Number(map)
		or map <= 0
		or map % 1 ~= 0
		or not Number(x)
		or not Number(y)
		or x < 0
		or x > 1
		or y < 0
		or y > 1
	then
		return nil
	end
	return ns.WorldPoint(map, x, y)
end

-- A world point as this API names places: the uiMapID C_Map projects it onto and 0-1 fractions there. It is the
-- reverse of Point, so a caller reads back the same shape it sent and never one of ns's own world points.
---@param point SPFPoint?
---@return SPFAPIPlace?
local function Place(point)
	if not point then
		return nil
	end
	local uiMap, position = C_Map.GetMapPosFromWorldPos(point.map, CreateVector2D(point.x, point.y))
	if not (uiMap and position and Number(uiMap) and uiMap > 0 and uiMap % 1 == 0) then
		return nil
	end
	local x, y = position:GetXY()
	if not (Number(x) and Number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
		return nil
	end
	return { map = uiMap, x = x, y = y }
end

-- A positive whole number: a quest or NPC id.
local function ID(value)
	return Number(value) and value % 1 == 0 and value >= 1
end

-- A stop's detail is one string with one line per quest (Adventure Guide joins its quest lines with newlines).
-- Split it here so every stop keeps its own lines for the pin tooltip (UI/StopPin.lua).
---@param text? string
---@return string[]?
local function DetailLines(text)
	if not text then
		return nil
	end
	local lines = {}
	for line in text:gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	return lines[1] and lines or nil
end

-- An objective area list: one or more places on a map, each with a yard radius. Every entry must be one this
-- client can place.
---@param shapes table
---@return boolean
local function Shapes(shapes)
	local count = #shapes
	if count < 1 then
		return false
	end
	for key, shape in pairs(shapes) do
		if not Number(key) or key % 1 ~= 0 or key < 1 or key > count then
			return false
		end
		if
			type(shape) ~= "table"
			or not Point(shape.map, shape.x, shape.y)
			or not Number(shape.radius)
			or shape.radius < 0
		then
			return false
		end
	end
	return true
end

-- The quests a held area stands for: one or more quest IDs, in order.
---@param quests table
---@return boolean
local function Quests(quests)
	local count = #quests
	if count < 1 then
		return false
	end
	for key, questID in pairs(quests) do
		if not Number(key) or key % 1 ~= 0 or key < 1 or key > count or not ID(questID) then
			return false
		end
	end
	return true
end

local function Loaded()
	return ns.db ~= nil and ns.charDB ~= nil
end

local function Ready()
	return Loaded() and not InCombatLockdown()
end

---@return nil, "loading"
local function Loading()
	local _, answer = APIKit.NotReady("loading")
	return nil, answer --[[@as "loading"]]
end

---@return nil, "none"
local function None()
	local _, answer = APIKit.NotReady("none")
	return nil, answer --[[@as "none"]]
end

local function Owner(owner)
	return canaccessvalue(owner) and type(owner) == "string" and owner:find("%S") ~= nil
end

-- Only this module owns the caller's itinerary. Journey handles one destination at a time.
---@type {owner: string, points: SPFPoint[], index: integer}?
local route
local MAX_STOPS = 64
-- Why each owner's last journey ended, and when (GetTime); an owner's new journey forgets it.
---@type table<string, {reason: SPFAPIEnded, at: number}>
local ended = {}

-- Subscribe's hub (ForeverCore.APIKit): told once per burst what happened to guidance, after every change in it has
-- landed. Each channel is a comparable key the hub reads when it dispatches. The five event channels count the notices
-- the old dispatcher queued, so a caller hears the same changes it used to, and "active" is the answer itself, so a
-- guide switched off and on again within one burst stays quiet.
local notices = { started = 0, changed = 0, ended = 0, stop = 0, leg = 0 }

---@param name "started"|"changed"|"ended"|"stop"|"leg"
---@return fun(): integer|false
local function Counter(name)
	return function()
		return notices[name] ~= 0 and notices[name] or false
	end
end

local hub = APIKit.Hub("ShortestPathForever", {
	started = Counter("started"),
	changed = Counter("changed"),
	ended = Counter("ended"),
	stop = Counter("stop"),
	leg = Counter("leg"),
	active = function()
		return ns.IsJourneyGuided() == true
	end,
})

-- What subscribers were last told about, kept whether or not anyone listens: the destination (to tell a start from
-- a change), the owner and stop CurrentStop answers for, and Active().
---@type SPFPoint?
local guided
---@type string?
local stopOwner
---@type integer?
local stopIndex
local active = false

---@param kind "started"|"changed"|"ended"|"stop"|"leg"
local function Notify(kind)
	notices[kind] = notices[kind] + 1
	hub.Queue()
end

---@param a SPFPoint?
---@param b SPFPoint?
local function SamePlace(a, b)
	return a == b or (a and b and a.map == b.map and a.x == b.x and a.y == b.y) or false
end

-- The stop and guide state as callers read them, compared with what subscribers last heard.
local function Settle()
	local owner, index = route and route.owner, route and route.index
	if owner ~= stopOwner or index ~= stopIndex then
		stopOwner, stopIndex = owner, index
		Notify("stop")
	end
	local now = ns.IsJourneyGuided() == true
	if now ~= active then
		active = now
		hub.Queue()
	end
end

-- JourneyGuide.lua: the guide started or stopped, which Active() reports.
function ns.GuideChanged()
	Settle()
end

-- Journey.lua: the leg under way moved on, skipped from the tracker or by another addon's SkipLeg. A stop changing
-- already says "changed"; this says the leg within the same stop is not the one a subscriber last read.
function ns.JourneyLegChanged()
	Notify("leg")
end

---@param point SPFPoint?
---@param reason? "arrived"|"cleared" -- why a nil point ended the journey
function ns.JourneyChanged(point, reason)
	if ns.ProgressJourneyChanged then
		ns.ProgressJourneyChanged(point, reason)
	end
	if not SamePlace(point, guided) then
		Notify(not point and "ended" or guided and "changed" or "started")
	end
	guided = point
	if not route then
		Settle()
		return
	end
	if point and point == route.points[route.index + 1] then
		route.index = route.index + 1
	elseif not point or point ~= route.points[route.index] then
		ended[route.owner] = { reason = point and "replaced" or reason or "cleared", at = GetTime() }
		route = nil
	else
		Settle()
		return
	end
	Settle()
	ns.ItineraryChanged()
end

-- A running route's stop was relabelled in place (API.RenameStop, from a guide renaming its step): the tracker names
-- it. The label is cosmetic, so a tracker that cannot draw is not this journey's problem.
local function Relabel()
	ns.RefreshTracker()
end

function ns.JourneyRelabeled()
	if ns.RefreshTracker then
		ns.core.SafeCall("journey relabel", Relabel)
	end
end

-- Which addon owns the journey under way, if one does (Resume.lua keeps only the player's own).
---@return string?
function ns.JourneyOwner()
	return route and route.owner
end

---@param point SPFPoint
---@return SPFPoint?
function ns.NextJourneyStop(point)
	-- A door stands in for the stop inside its instance (JourneyInput.lua).
	point = point.stop or point
	return route and route.points[route.index] == point and route.points[route.index + 1] or nil
end

-- Internal read-only map view; the public API never exposes these private world points.
---@return SPFPoint[]? points, integer? index
function ns.JourneyStops()
	if route and #route.points > 1 then
		return route.points, route.index
	end
end

---@class SPFPublicAPI
local API = { version = 2, minor = 0 }

local function Differs(a, b)
	for key, value in pairs(a) do
		if b[key] ~= value then
			return true
		end
	end
	for key, value in pairs(b) do
		if a[key] ~= value then
			return true
		end
	end
	return false
end

-- The planner options from here and now; a changed context drops every cached estimate.
---@param from SPFPoint
---@param to SPFPoint
local function Options(from, to)
	local options = ns.PlanContext.Options(from, to)
	local known, now, anchors = options.taxiKnown, options.now, options.anchors
	-- Discovery updates the same saved table in place; topology identity alone cannot detect it.
	local changed = Differs(known, knownSnapshot)
	if changed then
		plannerCache, knownSnapshot = {}, {}
		for id, value in pairs(known) do
			knownSnapshot[id] = value
		end
	end
	local x, y, _, map = ns.JourneyPosition()
	if not (x and map == from.map and (x - from.x) ^ 2 + (y - from.y) ^ 2 <= HERE ^ 2) then
		options.teleportReady = {}
	end
	for id, anchor in pairs(anchors) do
		if anchorSnapshot[id] ~= anchor.epoch then
			changed = true
		end
	end
	for id in pairs(anchorSnapshot) do
		if not anchors[id] then
			changed = true
		end
	end
	-- Same multimodal planner and baked walks as the arrow's initial plan. Endpoint terrain searches
	-- are asynchronous and deliberately omitted: this is an estimate, not a settled walking path.
	options.cache, options.waterWalking = plannerCache, ns.JourneyWaterWalking()
	for _, name in ipairs(CONTEXT_KEYS) do
		if context[name] ~= options[name] then
			changed = true
		end
	end
	if changed then
		estimates, order, slot, anchorSnapshot = {}, {}, 1, {}
		for id, anchor in pairs(anchors) do
			anchorSnapshot[id] = anchor.epoch
		end
		context = options
	end
	return options, now
end

-- Behind API.Estimate and EstimateDetail. Uncached, LuaJIT -joff: Auberdine -> Eastern Plaguelands 2.45 ms cold /
-- 0.51 ms warm; JIT compilation can make the first call ~4 ms. Callers should make at most one uncached call per
-- frame; AGF fetches its card estimates one per frame while its panel is open. Results are cached, 256 (origin
-- rounded to 0.0001, exact destination) for at most five seconds; cached calls measured ~0.003 ms.
---@param from SPFPoint
---@param to SPFPoint
---@param key string
local function Answer(from, to, key)
	local options, now = Options(from, to)
	local cached = estimates[key]
	if cached and now >= cached.at and now - cached.at < CACHE_MS then
		if cached.seconds then
			return cached
		end
		return nil, "unreachable"
	end
	local plan = ns.Planner.Plan(options)
	local seconds = plan and math.max(0, (plan.arrive - now) / 1000) or nil
	if not cached then
		if order[slot] then
			estimates[order[slot]] = nil
		end
		order[slot] = key
		slot = slot % CACHE_LIMIT + 1
	end
	local entry = { at = now, seconds = seconds or false, legs = plan and plan.legs }
	estimates[key] = entry
	if seconds then
		return entry
	end
	return nil, "unreachable"
end

-- The reason tells a caller whether asking again later can help: "combat" after combat, "loading" when the addon is
-- still building its data, "invalid" never for bad input, "unreachable" when known flight paths or boat timings change.
---@return { at: number, seconds: number|false, legs?: SPFLeg[] }?, ("combat"|"invalid"|"unreachable"|"loading")?
local function Lookup(fromMap, fromX, fromY, toMap, toX, toY)
	if not Ready() then
		if InCombatLockdown() then
			return nil, "combat"
		end
		return Loading()
	end
	local from, to = Point(fromMap, fromX, fromY), Point(toMap, toX, toY)
	if not from or not to then
		return nil, "invalid"
	end
	return Answer(from, to, string.format("%d:%.4f:%.4f:%d:%.17g:%.17g", fromMap, fromX, fromY, toMap, toX, toY))
end

-- Itinerary.lua draws the hops between later stops with this cheap planner; no terrain searches. It keeps each
-- hop's legs itself, so they stay out of the estimate cache the public API answers from.
---@param from SPFPoint
---@param to SPFPoint
---@return SPFLeg[]?
function ns.EstimateLegs(from, to)
	local plan = ns.Planner.Plan((Options(from, to)))
	return plan and plan.legs
end

function API.Estimate(fromMap, fromX, fromY, toMap, toX, toY)
	local entry, reason = Lookup(fromMap, fromX, fromY, toMap, toX, toY)
	if not entry then
		return nil, reason
	end
	return entry.seconds --[[@as number]] -- Lookup returns only answered entries.
end

-- Built on demand so plain estimates stay as cheap as before. Every table is new: a caller that edits or keeps
-- the result can never reach the planner's nodes or a later caller's copy.
function API.EstimateDetail(fromMap, fromX, fromY, toMap, toX, toY)
	local entry, reason = Lookup(fromMap, fromX, fromY, toMap, toX, toY)
	if not entry then
		return nil, reason
	end
	local legs, previous = {}, entry.at
	for index, leg in ipairs(entry.legs) do
		-- Planner legs carry arrival times; each span runs from the previous arrival, so it includes the wait.
		legs[index] = {
			mode = leg.mode,
			to = ns.LegLabel(leg),
			seconds = (leg.arrive - previous) / 1000,
			wait = leg.wait and leg.wait >= 60000 and leg.wait / 1000 or nil,
			newFlightPath = leg.mode == "walk" and leg.to.undiscovered or nil,
		}
		previous = leg.arrive
	end
	return {
		seconds = entry.seconds --[[@as number]],
		legs = legs,
	}
end

function API.NavigateRoute(owner, stops)
	if not Owner(owner) or not Ready() or not ns.db.journey or type(stops) ~= "table" then
		return false
	end
	local count = #stops
	if count < 1 or count > MAX_STOPS or not ns.JourneyPosition() then
		return false
	end
	for key in pairs(stops) do
		if not Number(key) or key % 1 ~= 0 or key < 1 or key > count then
			return false
		end
	end
	local points = {}
	for index = 1, count do
		local stop = stops[index]
		if
			type(stop) ~= "table"
			or (stop.title ~= nil and not (canaccessvalue(stop.title) and type(stop.title) == "string"))
			or (stop.tooltip ~= nil and not (canaccessvalue(stop.tooltip) and type(stop.tooltip) == "string"))
			or (stop.hold ~= nil and not (canaccessvalue(stop.hold) and type(stop.hold) == "boolean"))
			or (stop.radius ~= nil and (not Number(stop.radius) or stop.radius < 0))
			or (stop.z ~= nil and not Number(stop.z))
			or (stop.questID ~= nil and not ID(stop.questID))
			or (stop.questIDs ~= nil and (type(stop.questIDs) ~= "table" or not Quests(stop.questIDs)))
			or (stop.handins ~= nil and (type(stop.handins) ~= "table" or not Quests(stop.handins)))
			or (stop.npc ~= nil and not ID(stop.npc))
			or (stop.shapes ~= nil and (type(stop.shapes) ~= "table" or not Shapes(stop.shapes)))
		then
			return false
		end
		local point = Point(stop.map, stop.x, stop.y)
		if not point then
			return false
		end
		point.label = stop.title
		point.details = DetailLines(stop.tooltip)
		-- A caller's world height lets the stop pin compare its surface with the terrain under that spot.
		if stop.z ~= nil then
			point.z = stop.z
		elseif point.z == nil and stop.npc ~= nil then
			-- A stop naming the NPC it reaches (Nearby services) stands on that NPC's QuestieDB spawn, which has no
			-- height: the spawn's own, when it stands over or under another surface, keeps the walk on its floor. A
			-- stop naming no NPC (a TomTom or guide waypoint) may be any spot, so it keeps the cheapest surface.
			point.z = ns.SpawnHeight(point.map, point.x, point.y, SPAWN_REACH)
		end
		-- A caller such as Adventure Guide may need the route to remain visible while the
		-- player completes an interaction at this location. It resubmits the route after
		-- that state changes; ordinary API stops retain automatic arrival.
		point.hold = stop.hold == true
		point.radius = stop.radius
		point.questID = stop.questID
		-- The NPC whose service this stop reaches: Shortest Path marks that NPC's nameplate while the stop is
		-- current. Another addon's route passes no npc, so its own highlight is the only one.
		point.npc = stop.npc
		-- The quests whose client blobs the stop stands for, copied; StopInside prefers the client's own answer for them.
		if stop.questID or stop.questIDs then
			point.questIDs = { stop.questID }
			for _, questID in ipairs(stop.questIDs or {}) do
				if questID ~= stop.questID then
					point.questIDs[#point.questIDs + 1] = questID
				end
			end
		end
		-- The quests handed in at the stop, copied: they hide the game's own pins there (UI/QuestPins.lua) and never
		-- decide arrival or the stop's area, which are the quests above alone.
		if stop.handins then
			point.handins = {}
			for _, questID in ipairs(stop.handins) do
				point.handins[#point.handins + 1] = questID
			end
		end
		-- The areas are copied to world points too: the caller cannot redirect a journey they no longer own.
		if stop.shapes then
			point.shapes = {}
			for _, shape in ipairs(stop.shapes) do
				local at = Point(shape.map, shape.x, shape.y) --[[@as SPFAreaShape]]
				at.radius = shape.radius
				point.shapes[#point.shapes + 1] = at
			end
		end
		-- An unknown kind is dropped, not refused: a caller written for a later vocabulary still gets its route.
		point.look = ns.StopKind(stop.kind)
		point.number = index
		if count > 1 then
			local location = not point.label and ns.Locate(point)
			-- What to do there, apart from the count the tooltip gives its own line (UI/StopPin.lua).
			point.stopLabel = point.label or location and location.zone or UNKNOWN
			-- Keep the locale format beside the built title, so the tracker can colour the place inside it.
			point.routeTitleFormat = L["Stop %d of %d: %s"]
			point.routeCount = count
			point.routeTitle = string.format(point.routeTitleFormat, index, count, point.stopLabel)
		end
		points[index] = point
	end
	-- Validate and copy every stop before replacing guidance. Caller mutations cannot redirect a journey.
	if route and route.owner ~= owner then
		ended[route.owner] = { reason = "replaced", at = GetTime() }
	end
	ended[owner] = nil
	route = { owner = owner, points = points, index = 1 }
	ns.ItineraryChanged()
	return ns.StartJourney(points[1])
end

function API.Navigate(owner, map, x, y, title, kind)
	return API.NavigateRoute(owner, { { map = map, x = x, y = y, title = title, kind = kind } })
end

function API.CurrentStop(owner)
	if not Loaded() then
		return Loading()
	end
	if Owner(owner) and route and route.owner == owner then
		return route.index
	end
	return None()
end

function API.Cancel(owner)
	if not API.CurrentStop(owner) then
		return false
	end
	ns.ClearJourney()
	ended[owner] = { reason = "cancelled", at = GetTime() }
	return true
end

-- A place with the goal's name: the title its caller gave the stop, else the name the tracker's header gives it. The
-- header's own line also counts the stops ("Stop 1 of 2: ..."), which a caller reads from index instead.
---@param point SPFPoint
---@return SPFAPIJourneyGoal?
local function JourneyPlace(point)
	local place = Place(point)
	if not place then
		return nil
	end
	return { map = place.map, x = place.x, y = place.y, title = point.label or ns.JourneyTitle(point) }
end

local function Whole(ms)
	return math.max(0, math.ceil(ms / 1000))
end

-- The planner's legs from the one under way on, as fresh copies: the tracker's plain action words, the mode's own
-- name and the leg's whole seconds including its wait, which is how JourneyTime adds the header up.
---@param plan SPFPlan
---@param index integer
---@return SPFAPIJourneyLeg[]
local function JourneyLegs(plan, index)
	local legs = {}
	for legIndex = index, #plan.legs do
		local leg = plan.legs[legIndex]
		legs[#legs + 1] = {
			mode = leg.mode,
			text = ns.StepText(leg),
			seconds = Whole(ns.LegSpan(leg)) + Whole(leg.wait or 0),
		}
	end
	return legs
end

-- A corpse run is the journey under way while you are a ghost. Corpse.Info already names it, its one plan and the
-- step under way, so the run is read as the tracker draws it; the journey waiting behind it keeps its goal.
---@return SPFAPIJourney?
local function CorpseJourney()
	local title, _, plan, index = ns.Corpse.Info()
	local point = ns.Corpse.Point()
	local goal = point and JourneyPlace(point)
	if not (title and plan and goal and index) then
		return nil
	end
	goal.title = title
	return {
		owner = nil,
		goal = goal,
		legs = JourneyLegs(plan, index),
		index = index,
		guided = ns.IsJourneyGuided() == true,
		secondsLeft = ns.JourneyTime(plan.legs, index) / 1000,
	}
end

-- The journey under way, whoever owns it. Every table is new, and a search still working on its first plan has
-- nothing to read yet, exactly as the tracker shows a spinner.
---@return SPFAPIJourney?, SPFAPINotReady?
function API.Journey()
	if not Loaded() then
		return Loading()
	end
	if ns.Corpse and ns.Corpse.Active() then
		local run = CorpseJourney()
		if run then
			return run
		end
		-- A run with no corpse place or plan has nothing to read: the tracker likewise shows no run until it can.
		return Loading()
	end
	local goal = ns.JourneyGoal()
	if not goal then
		return None()
	end
	local plan, index = ns.JourneyPlan()
	index = index or 1
	if not plan and select(4, ns.JourneyStatus()) then
		return Loading()
	end
	local place = JourneyPlace(goal)
	if not place then
		return None()
	end
	return {
		owner = ns.JourneyOwner(),
		goal = place,
		legs = plan and JourneyLegs(plan, index) or {},
		index = index,
		guided = ns.IsJourneyGuided() == true,
		secondsLeft = plan and ns.JourneyTime(plan.legs, index) / 1000 or 0,
	}
end

-- Only the owner may steer its journey, and only while the player is alive to be guided: a corpse run is the
-- player's own guidance and the owner's journey waits behind it.
---@param owner string
---@return boolean
local function Steerable(owner)
	return Owner(owner)
		and route ~= nil
		and route.owner == owner
		and ns.JourneyGoal() ~= nil
		and not (ns.Corpse and ns.Corpse.Active())
end

-- Stop guidance and keep the goal and route, the state the tracker's guidance switch leaves when turned off. The
-- goal's pin turns bronze and the route waits for Resume.
---@param owner string
---@return boolean
function API.Pause(owner)
	if not (Loaded() and not InCombatLockdown() and Steerable(owner)) or not ns.IsJourneyGuided() then
		return false
	end
	ns.ToggleJourneyGuide()
	return true
end

-- Start guidance again on the same goal, as the tracker's Journeys switch does.
---@param owner string
---@return boolean
function API.Resume(owner)
	if not (Loaded() and not InCombatLockdown() and Steerable(owner)) or ns.IsJourneyGuided() then
		return false
	end
	ns.ToggleJourneyGuide()
	return true
end

-- Advance the leg under way, through the same step the tracker's leg menu takes. index is optional and, when given,
-- must name the current leg.
---@param owner string
---@param index? integer
---@return boolean
function API.SkipLeg(owner, index)
	if not (Loaded() and Steerable(owner)) or (index ~= nil and not (Number(index) and index % 1 == 0)) then
		return false
	end
	return ns.SkipJourneyStep(index) == true
end

-- Relabel a running route's stop in place: a guide renames a step whose position did not move, which must not cost a
-- replan. renamePoints says which later stops are that same place, so they keep the name too. The titles only a
-- multi-stop route draws stay as they were.
---@param owner string
---@param index integer the stop to rename, usually API.CurrentStop
---@param title string
---@param renamePoints? fun(point: SPFPoint): boolean?
---@return boolean
function API.RenameStop(owner, index, title, renamePoints)
	if not Owner(owner) or not route or route.owner ~= owner or type(title) ~= "string" then
		return false
	end
	if (title ~= "" and not canaccessvalue(title)) or not route.points[index] then
		return false
	end
	-- Our own points, written before the guard above saw them: nothing to re-read here.
	local current, shares = route.points[index], nil
	if renamePoints then
		shares = {}
		for _, point in ipairs(route.points) do
			shares[point] = not not renamePoints(point)
		end
	end
	for _, point in ipairs(route.points) do
		if point == current or (shares and shares[point]) then
			point.label = title
		end
	end
	ns.JourneyRelabeled()
	return true
end

-- A guide's step moved on without moving the player (a turn-in at the same NPC): the stop under way now stands for
-- other quests. Its lines are read live from the client, so only the stop's quest list and any action lines change.
-- Not part of the public API: the Guidelime, RestedXP and TomTom bridges use it to keep a stop's objectives current.
---@param owner string
---@param index integer the stop to update, usually API.CurrentStop
---@param quests? number[] the quests the stop now stands for; nil clears them
---@param details? string[] the stop's own action lines, as API.NavigateRoute's tooltip gives them; nil clears them
---@return boolean
function ns.SetStopQuests(owner, index, quests, details)
	if not Owner(owner) or not route or route.owner ~= owner then
		return false
	end
	local point = route.points[index]
	if not point then
		return false
	end
	local ids
	if quests ~= nil then
		if type(quests) ~= "table" or not Quests(quests) then
			return false
		end
		ids = {}
		for quest = 1, #quests do
			ids[quest] = quests[quest]
		end
	end
	local lines
	if details ~= nil then
		if type(details) ~= "table" then
			return false
		end
		lines = {}
		for line = 1, #details do
			if type(details[line]) ~= "string" then
				return false
			end
			lines[line] = details[line]
		end
		if not lines[1] then
			lines = nil
		end
	end
	point.questIDs, point.questID, point.details = ids, nil, lines
	-- The map's marks, the game's quest pins it hides and the arrow all read the stop's quests. RefreshRouteLines
	-- repaints the map and minimap without replanning; the arrow re-reads its lines.
	if ns.RefreshRouteLines then
		ns.RefreshRouteLines()
	end
	if ns.RefreshArrowLines then
		ns.RefreshArrowLines()
	end
	return true
end

function API.Ended(owner)
	if not Loaded() then
		return Loading()
	end
	local entry = Owner(owner) and ended[owner]
	if entry then
		return entry.reason, entry.at
	end
	return None()
end

-- Core/Progress.lua's travel journal, by the field its snapshot keeps. The API names the metrics and Progress keeps
-- the totals; the journal records no event time, so eventUnix is left out rather than invented.
local TRAVEL_METRICS = {
	{ metric = "distance_yards", field = "walkedYards" },
	{ metric = "routes_completed", field = "routesCompleted" },
	{ metric = "transports_used", field = "transportsUsed" },
	{ metric = "flights_taken", field = "flightsTaken" },
	{ metric = "portals_used", field = "portalsUsed" },
}

-- This character's own travel records, one fresh row per metric (Core/Progress.lua keeps them).
---@return SPFAPIStat[]?, SPFAPINotReady?
function API.Stats()
	if not Loaded() then
		return Loading()
	end
	local stats = ns.TravelStats()
	if not stats then
		return Loading()
	end
	local rows = {}
	for index, entry in ipairs(TRAVEL_METRICS) do
		rows[index] = {
			addon = "ShortestPathForever",
			metric = entry.metric,
			subject = "all",
			value = stats[entry.field],
		}
	end
	return rows
end

API.Subscribe = hub.Subscribe

-- Anyone's journey counts, the player's own included, so a caller can ask before replacing it.
function API.Active()
	return ns.IsJourneyGuided() == true
end

ShortestPathForever = ShortestPathForever or {}
ShortestPathForever.API = API
if (ForeverCore.APIKit.minor or 1) >= 2 then
	ForeverCore.APIKit.Publish("ShortestPathForever", API)
end

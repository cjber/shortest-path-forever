---@class SPFNamespace
local ns = select(2, ...)
local L = ns.L

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

local function QuestID(questID)
	return Number(questID) and questID % 1 == 0 and questID >= 1
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
		if not Number(key) or key % 1 ~= 0 or key < 1 or key > count or not QuestID(questID) then
			return false
		end
	end
	return true
end

local function Ready()
	return ns.db and ns.charDB and not InCombatLockdown()
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

---@param point SPFPoint?
---@param reason? "arrived"|"cleared" -- why a nil point ended the journey
function ns.JourneyChanged(point, reason)
	if not route then
		return
	end
	if point and point == route.points[route.index + 1] then
		route.index = route.index + 1
	elseif not point or point ~= route.points[route.index] then
		ended[route.owner] = { reason = point and "replaced" or reason or "cleared", at = GetTime() }
		route = nil
	else
		return
	end
	ns.ItineraryChanged()
end

---@param point SPFPoint
---@return SPFPoint?
function ns.NextJourneyStop(point)
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
local API = { version = 1 }

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

-- The reason tells a caller whether asking again later can help: "combat" after combat, "invalid" never for bad
-- input (only if the addon had not loaded yet), "unreachable" when known flight paths or boat timings change.
local function Lookup(fromMap, fromX, fromY, toMap, toX, toY)
	if not Ready() then
		return nil, InCombatLockdown() and "combat" or "invalid"
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
			or (stop.questID ~= nil and not QuestID(stop.questID))
			or (stop.questIDs ~= nil and (type(stop.questIDs) ~= "table" or not Quests(stop.questIDs)))
			or (stop.shapes ~= nil and (type(stop.shapes) ~= "table" or not Shapes(stop.shapes)))
		then
			return false
		end
		local point = Point(stop.map, stop.x, stop.y)
		if not point then
			return false
		end
		point.label = stop.title
		point.tooltip = stop.tooltip
		-- A caller such as Adventure Guide may need the route to remain visible while the
		-- player completes an interaction at this location. It resubmits the route after
		-- that state changes; ordinary API stops retain automatic arrival.
		point.hold = stop.hold == true
		point.radius = stop.radius
		point.questID = stop.questID
		-- The quests whose client blobs the stop stands for, copied; StopInside prefers the client's own answer for them.
		if stop.questID or stop.questIDs then
			point.questIDs = { stop.questID }
			for _, questID in ipairs(stop.questIDs or {}) do
				if questID ~= stop.questID then
					point.questIDs[#point.questIDs + 1] = questID
				end
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
		if count > 1 then
			local location = not point.label and ns.Locate(point)
			point.routeTitle = string.format(
				L["Stop %d of %d: %s"],
				index,
				count,
				point.label or location and location.zone or UNKNOWN
			)
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
	return Owner(owner) and route and route.owner == owner and route.index or nil
end

function API.Cancel(owner)
	if not API.CurrentStop(owner) then
		return false
	end
	ns.ClearJourney()
	ended[owner] = { reason = "cancelled", at = GetTime() }
	return true
end

function API.Ended(owner)
	local entry = Owner(owner) and ended[owner]
	if entry then
		return entry.reason, entry.at
	end
end

-- Anyone's journey counts, the player's own included, so a caller can ask before replacing it.
function API.Active()
	return ns.IsJourneyGuided() == true
end

ShortestPathForever = ShortestPathForever or {}
ShortestPathForever.API = API

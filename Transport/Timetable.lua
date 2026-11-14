---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L
local Model = ns.Model

-- The live timetable: the sightings this realm's boats were last timed by, and every answer read off them now:
-- when a route calls at a stop, what leaves a dock, where the ride you are on stops next, and how a departure
-- reads. Model.lua is the arithmetic and the planner takes sightings as plain data (Anchors); everything else
-- asks here, so the saved shape and the clock-to-phase step each have one home.
---@class SPFTimetable
local Timetable = {}
ns.Timetable = Timetable

-- Saved as ShortestPathForeverDB.anchors[routeID] = { epoch = server ms at phase 0, seen = server s }, one table
-- for the account: Forever is one server for every ruleset. Nothing outside this file reads it.
local function Store()
	local saved = ns.db.anchors
	if not saved then
		saved = {}
		ns.db.anchors = saved
	end
	return saved
end

-- Where in its loop a route is at server time `at` (ms).
local function Phase(route, anchor, at)
	return (at - anchor.epoch) % route.period
end

local listeners, version = {}, 0
-- Called after every sighting that changes the timetable.
---@param fn fun()
function Timetable.OnChange(fn)
	listeners[#listeners + 1] = fn
end

-- Counts those changes, for a caller that only needs to know whether its last reading still stands.
---@return number
function Timetable.Version()
	return version
end

-- Record a sighting unless the one held should stand.
---@param routeID number
---@param anchor SPFAnchor
---@return boolean
function Timetable.Sighted(routeID, anchor)
	local store = Store()
	if not Model.Newer(anchor, store[routeID]) then
		return false
	end
	store[routeID] = { epoch = anchor.epoch, seen = anchor.seen }
	version = version + 1
	for _, fn in ipairs(listeners) do
		fn()
	end
	return true
end

-- The route's sighting, kept until a newer sighting replaces it.
---@param routeID number
---@return SPFAnchor?
function Timetable.Anchor(routeID)
	return Store()[routeID]
end

-- Every sighting, as the plain data the planner takes.
---@return table<number, SPFAnchor>
function Timetable.Anchors()
	local anchors = {}
	for routeID, anchor in pairs(Store()) do
		anchors[routeID] = anchor
	end
	return anchors
end

-- The route's next visit of `stop` as of server time `at` (ms): Model.Visit's answer, or nothing while the
-- route is untimed.
---@param routeID number
---@param stop SPFStop
---@param at number
---@return boolean? docked, number? arriveIn, number? departIn
function Timetable.Visit(routeID, stop, at)
	local anchor = Timetable.Anchor(routeID)
	if not anchor then
		return nil
	end
	local route = ns.Routes[routeID]
	return Model.Visit(route, stop, Phase(route, anchor, at))
end

-- Timetable topology never changes with sightings; build it only when a dock first needs it.
local dockVisits = {}
-- Every call any route makes at a dock, shown or not: { route = routeID, stop = its stop, to = docks onward }.
---@param dockID number
---@return {route: number, stop: SPFStop, to: number[]}[]
function Timetable.Visits(dockID)
	if not dockVisits[dockID] then
		local visits = {}
		for routeID, route in pairs(ns.Routes) do
			for index, stop in ipairs(route.stops) do
				if stop.dock == dockID then
					visits[#visits + 1] = { route = routeID, stop = stop, to = Model.Onward(route, index) }
				end
			end
		end
		dockVisits[dockID] = visits
	end
	return dockVisits[dockID]
end

local function SoonestFirst(a, b)
	if a.known ~= b.known then
		return a.known
	end
	return (a.departIn or 0) < (b.departIn or 0) or (a.departIn == b.departIn and a.route < b.route)
end

-- What leaves a dock on the routes you are shown, soonest first, the untimed ones last.
---@param dockID number
---@return SPFDeparture[]
function Timetable.Departures(dockID)
	local departures, now, serverNow, store = {}, ns.NowMs(), GetServerTime(), Store()
	for _, visit in ipairs(Timetable.Visits(dockID)) do
		local routeID = visit.route
		local route = ns.Routes[routeID]
		if ns.RouteShown(route) then
			local anchor = store[routeID]
			local departure = { route = routeID, kind = route.kind, to = visit.to, known = false }
			if anchor then
				departure.known = true
				departure.docked, departure.arriveIn, departure.departIn =
					Model.Visit(route, visit.stop, Phase(route, anchor, now))
				departure.seen = serverNow - anchor.seen
			end
			departures[#departures + 1] = departure
		end
	end
	table.sort(departures, SoonestFirst)
	return departures
end

-- A dock's departures, one line per destination. Boats sharing a lane (Auberdine's two Menethil boats, a lift's
-- two cars) read as one line: the soonest, with when the one after it leaves once both are timed.
---@param dockID number
---@return SPFDeparture[]
function Timetable.ByDestination(dockID)
	local merged, first = {}, {}
	for _, departure in ipairs(Timetable.Departures(dockID)) do
		local labels = {}
		for _, toDock in ipairs(departure.to) do
			labels[#labels + 1] = ns.DockLabel(toDock)
		end
		local key = table.concat(labels, ",")
		local lead = first[key]
		if not lead then
			first[key] = departure
			merged[#merged + 1] = departure
		elseif lead.known and departure.known and not lead.thenIn then
			lead.thenIn = departure.departIn
		end
	end
	return merged
end

-- Where the route being ridden calls next, and in how many ms, when its schedule is known.
---@param routeID number
---@return number? dockID, number? arriveIn
function Timetable.NextStop(routeID)
	local anchor = Timetable.Anchor(routeID)
	if not anchor then
		return nil
	end
	local route = ns.Routes[routeID]
	local phase = Phase(route, anchor, ns.NowMs())
	local dockID, soonest
	for _, stop in ipairs(route.stops) do
		local docked, arriveIn = Model.Visit(route, stop, phase)
		if not docked and (not soonest or arriveIn < soonest) then
			dockID, soonest = stop.dock, arriveIn
		end
	end
	return dockID, soonest
end

-- Where a departure goes, every call in order.
---@param departure SPFDeparture
---@return string
function Timetable.Destination(departure)
	local text
	for _, dockID in ipairs(departure.to) do
		text = text and string.format(L["%s, then %s"], text, ns.DockLabel(dockID)) or ns.DockLabel(dockID)
	end
	return text or ""
end

local HERE = { boat = L["docked"], zeppelin = L["docked"], lift = L["here"], tram = L["boarding"] }

-- When a departure is here and when it leaves, as the tooltip and the tracker word it.
---@param departure SPFDeparture
---@return string
function Timetable.Status(departure)
	if not departure.known then
		return L["no sighting yet"]
	end
	local leaves = departure.thenIn
			and string.format(
				L["leaves %s, then %s"],
				Model.FormatCountdown(departure.departIn),
				Model.FormatCountdown(departure.thenIn)
			)
		or string.format(L["leaves %s"], Model.FormatCountdown(departure.departIn))
	if departure.docked then
		return string.format(L["%s · %s"], HERE[departure.kind], leaves)
	end
	return string.format(
		L["%s · %s"],
		string.format(L["arrives %s"], Model.FormatCountdown(departure.arriveIn)),
		leaves
	)
end

-- Older saves kept sightings per realm, and the retired swap stored other players' sightings among them. On load,
-- keep the newest sighting of each route that is yours, drop the realm level, and forget who reported it.
ns.Init(function()
	local saved = ns.db.anchors
	if type(saved) ~= "table" then
		ns.db.anchors = {}
		return
	end
	local best, realms = {}, {}
	for key, value in pairs(saved) do
		if type(key) == "string" and type(value) == "table" and value.epoch == nil then
			realms[#realms + 1] = key
			for routeID, anchor in pairs(value) do
				if
					type(routeID) == "number"
					and type(anchor) == "table"
					and anchor.epoch
					and anchor.seen
					and rawget(anchor, "source") ~= "player"
				then
					local held = best[routeID] or saved[routeID]
					if not held or anchor.seen > held.seen then
						best[routeID] = { epoch = anchor.epoch, seen = anchor.seen }
					end
				end
			end
		end
	end
	for _, realm in ipairs(realms) do
		saved[realm] = nil
	end
	for routeID, anchor in pairs(best) do
		saved[routeID] = anchor
	end
	-- The source field belonged to the retired swap; a sighting it marks as another player's goes, and every one
	-- kept here is the player's own.
	for routeID, anchor in pairs(saved) do
		if type(routeID) == "number" and type(anchor) == "table" then
			if rawget(anchor, "source") == "player" then
				saved[routeID] = nil
			else
				rawset(anchor, "source", nil)
			end
		end
	end
end)

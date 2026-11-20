---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- What a plan starts from, read from the client and the shipped data in one place: your run speed, faction, known
-- flight points, fresh sightings, usable teleports and the ride you are on, plus the static tables every plan
-- crosses. The journey search, the estimate, the bind-point landings and the corpse run ask here; Planner.lua's wide
-- option table stays the planner's own interface, filled by Options.
---@class SPFPlanContext
local Context = {}
ns.PlanContext = Context

local lastSpeed = 7
-- Stable identities let the planner reuse its walking topology between frames.
local empty = {}
local routeSource, routeFaction, unguarded

-- Landing guards affect boarding safety, not physical ownership. Keep landings as walking destinations.
-- Stable identities let journeys and estimates reuse topology until the route source or faction changes.
local function Routes(faction)
	if routeSource ~= ns.Routes or routeFaction ~= faction then
		routeSource, routeFaction, unguarded = ns.Routes, faction, {}
		local excluded = false
		for id, route in pairs(ns.Routes or {}) do
			if not route.guardedFaction or route.guardedFaction == faction then
				unguarded[id] = route
			else
				excluded = true
			end
		end
		if not excluded then
			unguarded = ns.Routes
		end
	end
	return unguarded
end

-- Run speed stays meaningful while standing still. Secret combat values retain the last readable speed.
---@return number
function Context.RunSpeed()
	local _, speed = GetUnitSpeed("player")
	if canaccessvalue(speed) and type(speed) == "number" and speed > 0 and speed < math.huge then
		lastSpeed = speed
	end
	return lastSpeed
end

-- The inputs every plan from here shares, read now. The caller adds what is its own: cache (topology is never
-- shared between callers), waterWalking, and the journey's ride and measured walks. teleportReady is as the client
-- reports it for where you stand; a caller planning from elsewhere clears it.
---@class SPFContextOptions : SPFPlanOptions
---@field taxiKnown table<number, boolean>
---@field anchors table<number, SPFAnchor>
---@field teleports SPFTeleportPlace[]
---@field teleportReady table<number, number>
---@field teleportState table<number, number>
---@field partyPortals SPFPartyPortal[]
---@field routePolicy? SPFRoutePolicy

---@param from SPFPoint
---@param to SPFPoint
---@param policy? SPFRoutePolicy
---@return SPFContextOptions
function Context.Options(from, to, policy)
	local now = ns.NowMs()
	local walking = policy == "walking"
	local teleports, ready, state, partyPortals
	if not walking then
		teleports, ready, state = ns.UsableTeleports(now)
		partyPortals = ns.PartyPortalPlaces and ns.PartyPortalPlaces(from) or nil
	end
	local faction = UnitFactionGroup("player")
	return {
		routePolicy = walking and "walking" or nil,
		class = select(2, UnitClass("player")),
		from = from,
		to = to,
		now = now,
		walkSpeed = Context.RunSpeed(),
		faction = faction,
		otherFaction = ns.db and ns.db.otherFaction or false,
		taxiKnown = walking and empty or ns.KnownTaxiNodes(),
		anchors = walking and empty or ns.Timetable.Anchors(),
		docks = walking and empty or ns.Docks,
		routes = walking and empty or Routes(faction),
		taxiNodes = walking and empty or ns.TaxiNodes,
		taxiPaths = walking and empty or ns.TaxiPaths,
		taxiTimes = walking and empty or ns.TaxiTimes and ns.TaxiTimes.Snapshot(),
		portals = walking and empty or ns.Portals,
		teleports = walking and empty or teleports,
		teleportReady = walking and empty or ready,
		teleportState = walking and empty or state or empty,
		partyPortals = walking and empty or partyPortals,
		hearthMinimumSavings = ns.db and ns.db.hearthMinimumSavings or 0,
		teleportMinimumSavings = ns.db and ns.db.teleportMinimumSavings or 0,
		landmasses = ns.Landmasses,
		baked = ns.Walks,
	}
end

-- The transport you are aboard and where it next stops, for a plan from where you stand.
---@param options SPFContextOptions from Options, planned from where you stand
---@return SPFCurrentRide?
function Context.Ride(options)
	if options.routePolicy == "walking" then
		return nil
	end
	local here, now = options.from, options.now
	local routeID = ns.CurrentRide()
	if not routeID then
		return nil
	end
	if ns.Timetable.Anchor(routeID) then
		for _, stop in ipairs(ns.Routes[routeID].stops) do
			-- The observer retains a ride for 30 seconds after disembarking, enough to run 210 yards away.
			local dock = ns.Docks[stop.dock]
			if
				ns.Timetable.Visit(routeID, stop, now)
				and here.map == dock.map
				and (here.x - dock.x) ^ 2 + (here.y - dock.y) ^ 2 <= 250 ^ 2
			then
				return nil
			end
		end
	end
	local dock, arriveIn = ns.Timetable.NextStop(routeID)
	-- Already aboard is separate from boarding eligibility: restrictions must still let this ride alight.
	return dock and { route = routeID, dock = dock, arrive = now + arriveIn, data = (ns.Routes or {})[routeID] } or nil
end

-- The fixed places your faction can use, with these teleport destinations (none for a bind point's own landing).
---@param teleports? SPFTeleportPlace[]
---@param partyPortals? SPFPartyPortal[]
---@param policy? SPFRoutePolicy
---@return SPFPlace[] places, string faction the faction they were chosen for
function Context.Places(teleports, partyPortals, policy)
	local faction = UnitFactionGroup("player")
	local walking = policy == "walking"
	return ns.Planner.Places({
		docks = walking and empty or ns.Docks,
		taxiNodes = walking and empty or ns.TaxiNodes,
		portals = walking and empty or ns.Portals,
		teleports = walking and empty or teleports,
		partyPortals = walking and empty or partyPortals,
		faction = faction,
		class = select(2, UnitClass("player")),
	}),
		faction
end

---@param point SPFPoint
---@return number?
function Context.Landmass(point)
	return ns.Planner.Landmass(point, ns.Landmasses or {})
end

---@param leg SPFLeg
---@return SPFWalkPoints
function Context.LegPoints(leg)
	return ns.Planner.LegPoints(leg, ns.Routes)
end

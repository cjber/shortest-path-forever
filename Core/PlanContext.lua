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
---@return SPFAvoidedTransport[]
function Context.Avoided()
	return ns.charDB and ns.charDB.avoided or empty
end

---@param path SPFTaxiPath
---@return string
function Context.TaxiHopID(path)
	return path.from .. ":" .. path.to
end

-- The planner's portal index addresses baked walks. Persist the named entrance instead.
---@param portal SPFPortal
---@return string
function Context.PortalID(portal)
	local from = portal.from
	return ("%d:%.17g:%.17g:%s:%s"):format(from.map, from.x, from.y, portal.kind, portal.name)
end

-- Each edit replaces the saved list. Its identity versions the filtered tables, which in turn version
-- the planner topology and the public estimate cache.
local routeSource, taxiSource, portalSource, routeFaction, version
local routes, taxiPaths, portals

local function Transport(faction)
	local avoided = Context.Avoided()
	if
		routeSource == ns.Routes
		and taxiSource == ns.TaxiPaths
		and portalSource == ns.Portals
		and routeFaction == faction
		and version == avoided
	then
		return routes, taxiPaths, portals
	end
	routeSource, taxiSource, portalSource, routeFaction, version = ns.Routes, ns.TaxiPaths, ns.Portals, faction, avoided
	local excludedRoutes, excludedHops, excludedPortals = {}, {}, {}
	for _, entry in ipairs(avoided) do
		local excluded = entry.kind == "flight" and excludedHops
			or (entry.kind == "portal" or entry.kind == "passage") and excludedPortals
			or excludedRoutes
		for _, id in ipairs(entry.ids) do
			excluded[id] = true
		end
	end
	routes, taxiPaths, portals = routeSource, taxiSource, portalSource
	for id, route in pairs(routeSource or empty) do
		-- Landing guards and avoids affect boarding. The dock remains a walking destination.
		if excludedRoutes[id] or (route.guardedFaction and route.guardedFaction ~= faction) then
			routes = {}
			break
		end
	end
	if routes ~= routeSource then
		for id, route in pairs(routeSource) do
			if not excludedRoutes[id] and (not route.guardedFaction or route.guardedFaction == faction) then
				routes[id] = route
			end
		end
	end
	if next(excludedHops) and taxiSource then
		taxiPaths = {}
		for _, path in ipairs(taxiSource) do
			if not excludedHops[Context.TaxiHopID(path)] then
				taxiPaths[#taxiPaths + 1] = path
			end
		end
	end
	if next(excludedPortals) and portalSource then
		local remaining, matched = {}, false
		for id, portal in ipairs(portalSource) do
			if excludedPortals[Context.PortalID(portal)] then
				matched = true
			else
				-- Keep the original keys: baked walks address portal endpoints by these IDs.
				remaining[id] = portal
			end
		end
		if matched then
			portals = remaining
		end
	end
	return routes, taxiPaths, portals
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
	local useRoutes, useTaxiPaths, usePortals = empty, empty, empty
	if not walking then
		useRoutes, useTaxiPaths, usePortals = Transport(faction)
	end
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
		routes = useRoutes,
		taxiNodes = walking and empty or ns.TaxiNodes,
		taxiPaths = useTaxiPaths,
		taxiTimes = walking and empty or ns.TaxiTimes and ns.TaxiTimes.Snapshot(),
		portals = usePortals,
		teleports = walking and empty or teleports,
		teleportReady = walking and empty or ready,
		teleportState = walking and empty or state or empty,
		partyPortals = walking and empty or partyPortals,
		hearthMinimumSavings = ns.db and ns.db.hearthMinimumSavings or 0,
		teleportMinimumSavings = ns.db and ns.db.teleportMinimumSavings or 0,
		landmasses = ns.Landmasses,
		baked = ns.Walks,
		bakedZones = ns.WalkZones,
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
	local usePortals = empty
	if not walking then
		usePortals = select(3, Transport(faction))
	end
	return ns.Planner.Places({
		docks = walking and empty or ns.Docks,
		taxiNodes = walking and empty or ns.TaxiNodes,
		portals = usePortals,
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

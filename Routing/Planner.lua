---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

local Model = ns.Model
---@class SPFPlanner
local Planner = {}
ns.Planner = Planner

-- Talking to the flight master and picking the destination. Taxis leave at once, so this is part of the flight's
-- time, never a wait.
local BOARDING = 3000
-- Every teleport here changes zone or recalls to a bind point, so it shows a loading screen: the same allowance as a
-- portal's.
local LOADING = 5000
-- A Hearthstone spends a long cooldown, so it must save at least 20 s over walking before it is chosen.
local HEARTH_MINIMUM_SAVING = 20
-- A journey that would be one walk of at least LONG_WALK takes a ride instead when that arrives within RIDE_MARGIN
-- of the walk's time and spends less than half its elapsed time walking (#1102).
local LONG_WALK, RIDE_MARGIN = 600000, 1.1

---@param node SPFPoint
---@param landmasses SPFLandmass[]
---@return number?
function Planner.Landmass(node, landmasses)
	for index, land in ipairs(landmasses) do
		if
			node.map == land.map
			and node.x >= land.minX
			and node.x <= land.maxX
			and node.y >= land.minY
			and node.y <= land.maxY
		then
			return index
		end
	end
end

local function Eligible(node, options)
	return (not node.faction or node.faction == options.faction) and (not node.class or node.class == options.class)
end

local function Keys(values)
	local keys = {}
	for key in pairs(values) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

local function Gap(a, b)
	local dz = a.z and b.z and a.z - b.z or 0
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + dz ^ 2)
end

local function PointKey(point)
	return string.format(
		"%d:%.17g:%.17g:%s",
		point.map,
		point.x,
		point.y,
		point.z and string.format("%.17g", point.z) or ""
	)
end

-- Endpoint batches supply exact costs or lower bounds in running yards. Index once per plan: repeatedly
-- scanning every measurement for every edge made frequent bounded plans more expensive than their searches.
local function WalkCost(options, a, b, index)
	local from = index[a.pointKey]
	local walk = from and from[b.pointKey]
	if walk then
		-- A feasible-only plan keeps just the walks that are known: a lower bound is no route to follow.
		if options.feasibleOnly and walk.estimated then
			return false, false
		end
		return walk.cost, walk.estimated or false, walk.apart
	end
	if options.feasibleOnly or (options.exactMaps and options.exactMaps[a.map]) then
		return false, false
	end
	if options.endpointBounds and ((a.kind == "start") ~= (b.kind == "goal")) and ns.Path.HasData(a.map) then
		-- A zero bound is not a proved transfer between walks.
		return ns.Path.LowerBound(a.map, a, b), true, true
	end
	return Gap(a, b), true
end

local NO_SHARES = {}

-- A fixed place's key in the baked walk table (Data/Walks.lua); nil for where you stand and where you are going.
local function PlaceKey(node)
	if node.kind ~= "start" and node.kind ~= "goal" then
		return node.kind .. node.id
	end
end

-- options.baked holds walks searched ahead of time between fixed places, per map; options.waterWalking picks
-- which of their two costs applies. They were searched without hazards, so options.hazards weights one by the hazards
-- on the straight way between its ends, as the walking search would weight the yards it walks inside them.
local function BakedCost(options, a, b, weigh)
	local ka, kb = a.bakedKey, b.bakedKey
	local baked = ka and kb and options.baked and options.baked[a.map]
	local key = baked and (ka < kb and ka .. " " .. kb or kb .. " " .. ka)
	local pair = key and baked[key]
	if pair then
		local mode = options.waterWalking and 2 or 1
		local yards = pair[mode + (ka > kb and pair[3] ~= nil and 2 or 0)]
		local reverse = pair[mode + (ka < kb and pair[3] ~= nil and 2 or 0)]
		local hazards = options.hazards
		if hazards and (yards or reverse) then
			weigh() -- a walk with no baked zone shares samples the zone map along its way
			-- A map's baked shares cover every baked walk on it; one it leaves out crosses nothing charged.
			local shares = options.bakedZones and options.bakedZones[a.map]
			local factor = hazards.Segment(a.map, a.x, a.y, b.x, b.y, shares and (shares[key] or NO_SHARES))
			yards, reverse = yards and yards * factor, reverse and reverse * factor
		end
		return true, yards, reverse
	end
	return false
end

-- The same fixed places feed the planner and endpoint batches. Keeping their identities here
-- prevents a new dock or portal from silently retaining an estimated start/goal edge.
---@param options SPFPlaceOptions
---@return SPFPlace[]
function Planner.Places(options)
	local places = {}
	local function add(kind, id, point, label)
		places[#places + 1] = {
			kind = kind,
			id = id,
			map = point.map,
			x = point.x,
			y = point.y,
			z = point.z,
			label = label or point.label,
		}
	end
	for _, id in ipairs(Keys(options.docks or {})) do
		local dock = options.docks[id]
		add("dock", id, dock.walk or dock)
	end
	for _, id in ipairs(Keys(options.taxiNodes or {})) do
		local node = options.taxiNodes[id]
		if Eligible(node, options) then
			add("taxi", id, node)
		end
	end
	for id, portal in ipairs(options.portals or {}) do
		if not portal.requires and Eligible(portal, options) then
			-- Named from the portal itself: an end inside an instance such as the Deeprun Tram has no zone to fall
			-- back on.
			add("portal", id * 2 - 1, portal.from, assert(portal.name, "every portal needs a name"))
			add("portal", id * 2, portal.to, Planner.PortalDestination(portal))
		end
	end
	-- Keyed by spell, so a fixed destination finds its baked walks. A party mage's capital portal lands on the same
	-- generated teleport destination, so it reuses that place when the character also knows the spell.
	local teleportSpells = {}
	for _, teleport in ipairs(options.teleports or {}) do
		add("teleport", teleport.spell, teleport)
		teleportSpells[teleport.spell] = true
	end
	for _, party in ipairs(options.partyPortals or {}) do
		if not teleportSpells[party.spell] then
			add("teleport", party.spell, party)
			teleportSpells[party.spell] = true
		end
	end
	return places
end

-- "Passage to Stormwind" leads to Stormwind.
function Planner.PortalDestination(portal)
	return (portal.name:gsub("^%a+ to ", ""))
end

-- A cheaper arrival only dominates another if it leaves at least the same onward choices. The no-revisit
-- rule depends on the path taken, so keeping just one arrival per travel mode can discard the fastest route.
local function Revisits(labels, current, target)
	while current do
		if labels.node[current] == target then
			return true
		end
		current = labels.parent[current]
	end
	return false
end

-- Whether anything but walking led here: a place standing where the journey starts is no ride.
local function Rode(labels, current)
	while labels.parent[current] do
		if labels.edge[current].mode ~= "walk" then
			return true
		end
		current = labels.parent[current]
	end
	return false
end

local function Subset(labels, first, second, target)
	while first do
		local node = labels.node[first]
		if node ~= target and not Revisits(labels, second, node) then
			return false
		end
		first = labels.parent[first]
	end
	return true
end

-- Only callers with immutable data tables opt in; replacing data rebuilds topology.
-- Taxi discovery is read each plan because the client mutates its known-node set in place.
local CACHE_KEYS = {
	"docks",
	"routes",
	"taxiNodes",
	"taxiPaths",
	"portals",
	"teleports",
	"partyPortals",
	"landmasses",
	"baked",
	"bakedZones",
	"taxiTimes",
	"faction",
	"class",
	"otherFaction",
	"waterWalking",
	"hazards",
}

-- A plan from its caller's own frame runs to its answer there and never yields: another addon's estimate inside a
-- secure hook can ask for one, and Lua 5.1 cannot yield across that C call (#717). A plan given its path job runs
-- there instead, pausing at the shared frame budget and going on next frame; every caller of this addon's own does
-- that. A sliced plan holds options.cache while it is paused, and any other plan meanwhile builds its own graph.
---@param options SPFPlanOptions
---@param cache table?
---@param check fun() reads the budget every CHECK_EVERY calls
---@param weigh fun() reads the budget on every call, before work that can ask the client
---@return SPFPlan?
-- Bounded label search shares topology and heap locals; splitting adds hot-path upvalues
local function Solve(options, cache, check, weigh)
	local topology = cache and cache.topology
	if topology then
		for _, key in ipairs(CACHE_KEYS) do
			local was, now = topology.options[key], options[key]
			-- A hazard profile is rebuilt for every search; its key names everything that weighs a walk.
			if key == "hazards" and was and now then
				was, now = was.key, now.key
			end
			if was ~= now then
				topology = nil
				break
			end
		end
	end
	local speed = options.walkSpeed or 7
	assert(speed > 0, "walkSpeed must be positive")
	local nodes, edges, masses = {}, {}, {}
	local docks, taxis, portals, teleports = {}, {}, {}, {}
	if topology then
		nodes, edges, masses = topology.nodes, topology.edges, topology.masses
		docks, taxis, teleports = topology.docks, topology.taxis, topology.teleports
		for index, adjacent in ipairs(edges) do
			for i = #adjacent, topology.counts[index] + 1, -1 do
				adjacent[i] = nil
			end
		end
		-- The graph is the same for every run speed; only a walking edge's duration scales. Rewriting the
		-- cached edges keeps a speed change from rebuilding the topology its identity did not depend on.
		for _, adjacent in ipairs(edges) do
			for _, edge in ipairs(adjacent) do
				if edge.yards and edge.mode == "walk" then
					edge.duration = edge.yards / speed * 1000
				end
			end
		end
	end
	local walkIndex = {}
	for _, walk in ipairs(options.walks or {}) do
		check()
		local from, to = PointKey(walk.from), PointKey(walk.to)
		walkIndex[from] = walkIndex[from] or {}
		local previous = walkIndex[from][to]
		-- An unresolved alias must not replace an exact measurement of the same physical endpoint.
		if not previous or previous.estimated or not walk.estimated then
			walkIndex[from][to] = walk
		end
	end
	local function Add(kind, id, point)
		local index = #nodes + 1
		-- The band a walk from where the player stands starts inside (Band.lua) rides along to the walk's own search.
		nodes[index] = {
			kind = kind,
			id = id,
			map = point.map,
			x = point.x,
			y = point.y,
			z = point.z,
			band = point.band,
			label = point.label,
		}
		nodes[index].pointKey = PointKey(point)
		nodes[index].bakedKey = PlaceKey(nodes[index])
		edges[index] = {}
		masses[index] = Planner.Landmass(point, options.landmasses or {})
		return index
	end

	local function Edge(from, to, edge)
		edge.to = to
		edges[from][#edges[from] + 1] = edge
	end

	local start, goal = 1, 2
	if not topology then
		Add("start", nil, options.from)
		Add("goal", nil, options.to)
		for _, place in ipairs(Planner.Places(options)) do
			check()
			local index = Add(place.kind, place.id, place)
			if place.kind == "dock" then
				docks[place.id] = index
			elseif place.kind == "taxi" then
				taxis[place.id] = index
			elseif place.kind == "teleport" then
				teleports[place.id] = index
			else
				portals[place.id] = index
			end
		end
		for id, portal in ipairs(options.portals or {}) do
			local from, to = portals[id * 2 - 1], portals[id * 2]
			if from and to then
				Edge(from, to, { mode = portal.kind, duration = portal.seconds * 1000 })
			end
		end
		for _, path in ipairs(options.taxiPaths or {}) do
			check()
			if taxis[path.from] and taxis[path.to] then
				-- A ride this character has flown overrides the shipped estimate for that directed path.
				local measured = options.taxiTimes and options.taxiTimes[path.from .. ":" .. path.to]
				Edge(taxis[path.from], taxis[path.to], {
					mode = "flight",
					path = path,
					-- A class flight master flies you by gossip, straight to its landing whether you know it or not.
					gossip = options.taxiNodes[path.from].class ~= nil or nil,
					duration = (measured or path.seconds) * 1000,
					estimated = not measured and path.estimated,
				})
			end
		end
		for _, id in ipairs(Keys(options.routes or {})) do
			local route = options.routes[id]
			for index, stop in ipairs(route.stops) do
				check()
				if docks[stop.dock] and (options.otherFaction ~= false or Eligible(route, options)) then
					for offset = 1, #route.stops - 1 do
						local onward = route.stops[(index + offset - 1) % #route.stops + 1]
						if docks[onward.dock] and onward.dock ~= stop.dock then
							Edge(docks[stop.dock], docks[onward.dock], {
								mode = route.kind,
								route = id,
								stop = stop,
								alighting = onward,
								duration = Model.RideTime(route, stop, onward),
							})
						end
					end
				end
			end
		end
		-- Fixed baked edges and the remaining dynamic pairs share one topology build.
		local pairs, groups = {}, {}
		for index = 3, #nodes do
			local map, mass = nodes[index].map, masses[index] or 0
			groups[map] = groups[map] or {}
			local group = groups[map][mass] or {}
			groups[map][mass] = group
			group[#group + 1] = index
		end
		for from = 1, #nodes do
			local endpoint = from <= 2
			local targets = endpoint and nodes or groups[nodes[from].map][masses[from] or 0]
			for index = endpoint and from + 1 or 1, #targets do
				-- a baked pair weighs the hazards on its way, so each pair counts
				check()
				local to = endpoint and index or targets[index]
				if endpoint then
					pairs[#pairs + 1], pairs[#pairs + 2] = from, to
				elseif to > from then
					local baked, yards, reverse = BakedCost(options, nodes[from], nodes[to], weigh)
					if not baked then
						pairs[#pairs + 1], pairs[#pairs + 2] = from, to
					else
						if yards then
							Edge(from, to, {
								mode = "walk",
								duration = yards / speed * 1000,
								yards = yards,
								transfer = yards == 0 or nil,
							})
						end
						if reverse then
							Edge(to, from, {
								mode = "walk",
								duration = reverse / speed * 1000,
								yards = reverse,
								transfer = reverse == 0 or nil,
							})
						end
					end
				end
			end
		end
		local counts, saved = {}, {}
		for i, adjacent in ipairs(edges) do
			check()
			counts[i] = #adjacent
		end
		for _, key in ipairs(CACHE_KEYS) do
			saved[key] = options[key]
		end
		topology = {
			nodes = nodes,
			edges = edges,
			masses = masses,
			docks = docks,
			taxis = taxis,
			teleports = teleports,
			counts = counts,
			options = saved,
			pairs = pairs,
		}
		if cache then
			cache.topology = topology
		end
	else
		-- Returned legs retain their endpoint objects; never move a previously drawn route in place.
		for i = 1, 2 do
			local point = i == 1 and options.from or options.to
			nodes[i] = {
				kind = i == 1 and "start" or "goal",
				map = point.map,
				x = point.x,
				y = point.y,
				z = point.z,
				band = point.band,
				label = point.label,
				pointKey = PointKey(point),
			}
			masses[i] = Planner.Landmass(point, options.landmasses or {})
		end
	end
	local undiscovered = false
	for id, index in pairs(taxis) do
		-- A class flight master has no discovery: every character it serves has it.
		local known = options.taxiKnown == nil or options.taxiKnown[id] and true or options.taxiNodes[id].class ~= nil
		nodes[index].undiscovered = not known
		if not known then
			undiscovered = true
		end
	end

	local ride = options.ride
	local rideRoute = ride and (ride.data or (options.routes or {})[ride.route])
	if ride and docks[ride.dock] and rideRoute then
		local route = rideRoute
		for _, stop in ipairs(route.stops) do
			if stop.dock == ride.dock then
				Edge(start, docks[ride.dock], {
					mode = route.kind,
					route = ride.route,
					aboard = true,
					alighting = stop,
					duration = math.max(0, ride.arrive - options.now),
				})
				break
			end
		end
	end
	-- Teleports leave from where you stand, once each is ready: its cooldown is a wait, like a boat's.
	local ready = options.teleportReady or {}
	for id, teleport in ipairs(options.teleports or {}) do
		if ready[id] and teleports[teleport.spell] then
			Edge(start, teleports[teleport.spell], {
				mode = "teleport",
				teleport = teleport,
				ready = ready[id],
				duration = teleport.cast + LOADING,
			})
		end
	end
	-- A party mage's portal starts where you stand: no walking leg to a portal object, just the ask and the cast.
	for _, party in ipairs(options.partyPortals or {}) do
		local index = teleports[party.spell]
		if index then
			Edge(start, index, {
				mode = "teleport",
				teleport = party,
				partyPortal = party,
				duration = party.cast + LOADING,
			})
		end
	end
	-- The walk straight from the start to the goal pays the charge on the goal's high-level zone (Hazards.Profile).
	local direct
	for pair = 1, #topology.pairs, 2 do
		check()
		local from, to = topology.pairs[pair], topology.pairs[pair + 1]
		local a, b = nodes[from], nodes[to]
		if a.map == b.map and masses[from] == masses[to] and not (ride and from == start) then
			for direction = 1, 2 do
				local first, last = direction == 1 and from or to, direction == 1 and to or from
				local origin, destination = nodes[first], nodes[last]
				local yards, estimated, apart
				if first ~= goal and last ~= start then
					yards, estimated, apart = WalkCost(options, origin, destination, walkIndex)
				end
				if yards then
					local factor = 1
					if first == start and last == goal and options.hazards and options.hazards.goalZone then
						factor = options.hazards.Direct(origin.map, origin.x, origin.y, destination.x, destination.y)
					end
					local edge = {
						mode = "walk",
						duration = yards * factor / speed * 1000,
						yards = yards,
						estimated = estimated,
						-- Zero yards join two walks unless the walk's batch knows the ends are on different nodes: an
						-- estimate of zero is then only a lower bound on a real walk.
						transfer = yards == 0 and not apart or nil,
					}
					Edge(first, last, edge)
					if factor > 1 then
						direct = edge
					end
				end
			end
		end
	end
	-- Keep arrivals on foot separate from transit and flight. Splitting a continuous walk at arbitrary places
	-- invents fresh straight-line shortcuts around a measured detour (or a blocked walk), so it must be one search.
	-- Zero-length transfers still connect co-located places and break a flight for boarding costs.
	local count = #nodes
	-- A fourth copy of the nodes marks the one unknown flight point this route walked up to and learned in person.
	-- Only that departure may then fly: every landing and connecting point still comes from the known set.
	local FLIGHT, WALKED, LEARNED = count, count * 2, count * 3
	-- Ignoring arrival modes and revisits gives an admissible remaining-time bound. It keeps the extra
	-- labels needed for correctness from exploring unrelated routes before reaching the destination.
	local backward, lower, done = {}, { [goal] = 0 }, {}
	---@type table<number, SPFAnchor>?
	local anchors = options.anchors
	for from, adjacent in ipairs(edges) do
		check()
		for _, edge in ipairs(adjacent) do
			local duration = edge.duration
			if edge.route and not edge.aboard and not (anchors and anchors[edge.route]) then
				duration = duration + options.routes[edge.route].period / 2
			end
			backward[edge.to] = backward[edge.to] or {}
			local list = backward[edge.to]
			list[#list + 1], list[#list + 2] = from, duration
		end
	end
	for _ = 1, count do
		check()
		local current, best
		for node, cost in pairs(lower) do
			if not done[node] and (not best or cost < best) then
				current, best = node, cost
			end
		end
		if not current then
			break
		end
		done[current] = true
		local adjacent = backward[current] or {}
		for i = 1, #adjacent, 2 do
			local node, cost = adjacent[i], best + adjacent[i + 1]
			if not lower[node] or cost < lower[node] then
				lower[node] = cost
			end
		end
	end
	local function NewLabels()
		return {
			node = {},
			state = {},
			time = {},
			walking = {},
			key = {},
			parent = {},
			edge = {},
			depart = {},
			wait = {},
			estimated = {},
			discarded = {},
		}
	end
	local function Search(withoutHearth, withoutTeleports, cutoff, ridden, assumeKnown, ownLabels)
		local labels
		if ownLabels then
			labels = NewLabels()
		else
			labels = topology.labels or NewLabels()
			for i = 1, labels.count or 0 do
				labels.discarded[i], labels.edge[i], labels.walking[i] = nil, nil, nil
			end
			topology.labels = labels
		end
		labels.node[1], labels.state[1], labels.time[1] = start, start, options.now
		labels.walking[1] = 0
		local walkingLimit = ridden and (cutoff - options.now) / 2
		labels.key[1], labels.parent[1] = options.now + (lower[start] or math.huge), nil
		local labelCount = 1
		labels.count = 1
		local states, heap = { [start] = { 1 } }, { 1 }
		local function push(id)
			local at = #heap + 1
			while at > 1 do
				local parent = math.floor(at / 2)
				if labels.key[heap[parent]] <= labels.key[id] then
					break
				end
				heap[at], at = heap[parent], parent
			end
			heap[at] = id
		end
		local function pop()
			local first, last = heap[1], table.remove(heap)
			if #heap > 0 then
				local at = 1
				while at * 2 <= #heap do
					local child = at * 2
					if child < #heap and labels.key[heap[child + 1]] < labels.key[heap[child]] then
						child = child + 1
					end
					if labels.key[last] <= labels.key[heap[child]] then
						break
					end
					heap[at], at = heap[child], child
				end
				heap[at] = last
			end
			return first
		end
		local finishAt
		while #heap > 0 do
			check()
			local current = pop()
			if cutoff and labels.key[current] >= cutoff then
				return nil
			end
			if not labels.discarded[current] then
				local node, earliest = labels.node[current], labels.time[current]
				local state = labels.state[current]
				if node == goal then
					finishAt = current
					break
				end
				local flying = state > FLIGHT and state <= WALKED
				local walked = state > WALKED
				local learned = state > LEARNED
				-- A flight may only leave, land at or connect through flight points the character knows. Walking to
				-- an unknown flight master learns that one point in person, so only its departure may fly; every
				-- landing and connecting point still has to be known. A gossip landing is the same in-person arrival.
				local canLeaveNode = assumeKnown or not flying or not nodes[node].undiscovered
				learned = learned or (labels.edge[current] ~= nil and labels.edge[current].gossip == true)
				for _, edge in ipairs(edges[node]) do
					local canLeave = canLeaveNode
					if edge.mode == "flight" and not assumeKnown then
						local departureKnown = not nodes[node].undiscovered or learned
						if not departureKnown or (nodes[edge.to].undiscovered and not edge.gossip) then
							canLeave = false
						end
					end
					if withoutHearth and edge.teleport and edge.teleport.bind then
						canLeave = false
					end
					if withoutTeleports and edge.teleport and not edge.partyPortal and not edge.teleport.bind then
						canLeave = false
					end
					if walked and edge.mode == "walk" and not edge.transfer then
						canLeave = false
					end
					if ridden and edge.to == goal and edge.mode == "walk" and not Rode(labels, current) then
						canLeave = false
					end
					if canLeave and lower[edge.to] and not Revisits(labels, current, edge.to) then
						local wait, estimated = 0, edge.estimated or false
						if edge.route and not edge.aboard then
							local route = options.routes[edge.route]
							---@type SPFAnchor?
							local anchor = anchors and anchors[edge.route]
							if anchor then
								local _, _, departIn =
									Model.Visit(route, edge.stop, (earliest - anchor.epoch) % route.period)
								wait = departIn
							else
								wait, estimated = route.period / 2, true
							end
						elseif edge.ready then
							wait = math.max(0, edge.ready - earliest)
						end
						local depart = earliest + wait
						local finish = depart + edge.duration
						if edge.mode == "flight" and not flying then
							finish = finish + BOARDING
						end
						-- A gossip flight ends on the ground at its landing: flying on means talking to that flight master.
						local target = edge.to + (edge.mode == "flight" and not edge.gossip and FLIGHT or 0)
						if edge.mode == "walk" then
							if nodes[edge.to].undiscovered and not assumeKnown then
								-- Standing at this master is what unlocks its flights, so this arrival is the one
								-- departure the route may use while unknown.
								target = edge.to + LEARNED
							elseif walked or not edge.transfer then
								target = edge.to + WALKED
							end
						end
						local peers = states[target] or {}
						-- A label that cannot arrive before the cutoff leads nowhere, and dominates nothing that could: a peer
						-- at the same node has the same remaining bound.
						local dominated = cutoff ~= nil and finish + lower[edge.to] >= cutoff
						local walking
						if ridden and not dominated then
							walking = labels.walking[current] + (edge.mode == "walk" and finish - earliest or 0)
							-- A short flight that leaves most of the trip on foot is still a long walk (#86, #1102).
							-- Reject those goals before they can dominate a qualifying arrival (#1104).
							dominated = walking >= walkingLimit
								or (edge.to == goal and walking * 2 >= finish - options.now)
						end
						-- A ridden label dominates only by arriving at the same time with no more walking. An earlier arrival can
						-- catch an earlier boat, and the later label's wait for the next one counts as riding, so arriving first
						-- does not keep the walking share below half. At the goal there is no suffix: first and least walking wins.
						local sameTime = ridden and edge.to ~= goal
						if not dominated then
							-- The first offer only needs a valid incumbent. The exact proof retains the visited-set
							-- alternatives that this preliminary search can discard.
							for _, peer in ipairs(peers) do
								if
									not labels.discarded[peer]
									and labels.time[peer] <= finish
									and (not ridden or labels.walking[peer] <= walking)
									and (not sameTime or labels.time[peer] == finish)
									and (options.feasibleOnly or Subset(labels, peer, current, edge.to))
								then
									dominated = true
									break
								end
							end
						end
						if not dominated then
							labelCount = labelCount + 1
							labels.count = labelCount
							local id = labelCount
							labels.node[id], labels.state[id], labels.time[id] = edge.to, target, finish
							if ridden then
								labels.walking[id] = walking
							end
							labels.key[id], labels.parent[id], labels.edge[id] = finish + lower[edge.to], current, edge
							labels.depart[id], labels.wait[id], labels.estimated[id] = depart, wait, estimated
							for _, peer in ipairs(peers) do
								if
									not labels.discarded[peer]
									and finish <= labels.time[peer]
									and (not ridden or walking <= labels.walking[peer])
									and (not sameTime or finish == labels.time[peer])
									and (options.feasibleOnly or Subset(labels, id, peer))
								then
									labels.discarded[peer] = true
								end
							end
							states[target] = peers
							peers[#peers + 1] = id
							push(id)
						end
					end
				end
			end
		end
		labels.count = labelCount
		if not finishAt then
			return nil
		end
		local reversed, legs, current = {}, {}, finishAt
		local needsStart, needsGoal, pendingWalks = false, false, {}
		while labels.parent[current] do
			local edge = labels.edge[current]
			local leg = {
				mode = edge.mode,
				from = nodes[labels.node[labels.parent[current]]],
				to = nodes[labels.node[current]],
				depart = labels.depart[current],
				arrive = labels.time[current],
				wait = labels.wait[current],
				estimated = labels.estimated[current],
				route = edge.route,
				aboard = edge.aboard,
				boarding = edge.stop,
				alighting = edge.alighting,
				hops = edge.path and { edge.path } or nil,
				gossip = edge.gossip,
				yards = edge.yards,
				teleport = edge.teleport,
				partyPortal = edge.partyPortal,
				ready = edge.ready,
			}
			-- Zero-cost lower bounds may disappear from the displayed steps, but still need proof.
			if leg.mode == "walk" and leg.estimated then
				if leg.from.kind == "start" or leg.to.kind == "goal" then
					-- Its own record, so the probe costs this estimated walk, not one merged below (#1080).
					pendingWalks[#pendingWalks + 1] = { mode = "walk", from = leg.from, to = leg.to, estimated = true }
				end
				needsStart = needsStart or leg.from.kind == "start"
				needsGoal = needsGoal or (leg.to.kind == "goal" and leg.from.kind ~= "start")
			end
			reversed[#reversed + 1] = leg
			current = labels.parent[current]
		end
		for index = #reversed, 1, -1 do
			local leg, last = reversed[index], legs[#legs]
			local preceding = reversed[index + 1]
			local chained = leg.mode == "flight" and preceding.mode == "flight" and not (leg.gossip or preceding.gossip)
			if chained and last then
				last.to, last.arrive = leg.to, leg.arrive
				last.hops[#last.hops + 1] = leg.hops[1]
				-- Connecting hops stay in flight; only the initial departure pays boarding.
				last.estimated = last.estimated or leg.estimated
			elseif leg.mode == "walk" and leg.arrive == leg.depart and last and last.mode == "walk" then
				-- A zero-time walk to a place the walk before already reaches (both snap to one walking-map node)
				-- extends that walk, or it would end short of where the walk really ends.
				last.to, last.arrive = leg.to, leg.arrive
				last.yards = (last.yards or 0) + (leg.yards or 0)
				last.estimated = last.estimated or leg.estimated
				-- The old end's geometry does not reach the new one.
				last.walkPoints, last.walkDrawn, last.walkError = nil, nil, nil
			elseif leg.mode ~= "walk" or leg.arrive > leg.depart or #reversed == 1 then
				legs[#legs + 1] = leg
			end
		end
		local arrive, charged = labels.time[finishAt], nil
		if #legs == 1 and labels.edge[finishAt] == direct then
			-- The charge only weighs the choice: the walk itself takes its real time. A later search bounded by this plan
			-- compares charged labels, so it is bounded by the charged arrival.
			charged = arrive
			arrive = legs[1].depart + direct.yards / speed * 1000
			legs[1].arrive = arrive
		end
		return {
			arrive = arrive,
			charged = charged,
			legs = legs,
			needsStart = needsStart,
			needsGoal = needsGoal,
			pendingWalks = pendingWalks,
		}
	end
	-- A walk with no flight at all may still be walking only because the flight point it would use has not been
	-- discovered. Proving that needs a second search that treats every node as known: only a route it finds that
	-- both beats this one and flies is evidence the walk waits on an unknown node, not on the walk being quickest.
	-- What the savings check below drops stays dropped for every later search.
	local withoutHearth, withoutTeleports = options.withoutHearth == true, false
	local function UnknownFlightMaps(plan)
		if not plan or not options.unknownFlightNotice or not undiscovered then
			return nil
		end
		local walk = false
		for _, leg in ipairs(plan.legs) do
			if leg.mode == "flight" then
				return nil
			end
			walk = walk or leg.mode == "walk"
		end
		if not walk then
			return nil
		end
		local faster = Search(withoutHearth, withoutTeleports, plan.arrive, false, true, true)
		if not faster then
			return nil
		end
		local maps
		for _, leg in ipairs(faster.legs) do
			if leg.mode == "flight" then
				maps = maps or {}
				maps[leg.from.map] = true
			end
		end
		return maps
	end
	local function MarkUnknownFlight(plan)
		plan.unknownFlightMaps = UnknownFlightMaps(plan)
		plan.unknownFlight = plan.unknownFlightMaps and true or nil
	end
	-- options.incumbent, an arrival already in hand, ends the search for anything that cannot beat it: no route
	-- then means the incumbent stands. Its plan still passes through hearth, teleport and long-walk preferences below.
	local planned = Search(withoutHearth, withoutTeleports, options.incumbent) or options.incumbentPlan
	-- options.lowerBound asks how soon any route could arrive. The preferences below trade arrival for a cooldown or a
	-- ride, so a walk measured longer could unlock a faster route they dropped here: a bound skips them.
	if options.lowerBound then
		return planned
	end
	local hearthMinimum = math.max(options.hearthMinimumSavings or 0, HEARTH_MINIMUM_SAVING) * 1000
	local teleportMinimum = (options.teleportMinimumSavings or 0) * 1000
	---@type SPFSavingsOptions
	local savings = {
		hearthMinimum = hearthMinimum,
		teleportMinimum = teleportMinimum,
		withoutHearth = withoutHearth,
	}
	planned, withoutHearth, withoutTeleports = ns.Savings.Apply(planned, function(hearth, noTeleports, cutoff)
		return Search(hearth, noTeleports, cutoff)
	end, savings)
	-- A long way on foot is one line with nothing to follow through whatever lies between, so a ride nearly as quick
	-- wins. It never spends the hearthstone (that would trade a cooldown for a slower arrival), nor, with a minimum
	-- set, a class teleport: a ride arrives after this walk, so a teleport on it saves less than any minimum.
	if
		planned
		and #planned.legs == 1
		and planned.legs[1].mode == "walk"
		and planned.arrive - options.now >= LONG_WALK
	then
		withoutTeleports = withoutTeleports or teleportMinimum > 0
		local ridden = Search(true, withoutTeleports, options.now + (planned.arrive - options.now) * RIDE_MARGIN, true)
		if ridden then
			ridden.preferred = true
			MarkUnknownFlight(ridden)
			return ridden
		end
	end
	if planned then
		MarkUnknownFlight(planned)
		-- The charge decided it when walking straight there would have won on real time, by the same margin a long walk
		-- gives a ride, but the ride won once the yards inside the goal's zone were charged. A teleport is no ride.
		local walked = direct and direct.yards / speed * 1000
		local margin = walked and walked >= LONG_WALK and RIDE_MARGIN or 1
		local rides = #planned.legs > 1
		for _, leg in ipairs(planned.legs) do
			rides = rides and leg.mode ~= "teleport"
		end
		if walked and rides and walked * margin < planned.arrive - options.now then
			planned.rideNote = ns.Hazards.RideNote(options.hazards)
		end
	end
	return planned
end

local CHECK_EVERY = 16
local function NoCheck() end

---@param options SPFPlanOptions
---@param job SPFPathJob? the path job this plan runs in ; nil runs it whole in the caller's frame
---@return SPFPlan?
local function Plan(options, job)
	local cache = options.cache
	local holder = cache and cache.busy
	if cache and holder and holder ~= job then
		if holder.done or holder.cancelled then
			-- Its plan stopped part way: the topology it was building is not trusted.
			for key in pairs(cache) do
				cache[key] = nil
			end
		else
			cache = nil
		end
	end
	local check, weigh = NoCheck, NoCheck
	if job then
		local checkpoint, count = ns.Path.Checkpoint, 0
		weigh = checkpoint
		check = function()
			count = count + 1
			if count >= CHECK_EVERY then
				count = 0
				checkpoint()
			end
		end
		if cache then
			cache.busy = job
		end
	end
	local planned = Solve(options, cache, check, weigh)
	if cache and cache.busy == job then
		cache.busy = nil
	end
	return planned
end

Planner.Plan = Plan

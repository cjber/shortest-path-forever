-- Planner.Plan's two journey options: feasibleOnly drops every walk that is only a lower bound, and incumbent ends
-- the search for a route that cannot beat an arrival already in hand. Neither changes a plan without the option.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Savings.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/PlanBounds.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/LegPoints.lua"))("ShortestPathForever", ns)
local Plan = ns.Planner.Plan

local function point(x, y)
	return { map = 1, x = x, y = y or 0 }
end

-- A line of flight points a hundred seconds apart, joined both ways, with a walk over the same ground.
local function line(nodes)
	local taxiNodes, taxiPaths = {}, {}
	for id = 1, nodes do
		taxiNodes[id] = point(id * 1000)
		if id > 1 then
			taxiPaths[#taxiPaths + 1] = { from = id - 1, to = id, seconds = 100 }
			taxiPaths[#taxiPaths + 1] = { from = id, to = id - 1, seconds = 100 }
		end
	end
	return {
		from = point(0),
		to = point((nodes + 1) * 1000),
		now = 1000,
		walkSpeed = 7,
		faction = "Alliance",
		taxiNodes = taxiNodes,
		taxiPaths = taxiPaths,
	}
end

local function walk(from, to, cost, estimated)
	return { from = from, to = to, cost = cost, estimated = estimated }
end

local function modes(planned)
	local list = {}
	for _, leg in ipairs(planned.legs) do
		list[#list + 1] = leg.mode
	end
	return table.concat(list, ",")
end

-- feasibleOnly: no guessed walks, only measured ones.
do
	local o = line(3)
	assert(Plan(o), "the unrestricted plan walks the straight-line guess")
	o.feasibleOnly = true
	assert(not Plan(o), "no measured walk, no feasible route")
	o.walks = { walk(o.from, o.to, 4000, true) }
	assert(not Plan(o), "a lower bound is not a walk to follow")
	o.walks = { walk(o.from, o.to, 4000) }
	local planned = Plan(o)
	assert(planned and modes(planned) == "walk" and planned.legs[1].yards == 4000 and not planned.legs[1].estimated)
	assert(planned.arrive == 1000 + 4000 / 7 * 1000 and not planned.needsStart and not planned.needsGoal)
	-- A lower bound never replaces a measurement of the same pair, in either order.
	for _, walks in ipairs({
		{ walk(o.from, o.to, 10, true), walk(o.from, o.to, 4000) },
		{ walk(o.from, o.to, 4000), walk(o.from, o.to, 10, true) },
	}) do
		o.walks = walks
		assert(Plan(o).legs[1].yards == 4000)
	end
end

-- Measured walks to and from flight points join them by flight, the guessed one between the places does not.
do
	local o = line(3)
	o.feasibleOnly = true
	o.walks = { walk(o.from, o.taxiNodes[1], 1000), walk(o.taxiNodes[3], o.to, 1000) }
	local planned = Plan(o)
	assert(planned and modes(planned) == "walk,flight,walk", planned and modes(planned))
	o.walks[2] = walk(o.taxiNodes[3], o.to, 1000, true)
	assert(not Plan(o), "an unproved landing walk leaves no route")
end

-- A goal beside a flight point: the guessed walk to the flight point and the zero-time walk on to the goal show as one
-- walk, but the walk still to prove is the guessed one. Its probe must cost the walk to the flight point (#1080).
do
	local o = line(1)
	o.to = point(1001)
	o.walks = {
		walk(o.from, o.taxiNodes[1], 900, true),
		walk(o.taxiNodes[1], o.to, 0),
		walk(o.from, o.to, 1500),
	}
	local planned = Plan(o)
	assert(planned and modes(planned) == "walk" and planned.legs[1].to.kind == "goal", planned and modes(planned))
	assert(planned.legs[1].estimated and planned.needsStart)
	local pending = planned.pendingWalks
	assert(#pending == 1, #pending)
	assert(pending[1].from.kind == "start" and pending[1].to.kind == "taxi", pending[1].to.kind)
end

-- A baked walk between two fixed places is a known cost and stays: here the only way from one flight to the next.
do
	local o = line(4)
	o.taxiPaths = { { from = 1, to = 2, seconds = 100 }, { from = 3, to = 4, seconds = 100 } }
	o.feasibleOnly = true
	o.walks = { walk(o.from, o.taxiNodes[1], 1000), walk(o.taxiNodes[4], o.to, 1000) }
	assert(not Plan(o), "the flights do not meet")
	o.baked = { [1] = { ["taxi2 taxi3"] = { 2000 } } }
	local planned = Plan(o)
	assert(planned and modes(planned) == "walk,flight,walk,flight,walk", planned and modes(planned))
	assert(planned.legs[3].yards == 2000)
end

-- incumbent: the same plan beating it, nothing otherwise, and fewer labels met on the way.
local function labels(o)
	o.cache = {}
	local planned = Plan(o)
	return planned, o.cache.topology.labels.count
end
for nodes = 4, 40, 12 do
	local o = line(nodes)
	local best, full = labels(o)
	assert(best and modes(best):find("flight"), "the flights beat the walk")
	for _, delta in ipairs({ 1, 50, 5000, 100000 }) do
		local pruned = line(nodes)
		pruned.incumbent = best.arrive + delta
		local planned, met = labels(pruned)
		assert(
			planned and planned.arrive == best.arrive and modes(planned) == modes(best),
			"a looser incumbent changes nothing"
		)
		assert(met <= full)
	end
	for _, delta in ipairs({ 0, -1, -5000 }) do
		local pruned = line(nodes)
		pruned.incumbent = best.arrive + delta
		local planned, met = labels(pruned)
		assert(planned == nil, "nothing beats an arrival already at the optimum")
		assert(met < full, "labels that cannot beat the incumbent are never made")
	end
end

-- The walk that is the optimum is itself pruned by an incumbent at its arrival.
do
	local o = line(2)
	o.taxiPaths = {}
	local walked = Plan(o)
	assert(modes(walked) == "walk")
	o.incumbent = walked.arrive
	assert(Plan(o) == nil)
	o.incumbent = walked.arrive + 1
	assert(Plan(o).arrive == walked.arrive)
end

-- An equal incumbent still passes through the journey's preference for a nearly as quick ride.
do
	local from, to = point(0), point(7000)
	local o = {
		from = from,
		to = to,
		now = 0,
		walkSpeed = 7,
		exactMaps = { [1] = true },
		taxiNodes = { from, to },
		taxiPaths = {},
		walks = { walk(from, to, 7000), walk(from, from, 0), walk(to, to, 0) },
	}
	local incumbent = assert(Plan(o))
	assert(modes(incumbent) == "walk")
	o.taxiPaths = { { from = 1, to = 2, seconds = 1020 } }
	local preferred = assert(Plan(o))
	assert(preferred.preferred and preferred.arrive > incumbent.arrive)
	o.incumbent, o.incumbentPlan = incumbent.arrive, incumbent
	local bounded = assert(Plan(o))
	assert(bounded.preferred and bounded.arrive == preferred.arrive and modes(bounded) == modes(preferred))
end

-- A short flight away from the goal and a long walk back is not the ride a long walk gives way to: it is still mostly
-- on foot, and arrives later. Orgrimmar to Azshara on foot flew to Splintertree Post and walked back east (#1102).
do
	local from, away, to = point(0), point(0, 600), point(4300)
	local o = {
		from = from,
		to = to,
		now = 0,
		walkSpeed = 7,
		exactMaps = { [1] = true },
		taxiNodes = { from, away },
		taxiPaths = { { from = 1, to = 2, seconds = 89 } },
		walks = {
			walk(from, to, 4315),
			walk(away, to, 3800),
			walk(from, from, 0),
			walk(away, away, 0),
			walk(to, to, 0),
		},
	}
	local planned = assert(Plan(o))
	assert(modes(planned) == "walk" and not planned.preferred, "the walk stays: got " .. modes(planned))
	assert(math.abs(planned.arrive - 4315 / 7 * 1000) < 1, "and arrives first")
end

-- The first ride within the cutoff still leaves most of the journey on foot (#1104).
do
	local from, away, near, to = point(0), point(0, 600), point(4200), point(4300)
	local o = {
		from = from,
		to = to,
		now = 1000,
		walkSpeed = 7,
		exactMaps = { [1] = true },
		taxiNodes = { from, away, near },
		taxiPaths = { { from = 1, to = 2, seconds = 89 }, { from = 1, to = 3, seconds = 630 } },
		walks = {
			walk(from, to, 4315),
			walk(away, to, 3800),
			walk(near, to, 100),
			walk(from, from, 0),
			walk(away, away, 0),
			walk(near, near, 0),
			walk(to, to, 0),
		},
	}
	local planned = assert(Plan(o))
	assert(
		planned.preferred and modes(planned) == "flight,walk",
		"expected the mostly ridden plan, got " .. modes(planned)
	)
	assert(planned.legs[1].hops[1].to == 3, "the preferred flight lands near the goal")

	-- Two flights can share a landing and walk. The faster flight still spends most of its time walking.
	o.taxiPaths = { { from = 1, to = 2, seconds = 300 }, { from = 1, to = 2, seconds = 350 } }
	o.walks[2] = walk(away, to, 2240)
	planned = assert(Plan(o))
	assert(planned.preferred and modes(planned) == "flight,walk")
	assert(planned.legs[1].hops[1].seconds == 350, "the longer flight makes the shared walk less than half the trip")
	-- A label reaching the dock first catches an earlier boat and still walks half the way. The one that misses it waits
	-- for the next, and that wait keeps its walking under half: arriving first does not dominate in the ride search.
	local function at(x, z)
		return { map = 1, x = x, y = 0, z = z }
	end
	local start, goal, master, dock, side, landing =
		at(0, 0), at(300, 0), at(100, 0), at(200, 0), at(200, 1), at(300, 0)
	planned = assert(Plan({
		from = start,
		to = goal,
		now = 0,
		walkSpeed = 7,
		faction = "Alliance",
		exactMaps = { [1] = true },
		docks = { [1] = dock, [2] = side, [3] = landing },
		routes = {
			[1] = {
				kind = "boat",
				period = 50000,
				stops = { { dock = 1, arrive = 0, depart = 0 }, { dock = 3, arrive = 40000, depart = 40000 } },
			},
		},
		anchors = { [1] = { epoch = 950000 } },
		taxiNodes = { [1] = start, [2] = master },
		taxiPaths = { { from = 1, to = 2, seconds = 437 } },
		walks = {
			walk(start, goal, 6895),
			walk(start, start, 0),
			walk(master, dock, 3570),
			walk(master, side, 3605),
			walk(side, dock, 0),
			walk(landing, goal, 0),
		},
	}))
	assert(planned.preferred and planned.arrive == 1040000, "the later boat mostly rides: got " .. planned.arrive)
end

-- A cached topology and an incumbent compose: feasible, full and bounded plans share one cache.
do
	local o = line(8)
	local cache = {}
	local fresh = Plan(line(8))
	o.cache = cache
	o.feasibleOnly = true
	assert(not Plan(o))
	o.feasibleOnly, o.incumbent = nil, fresh.arrive + 1
	assert(Plan(o).arrive == fresh.arrive)
	o.incumbent = nil
	assert(Plan(o).arrive == fresh.arrive and modes(Plan(o)) == modes(fresh))
end
print("planner_pruning_spec: feasible-only walks, baked costs and incumbent cutoff: ok")

-- Planner.Plan's two journey options: feasibleOnly drops every walk that is only a lower bound, and incumbent ends
-- the search for a route that cannot beat an arrival already in hand. Neither changes a plan without the option.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)
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

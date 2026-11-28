local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Savings.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/PlanBounds.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)

local start = { map = 1, x = 0, y = 0 }
local goal = { map = 1, x = 700, y = 0 }
local options = {
	from = start,
	to = goal,
	now = 1000,
	walkSpeed = 7,
	taxiNodes = { [1] = start, [2] = goal },
	taxiPaths = { { from = 1, to = 2, seconds = 220 } },
	exactMaps = { [1] = true },
	walks = {
		{ from = start, to = goal, cost = 700 },
		{ from = start, to = start, cost = 0 },
		{ from = goal, to = goal, cost = 0 },
	},
}
local original = assert(ns.Planner.Plan(options))
options.flightAllowance = 0
local walk = assert(ns.Planner.Plan(options))
assert(#walk.legs == 1 and walk.legs[1].mode == "walk")
assert(walk.arrive == original.arrive and walk.arrive == 101000)

options.flightAllowance = 2
local tooSlow = assert(ns.Planner.Plan(options))
assert(tooSlow.legs[1].mode == "walk", "123 extra seconds exceeds a two minute allowance")

options.flightAllowance = 3
local flight = assert(ns.Planner.Plan(options))
assert(#flight.legs == 1 and flight.legs[1].mode == "flight", "a three minute allowance prefers the flight")
assert(flight.arrive == 224000 and flight.legs[1].arrive == flight.arrive, "ETA includes boarding and the full flight")

options.lowerBound = true
assert(assert(ns.Planner.Plan(options)).arrive == walk.arrive, "preference does not change the arrival lower bound")

options.lowerBound = false
options.walks[1].estimated = true
local estimated = assert(ns.Planner.Plan(options))
assert(estimated.legs[1].mode == "flight")
assert(estimated.needsStart and #estimated.pendingWalks == 1, "the competing walk still needs proof")

-- Both searches fit the unchanged 3 ms planner budget, including a cold topology. CI asserts the plan only;
-- SPF_BENCH_STRICT=1 also asserts the budget, which shared runners are too slow and noisy to hold.
local strict = os.getenv("SPF_BENCH_STRICT") == "1"
local ns = {}
for _, file in ipairs({
	"Transport/Model.lua",
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
	"Routing/Planner.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local known = {}
for id in pairs(ns.TaxiNodes) do
	known[id] = true
end
local from, goal = ns.TaxiNodes[26], ns.TaxiNodes[67]
local options = {
	from = from,
	to = goal,
	now = 0,
	walkSpeed = 7,
	faction = "Alliance",
	docks = ns.Docks,
	routes = ns.Routes,
	taxiNodes = ns.TaxiNodes,
	taxiPaths = ns.TaxiPaths,
	taxiKnown = known,
	portals = ns.Portals,
	landmasses = ns.Landmasses,
	baked = ns.Walks,
	teleports = { { map = goal.map, x = goal.x, y = goal.y, spell = 8690, item = 6948, cast = 10000 } },
	teleportReady = { 0 },
	hearthMinimumSavings = 600,
}
for _, cold in ipairs({ true, false }) do
	options.cache = {}
	local worst = 0
	for _ = 1, 100 do
		if cold then
			options.cache = {}
		end
		local start = os.clock()
		local plan = ns.Planner.Plan(options)
		worst = math.max(worst, (os.clock() - start) * 1000)
		assert(plan and plan.legs[1].mode == "teleport", "the winning Hearthstone needs a non-hearth comparison")
		assert(plan.arrive == 15000, "the threshold does not inflate the actual cast and loading time")
	end
	print(string.format("hearth savings %s: worst %.3f ms", cold and "cold" or "warm", worst))
	assert(not strict or worst < 3, "Hearthstone savings comparison exceeds 3 ms")
end

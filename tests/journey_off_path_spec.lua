local function OffPathSearches(tolerance)
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local path = driver.path
	driver.ns.db.offPathTolerance = tolerance or driver.ns.db.offPathTolerance
	driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 1000, y = 0 })
	local leg = driver.shown().legs[1]
	assert(leg.mode == "walk" and leg.measured, "the initial walk is measured")
	local before = #path.batches
	driver.move({ map = 1, x = 50, y = 30 })
	driver.update(5)
	return #path.batches - before
end

assert(OffPathSearches() == 1, "a 30-yard detour starts a new search at the default tolerance")
assert(OffPathSearches(40) == 0, "a 30-yard detour keeps the existing walk at 40 yards")

local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
ns.db.offPathTolerance = 100
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 1000, y = 0 })
ns.speed = 10
driver.update(1)
local before = #driver.path.batches
driver.move({ map = 1, x = 1000, y = 90 })
driver.update(5)
local leg = driver.shown().legs[1]
assert(#driver.path.batches == before, "the 90-yard detour stays within tolerance")
assert(
	math.abs(leg.yards - 90) < 1e-6 and math.abs(leg.arrive - leg.depart - 9000) < 1e-6,
	"the remaining walk includes 90 yards to rejoin"
)

local plan = ns.Planner.Plan
local measuredCost
ns.Planner.Plan = function(options, job)
	for _, walk in ipairs(options.walks) do
		if walk.from.x == 1000 and walk.from.y == 90 and walk.to == leg.to then
			measuredCost = walk.cost
		end
	end
	return plan(options, job)
end
ns.JourneySearch.Replan(nil, false, false, true)
driver.path.settle()
assert(measuredCost and math.abs(measuredCost - 90) < 1e-6, "the planner also prices the 90 yards to rejoin")

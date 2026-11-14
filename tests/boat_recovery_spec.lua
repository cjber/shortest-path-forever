-- Real journey progress and retained-route comparison, without a level-up or destination reset.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
driver.load("Data/Routes.lua")
local route = ns.Routes[241]
local from = ns.Docks[route.stops[1].dock]
local to = ns.Docks[route.stops[2].dock]
local function point(dock, offset)
	dock = dock.walk or dock
	return { map = dock.map, x = dock.x + (offset or 0), y = dock.y, z = dock.z }
end
local target = point(to, 100)
local guided
ns.PointGuideArrow = function(at)
	guided = at and at[1]
end
driver.begin(point(from, 100), target)
driver.move(point(from))
driver.update(0.1)
local _, _, plan, index = ns.JourneyInfo()
assert(plan.legs[index].mode == "boat", "reaching the dock waits on its boat")
driver.update(5)
_, _, plan, index = ns.JourneyInfo()
assert(plan.legs[index].mode == "boat", "waiting at the dock does not complete the boat leg")
local waiting = plan
local function atDock()
	return guided and guided.map == from.map and guided.x == from.x and guided.y == from.y
end
assert(atDock(), "waiting without boarding must guide to departure, not the far shore")
driver.move(point(from, 500))
driver.update(5)
_, _, plan, index = ns.JourneyInfo()
assert(plan.legs[index].mode == "walk", "leaving without boarding restores the walking leg")
assert(plan ~= waiting, "the retained boat cannot omit the return walk")
assert(plan.legs[index].from.x == point(from).x + 500, "the return walk starts at the current position")
for _ = 1, 13 do
	driver.update(5)
end
_, _, plan, index = ns.JourneyInfo()
assert(plan.legs[index].mode == "walk", "waiting over 60 seconds preserves recovered walking guidance")
driver.move(point(from))
driver.update(0.1)
_, _, plan, index = ns.JourneyInfo()
assert(plan.legs[index].mode == "boat" and atDock(), "returning to the dock waits for boarding again")
ns.CurrentRide = function()
	return 241
end
driver.update(0.1)
assert(guided and guided.map == to.map, "observed boarding guides to the destination dock")
driver.move(point(to))
driver.update(0.1)
_, _, plan, index = ns.JourneyInfo()
assert(plan.legs[index].mode == "walk", "arrival resumes the destination walk")
print("boat_recovery_spec: missed boarding recovers without an unrelated event")

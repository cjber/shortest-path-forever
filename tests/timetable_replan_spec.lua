-- Run from the repository root: luajit tests/timetable_replan_spec.lua
-- A journey's timed tick, against a clock the spec moves: a route that waits for a boat is retimed while that boat is
-- still to come, and planned again only when the departure it waits for leaves without it.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, walking = driver.ns, driver.path
walking.auto = true

-- A bay crossed by one boat, slower to walk round, leaving every forty seconds; the dock is where the journey starts.
ns.Docks = {
	[1] = { map = 1, x = 100, y = 0 },
	[2] = { map = 1, x = 1200, y = 0 },
}
ns.Routes = {
	[9] = {
		kind = "boat",
		period = 40000,
		stops = { { dock = 1, arrive = 0, depart = 20000 }, { dock = 2, arrive = 30000, depart = 35000 } },
	},
}
ns.Timetable.Sighted(9, { epoch = 0, seen = 0 })

local plans = 0
local plan = ns.Planner.Plan
ns.Planner.Plan = function(options)
	plans = plans + 1
	return plan(options)
end

-- The driver's own frames, at sixty a second, as the client's OnUpdate gives them.
local function run(seconds)
	for _ = 1, math.floor(seconds * 60 + 0.5) do
		driver.update(1 / 60)
	end
end

local function near(actual, expected, what)
	assert(math.abs(actual - expected) < 100, string.format("%s: %.1f, expected about %d", what, actual, expected))
end

local dock, goal = { map = 1, x = 100, y = 0, z = 0 }, { map = 1, x = 1400, y = 0 }
driver.begin(dock, goal)
local route = assert(driver.shown())
local boat = route.legs[1]
assert(boat.route == 9 and boat.mode == "boat", "the spec needs a journey that waits for the boat")
assert(boat.depart == 20000 and boat.wait == 20000, "the docked boat leaves in twenty seconds")

-- Sixteen seconds at the dock: three timed ticks, the boat still to come. Each retimes the route from where the
-- player stands, and none of them plans.
plans = 0
run(16)
assert(plans == 0, "a tick whose sailing still stands must not plan")
assert(driver.shown() == route, "a retimed route is not drawn again")
boat = driver.shown().legs[1]
assert(boat.route == 9 and boat.depart == 20000, "the sailing being waited for must stand while it is still to come")
near(boat.wait, 5000, "the wait counts down with the clock")

-- The boat leaves without the player. The next tick plans: the route now waits for a later sailing.
plans = 0
run(10)
assert(plans == 1, "a departure that left without the player must plan once")
boat = driver.shown().legs[1]
assert(boat.route == 9 and boat.depart == 60000, "the route waits for the next sailing: " .. tostring(boat.depart))
assert(boat.wait > 0 and boat.wait < 40000, "the wait counts down to the next sailing")

-- A run speed change still plans what the new speed makes quicker, whatever the timetable says.
plans = 0
ns.speed = 14
run(5)
assert(plans == 1, "a change of run speed must plan without waiting for a sailing")
-- The speed going back settles on a frame of its own, before the next journey starts.
ns.speed = nil
run(1)
ns.ClearJourney()

-- Walking to the dock: each tick retimes the walk and the wait from where the player stands, and the sailing they
-- still catch is the same one, so nothing is planned.
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, goal)
assert(driver.shown().legs[1].mode == "walk" and driver.shown().legs[2].route == 9, "the walk to the dock comes first")
local sailing = driver.shown().legs[2].depart
plans = 0
for step = 1, 2 do
	driver.move({ map = 1, x = step * 35, y = 0, z = 0 })
	run(5)
end
assert(plans == 0, "walking to a dock the boat still waits at must not plan")
assert(driver.shown().legs[2].depart == sailing, "the sailing still stands at the dock")
ns.ClearJourney()

-- The same journey on foot, with nothing to wait for: fifty stationary seconds, ten ticks, no plan at all.
ns.Routes, ns.Docks = {}, {}
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 1200, y = 0 })
assert(driver.shown().legs[1].mode == "walk", "the spec needs a walk-only journey")
plans = 0
run(50)
assert(plans == 0, "a walk with no departure to wait for must not plan while standing still")
assert(driver.shown().legs[1].mode == "walk")
print("timetable_replan_spec: a tick plans only for the departures the drawn route waits for")

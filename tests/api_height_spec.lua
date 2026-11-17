-- Public places preserve only the finite heights held by the planner, with fresh tables on every read.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/API.lua")
local API = env.ShortestPathForever.API
local first = { map = 1, x = 0, y = 0, z = -40 }
local last = { map = 1, x = 100, y = 0, z = 125, label = "Goal" }
local points = { first, last }
local plan = { legs = { { mode = "walk", from = first, to = last, points = points, arrive = 1000, depart = 0 } } }
ns.JourneyGoal = function()
	return last
end
ns.JourneyPlan = function()
	return plan, 1
end
ns.PlanContext.LegPoints = function()
	return points
end
ns.GuideState = function()
	return first, points, 1
end
local function check(height)
	first.z, last.z = height, height
	local journey = assert(API.Journey())
	local guidance = assert(API.Guidance())
	for _, place in ipairs({
		journey.goal,
		journey.legs[1].from,
		journey.legs[1].to,
		guidance.point,
		guidance.waypoints[1],
		guidance.waypoints[2],
	}) do
		assert(place.z == height, "each public place preserves the stored height")
		place.z = 999
	end
	assert(first.z == height and last.z == height, "returned places cannot change stored heights")
	assert(API.Journey().goal.z == height and API.Guidance().point.z == height, "reads make fresh copies")
end
check(-40)
check(125)
check(0)
check(nil)
for _, invalid in ipairs({ math.huge, -math.huge, 0 / 0, "125" }) do
	first.z, last.z = invalid, invalid
	local journey, guidance = assert(API.Journey()), assert(API.Guidance())
	assert(journey.goal.z == nil and journey.legs[1].from.z == nil and journey.legs[1].to.z == nil)
	assert(guidance.point.z == nil and guidance.waypoints[1].z == nil and guidance.waypoints[2].z == nil)
end
-- A goal on another floor is a changed destination even when its map coordinates match.
local timers, changed = {}, false
env.C_Timer = {
	After = function(_, fn)
		timers[#timers + 1] = fn
	end,
}
local unsubscribe = API.Subscribe(function(changes)
	changed = changed or changes.changed == true
end)
ns.JourneyChanged({ map = 1, x = 0, y = 0, z = -40 })
for _, fn in ipairs(timers) do
	fn()
end
timers, changed = {}, false
ns.JourneyChanged({ map = 1, x = 0, y = 0, z = 125 })
for _, fn in ipairs(timers) do
	fn()
end
assert(changed, "a height-only destination change reaches subscribers")
unsubscribe()
print("api_height_spec: ok")

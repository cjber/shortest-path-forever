-- Nothing an event, a tooltip, a click or a callback runs may plan in its own frame (#1023). A plan is heavy work:
-- every one the addon makes for itself carries the path job it runs in, so it pauses at the frame budget and goes on
-- next frame. The only plans made whole are the public API's synchronous estimates, which other addons ask for.
-- This counts every plan made without a job across a journey's life: its start, the notify callbacks of its walking
-- searches, timed replans while the player moves, a route of several stops (whose later hops Itinerary plans) and the
-- goal pin's other-faction comparison.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
driver.load("Journey/FactionHint.lua")
ns.IsObservingRide = function() end
local API = env.ShortestPathForever.API

local plans, whole, public = 0, {}, 0
local plan = ns.Planner.Plan
ns.Planner.Plan = function(options, job)
	plans = plans + 1
	if not job and public == 0 then
		whole[#whole + 1] = debug.traceback("a plan made whole in the asking frame", 2)
	end
	return plan(options, job)
end
-- The public estimates are synchronous by contract: the caller asked for an answer now.
for _, name in ipairs({ "Estimate", "EstimateDetail" }) do
	local estimate = API[name]
	API[name] = function(...)
		public = public + 1
		local a, b = estimate(...)
		public = public - 1
		return a, b
	end
end
local function clean(label)
	assert(#whole == 0, label .. ":\n" .. tostring(whole[1]))
end

-- A journey: start, walk, replan on the timer, and ask the goal pin's comparison on the way.
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 2000, y = 0 })
clean("starting a journey")
for step = 1, 40 do
	driver.move({ map = 1, x = step * 10, y = 0, z = 0 })
	driver.update(0.5)
	if step % 10 == 0 then
		ns.OtherFactionHint()
	end
end
clean("walking a journey with timed replans")
assert(plans > 0, "the journey planned")

-- A route of several stops: Itinerary plans the hops after the current one.
ns.ClearJourney()
driver.move({ map = 1, x = 0, y = 0, z = 0 })
assert(API.NavigateRoute("Frame budget", {
	{ map = 1, x = 0.502, y = 0.5, title = "First" },
	{ map = 1, x = 0.504, y = 0.5, title = "Second" },
	{ map = 1, x = 0.506, y = 0.5, title = "Third" },
}))
for _ = 1, 20 do
	driver.update(0.5)
end
clean("a route of several stops")

-- The public estimate still answers in the asking frame.
local before = plans
assert(API.Estimate(1, 0.5, 0.5, 1, 0.51, 0.5), "a public estimate answers now")
assert(plans > before, "and it planned to answer")
clean("a public estimate")

print("frame_budget_spec: no plan made whole outside the public estimate: ok")

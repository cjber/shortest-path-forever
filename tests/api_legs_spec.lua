-- Journey() names where each leg starts and ends, copied from the planner's own leg points, and Subscribe says when
-- the plan was worked out again. A point this client cannot place stays absent: nothing is estimated.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = driver.ns, driver.env, 0
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API
-- The teleport leg's own words name the item it asks for.
env.C_Item = {
	GetItemNameByID = function()
		return "Hearthstone"
	end,
	GetItemIconByID = function()
		return 1
	end,
}
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected, label)
	checks = checks + 1
	assert(type(actual) == "number" and math.abs(actual - expected) < 1e-6, label)
end

-- The driver maps a uiMap point (x, y) to world (x, y) as (0.5 - y) * 50000, (0.5 - x) * 50000.
local function uiX(worldY)
	return 0.5 - worldY / 50000
end
local function uiY(worldX)
	return 0.5 - worldX / 50000
end
local function settle()
	local journey
	for _ = 1, 100 do
		journey = API.Journey()
		if journey and #journey.legs > 0 then
			return journey
		end
		driver.update(0.1)
	end
	error("the journey never settled")
end
local function ends(leg, label)
	checks = checks + 1
	assert(leg.from and leg.to, label .. ": both ends are named")
	return leg.from, leg.to
end

driver.move({ map = 1, x = 0, y = 0, z = 0 })
equal(API.NavigateRoute("AGF", { { map = 1, x = 0.5, y = 0.52, title = "Goal" } }), true, "a walking route starts")
local journey = settle()
equal(#journey.legs, 1, "one walking leg")
local leg = journey.legs[1]
local from, to = ends(leg, "a walking leg")
equal(from.map, 1, "the start's map")
near(from.x, 0.5, "the start's x")
near(from.y, 0.5, "the start's y")
equal(to.map, 1, "the end's map")
near(to.x, 0.5, "the end's x")
near(to.y, 0.52, "the end's y")
equal(from.z, nil, "only map, x and y are copied")
equal(to.title, nil, "a leg end is a place, not a goal")

-- Copies only: changing or keeping one reaches neither the plan nor the next read.
local plan = select(1, ns.JourneyPlan())
assert(plan and plan.legs[1], "the plan under way")
assert(from ~= plan.legs[1].from and to ~= plan.legs[1].to, "the ends are not the planner's own points")
from.x, to.y = 9, 9
local again = API.Journey()
local freshFrom, freshTo = ends(again.legs[1], "a fresh read")
near(freshFrom.x, 0.5, "the start is copied again")
near(freshTo.y, 0.52, "the end is copied again")
assert(freshFrom ~= from and freshTo ~= to, "no end table is shared between reads")

-- An end this client cannot project is absent, not guessed, and comes back when it can be placed.
local project = env.C_Map.GetMapPosFromWorldPos
env.C_Map.GetMapPosFromWorldPos = function(map, point)
	if point.x > -1 then
		return nil
	end
	return project(map, point)
end
local partial = API.Journey().legs[1]
equal(partial.from, nil, "an end this client cannot place stays absent")
assert(partial.to, "the other end is still placed")
env.C_Map.GetMapPosFromWorldPos = project
assert(API.Journey().legs[1].from, "and returns once it can place it")
equal(API.Cancel("AGF"), true, "the walking journey clears")

-- A teleport and the walk on: each leg names its own ends, and the walk starts where the teleport lands.
driver.move({ map = 1, x = 0, y = 0, z = 0 })
ns.teleports = { { map = 1, x = -930, y = 0, spell = 8690, item = 6948, cast = 10000, label = "Hearth" } }
ns.teleportReady = { 0 }
equal(API.NavigateRoute("AGF", { { map = 1, x = 0.5, y = 0.52, title = "Far" } }), true, "a route with a teleport")
local hearthed = settle()
equal(#hearthed.legs, 2, "a teleport and the walk on")
equal(hearthed.legs[1].mode, "teleport", "the first leg casts")
equal(hearthed.legs[2].mode, "walk", "the second walks on")
local castFrom, castTo = ends(hearthed.legs[1], "the cast")
near(castFrom.x, 0.5, "the cast starts where the player stands")
near(castFrom.y, 0.5, "the cast's start")
near(castTo.x, uiX(0), "the cast lands at the teleport place")
near(castTo.y, uiY(-930), "the cast's landing")
local walkFrom, walkTo = ends(hearthed.legs[2], "the walk on")
near(walkFrom.x, castTo.x, "the walk starts where the teleport lands, in x")
near(walkFrom.y, castTo.y, "the walk starts where the teleport lands, in y")
near(walkTo.x, 0.5, "and ends at the goal, in x")
near(walkTo.y, 0.52, "and ends at the goal, in y")
equal(API.Cancel("AGF"), true, "the teleport journey clears")
ns.teleports, ns.teleportReady = nil, nil

-- Subscribe says when a plan was worked out again, so a companion need not poll a "loading" journey.
local timers, heard = {}, {}
env.C_Timer = {
	After = function(_, fn)
		timers[#timers + 1] = fn
	end,
}
local function frameEnd()
	local due = timers
	timers = {}
	for _, fn in ipairs(due) do
		fn()
	end
end
local unsubscribe = API.Subscribe(function(changes)
	heard[#heard + 1] = changes
end)
driver.move({ map = 1, x = 0, y = 0, z = 0 })
equal(API.NavigateRoute("AGF", { { map = 1, x = 0.5, y = 0.52, title = "Goal" } }), true, "a route starts")
equal(#heard, 0, "the notice waits for the next frame")
local first = settle()
assert(first and #first.legs == 1, "the first plan is ready")
assert(#timers > 0, "a plan worked out again is queued")
frameEnd()
local replanned = false
for _, changes in ipairs(heard) do
	if changes.replan then
		replanned = true
	end
end
assert(replanned, "the first plan ready is a replan change")
local after = API.Journey()
local afterFrom, afterTo = ends(after.legs[1], "after the replan")
near(afterFrom.x, 0.5, "the replanned leg's start")
near(afterTo.y, 0.52, "the replanned leg's end")

-- A new destination is a new plan, and its legs are the ones the next read names.
frameEnd()
local before = #heard
equal(API.NavigateRoute("AGF", { { map = 1, x = 0.5, y = 0.54, title = "Elsewhere" } }), true, "the goal changes")
-- A moved goal keeps the plan and drawn route until the new plan lands, so let the search answer first.
driver.path.settle()
frameEnd()
assert(#heard > before, "the replacement journey is heard")
local changedFrom, changedTo = ends(API.Journey().legs[1], "the replacement plan")
near(changedFrom.x, 0.5, "the replacement starts where the player stands")
near(changedTo.y, 0.54, "and ends at the new goal")
API.Cancel("AGF")
frameEnd()
unsubscribe()
frameEnd()
equal(#timers, 0, "no subscribers left: nothing scheduled")

print(("api_legs_spec: ok (%d checks)"):format(checks))

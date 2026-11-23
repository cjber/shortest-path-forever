-- #1026: other addons can steer along the walking map without taking the journey slot or drawing guidance.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, path = driver.ns, driver.env, driver.path
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/APIWalks.lua")
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
local API = env.ShortestPathForever.API
assert(type(API.WalkPath) == "function", "WalkPath is published")

local FROM = { map = 1, x = 0.5, y = 0.5 }
local TO = { map = 10, x = 0.502, y = 0.501 }
local project = env.C_Map.GetWorldPosFromMapPos
env.C_Map.GetWorldPosFromMapPos = function(map, point)
	return project(map == 10 and 1 or map, point)
end
local back = env.C_Map.GetMapPosFromWorldPos
env.C_Map.GetMapPosFromWorldPos = function(map, point)
	return back(point.x < 0 and 11 or map, point)
end
local draws = 0
local function draw()
	draws = draws + 1
end
ns.SetJourneyRoute, ns.RefreshTracker, ns.PointGuideArrow, env.C_Map.SetUserWaypoint = draw, draw, draw, draw

local function equal(actual, expected, label)
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function place(actual, map, x, y)
	equal(actual.map, map, "projected uiMapID")
	assert(math.abs(actual.x - x) < 1e-6 and math.abs(actual.y - y) < 1e-6, "projected fractions")
	equal(actual.z, nil, "waypoints report only map coordinates")
end

local answers, estimates = {}, {}
local function receive(result, reason)
	answers[#answers + 1] = { result = result, reason = reason }
end
local function estimate(costs)
	estimates[#estimates + 1] = costs[1]
end

-- The two endpoints use different uiMaps of one landmass. The path keeps its bends and snapped end, while the
-- cost comes straight from the search, even when it differs from the distance along the bends.
path.auto = false
API.EstimateWalks("Owner", FROM, { TO }, estimate)
local cancel = API.WalkPath("Owner", FROM, TO, receive, { waterWalking = true })
equal(type(cancel), "function", "a path request returns a cancel function")
equal(#answers, 0, "no synchronous callback")
equal(#path.finds, 1, "one path job")
local job = path.finds[1]
equal(job.map, 1, "one walking map")
equal(job.water, true, "explicit water walking")
equal(job.hazards, nil, "plain walking")
equal(path.batches[1].cancelled, nil, "the walk path leaves the estimate running")
API.EstimateWalks("Owner", FROM, { TO }, estimate)
equal(job.cancelled, nil, "the estimate leaves the walk path running")
local points = {
	job.from,
	{ map = 1, x = 0, y = -50, z = 27 },
	{ map = 1, x = -40, y = -95 },
}
path.finish(job, points, 117)
path.finish(path.batches[2], { 117 })
equal(#answers, 1, "one result")
equal(answers[1].reason, nil, "success has no reason")
local result = answers[1].result
equal(result.yards, estimates[1], "the estimate's running yards")
equal(result.navVersion, API.NavVersion(), "freshness token")
equal(#result.waypoints, 3, "start, bend and end")
place(result.waypoints[1], 1, 0.5, 0.5)
place(result.waypoints[2], 1, 0.501, 0.5)
place(result.waypoints[3], 11, 0.5019, 0.5008)
result.waypoints[2].x = 0
equal(points[2].x, 0, "the search's original X")
equal(points[2].y, -50, "the search's original Y")
equal(points[2].z, 27, "the search's original height")
cancel()
cancel()

local journey, reason = API.Journey()
equal(journey, nil, "no journey started")
equal(reason, "none", "journey slot remains empty")
equal((API.CurrentStop("Owner")), nil, "no current stop")
equal(draws, 0, "no guidance drawn")

-- Replacement and cancellation also silence a late answer from the search.
ns.water = true
local first = API.WalkPath("Owner", FROM, TO, receive)
equal(path.finds[2].water, true, "the player's spell applies by default")
local second = API.WalkPath("Owner", FROM, TO, receive, { waterWalking = false })
equal(path.finds[3].water, false, "an explicit false overrides the player's spell")
equal(path.finds[2].cancelled, true, "a new path replaces the old one for this owner")
first()
path.finish(path.finds[2], points, 117)
equal(#answers, 1, "replaced path stayed silent")
path.finish(path.finds[3], points, 117)
equal(#answers, 2, "replacement answered")
local replacement = answers[2].result
assert(replacement ~= result and replacement.waypoints ~= result.waypoints, "results use fresh tables")
place(replacement.waypoints[2], 1, 0.501, 0.5)
second()

cancel = API.WalkPath("Owner", FROM, TO, receive)
cancel()
cancel()
equal(path.finds[4].cancelled, true, "cancel stops the job")
path.finish(path.finds[4], points, 117)
equal(#answers, 2, "cancelled path stayed silent")

for _, failure in ipairs({ "nodata", "outside", "offmesh", "unreachable", "error" }) do
	API.WalkPath("Owner", FROM, TO, receive)
	path.finish(path.finds[#path.finds], nil, failure)
	equal(answers[#answers].result, nil, "a failed job has no path")
	equal(answers[#answers].reason, failure, "failure reason")
end
equal(#answers, 7, "each failed job answered")
API.WalkPath("Owner", FROM, TO, receive)
env.C_Map.GetMapPosFromWorldPos = function() end
path.finish(path.finds[#path.finds], points, 117)
equal(#answers, 8, "an unprojectable path answered")
equal(answers[8].result, nil, "no partial path")
equal(answers[8].reason, "outside", "waypoint projection failure")
env.C_Map.GetMapPosFromWorldPos = back

local function refused(expected, handle, refusal)
	equal(handle, nil, "refused path has no cancel function")
	equal(refusal, expected, "refusal reason")
end
local searches = #path.finds
refused("invalid", API.WalkPath(" ", FROM, TO, receive))
refused("invalid", API.WalkPath("Owner", nil, TO, receive))
refused("invalid", API.WalkPath("Owner", FROM, { map = 1, x = 2, y = 0.5 }, receive))
refused("invalid", API.WalkPath("Owner", FROM, { map = 2, x = 0.5, y = 0.5 }, receive))
refused("invalid", API.WalkPath("Owner", FROM, TO, nil))
refused("invalid", API.WalkPath("Owner", FROM, TO, receive, { waterWalking = "yes" }))
local db = ns.db
ns.db = nil
refused("loading", API.WalkPath("Owner", FROM, TO, receive))
ns.db = db
env.InCombatLockdown = function()
	return true
end
refused("combat", API.WalkPath("Owner", FROM, TO, receive))
env.InCombatLockdown = function()
	return false
end
path.data = false
refused("nodata", API.WalkPath("Owner", FROM, TO, receive))
equal(#path.finds, searches, "no refusal queued a search")
equal(#answers, 8, "no refusal calls back")
equal(draws, 0, "searches never drew guidance")

print("api_walk_path: ok")

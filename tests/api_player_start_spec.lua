-- #1409: a live start carries the same floor as a journey, even when a fixed point at the same spot has no height.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, path = driver.ns, driver.env, driver.path
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/APIWalks.lua")
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
local API = env.ShortestPathForever.API

local function equal(actual, expected, label)
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local height, band, inInstance, onTaxi = -40, nil, false, false
local bandReads = 0
local x, y = 30, -60
driver.move({ map = 1, x = x, y = y, z = 0 })
env.IsInInstance = function()
	return inInstance
end
env.UnitOnTaxi = function()
	return onTaxi
end
local sampled
ns.Floor = {
	Sample = function(map, atX, atY)
		sampled = { map, atX, atY }
	end,
	Height = function(map, atX, atY)
		assert(sampled and sampled[1] == map and sampled[2] == atX and sampled[3] == atY, "follow, then read the floor")
		sampled = nil
		equal(map, 1, "floor world map")
		equal(atX, x, "floor world X")
		equal(atY, y, "floor world Y")
		return height
	end,
}
ns.Band = {
	At = function()
		assert(height == nil, "the band is measured only when the floor is unknown")
		bandReads = bandReads + 1
		return band
	end,
}

local from = { map = 1, x = 0.5 - y / 50000, y = 0.5 - x / 50000 }
local to = { map = 1, x = 0.502, y = 0.5 }
local function noCallback()
	error("a cancelled or refused player search called back")
end
local function walk(origin)
	return API.WalkPath("PlayerFloor", origin or "player", to, noCallback)
end
local function costs(origin)
	return API.EstimateWalks("PlayerFloor", origin or "player", { to }, noCallback)
end
local function estimate()
	return API.Estimate("player", nil, nil, to.map, to.x, to.y)
end
local function detail()
	return API.EstimateDetail("player", nil, nil, to.map, to.x, to.y)
end
local function start(call, jobs)
	local cancel, reason = call()
	equal(reason, nil, "a player search starts")
	assert(cancel)()
	return jobs[#jobs].from
end

local navVersion = API.NavVersion()
for _, search in ipairs({ { walk, path.finds }, { costs, path.batches } }) do
	local call, jobs = search[1], search[2]
	local cancel = assert(call(from))
	equal(jobs[#jobs].from.z, nil, "same map coordinate as a fixed point has no height")
	cancel()
	local point = start(call, jobs)
	equal(point.x, x, "the live world X")
	equal(point.y, y, "the live world Y")
	equal(point.z, -40, "search starts on the followed floor")
	equal(point.band, nil, "known floor does not need a band")
end

-- The same XY on a different floor is a fresh input, even inside the synchronous estimate cache's lifetime.
local plan, origins = ns.Planner.Plan, {}
ns.Planner.Plan = function(options, job)
	origins[#origins + 1] = options.from
	return plan(options, job)
end
assert(estimate())
assert(detail())
equal(#origins, 1, "both synchronous estimates share the same cached origin")
equal(origins[1].z, -40, "the synchronous planner gets the followed floor too")
height = 0
assert(detail())
equal(#origins, 2, "same XY on a new floor needs a fresh plan")
equal(origins[2].z, 0, "zero is a known floor")
equal(start(costs, path.batches).z, 0, "a second batch uses the new floor")
equal(path.batches[2].from.z, -40, "a later floor cannot alter an earlier batch")
equal(API.NavVersion(), navVersion, "the floor is not a walking data version")

height, band = nil, { lo = -45, hi = -35 }
equal(start(walk, path.finds).band, band, "a walk can use the journey's height band")
equal(start(costs, path.batches).band, band, "a batch can use the same height band")
band = nil
equal(start(walk, path.finds).z, nil, "an unknown floor leaves the available surfaces open")
local reads = bandReads
assert(estimate())
equal(#origins, 3, "unknown floor does not reuse the known-floor estimate")
equal(bandReads, reads, "estimates that omit terrain also skip its range checks")

local function refused(expected, value, reason)
	equal(value, nil, "refusal returns no result or cancel function")
	equal(reason, expected, "refusal reason")
end

local finds, batches = #path.finds, #path.batches
local db = ns.db
ns.db = nil
for _, call in ipairs({ walk, costs, estimate, detail }) do
	refused("loading", call())
end
ns.db = db
env.InCombatLockdown = function()
	return true
end
for _, call in ipairs({ walk, costs, estimate, detail }) do
	refused("combat", call())
end
env.InCombatLockdown = function()
	return false
end

height = -40
for _, call in ipairs({ walk, costs, estimate, detail }) do
	inInstance = true
	refused("unavailable", call())
	inInstance = false
	onTaxi = true
	refused("unavailable", call())
	onTaxi = false
end
path.data = false
refused("nodata", walk())
refused("nodata", costs())
path.data = true

env.UnitPosition = function() end
env.C_Map.GetBestMapForUnit = function() end
for _, call in ipairs({ walk, costs, estimate, detail }) do
	refused("unavailable", call())
end
refused("invalid", API.Estimate("player", 0.5, nil, to.map, to.x, to.y))
-- Bad targets stay "invalid" while the origin is unavailable, so a caller does not retry them.
refused("invalid", API.WalkPath("PlayerFloor", "player", "nowhere", noCallback))
refused("invalid", API.EstimateWalks("PlayerFloor", "player", "nowhere", noCallback))
refused("invalid", API.EstimateWalks("PlayerFloor", "player", {}, noCallback))
refused("invalid", API.Estimate("player", nil, nil, to.map, 2, to.y))
local canAccess, secret = env.canaccessvalue, {}
env.canaccessvalue = function(value)
	return value ~= secret
end
refused("invalid", walk(secret))
refused("invalid", API.Estimate(secret, nil, nil, to.map, to.x, to.y))
refused("invalid", API.Estimate("player", secret, nil, to.map, to.x, to.y))
env.canaccessvalue = canAccess
equal(#path.finds, finds, "no refusal queued a path")
equal(#path.batches, batches, "no refusal queued a batch")

-- Instance and taxi checks are specific to live origins. Fixed lookups can plan a walk elsewhere.
inInstance, onTaxi = true, true
assert(walk(from))()
assert(costs(from))()
assert(API.Estimate(from.map, from.x, from.y, to.map, to.x, to.y))
assert(API.EstimateDetail(from.map, from.x, from.y, to.map, to.x, to.y))

print("api_player_start: ok")

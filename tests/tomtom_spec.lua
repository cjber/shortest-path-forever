-- The TomTom shim answers a third-party guide's waypoint with a Shortest Path journey, but only while TomTom is
-- absent and the setting is on, and never leaves a waypoint behind a journey that ended.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = driver.ns, driver.env, 0
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- The client has both; the harness supplies them before the shim asks.
local installed = false
env.C_AddOns = {
	DoesAddOnExist = function()
		return installed
	end,
	IsAddOnLoaded = function()
		return installed
	end,
}
-- The real hooksecurefunc runs the hook after the function it hooks.
env.hooksecurefunc = function(target, key, hook)
	local original = target[key]
	target[key] = function(...)
		original(...)
		hook(...)
	end
end
ns.db.tomtom = true

-- The shim's ADDON_LOADED watcher, to hand it TomTom loading later.
local created = {}
local baseFrame = env.CreateFrame
env.CreateFrame = function(...)
	local frame = baseFrame(...)
	created[#created + 1] = frame
	return frame
end
driver.load("Core/TomTom.lua")
local watcher = created[#created]

equal(type(env.TomTom), "table", "the shim is defined while TomTom is absent")
equal(type(env.TomTom.AddWaypoint), "function", "AddWaypoint is present")
equal(type(env.TomTom.AddZWaypoint), "function", "AddZWaypoint is present")
equal(type(env.TomTom.AddMFWaypoint), "function", "AddMFWaypoint is present")
equal(type(env.TomTom.RemoveWaypoint), "function", "RemoveWaypoint is present")
equal(type(env.TomTom.waypoints), "table", "waypoints is present")

-- A Questie ctrl-click names the map first, with normalized coordinates and its own options.
local uid = env.TomTom:AddWaypoint(1, 0.6, 0.5, {
	title = "Questie",
	from = "Questie",
	crazy = true,
	persistent = false,
})
driver.path.settle()
equal(type(uid), "table", "AddWaypoint returns the waypoint")
equal(uid[1], 1, "waypoint map")
equal(uid[2], 0.6, "waypoint x")
equal(uid[3], 0.5, "waypoint y")
equal(uid.title, "Questie", "the caller's title is kept")
equal(uid.from, "Questie", "the caller's name is kept")
equal(uid.crazy, true, "extra options are copied")
equal(uid.persistent, false, "false options are copied")
equal(API.CurrentStop("TomTom"), 1, "the waypoint starts a journey")
equal(ns.HasJourney(), true, "the journey is active")
equal(ns.JourneyInfo(), "Journey to Questie", "the title leads the journey")
equal(env.TomTom.waypoints[1][next(env.TomTom.waypoints[1])], uid, "the waypoint is recorded on its map")

-- A second waypoint replaces the journey rather than queueing behind the first.
local second = env.TomTom:AddWaypoint(1, 0.7, 0.5, { title = "Zygor" })
driver.path.settle()
equal(API.CurrentStop("TomTom"), 1, "a replaced waypoint keeps one journey")
local maps, keys = 0, 0
for _ in pairs(env.TomTom.waypoints) do
	maps = maps + 1
end
for _ in pairs(env.TomTom.waypoints[1]) do
	keys = keys + 1
end
equal(maps, 1, "only the current map carries waypoints")
equal(keys, 1, "only the newest waypoint is kept")
equal(env.TomTom.waypoints[1][next(env.TomTom.waypoints[1])], second, "the newest waypoint is the recorded one")
equal(ns.JourneyInfo(), "Journey to Zygor", "the newest title leads the journey")

-- A guide removes the waypoint it set, and nothing else.
equal(env.TomTom:RemoveWaypoint(second), true, "removing the current waypoint")
equal(API.CurrentStop("TomTom"), nil, "the journey is cleared")
equal(ns.HasJourney(), false, "no journey runs")
equal(next(env.TomTom.waypoints), nil, "the waypoints table is emptied")
equal(env.TomTom:RemoveWaypoint(second), false, "removing twice does nothing")
local live = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "Questie" })
driver.path.settle()
equal(env.TomTom:RemoveWaypoint({ 1, 0.6, 0.5, title = "Something else" }), false, "a foreign waypoint is refused")
equal(API.CurrentStop("TomTom"), 1, "a foreign waypoint leaves the journey running")
env.TomTom:RemoveWaypoint(live)

-- Every argument is checked like the public API's own.
for _, bad in ipairs({ { 0, 0.5, 0.5 }, { 1, 2, 0.5 }, { 1, 0.5, -0.1 }, { 1, 0.5, "0.5" }, { 1, 0 / 0, 0.5 } }) do
	equal(env.TomTom:AddWaypoint(bad[1], bad[2], bad[3], {}), nil, "a bad point is refused")
end
equal(env.TomTom:AddWaypoint(1, 0.5, 0.5, "opts"), nil, "opts must be a table")
equal(env.TomTom:AddWaypoint(1, 0.5, 0.5, { from = 7 }), nil, "from must be a string")
equal(env.TomTom:AddWaypoint(1, 0.5, 0.5, { title = 7 }), nil, "title must be a string")
equal(ns.HasJourney(), false, "bad input starts nothing")

-- The old continent and zone form, on a 0-100 scale.
local zone = env.TomTom:AddZWaypoint(10, 1, 50, 50, "Step", false, true, true, nil, true, true)
driver.path.settle()
equal(type(zone), "table", "AddZWaypoint accepts the zone as a uiMapID")
equal(zone[1], 1, "the zone names the map")
equal(zone[2], 0.5, "coordinates are scaled to 0-1")
equal(zone.title, "Step", "the description is the title")
equal(zone.minimap, true, "flags are copied")
env.TomTom:RemoveWaypoint(zone)
local mapInfo = env.C_Map.GetMapInfo
env.C_Map.GetMapInfo = function(id)
	if id >= 998 then
		return nil
	end
	return mapInfo(id)
end
local fallback = env.TomTom:AddZWaypoint(1, 999, 50, 50, "From the continent")
driver.path.settle()
equal(type(fallback), "table", "the continent is used when the zone is not a map")
equal(fallback[1], 1, "the continent names the map")
env.TomTom:RemoveWaypoint(fallback)
equal(env.TomTom:AddZWaypoint(998, 999, 50, 50, "Nowhere"), nil, "no map means no journey")
env.C_Map.GetMapInfo = mapInfo
local flags = env.TomTom:AddZWaypoint(1, 1, 50, 50, "Flags", false, false, false, false, false, false)
driver.path.settle()
equal(type(flags), "table", "false callbacks and flags are accepted")
env.TomTom:RemoveWaypoint(flags)

-- The map and floor form the newer TomTom also carries.
local mf = env.TomTom:AddMFWaypoint(1, 0, 0.5, 0.5, { title = "Floor" })
driver.path.settle()
equal(type(mf), "table", "AddMFWaypoint starts a journey")
equal(mf.title, "Floor", "AddMFWaypoint keeps the title")
env.TomTom:RemoveWaypoint(mf)
equal(env.TomTom:AddMFWaypoint(1, "0", 0.5, 0.5, {}), nil, "the floor must be a number")

-- A journey the shim did not cancel still leaves no waypoint behind.
local ending = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "Arrive" })
driver.path.settle()
equal(type(ending), "table", "a journey to arrive at")
ns.ClearJourney()
equal(next(env.TomTom.waypoints), nil, "a cleared journey leaves no waypoint")
equal(API.CurrentStop("TomTom"), nil, "the journey is gone")

-- The setting and an installed TomTom both take the global away.
local off = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "Off" })
driver.path.settle()
equal(type(off), "table", "a journey the setting will clear")
ns.db.tomtom = false
ns.RefreshTomTom()
equal(env.TomTom, nil, "the setting removes the global")
equal(ns.HasJourney(), false, "and clears the journey it started")
ns.db.tomtom = true
ns.RefreshTomTom()
equal(type(env.TomTom.AddWaypoint), "function", "the setting brings the global back")
installed = true
ns.RefreshTomTom()
equal(env.TomTom, nil, "an installed TomTom keeps its own global")
installed = false
ns.RefreshTomTom()
equal(type(env.TomTom.AddWaypoint), "function", "with TomTom absent the shim returns")

-- TomTom loading later replaces the global; the shim stands down and clears what it started.
local late = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "Late" })
driver.path.settle()
equal(type(late), "table", "a journey TomTom's arrival will clear")
local real = { AddWaypoint = function() end }
env.TomTom = real
watcher:OnEvent("ADDON_LOADED", "TomTom")
equal(env.TomTom, real, "the real TomTom's global is left alone")
equal(ns.HasJourney(), false, "the shim's journey is cleared when TomTom arrives")

print("tomtom: ok, " .. checks .. " checks")

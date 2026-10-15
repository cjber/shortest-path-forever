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
local installed, disabled, loaded = false, false, false
env.C_AddOns = {
	DoesAddOnExist = function()
		return installed or disabled
	end,
	IsAddOnLoaded = function()
		return loaded
	end,
	GetAddOnEnableState = function(_, character)
		assert(character == "Tester", "enabled for this character")
		return installed and 2 or 0
	end,
}
env.UnitName = function()
	return "Tester"
end
-- The real hooksecurefunc runs the hook after the function it hooks.
env.hooksecurefunc = function(target, key, hook)
	local original = target[key]
	target[key] = function(...)
		original(...)
		hook(...)
	end
end
ns.db.tomtom = true
-- The follow watcher's PLAYER_ENTERING_WORLD waits a frame; nothing here runs it.
env.C_Timer = {
	After = function() end,
}
local combat = false
env.InCombatLockdown = function()
	return combat
end

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

-- The rest of TomTom's waypoint calls that guides make, for the shim's one waypoint.
for _, name in ipairs({
	"IsValidWaypoint",
	"WaypointExists",
	"ClearWaypoint",
	"ClearAllWaypoints",
	"GetClosestWaypoint",
	"SetClosestWaypoint",
	"SetCrazyArrow",
	"GetDistanceToWaypoint",
	"AddWaypointToCurrentZone",
}) do
	equal(type(env.TomTom[name]), "function", name .. " is present")
end
local set = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "RestedXP" })
driver.path.settle()
equal(env.TomTom:IsValidWaypoint(set), true, "the shim's waypoint is valid")
equal(env.TomTom:IsValidWaypoint({ 1, 0.6, 0.5, title = "Other" }), false, "another is not")
equal(env.TomTom:IsValidWaypoint("uid"), false, "nor is a non-table")
equal(env.TomTom:WaypointExists(1, 0.6, 0.5, "RestedXP"), true, "the waypoint exists")
equal(env.TomTom:WaypointExists(1, 0.6, 0.5, "Other"), false, "under its own title only")
equal(env.TomTom:WaypointExists(1, 60 / 100 + 1e-12, 0.5, "RestedXP"), true, "the same point worked out another way")
equal(env.TomTom:WaypointExists(1, driver.secret, 0.5, "RestedXP"), false, "a secret point is never compared")
driver.move({ map = 1, x = 0, y = 0 })
equal(env.TomTom:GetClosestWaypoint(), set, "the closest is the only one")
equal(env.TomTom:SetClosestWaypoint(), set, "and setting it changes nothing")
driver.move({ map = 0, x = 0, y = 0 })
equal(env.TomTom:GetClosestWaypoint(), nil, "none on another continent")
equal(env.TomTom:GetDistanceToWaypoint(set), nil, "and no distance to it")
equal(API.CurrentStop("TomTom"), 1, "the journey runs on")
driver.move({ map = 1, x = 0, y = 0 })
local yards = env.TomTom:GetDistanceToWaypoint(set)
equal(type(yards) == "number" and math.abs(yards - 5000) < 1e-6, true, "its yards from you")
equal(env.TomTom:GetDistanceToWaypoint({ 1, 0.6, 0.5 }), nil, "no distance to another")
env.TomTom:SetCrazyArrow(set, 15, "RestedXP")
equal(env.TomTom:IsValidWaypoint(set), true, "pointing at the current one keeps it")
local held = { 1, 0.7, 0.5, title = "Next step", from = "Guide" }
env.TomTom:SetCrazyArrow(held, 15, "Step 3: Next step")
driver.path.settle()
equal(ns.JourneyInfo(), "Journey to Next step", "pointing at another starts its journey, under its own title")
equal(env.TomTom:IsValidWaypoint(held), true, "and the table the guide holds is the one set")
equal(env.TomTom:GetClosestWaypoint().from, "Guide", "with its own fields")
equal(env.TomTom:ClearWaypoint(set), false, "clearing a replaced waypoint does nothing")
env.TomTom:ClearAllWaypoints()
equal(ns.HasJourney(), false, "clearing all ends the journey")
local bestMap = env.C_Map.GetBestMapForUnit
env.C_Map.GetBestMapForUnit = function()
	return 1
end
local here = env.TomTom:AddWaypointToCurrentZone(60, 50, "Here")
driver.path.settle()
equal(type(here) == "table" and here[1] == 1 and here[2] == 0.6, true, "a waypoint on the map you are on")
equal(env.TomTom:ClearWaypoint(here), true, "cleared like a removal")
equal(env.TomTom:AddWaypointToCurrentZone("60", 50), nil, "bad coordinates are refused")
env.C_Map.GetBestMapForUnit = bestMap

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
-- TomTom switched off in the AddOns list never loads, so the shim answers in its place.
disabled = true
ns.RefreshTomTom()
equal(type(env.TomTom.AddWaypoint), "function", "a disabled TomTom leaves the shim in place")
loaded = true
ns.RefreshTomTom()
equal(env.TomTom, nil, "a loaded TomTom keeps its own global")
disabled, loaded = false, false
ns.RefreshTomTom()
-- A client with no answer for the enable state errs towards TomTom, as before the state was read.
local enableState = env.C_AddOns.GetAddOnEnableState
env.C_AddOns.GetAddOnEnableState = function() end
disabled = true
ns.RefreshTomTom()
equal(env.TomTom, nil, "no enable state reads as an enabled TomTom")
env.C_AddOns.GetAddOnEnableState = enableState
disabled = false
ns.RefreshTomTom()
equal(type(env.TomTom.AddWaypoint), "function", "the shim returns once TomTom is gone")

-- TomTom loading later replaces the global; the shim stands down and clears what it started.
local late = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "Late" })
driver.path.settle()
equal(type(late), "table", "a journey TomTom's arrival will clear")
local real = { AddWaypoint = function() end }
env.TomTom = real
watcher:OnEvent("ADDON_LOADED", "TomTom")
equal(env.TomTom, real, "the real TomTom's global is left alone")
equal(ns.HasJourney(), false, "the shim's journey is cleared when TomTom arrives")

-- Following TomTom's arrow while it is installed: tests/tomtom_follow_spec.lua.

print("tomtom: ok, " .. checks .. " checks")

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
-- One frame later, as the client runs C_Timer.After(0, ...).
local timers = {}
env.C_Timer = {
	After = function(_, fn)
		timers[#timers + 1] = fn
	end,
}
local function nextFrame()
	local due = timers
	timers = {}
	for _, fn in ipairs(due) do
		fn()
	end
end
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

-- With TomTom installed, a journey can follow its arrow: its own SetCrazyArrow and RemoveWaypoint, hooked on its table.
local arrow
local tomtom = {
	AddWaypoint = function(self, map, x, y, opts)
		local point = { map, x, y, title = opts and opts.title }
		self:SetCrazyArrow(point, 15, point.title)
		return point
	end,
	SetCrazyArrow = function(_, point)
		arrow = point
	end,
	RemoveWaypoint = function(_, point)
		if arrow == point then
			arrow = nil
		end
	end,
}
env.TomTom = tomtom
ns.RefreshTomTomFollow()
equal(env.TomTom, tomtom, "TomTom keeps its own table")
-- Off by default: TomTom's own waypoints plan nothing.
local restored = tomtom:AddWaypoint(1, 0.4, 0.4, { title = "Restored" })
equal(arrow, restored, "TomTom's own arrow still takes the waypoint")
equal(ns.HasJourney(), false, "the arrow is not followed while the setting is off")
ns.db.tomtomFollow = true
ns.RefreshTomTomFollow()
-- TomTom restores its saved waypoints as it loads; only waypoints after the world is up are followed.
tomtom:AddWaypoint(1, 0.4, 0.4, { title = "Restored" })
equal(ns.HasJourney(), false, "a waypoint TomTom restores at login plans nothing")
watcher:OnEvent("PLAYER_ENTERING_WORLD")
tomtom:AddWaypoint(1, 0.4, 0.4, { title = "Too soon" })
equal(ns.HasJourney(), false, "nor one in the same frame as the world coming up")
nextFrame()
local way = tomtom:AddWaypoint(1, 0.6, 0.5, { title = "Goldshire" })
driver.path.settle()
equal(API.CurrentStop("TomTom"), 1, "the arrow's waypoint starts a journey")
equal(ns.JourneyInfo(), "Journey to Goldshire", "with TomTom's title")
-- The same waypoint again keeps the journey; a new one replaces it.
tomtom:SetCrazyArrow(way)
equal(API.CurrentStop("TomTom"), 1, "the arrow re-pointed at the same waypoint keeps the journey")
local other = tomtom:AddWaypoint(1, 0.7, 0.5, { title = "Inn" })
driver.path.settle()
equal(ns.JourneyInfo(), "Journey to Inn", "a new arrow waypoint replaces the journey")
-- Removing another waypoint leaves the journey; removing the followed one ends it.
tomtom:RemoveWaypoint(way)
equal(API.CurrentStop("TomTom"), 1, "removing a waypoint not followed keeps the journey")
tomtom:RemoveWaypoint(other)
equal(ns.HasJourney(), false, "removing the followed waypoint ends the journey")
-- A bad waypoint is refused as the API refuses it.
tomtom:SetCrazyArrow({ 1, 2, 0.5 })
tomtom:SetCrazyArrow("uid")
equal(ns.HasJourney(), false, "bad points start nothing")
tomtom:SetCrazyArrow({ 1, 0.55, 0.5, title = 7 })
driver.path.settle()
equal(ns.JourneyInfo(), "Journey to Test", "a bad title is dropped, the point kept")
ns.ClearJourney()
-- In combat the waypoint waits, then is followed once combat ends.
combat = true
local fight = tomtom:AddWaypoint(1, 0.6, 0.5, { title = "After the fight" })
equal(ns.HasJourney(), false, "nothing is planned in combat")
combat = false
watcher:OnEvent("PLAYER_REGEN_ENABLED")
driver.path.settle()
equal(ns.JourneyInfo(), "Journey to After the fight", "the waiting waypoint is followed after combat")
-- A journey of the player's own replaces it; the next arrow change is followed again.
ns.ClearJourney()
tomtom:SetCrazyArrow(fight)
driver.path.settle()
equal(API.CurrentStop("TomTom"), 1, "the arrow is followed again after another journey")
-- Turning the setting off ends the followed journey and follows nothing more.
ns.db.tomtomFollow = false
ns.RefreshTomTomFollow()
equal(ns.HasJourney(), false, "the setting ends the followed journey")
tomtom:AddWaypoint(1, 0.6, 0.5, { title = "Off" })
equal(ns.HasJourney(), false, "and follows nothing more")
-- The hooks are added once, however often the setting changes.
ns.db.tomtomFollow = true
ns.RefreshTomTomFollow()
ns.RefreshTomTomFollow()
local seen = 0
local navigate = API.Navigate
API.Navigate = function(...)
	seen = seen + 1
	return navigate(...)
end
tomtom:AddWaypoint(1, 0.65, 0.5, { title = "Once" })
API.Navigate = navigate
equal(seen, 1, "one hook per TomTom call")
ns.ClearJourney()

print("tomtom: ok, " .. checks .. " checks")

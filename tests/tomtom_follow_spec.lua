-- With TomTom installed and "Follow TomTom's arrow" on, a journey follows the waypoint TomTom's arrow takes. TomTom
-- here is tests/tomtom_fake.lua, which behaves as TomTom v4.3.12 does: the login order, the waypoint's shape, the
-- arrow re-pointing itself, "Remove all waypoints" clearing without RemoveWaypoint, and its corpse arrow.
local Fake = assert(loadfile("tests/tomtom_fake.lua"))()
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- A fresh client with Shortest Path loaded first, as the AddOns folder orders it, and TomTom installed and enabled.
---@param follow boolean the setting
local function Boot(follow)
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local ns, env = driver.ns, driver.env
	driver.load("UI/Looks.lua")
	driver.load("Core/API.lua")
	driver.load("Journey/Itinerary.lua")
	local client = { combat = false, timers = {} }
	env.C_AddOns = {
		DoesAddOnExist = function(name)
			return name == "TomTom"
		end,
		IsAddOnLoaded = function(name)
			return name == "TomTom" and env.TomTom ~= nil
		end,
		GetAddOnEnableState = function(name)
			return name == "TomTom" and 2 or 0
		end,
	}
	env.UnitName = function()
		return "Tester"
	end
	-- The real hooksecurefunc runs the hook after the function it hooks, with the same arguments.
	env.hooksecurefunc = function(target, key, hook)
		local original = target[key]
		target[key] = function(...)
			original(...)
			hook(...)
		end
	end
	env.C_Timer = {
		After = function(_, fn)
			client.timers[#client.timers + 1] = fn
		end,
	}
	env.InCombatLockdown = function()
		return client.combat
	end
	ns.db.tomtom, ns.db.tomtomFollow = true, follow
	local created = {}
	local baseFrame = env.CreateFrame
	env.CreateFrame = function(...)
		local frame = baseFrame(...)
		created[#created + 1] = frame
		return frame
	end
	driver.load("Core/TomTom.lua")
	client.driver, client.ns, client.env, client.watcher = driver, ns, env, created[#created]
	client.API = env.ShortestPathForever.API
	equal(env.TomTom, nil, "an installed TomTom keeps the shim away")
	-- One frame later, as the client runs C_Timer.After(0, ...).
	function client.frame()
		local due = client.timers
		client.timers = {}
		for _, fn in ipairs(due) do
			fn()
		end
		driver.path.settle()
	end
	-- TomTom's files load (its table becomes the global), then its ADDON_LOADED, then PLAYER_LOGIN runs its Enable.
	function client.login(saved)
		local tomtom = Fake.New(saved)
		env.TomTom = tomtom
		client.watcher:OnEvent("ADDON_LOADED", "TomTom")
		tomtom:Enable()
		client.tomtom = tomtom
		return tomtom
	end
	function client.world()
		client.watcher:OnEvent("PLAYER_ENTERING_WORLD")
	end
	function client.title()
		return ns.JourneyInfo()
	end
	return client
end

-- A reload: TomTom restores its saved waypoints at PLAYER_LOGIN, pointing the arrow at each in turn. Nothing is
-- planned before the world is up; then the waypoint the arrow was left on becomes the journey.
do
	local c = Boot(true)
	local tomtom = c.login({ { 1, 0.4, 0.4, title = "Saved A" }, { 1, 0.45, 0.4, title = "Saved B" } })
	equal(type(tomtom.Arrow()), "table", "TomTom's arrow takes a restored waypoint")
	equal(c.ns.HasJourney(), false, "nothing is planned while TomTom restores its waypoints")
	c.world()
	equal(c.ns.HasJourney(), false, "nor in the frame the world comes up")
	c.frame()
	equal(c.API.CurrentStop("TomTom"), 1, "the arrow's waypoint is followed once the world is up")
	equal(c.title(), "Journey to " .. tomtom.Arrow().title, "the journey goes where the arrow points")

	-- /way, a guide's waypoint or the player's pick: each waypoint the arrow takes replaces the journey.
	local way = tomtom:Way(1, 60, 50, "Goldshire")
	c.driver.path.settle()
	equal(c.title(), "Journey to Goldshire", "TomTom's /way is followed, with its title")
	equal(tomtom:Way(1, 60, 50, "Goldshire"), way, "the same /way is TomTom's same waypoint")
	tomtom:SetCrazyArrow(way, 15, way.title)
	equal(c.API.CurrentStop("TomTom"), 1, "the arrow re-pointed at the same waypoint keeps the journey")
	local inn = tomtom:Way(1, 70, 50)
	c.driver.path.settle()
	equal(c.title(), "Journey to TomTom waypoint", "an untitled /way has TomTom's own title")

	-- Removing a waypoint not followed keeps the journey; removing the followed one ends it, and the arrow then
	-- takes the closest one left, which is followed in turn.
	tomtom:RemoveWaypoint(way)
	equal(c.title(), "Journey to TomTom waypoint", "removing another waypoint keeps the journey")
	tomtom:RemoveWaypoint(inn)
	equal(c.ns.HasJourney(), false, "removing the followed waypoint ends the journey")
	local closest = tomtom.waypoints[1][next(tomtom.waypoints[1])]
	tomtom:ArrowUpdate(closest)
	c.driver.path.settle()
	equal(c.title(), "Journey to " .. closest.title, "the closest waypoint the arrow takes next is followed")

	-- "Remove all waypoints" and /way reset all clear through ClearWaypoint and ReloadWaypoints, never RemoveWaypoint.
	tomtom:RemoveAll()
	equal(next(tomtom.waypoints), nil, "TomTom keeps no waypoints")
	equal(c.ns.HasJourney(), false, "removing all of TomTom's waypoints ends the followed journey")

	-- Clearing the arrow alone leaves the waypoint set in TomTom, and the journey with it.
	tomtom:Way(1, 55, 50, "Kept")
	c.driver.path.settle()
	tomtom:ClearCrazyArrowPoint(false)
	equal(c.title(), "Journey to Kept", "clearing only the arrow keeps the journey to a waypoint TomTom still has")
	tomtom:ClearCrazyArrowPoint(true)

	-- Dying: TomTom's corpse arrow is not followed. The corpse run is Shortest Path's own, and the journey you were on
	-- waits for it; coming back to life removes TomTom's corpse waypoint and leaves that journey alone.
	c.API.Navigate("Guide", 1, 0.6, 0.55, "Guide stop")
	c.driver.path.settle()
	local corpse = tomtom:Die(1, 0.3, 0.3)
	equal(tomtom.Arrow(), corpse, "TomTom's arrow points at the corpse")
	c.driver.path.settle()
	equal(c.API.CurrentStop("Guide"), 1, "the corpse arrow does not replace the journey you were on")
	tomtom:Revive()
	tomtom:ArrowUpdate(nil)
	equal(c.title(), "Journey to Guide stop", "nor does its removal end it")
	c.ns.ClearJourney()

	-- In combat the waypoint waits for combat to end; one removed meanwhile is dropped.
	c.combat = true
	tomtom:Way(1, 60, 52, "After the fight")
	equal(c.ns.HasJourney(), false, "nothing is planned in combat")
	c.combat = false
	c.watcher:OnEvent("PLAYER_REGEN_ENABLED")
	c.driver.path.settle()
	equal(c.title(), "Journey to After the fight", "the waiting waypoint is followed after combat")
	c.ns.ClearJourney()
	c.combat = true
	local gone = tomtom:Way(1, 61, 52, "Gone")
	tomtom:RemoveAll()
	c.combat = false
	c.watcher:OnEvent("PLAYER_REGEN_ENABLED")
	equal(c.ns.HasJourney(), false, "a waypoint removed during combat is not followed after it")
	equal(tomtom:IsValidWaypoint(gone), false, "and TomTom no longer has it")

	-- A journey of the player's own replaces the followed one; the arrow's next change is followed again.
	local again = tomtom:Way(1, 60, 52, "After the fight")
	c.driver.path.settle()
	c.ns.ClearJourney()
	tomtom:SetCrazyArrow(again, 15, again.title)
	c.driver.path.settle()
	equal(c.API.CurrentStop("TomTom"), 1, "the arrow is followed again after another journey")

	-- Bad waypoints are refused as the API refuses them.
	c.ns.ClearJourney()
	tomtom:SetCrazyArrow({ 1, 2, 0.5 })
	tomtom:SetCrazyArrow("uid")
	equal(c.ns.HasJourney(), false, "bad points start nothing")
	tomtom:SetCrazyArrow({ 1, 0.55, 0.5, title = 7 })
	c.driver.path.settle()
	equal(c.title(), "Journey to Test", "a bad title is dropped, the point kept")

	-- Turning the setting off ends the followed journey and follows nothing more.
	c.ns.db.tomtomFollow = false
	c.ns.RefreshTomTomFollow()
	equal(c.ns.HasJourney(), false, "the setting ends the followed journey")
	tomtom:Way(1, 62, 50, "Off")
	equal(c.ns.HasJourney(), false, "and follows nothing more")

	-- The hooks are added once, however often the setting changes.
	c.ns.db.tomtomFollow = true
	c.ns.RefreshTomTomFollow()
	c.ns.RefreshTomTomFollow()
	local seen, navigate = 0, c.API.Navigate
	c.API.Navigate = function(...)
		seen = seen + 1
		return navigate(...)
	end
	tomtom:Way(1, 65, 50, "Once")
	c.API.Navigate = navigate
	equal(seen, 1, "one hook per TomTom call")
end

-- A journey already under way when the world comes up is not replaced by a waypoint TomTom restored.
do
	local c = Boot(true)
	c.login({ { 1, 0.4, 0.4, title = "Saved" } })
	c.world()
	c.API.Navigate("Guide", 1, 0.6, 0.55, "Guide stop")
	c.frame()
	equal(c.title(), "Journey to Guide stop", "the journey under way is kept")
end

-- A restored waypoint TomTom drops before the world is up is not followed.
do
	local c = Boot(true)
	local tomtom = c.login({ { 1, 0.4, 0.4, title = "Saved" } })
	tomtom:RemoveAll()
	c.world()
	c.frame()
	equal(c.ns.HasJourney(), false, "a waypoint removed during login plans nothing")
end

-- With the setting off, TomTom's own waypoints plan nothing, at login or after it.
do
	local c = Boot(false)
	local tomtom = c.login({ { 1, 0.4, 0.4, title = "Saved" } })
	c.world()
	c.frame()
	equal(c.ns.HasJourney(), false, "a restored waypoint is not followed while the setting is off")
	tomtom:Way(1, 60, 50, "Goldshire")
	equal(c.ns.HasJourney(), false, "nor a new one")
	equal(tomtom.Arrow().title, "Goldshire", "TomTom's arrow is its own")
end

print("tomtom_follow: ok, " .. checks .. " checks")

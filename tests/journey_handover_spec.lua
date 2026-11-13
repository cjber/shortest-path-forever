-- A journey shown to a tracked quest, and TomTom's arrow pointing at the same place under its own name: the journey
-- is handed over, not started again. Restarting it stopped the guide, took the native waypoint away and searched the
-- same place afresh, so guidance blinked off and on while the journey scanned, and every waypoint TomTom re-pointed
-- at that destination did it again (#826).
local Fake = assert(loadfile("tests/tomtom_fake.lua"))()
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env

driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
driver.load("Core/Zygor.lua")

-- The client's TomTom, installed and enabled as the AddOns folder orders it (Shortest Path loads first).
local timers, created = {}, {}
env.C_AddOns = {
	DoesAddOnExist = function(name)
		return name == "TomTom"
	end,
	IsAddOnLoaded = function(name)
		return name == "TomTom" and env.TomTom ~= nil
	end,
	GetAddOnEnableState = function()
		return 2
	end,
}
env.UnitName = function()
	return "Tester"
end
env.hooksecurefunc = function(target, key, hook)
	local original = target[key] or function() end
	target[key] = function(...)
		local result = original(...)
		hook(...)
		return result
	end
end
env.C_Timer = {
	After = function(_, fn)
		timers[#timers + 1] = fn
	end,
}
local createFrame = env.CreateFrame
env.CreateFrame = function(...)
	local frame = createFrame(...)
	created[#created + 1] = frame
	return frame
end
ns.db.tomtom, ns.db.tomtomFollow = true, true
ns.PointGuideArrow = function(points, placeBend)
	-- The arrow places the bend it is handed, as its poll does, and the guide writes its waypoint.
	if points and placeBend then
		placeBend(points[#points], false)
	end
end

local starts, searches, writes, clears = 0, 0, 0, 0
local startJourney, startSearch = ns.StartJourney, ns.JourneySearch.Start
ns.StartJourney = function(...)
	starts = starts + 1
	return startJourney(...)
end
ns.JourneySearch.Start = function(...)
	searches = searches + 1
	return startSearch(...)
end
local setWaypoint, clearWaypoint = env.C_Map.SetUserWaypoint, env.C_Map.ClearUserWaypoint
env.C_Map.SetUserWaypoint = function(point)
	writes = writes + 1
	return setWaypoint(point)
end
env.C_Map.ClearUserWaypoint = function(...)
	clears = clears + 1
	return clearWaypoint(...)
end

driver.load("Core/TomTom.lua")
local API = env.ShortestPathForever.API
local tomtom = Fake.New(nil)
function tomtom.ShowHideCrazyArrow() end
env.TomTom = tomtom
created[#created]:OnEvent("ADDON_LOADED", "TomTom")
tomtom:Enable()
created[#created]:OnEvent("PLAYER_ENTERING_WORLD")
for _, fn in ipairs(timers) do
	fn()
end
driver.path.settle()

-- One quest tracked, and the journey the tracker binding plans: the player's own, to the quest's objective, with no
-- addon owning it.
local QUEST = 1234
env.C_SuperTrack.SetSuperTrackedQuestID(QUEST)
local MAP, X, Y = 1, 0.6, 0.5
local objective = assert(ns.WorldPoint(MAP, X, Y))
objective.label, objective.questID, objective.questIDs = "The Escape", QUEST, { QUEST }
assert(ns.StartJourney(objective))
driver.path.settle()
assert(driver.shown(), "the journey is drawn")
assert(ns.IsJourneyGuided(), "and guided")
assert(driver.waypoint(), "the guide writes its waypoint")
assert(starts == 1 and searches == 1, "one journey, one search")
local heldWrites, heldClears = writes, clears
local waypoint = driver.waypoint()

-- TomTom's arrow takes its own waypoint at that same objective, as it does when a waypoint it holds is re-added or
-- the closest one left is taken. The place is the journey's, so nothing restarts.
assert(tomtom:AddWaypoint(MAP, X, Y, { title = "The Escape" }))
driver.path.settle()
assert(starts == 1, "the same destination from TomTom's arrow starts no second journey")
assert(searches == 1, "and searches nothing")
assert(ns.IsJourneyGuided(), "guidance is not stopped and started again")
assert(driver.waypoint() == waypoint and writes == heldWrites and clears == heldClears, "the waypoint is kept")
assert(driver.shown(), "the drawn route stays")
assert(API.CurrentStop("TomTom") == 1, "TomTom's stop is the journey's")

-- TomTom's arrow re-points at the same place through a waypoint of its own again: still the journey it had.
local again = tomtom:AddWaypoint(MAP, X, Y, { title = "Turn in: The Escape" })
tomtom:SetCrazyArrow(again, 15, again.title)
driver.path.settle()
assert(starts == 1 and searches == 1, "a second waypoint at the same destination starts nothing")
assert(ns.IsJourneyGuided() and driver.waypoint(), "guidance and its waypoint are still there")
assert(API.Ended("TomTom") == nil, "the journey TomTom owns has not ended")

-- A guide naming the same stop hands the journey over from TomTom: only who owns it changes.
assert(API.NavigateRoute("Guide", { { map = MAP, x = X, y = Y, title = "The Escape" } }))
driver.path.settle()
assert(starts == 1 and searches == 1, "another owner at the same destination starts nothing")
assert(ns.IsJourneyGuided() and driver.waypoint(), "guidance and its waypoint stay")
assert(API.Ended("TomTom") == "replaced", "the owner before reads replaced")
assert(API.CurrentStop("Guide") == 1, "and the guide's stop is the journey's")

-- A destination that really is elsewhere is a new journey, as the API has always answered.
assert(tomtom:AddWaypoint(1, 0.7, 0.5, { title = "Somewhere else" }))
driver.path.settle()
assert(starts == 2, "another place is a new journey")
assert(ns.JourneyGoal().y ~= objective.y, "the journey now goes there")

-- While the journey is still scanning, with its first route not found yet, a re-point at the same destination must
-- not start the search over: that is the "Finding the fastest way…" left running while guidance blinked (#826).
ns.ClearJourney()
driver.path.settle()
driver.path.auto = false
local scanningStarts, scanningSearches = starts, searches
assert(API.NavigateRoute("Guide", { { map = MAP, x = X, y = Y, title = "The Escape" } }))
assert(ns.JourneyStatus() == true, "the journey is scanning")
assert(API.NavigateRoute("TomTom", { { map = MAP, x = X, y = Y, title = "The Escape" } }))
assert(starts == scanningStarts + 1, "the hand-over starts no second journey while the first is scanning")
assert(searches == scanningSearches + 1, "and does not restart the search")
assert(ns.JourneyStatus() == true, "the same search is the one still running")
driver.path.auto = true
driver.path.settle()
assert(driver.shown(), "the first search settles into the journey it was searching for")

print("journey handover: another owner re-pointing the journey's own destination keeps it")

local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API

local combat = false
env.InCombatLockdown = function()
	return combat
end
-- The client runs a secure hook's callback after the hooked method; the test does the same, and refuses to wrap a
-- missing method as the client would.
env.hooksecurefunc = function(object, method, callback)
	local original = object[method]
	assert(type(original) == "function", "hooksecurefunc needs a real method: " .. method)
	object[method] = function(...)
		original(...)
		callback(...)
	end
end

-- A change inside Dugi's call stack asks for one read on the next frame. The test runs those explicitly.
local timers = {}
env.C_Timer = {
	After = function(_, callback)
		timers[#timers + 1] = callback
	end,
}
local function flush()
	while #timers > 0 do
		local callback = table.remove(timers, 1)
		callback()
	end
end

-- Dugi 1.087's shape, synthetic: the viewer publishes the guide state, and its arrow module owns the waypoints.
-- The arrow's real methods are defined inside Initialize, so the module starts without a raw WaypointsChanged.
local smart
local viewer = {
	chardb = { GuideOn = true },
	guides = { ["Dugi Guide"] = true },
	actions = {},
	GuideOn = function(self)
		return self.chardb.GuideOn
	end,
	isValidGuide = function(self, title)
		return self.guides[title] ~= nil
	end,
	GetRunningAutoroutine = function(key)
		return key == "SetSmartWaypoint" and smart or nil
	end,
	ReloadModules = function() end,
	ClearScreen = function() end,
	LoadNextGuide = function() end,
}
local arrow = {}
viewer.DugisArrow = arrow
env.DugisGuideViewer = viewer
env.CurrentTitle = "Dugi Guide"
env.C_QuestLog = {
	GetTitleForQuestID = function(questID)
		return questID == 100 and "The Farm" or nil
	end,
}

local originalReloadModules = viewer.ReloadModules
local watcher
local create = env.CreateFrame
env.CreateFrame = function(...)
	watcher = create(...)
	return watcher
end
ns.db.dugi = true
driver.load("Core/Dugi.lua")

-- Dugi's arrow module answers missing methods with a callable stub until Initialize runs; the adapter must not hook
-- that stub. A module load is the signal that the real method exists now.
assert(rawget(arrow, "WaypointsChanged") == nil, "the uninitialized arrow module exposes no raw callback")
assert(rawget(viewer, "ReloadModules") ~= originalReloadModules, "the module load is watched")
arrow.WaypointsChanged = function() end
viewer:ReloadModules()
flush()
assert(rawget(arrow, "WaypointsChanged") ~= nil, "the initialized arrow callback is hooked")

-- A guide's next destination is the first waypoint that is not a travel leg, not the last coordinate of a
-- multi-coordinate step. The travel leg carries the flight step's quest id, and must never become the stop.
local planned, navigations = nil, 0
local navigate = API.NavigateRoute
API.NavigateRoute = function(owner, stops)
	if owner == "Dugi" then
		navigations = navigations + 1
		planned = stops[1]
	end
	return navigate(owner, stops)
end

viewer.actions[1], viewer.actions[2] = "R", "A"
arrow.waypoints = {
	{ map = 1, x = 40, y = 40, desc = "Fly to Ironforge", guideIndex = 1, questId = 307, isRouteWaypoint = true },
	{ map = 1, x = 60, y = 50, desc = "|cffffd200Accept 'The Farm'|r", guideIndex = 2, questId = 100 },
	{ map = 1, x = 70, y = 30, desc = "Last stop of the step", guideIndex = 2, questId = 100 },
}
arrow:WaypointsChanged()
flush()
assert(navigations == 1 and API.CurrentStop("Dugi") == 1, "the guide's next destination starts a journey")
assert(planned.map == 1 and planned.x == 0.6 and planned.y == 0.5, "the first objective is used, not the last")
assert(planned.x ~= 0.7, "the final waypoint of a multi-coordinate step is not the next stop")
assert(planned.hold == true, "Dugi decides when its step is complete")
assert(planned.questIDs and planned.questIDs[1] == 100, "an accept step names its quest")
assert(planned.tooltip == "The Farm (pick up)", "and the shared collector words the action")
assert(planned.title == "Accept 'The Farm'", "the step's colour markup is cleaned: " .. tostring(planned.title))

-- A travel leg is only flagged after Dugi's change callback fires. The one-frame read sees the flag, not a
-- half-built route: without that deferral the flight leg's quest id would become the stop.
navigations = 0
local leg = { map = 1, x = 45, y = 45, desc = "Fly", guideIndex = 3, questId = 307 }
viewer.actions[3], viewer.actions[4] = "R", "A"
arrow.waypoints = { leg }
arrow:WaypointsChanged()
leg.isRouteWaypoint = true
arrow.waypoints[2] = { map = 1, x = 65, y = 55, desc = "New step", guideIndex = 4, questId = 200 }
flush()
assert(navigations == 1 and planned.x == 0.65, "a travel leg still being flagged is not planned")

-- The smart route clears the waypoints and fills them in later, so an empty list while it runs is a step in
-- progress. The journey waits rather than cancelling and replanning through every intermediate state.
navigations = 0
smart = {}
arrow.waypoints = nil
arrow:WaypointsChanged()
flush()
assert(API.CurrentStop("Dugi") == 1, "a smart route in progress keeps the current stop")
assert(navigations == 0, "no half-built route is planned")
smart = nil
arrow.waypoints = { { map = 1, x = 65, y = 55, desc = "Step", guideIndex = 4, questId = 200 } }
arrow:WaypointsChanged()
flush()
assert(navigations == 0, "the completed route kept the same place")

-- A step that moves on at the same place updates the stop's quest and label instead of planning a second route.
navigations = 0
viewer.actions[5] = "T"
arrow.waypoints = { { map = 1, x = 65, y = 55, desc = "Turn in 'The Farm'", guideIndex = 5, questId = 100 } }
arrow:WaypointsChanged()
flush()
assert(navigations == 0, "the same place plans nothing")
local goal = ns.JourneyGoal()
assert(goal and goal.questIDs and goal.questIDs[1] == 100, "the turn-in stands for its quest")
assert(goal.label == "Turn in 'The Farm'", "the step's new title names the stop: " .. tostring(goal.label))
assert(goal.details and goal.details[1] == "The Farm (turn in)", "with its action line")

viewer.actions[6] = "T"
arrow.waypoints = { { map = 1, x = 65, y = 55, desc = "Turn in 'The Second'", guideIndex = 6, questId = 101 } }
arrow:WaypointsChanged()
flush()
goal = ns.JourneyGoal()
assert(navigations == 0, "a second transition at the same place plans nothing")
assert(goal.questIDs and goal.questIDs[1] == 101, "the same stop now stands for the next quest")
assert(goal.label == "Turn in 'The Second'", "and its title moved on")

-- Travel steps carry a quest id too; only accept, turn in, complete and kill steps name a quest. A POI step has no
-- guide index and carries the quest itself.
navigations = 0
viewer.actions[7] = "R"
arrow.waypoints = { { map = 1, x = 43, y = 47, desc = "Fly to the next zone", guideIndex = 7, questId = 307 } }
arrow:WaypointsChanged()
flush()
assert(navigations == 1 and planned.questIDs == nil and planned.tooltip == nil, "a flight step names no quest")
arrow.waypoints = { { map = 1, x = 44, y = 48, desc = "Find the farm", questId = 309 } }
arrow:WaypointsChanged()
flush()
assert(navigations == 2 and planned.questIDs and planned.questIDs[1] == 309, "a POI step keeps its quest")

-- A map the client does not know, a non-finite coordinate or one outside the percent range clears the journey.
local mapInfo = env.C_Map.GetMapInfo
env.C_Map.GetMapInfo = function(mapID)
	if mapID == 999 then
		return nil
	end
	return mapInfo(mapID)
end
navigations = 0
arrow.waypoints = { { map = 999, x = 50, y = 50, desc = "Nowhere", guideIndex = 8, questId = 300 } }
arrow:WaypointsChanged()
flush()
assert(not API.CurrentStop("Dugi") and navigations == 0, "an unknown map clears the journey")
arrow.waypoints = { { map = 1, x = 0 / 0, y = 50, desc = "Nowhere", guideIndex = 8, questId = 300 } }
arrow:WaypointsChanged()
flush()
assert(not API.CurrentStop("Dugi") and navigations == 0, "a non-finite coordinate clears the journey")
arrow.waypoints = { { map = 1, x = 150, y = 50, desc = "Outside", guideIndex = 8, questId = 300 } }
arrow:WaypointsChanged()
flush()
assert(not API.CurrentStop("Dugi") and navigations == 0, "a coordinate outside the map clears the journey")
env.C_Map.GetMapInfo = mapInfo

-- Combat defers the change and comes back to it once combat ends.
navigations = 0
arrow.waypoints = { { map = 1, x = 55, y = 45, desc = "Step", guideIndex = 9, questId = 400 } }
arrow:WaypointsChanged()
flush()
assert(API.CurrentStop("Dugi") == 1, "a valid step starts again")
combat = true
arrow.waypoints = { { map = 1, x = 56, y = 46, desc = "Step", guideIndex = 9, questId = 400 } }
arrow:WaypointsChanged()
flush()
assert(navigations == 1, "combat defers the next step")
assert(not API.CurrentStop("Dugi"), "and drops the stale stop while it waits")
combat = false
watcher:OnEvent("PLAYER_REGEN_ENABLED")
driver.path.settle()
assert(navigations == 2 and API.CurrentStop("Dugi") == 1, "combat end uses the latest step")

-- A guide switched off, cleared or missing its title ends only its own journey.
viewer.chardb.GuideOn = false
arrow:WaypointsChanged()
flush()
assert(not API.CurrentStop("Dugi"), "a guide switched off clears its journey")
assert(
	API.NavigateRoute("RestedXP", { { map = 1, x = 0.4, y = 0.4, title = "Other guide" } }),
	"another guide's journey starts"
)
arrow:WaypointsChanged()
flush()
assert(API.CurrentStop("RestedXP") == 1, "another owner's journey is never cancelled")
viewer.chardb.GuideOn = true
env.CurrentTitle = nil
arrow:WaypointsChanged()
flush()
assert(not API.CurrentStop("Dugi"), "a guide with no title clears the journey")
env.CurrentTitle = "Dugi Guide"
API.Cancel("RestedXP")

-- A guide that advances past its last step clears the title without a waypoint change; the guide clear is a signal.
navigations = 0
arrow.waypoints = { { map = 1, x = 57, y = 47, desc = "Step", guideIndex = 9, questId = 400 } }
ns.ResumeDugi()
driver.path.settle()
assert(API.CurrentStop("Dugi") == 1, "a valid step starts again before the guide clears")
env.CurrentTitle = nil
viewer:LoadNextGuide()
flush()
assert(not API.CurrentStop("Dugi"), "a guide advanced past its last step clears the journey")
env.CurrentTitle = "Dugi Guide"

-- RestedXP, Adventure Guide and Guidelime lead while they run; when one stops leading, the step comes back.
navigations = 0
arrow.waypoints = { { map = 1, x = 57, y = 47, desc = "Step", guideIndex = 9, questId = 400 } }
ns.ResumeDugi()
driver.path.settle()
assert(API.CurrentStop("Dugi") == 1, "the guide takes its step after another owner ends")
assert(API.NavigateRoute("Guidelime", { { map = 1, x = 0.4, y = 0.4, title = "Guidelime step" } }))
navigations = 0
arrow.waypoints = { { map = 1, x = 58, y = 48, desc = "Step", guideIndex = 9, questId = 400 } }
arrow:WaypointsChanged()
flush()
assert(API.CurrentStop("Guidelime") == 1 and navigations == 0, "Dugi yields to Guidelime")
API.Cancel("Guidelime")
flush()
assert(API.CurrentStop("Dugi") == 1, "Guidelime ending hands the step back")

-- A higher-ranked guide's takeover is seen through JourneyChanged itself, so its own cancel hands the step back even
-- when Dugi's arrow never changed in between.
assert(
	API.NavigateRoute("Guidelime", { { map = 1, x = 0.4, y = 0.4, title = "Guidelime step" } }),
	"Guidelime takes the journey"
)
assert(not API.CurrentStop("Dugi"), "Guidelime leads without a Dugi change")
API.Cancel("Guidelime")
flush()
assert(API.CurrentStop("Dugi") == 1, "the leader's own cancel hands the step back without a Dugi callback")

-- The player clearing the journey another guide led is not an invitation for Dugi to take it back: it stays off until
-- *Resume guide*. API.Cancel marks the leader cancelled only after ClearJourney returns, so the handback is read from
-- API.Ended on the next frame, where a player clear is still "cleared".
assert(
	API.NavigateRoute("Guidelime", { { map = 1, x = 0.4, y = 0.4, title = "Guidelime step" } }),
	"Guidelime takes the journey again"
)
arrow:WaypointsChanged()
flush()
assert(API.CurrentStop("Guidelime") == 1, "Guidelime still leads")
ns.ClearJourney()
flush()
assert(not API.CurrentStop("Dugi") and not ns.JourneyOwner(), "the player's clear is not turned into a Dugi start")
arrow:WaypointsChanged()
flush()
assert(not API.CurrentStop("Dugi"), "and Dugi stays off until Resume")
ns.ResumeDugi()
driver.path.settle()
assert(API.CurrentStop("Dugi") == 1, "Resume takes the step back")

-- Resume takes the step back from another owner and after the player cancels it.
assert(API.NavigateRoute("Other", { { map = 1, x = 0.4, y = 0.4, title = "Other" } }))
ns.ResumeDugi()
driver.path.settle()
assert(API.CurrentStop("Dugi") == 1, "resume takes the current step back")
API.Cancel("Dugi")
assert(not API.CurrentStop("Dugi"), "a cancelled guide journey stays cancelled")
ns.ResumeDugi()
driver.path.settle()
assert(API.CurrentStop("Dugi") == 1, "resume starts the same step again")

-- The setting and journeys gate the follower.
ns.db.dugi = false
ns.RefreshDugi()
assert(not API.CurrentStop("Dugi"), "the setting off clears its journey")
ns.db.dugi = true
ns.RefreshDugi()
driver.path.settle()
assert(API.CurrentStop("Dugi") == 1, "the setting on follows the current step")
ns.db.journey = false
ns.RefreshDugi()
assert(not API.CurrentStop("Dugi"), "journeys off clears its journey")
ns.db.journey = true

-- Reading is all the adapter does: no waypoint field, action table or guide table is written.
local waypoint = { map = 1, x = 59, y = 49, desc = "Kill the wolves", guideIndex = 10, questId = 401 }
viewer.actions[10] = "K"
local snapshot = {}
for key, value in pairs(waypoint) do
	snapshot[key] = value
end
arrow.waypoints = { waypoint }
arrow:WaypointsChanged()
flush()
for key, value in pairs(waypoint) do
	assert(snapshot[key] == value, "no waypoint field is written: " .. key)
end
local fields = 0
for _ in pairs(waypoint) do
	fields = fields + 1
end
assert(fields == 6, "no field is added to the waypoint")
assert(viewer.actions[10] == "K" and viewer.guides["Dugi Guide"] == true, "no Dugi table is changed")

-- A guide whose module never initializes leaves the last journey alone and plans nothing.
local last = API.CurrentStop("Dugi")
arrow.WaypointsChanged = nil
viewer:ReloadModules()
flush()
assert(API.CurrentStop("Dugi") == last, "an uninitialized arrow module does not disturb the stop")

-- Dugi's scheduler keeps an interrupted SetSmartWaypoint in the running list until it next reaps it, and it emits no
-- follow-up change event. An interrupted routine is therefore not a step in progress: the stop it left behind goes.
assert(last, "the previous step is still followed")
arrow.WaypointsChanged = function() end
ns.RefreshDugi()
flush()
smart = { interrupt = true }
arrow.waypoints = nil
arrow:WaypointsChanged()
flush()
assert(not API.CurrentStop("Dugi"), "an interrupted smart routine no longer holds the stop")
assert(not ns.JourneyOwner(), "and it starts nothing else")
smart = nil

print("dugi: ok")

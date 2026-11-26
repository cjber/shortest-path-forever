-- Run from the repository root: luajit tests/focused_pin_clear_spec.lua
-- Deleting the map pin that planned a journey ends that journey (#1348), without clearing a guide's journey,
-- a journey the player replaced, or a journey whose native waypoint Guide itself cleared or moved to a bend.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env

driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API

local function vector(x, y)
	return {
		x = x,
		y = y,
		GetXY = function(self)
			return self.x, self.y
		end,
	}
end

-- Project points back onto their map coordinates instead of the driver's fixed (0.5, 0.5) spot at the player.
ns.Locate = function(point)
	local uiMap, pos = env.C_Map.GetMapPosFromWorldPos(point.map, vector(point.x, point.y))
	return { uiMap = uiMap, x = pos.x, y = pos.y, zone = "Test" }
end

local placeBend
ns.PointGuideArrow = function(points, callback)
	placeBend = callback
	if points and callback then
		callback(points[#points], false)
	end
end

local function pin(uiMapID, x, y)
	env.C_Map.SetUserWaypoint({ uiMapID = uiMapID, position = vector(x, y) })
	driver.update(0)
end

local function clearPin()
	env.C_Map.ClearUserWaypoint()
	driver.update(0)
end

driver.fire("PLAYER_LOGIN")
ns.db.focusedQuest = false

-- A quest route's guide marker is also the user waypoint OpenMap mirrors. Clearing that borrowed marker must end the
-- quest route even though no player pin planned it (#1366).
local questGoal = { map = 1, x = 900, y = 0, z = 0, questID = 77, questIDs = { 77 } }
assert(ns.StartJourney(questGoal), "a quest route starts a journey")
driver.update(0)
assert(env.C_Map.GetUserWaypoint(), "the quest route has a guide waypoint for OpenMap to mirror")
clearPin()
assert(not ns.HasJourney(), "clearing the borrowed guide waypoint ends the quest route")

-- With focused routing on, placing a map pin starts a journey and deleting it ends the route (#1348).
ns.db.focusedQuest = true
ns.db.guideStops = true
pin(1, 0.4, 0.6)
assert(ns.HasJourney(), "placing a map pin starts a journey")
assert(env.C_Map.GetUserWaypoint(), "the pin is on the map")
clearPin()
assert(not ns.HasJourney(), "deleting the focused pin cancels the route it planned")
assert(env.C_Map.GetUserWaypoint() == nil, "clearing the route does not restore the deleted pin")

-- In bend-marking mode, Guide moves the native waypoint onto an intermediate bend (owned = true);
-- that Guide write must not forget the pin-planned goal, so deleting the pin still ends the route.
ns.db.guideStops = false
pin(1, 0.4, 0.6)
local bendGoal = ns.JourneyGoal()
assert(bendGoal, "pin starts a journey in bend-marking mode")
assert(placeBend and placeBend({ map = 1, x = 1200, y = 400 }, false), "Guide writes a bend waypoint")
driver.update(0)
assert(ns.JourneyGoal() == bendGoal, "Guide moving the waypoint to a bend keeps the journey")
clearPin()
assert(not ns.HasJourney(), "deleting the pin after Guide moved it to a bend still cancels the route")

-- Guide's own temporary waypoint clear (e.g. hiding directions or pausing) is Guide-owned and must keep the journey.
ns.db.guideStops = true
pin(1, 0.4, 0.6)
local heldGoal = ns.JourneyGoal()
assert(heldGoal, "pin starts a journey before Guide clears its own waypoint")
ns.JourneyGuide.Pause()
driver.update(0)
assert(ns.JourneyGoal() == heldGoal, "Guide pausing and clearing its own waypoint keeps the journey")
-- When Guide writes the pin again and the player deletes it, the journey still ends.
ns.JourneyGuide.To(heldGoal, { heldGoal }, heldGoal)
driver.update(0)
clearPin()
assert(not ns.HasJourney(), "deleting the pin after Guide resumed still cancels the route")

-- A player clicking a quest yields native tracking (Guide clears its own waypoint), keeping the pin-planned journey.
pin(1, 0.4, 0.6)
local yieldedGoal = ns.JourneyGoal()
assert(yieldedGoal, "pin starts a journey before yielding to a quest")
env.C_SuperTrack.SetSuperTrackedQuestID(77)
driver.update(0)
assert(ns.JourneyGoal() == yieldedGoal, "Guide clearing its waypoint on yield keeps the journey")
ns.ClearJourney()
env.C_SuperTrack.SetSuperTrackedQuestID(0)
driver.update(0)
clearPin()

-- Toggling guidance off restores the player's pin (owned = true); deleting that pin still ends the unguided route.
pin(1, 0.4, 0.6)
local unguidedGoal = ns.JourneyGoal()
assert(unguidedGoal and ns.IsJourneyGuided(), "pin starts a guided journey")
ns.ToggleJourneyGuide()
driver.update(0)
assert(ns.JourneyGoal() == unguidedGoal and not ns.IsJourneyGuided(), "toggling guidance off keeps the route")
assert(env.C_Map.GetUserWaypoint(), "and restores the player's pin")
clearPin()
assert(not ns.HasJourney(), "deleting the restored pin ends the unguided route")

-- Crossing a loading screen (boat, portal, tram) runs FocusedTrackingReset; deleting the pin afterwards still ends it.
pin(1, 0.4, 0.6)
assert(ns.HasJourney(), "pin starts a journey before a loading screen")
driver.fire("PLAYER_ENTERING_WORLD")
clearPin()
assert(not ns.HasJourney(), "deleting the pin after a loading screen still cancels the route")

-- Re-pinning the same destination after Guide moved the pin to a bend keeps ownership so deleting it still cancels.
ns.db.guideStops = false
pin(1, 0.4, 0.6)
local sameGoal = ns.JourneyGoal()
assert(placeBend and placeBend({ map = 1, x = 1200, y = 400 }, false), "Guide moves waypoint to a bend")
driver.update(0)
pin(1, 0.4, 0.6)
assert(ns.JourneyGoal() == sameGoal, "re-pinning the same destination keeps the journey")
clearPin()
assert(not ns.HasJourney(), "deleting the re-pinned destination still cancels the route")
ns.db.guideStops = true

-- Deleting the pin mid-search (before Guide writes a waypoint) still cancels the route.
driver.path.auto = false
pin(1, 0.4, 0.6)
assert(ns.HasJourney(), "pin starts a journey before the walk settles")
clearPin()
assert(not ns.HasJourney(), "deleting the pin before the search settles still cancels the route")
driver.path.auto = true

-- Moving the pin from A to B transfers ownership to B; deleting B cancels B.
pin(1, 0.4, 0.6)
local goalA = ns.JourneyGoal()
pin(1, 0.3, 0.7)
local goalB = ns.JourneyGoal()
assert(goalB and goalB ~= goalA, "moving the pin plans a new journey")
clearPin()
assert(not ns.HasJourney(), "deleting the moved pin cancels the new journey")

-- Deleting the waypoint does NOT cancel a journey the player started with Shift-click.
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 4000, y = 0, z = 0 })
local shiftGoal = ns.JourneyGoal()
assert(shiftGoal, "Shift-click starts a journey")
clearPin()
assert(ns.JourneyGoal() == shiftGoal, "deleting the pin keeps a Shift-click journey")
ns.ClearJourney()

-- Deleting the pin does NOT cancel a journey that replaced the pin-planned one (Shift-click replacement).
pin(1, 0.4, 0.6)
assert(ns.HasJourney(), "pin starts a journey")
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 5000, y = 0, z = 0 })
local replaced = ns.JourneyGoal()
assert(replaced, "Shift-click replaces the pin journey")
clearPin()
assert(ns.JourneyGoal() == replaced, "deleting the pin preserves the replacement journey")
ns.ClearJourney()

-- Manually restarting to the same pin via the Travel to my map pin binding replaces the pin-owned goal.
pin(1, 0.4, 0.6)
assert(ns.JourneyToUserWaypoint(), "manual binding restarts to the same pin")
local manual = ns.JourneyGoal()
clearPin()
assert(ns.JourneyGoal() == manual, "deleting the pin preserves a manually restarted journey")
ns.ClearJourney()

-- Deleting the pin NEVER cancels a guide addon's journey.
assert(API.NavigateRoute("Guide", { { map = 1, x = 0.4, y = 0.5, title = "Step 1" } }))
driver.path.settle()
local guideGoal = ns.JourneyGoal()
assert(guideGoal and API.CurrentStop("Guide") == 1, "guide owns the journey")
clearPin()
assert(ns.JourneyGoal() == guideGoal and API.CurrentStop("Guide") == 1, "deleting the pin keeps a guide's journey")
API.Cancel("Guide")

-- Even if a guide takes over right after a pin-planned journey, deleting the pin leaves the guide's journey alone.
pin(1, 0.4, 0.6)
assert(API.NavigateRoute("Guide", { { map = 1, x = 0.4, y = 0.5, title = "Step 1" } }))
driver.path.settle()
local takenOver = ns.JourneyGoal()
clearPin()
assert(ns.JourneyGoal() == takenOver and API.CurrentStop("Guide") == 1, "deleting the pin keeps a taking-over guide")
API.Cancel("Guide")

-- A pre-existing pin present at login cancels nothing when deleted.
env.C_Map.SetUserWaypoint({ uiMapID = 1, position = vector(0.4, 0.6) })
driver.fire("PLAYER_LOGIN")
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 3000, y = 0, z = 0 })
local afterLogin = ns.JourneyGoal()
clearPin()
assert(ns.JourneyGoal() == afterLogin, "deleting a pin from before login cancels no journey")
ns.ClearJourney()

print("focused pin clear: ok")

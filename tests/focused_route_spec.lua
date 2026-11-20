-- Run from the repository root: luajit tests/focused_route_spec.lua
-- Route to the focused quest (Journey/JourneyInput.lua): with the setting on, a super-tracked quest or the player's
-- own map pin starts a journey. A guide's own journey and a guide's own waypoint writes are left alone, including
-- the pin Guide gives back when it stops.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env

local function vector(x, y)
	return {
		x = x,
		y = y,
		GetXY = function(self)
			return self.x, self.y
		end,
	}
end

-- The quest side of JourneyInput.PlanQuest, without the real quest log.
env.GetQuestUiMapID = function()
	return 1
end
env.C_QuestLog = {
	GetNextWaypoint = function()
		return 1, 0.5, 0.5
	end,
	GetQuestsOnMap = function()
		return {}
	end,
	GetTitleForQuestID = function(questID)
		return "Focused " .. questID
	end,
	IsComplete = function()
		return false
	end,
}
ns.Planner.QuestDestination = function(questID)
	return { uiMapID = 1, x = 0.8, y = 0.8, label = "Focused " .. questID }
end

local function focus(questID)
	env.C_SuperTrack.SetSuperTrackedQuestID(questID)
	driver.update(0)
end

local function pin(uiMapID, x, y)
	env.C_Map.SetUserWaypoint({ uiMapID = uiMapID, position = vector(x, y) })
	driver.update(0)
end

local function clearPin()
	env.C_Map.ClearUserWaypoint()
	driver.update(0)
end

local function goalQuest()
	local goal = ns.JourneyGoal()
	return goal and goal.questID
end

driver.fire("PLAYER_LOGIN")
ns.db.focusedQuest = false

-- Off by default: a focused quest changes nothing.
focus(101)
assert(not ns.HasJourney(), "the setting is off by default, so a focused quest starts nothing")

-- On: a focused quest starts the journey the tracked-quest binding would plan.
ns.db.focusedQuest = true
focus(102)
assert(goalQuest() == 102, "a focused quest starts a journey to it")
local same = ns.JourneyGoal()
focus(102)
assert(ns.JourneyGoal() == same, "focusing the same quest again does not replan the journey")

-- A new focus replaces it.
focus(103)
assert(goalQuest() == 103, "a newly focused quest takes the journey")
ns.ClearJourney()

-- A guide's own journey leads: its focus changes are its steps, not the player's choice.
local owner
ns.JourneyOwner = function()
	return owner
end
owner = "RestedXP"
focus(104)
assert(not ns.HasJourney(), "a quest focused while a guide leads its journey starts nothing")
owner = nil

-- The player's own map pin starts a journey with the setting on.
pin(1, 0.4, 0.6)
local goal = ns.JourneyGoal()
assert(goal and goal.map == 1 and goal.x < -4999 and goal.y > 4999, "the player's pin starts a journey")
local pinned = ns.JourneyGoal()
pin(1, 0.4, 0.6)
assert(ns.JourneyGoal() == pinned, "the same pin again does not replan the journey")
ns.ClearJourney()

-- A guide's own waypoint write is not the player's pin. The guide's pin and the pin it restores when it stops
-- both leave the journey alone.
clearPin()
ns.db.focusedQuest = false
pin(1, 0.2, 0.1)
ns.db.focusedQuest = true
local placeBend
ns.PointGuideArrow = function(_, callback)
	placeBend = callback
end
ns.JourneyGuide.Start()
ns.JourneyGuide.To({ map = 1, x = 1200, y = 0 }, { { map = 1, x = 1200, y = 0 } }, { routeTitle = "Guide" })
assert(placeBend and placeBend({ map = 1, x = 1200, y = 0 }), "the guide writes its own waypoint")
driver.update(0)
assert(not ns.HasJourney(), "a guide's own waypoint is not the player placing a pin")
ns.JourneyGuide.Stop()
driver.update(0)
assert(not ns.HasJourney(), "the pin a guide gives back when it stops starts nothing")
assert(env.C_Map.GetUserWaypoint(), "and the player's earlier pin is back")

-- A player pin replaces a guide-led journey too: placing a pin is the player's own choice.
owner = "Guidelime"
pin(1, 0.7, 0.3)
assert(ns.JourneyGoal() and ns.JourneyGoal().x > 9999, "a player pin starts even while a guide leads")
owner = nil
ns.ClearJourney()

-- Clearing a pin starts nothing.
clearPin()
assert(not ns.HasJourney(), "removing the pin starts no journey")

-- A flight point the player super-tracks with a plain left click on the map (UI/FlightPins.lua) is the same choice of
-- destination as Shift-click: with the setting on it starts the journey there (#1079).
local trackedPin
env.Enum = env.Enum or {}
env.Enum.SuperTrackingMapPinType = { TaxiNode = 2 }
env.C_SuperTrack.GetSuperTrackedMapPin = function()
	if trackedPin then
		return 2, trackedPin
	end
end
ns.TaxiNodes[26] = { map = 1, x = 3000, y = -2000 }
ns.TaxiName = function(node)
	return node == 26 and "Sentinel Hill" or nil
end
local function trackNode(node)
	trackedPin = node
	driver.fire("SUPER_TRACKING_CHANGED")
	driver.update(0)
end
ns.db.focusedQuest = false
trackNode(26)
assert(not ns.HasJourney(), "a tracked flight point starts nothing with the setting off")
trackNode(nil)
ns.db.focusedQuest = true
trackNode(26)
goal = ns.JourneyGoal()
assert(goal and goal.map == 1 and goal.x == 3000 and goal.y == -2000, "a tracked flight point starts a journey")
assert(goal.label == "Sentinel Hill", "named for the flight point")
assert(ns.TaxiNodes[26].label == nil, "the shared node is left as it is")
local flown = ns.JourneyGoal()
driver.fire("SUPER_TRACKING_CHANGED")
driver.update(0)
assert(ns.JourneyGoal() == flown, "the same tracked flight point does not replan")
ns.ClearJourney()
trackNode(nil)
assert(not ns.HasJourney(), "letting the flight point go starts nothing")

print("focused route: ok")

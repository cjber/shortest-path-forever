-- A quest whose client data names only its start (and turn-in) NPC still gets a journey there, even when the
-- quest's own map query names no map and its next waypoint is empty. Dragonmaw Shinbones (1846) is such a quest:
-- its objective is an item drop with no map area, and the only pin the client has is Velora Nitely in the
-- Undercity.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)
ns.db = { journey = true }
ns.MapCanvas = { OnClick = function() end }
ns.FamilyHints = { AddQuestMenu = function() end }
ns.Init = function(fn)
	fn()
end

local destination, printed
ns.StartJourney = function(point)
	destination = point
end
ns.Print = function(message)
	printed = message
end

local function vector(x, y)
	return {
		x = x,
		y = y,
		GetXY = function()
			return x, y
		end,
	}
end

local superTracked, pois = 1846, {}
local titles = { [1846] = "Dragonmaw Shinbones", [9999] = "Nowhere" }
local env = setmetatable({
	CreateFrame = function()
		return {
			RegisterEvent = function() end,
			SetSize = function() end,
			Hide = function() end,
			SetScript = function(self, event, fn)
				self.scripts = self.scripts or {}
				self.scripts[event] = fn
			end,
		}
	end,
	IsShiftKeyDown = function()
		return false
	end,
	IsAltKeyDown = function()
		return false
	end,
	GetMouseFoci = function()
		return {}
	end,
	WorldMapFrame = {
		AddCanvasClickHandler = function() end,
		AddGlobalPinMouseActionHandler = function() end,
		GetMapID = function()
			return 1458
		end,
	},
	Minimap = { HookScript = function() end },
	Menu = { ModifyMenu = function() end },
	MapCanvasMixin = { MouseAction = { Click = 3 } },
	Enum = { UIMapType = { Continent = 2 } },
	CreateVector2D = vector,
	GetInstanceInfo = function()
		return "", "none", 0, "", 0, 0, false, 0
	end,
	GetRealZoneText = function()
		return ""
	end,
	ChatEdit_GetActiveWindow = function()
		return nil
	end,
	GetQuestUiMapID = function()
		return 0
	end,
	C_Map = {
		GetBestMapForUnit = function()
			return 1458
		end,
		GetWorldPosFromMapPos = function(_, point)
			return 0, vector(point.x, point.y)
		end,
		GetMapInfo = function()
			return { mapType = 3 }
		end,
	},
	C_SuperTrack = {
		GetSuperTrackedQuestID = function()
			return superTracked
		end,
	},
	C_QuestLog = {
		GetNextWaypoint = function()
			return nil
		end,
		GetQuestsOnMap = function(mapID)
			return pois[mapID]
		end,
		GetTitleForQuestID = function(questID)
			return titles[questID]
		end,
		IsComplete = function()
			return false
		end,
		GetNumQuestWatches = function()
			return 0
		end,
	},
}, { __index = _G })
setfenv(assert(loadfile("Journey/JourneyInput.lua")), env)("ShortestPathForever", ns)

-- Quest 1846 in the Undercity: no map of its own, no waypoint, and only the start/turn-in pin the client reports
-- on the map the player stands on. The journey goes there instead of silently doing nothing.
pois = {
	[1458] = { { questID = 1846, x = 0.624, y = 0.392, isQuestStart = true, inProgress = true } },
}
assert(ns.JourneyToTrackedQuest(), "the tracked quest plans a journey")
assert(destination and destination.questID == 1846, "the start pin becomes the journey's goal")
assert(destination.label == "Dragonmaw Shinbones", "the goal keeps the quest's title")
assert(destination.map == 0 and destination.x == 0.624 and destination.y == 0.392, "the goal is the start pin")
assert(printed == nil, "a found start pin prints no missing-location line")

-- A quest with no pin and no waypoint anywhere still says why it cannot be planned.
superTracked, pois, destination, printed = 9999, {}, nil, nil
assert(not ns.JourneyToTrackedQuest(), "a quest with no location plans nothing")
assert(destination == nil and printed == "No location for that quest yet.", "a missing location says so")

print("quest destination: ok")

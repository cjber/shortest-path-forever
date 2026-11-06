-- The key bindings a controller or keyboard reaches the Shift-click actions with: Bindings.xml names three hidden
-- buttons, and each runs the same journey entry point Journey/JourneyInput.lua already uses.
local function read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return text
end

-- Bindings.xml is loaded by the client itself, never through the TOC, which would parse it as a UI XML file and log
-- a warning for every binding.
local bindings = read("Bindings.xml")
local toc = read("ShortestPathForever.toc")
assert(not toc:lower():find("bindings.xml", 1, true), "the client loads Bindings.xml by itself")
assert(bindings:find('header="BINDING_HEADER_SHORTESTPATHFOREVER"', 1, true), "the bindings share one header")
assert(select(2, bindings:gsub("<Binding ", "")) == 3, "one entry per action")
for _, button in ipairs({
	"ShortestPathForeverTravelToPinButton",
	"ShortestPathForeverTravelToTrackedQuestButton",
	"ShortestPathForeverClearJourneyButton",
}) do
	assert(bindings:find('name="CLICK ' .. button .. ':LeftButton"', 1, true), "the binding clicks " .. button)
end
assert(not bindings:find("<Binding[^>]*>%s*[^<%s]"), "the entries hold no Lua of their own")

local destination, waypoint, quest, cleared = nil, nil, 0, 0
local printed = {}
local env
local function vector(x, y)
	return {
		x = x,
		y = y,
		GetXY = function()
			return x, y
		end,
	}
end
local ns = {
	db = { journey = true },
	L = {},
	TaxiNodes = {},
	StartJourney = function(point)
		destination = point
	end,
	ClearJourney = function()
		cleared = cleared + 1
	end,
	Print = function(message)
		printed[#printed + 1] = message
	end,
	Locate = function()
		return { uiMap = 1440, x = 0.5, y = 0.5 }
	end,
	Init = function(fn)
		fn()
	end,
	Planner = {
		QuestDestination = function()
			return { uiMapID = 1440, x = 0.5, y = 0.5, label = "Tracked" }
		end,
	},
	MapCanvas = { OnClick = function() end },
}
env = setmetatable({
	CreateFrame = function(_, name)
		local frame = {
			RegisterEvent = function() end,
			SetSize = function() end,
			Hide = function() end,
			SetScript = function(self, event, fn)
				self.scripts = self.scripts or {}
				self.scripts[event] = fn
			end,
		}
		if name then
			env[name] = frame
		end
		return frame
	end,
	UIParent = {},
	CreateVector2D = vector,
	IsShiftKeyDown = function()
		return false
	end,
	IsAltKeyDown = function()
		return false
	end,
	GetMouseFoci = function()
		return {}
	end,
	GetInstanceInfo = function()
		return "", "none", 0, "", 0, 0, false, 0
	end,
	GetRealZoneText = function()
		return ""
	end,
	GetQuestUiMapID = function()
		return 1440
	end,
	ChatEdit_GetActiveWindow = function()
		return nil
	end,
	WorldMapFrame = {
		AddCanvasClickHandler = function() end,
		AddGlobalPinMouseActionHandler = function() end,
		GetMapID = function()
			return 1440
		end,
	},
	Minimap = { HookScript = function() end },
	Menu = { ModifyMenu = function() end },
	MapCanvasMixin = { MouseAction = { Click = 3 } },
	Enum = { UIMapType = { Continent = 2 } },
	C_Map = {
		GetUserWaypoint = function()
			return waypoint
		end,
		GetWorldPosFromMapPos = function(_, point)
			return 1, vector(point.x, point.y)
		end,
		GetMapInfo = function()
			return { mapType = 3 }
		end,
	},
	C_SuperTrack = {
		GetSuperTrackedQuestID = function()
			return quest
		end,
	},
	C_QuestLog = {
		GetNextWaypoint = function()
			return 1440, 0.5, 0.5
		end,
		GetQuestsOnMap = function()
			return {}
		end,
		GetTitleForQuestID = function()
			return "Tracked"
		end,
		IsComplete = function()
			return false
		end,
	},
}, { __index = _G })
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
setfenv(assert(loadfile("Journey/JourneyInput.lua")), env)("ShortestPathForever", ns)

assert(env.BINDING_HEADER_SHORTESTPATHFOREVER == "Shortest Path Forever", "the header names the addon")
assert(
	env["BINDING_NAME_CLICK ShortestPathForeverTravelToPinButton:LeftButton"] == "Travel to my map pin",
	"the map-pin binding is named"
)
assert(
	env["BINDING_NAME_CLICK ShortestPathForeverTravelToTrackedQuestButton:LeftButton"] == "Travel to my tracked quest",
	"the tracked-quest binding is named"
)
assert(env["BINDING_NAME_CLICK ShortestPathForeverClearJourneyButton:LeftButton"] == "Clear journey", "clear is named")

local function Press(button)
	button.scripts.OnClick(button)
end

waypoint = { uiMapID = 1440, position = { x = 0.4, y = 0.6 } }
Press(env.ShortestPathForeverTravelToPinButton)
assert(destination and destination.x == 0.4 and destination.y == 0.6, "the key starts a journey to the map pin")
waypoint, destination, printed = nil, nil, {}
Press(env.ShortestPathForeverTravelToPinButton)
assert(destination == nil and printed[1] == "no map pin is set.", "no pin says so")

destination, quest, printed = nil, 9, {}
Press(env.ShortestPathForeverTravelToTrackedQuestButton)
assert(destination and destination.questID == 9 and destination.label == "Tracked", "the next key goes to the quest")
quest, destination, printed = 0, nil, {}
Press(env.ShortestPathForeverTravelToTrackedQuestButton)
assert(destination == nil and printed[1] == "no quest is tracked.", "no tracked quest says so")

Press(env.ShortestPathForeverClearJourneyButton)
assert(cleared == 1, "the third key clears the journey")

print("bindings_spec: ok")

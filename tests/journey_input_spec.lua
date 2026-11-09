local handler, destination, mouseEvent, ownClick
local canvasClick, updateWatcher, watcherShown
local gamepad = false
local questTrackerMenu, questMapLogMenu
local alt, overMap, shown = false, true, true
local map = {
	GetMapID = function()
		return 1440
	end,
}
local pin = {
	pinTemplate = "FlightPointPinTemplate",
	GetMap = function()
		return map
	end,
	poiInfo = { nodeID = 26, name = "Astranaar" },
}
local shift = true
local chatBox
local ns = {
	db = { journey = true },
	L = {},
	GamepadUI = function()
		return gamepad
	end,
	TaxiNodes = { [26] = { map = 1, x = 100, y = 200 } },
	StartJourney = function(point)
		destination = point
	end,
	Locate = function()
		return { uiMap = 1440, x = 0.5, y = 0.5 }
	end,
	Init = function(fn)
		fn()
	end,
	-- UI/MapCanvas.lua: the addon's own pins hand their clicks to this filter.
	MapCanvas = {
		OnClick = function(fn)
			ownClick = fn
		end,
	},
	FamilyHints = { AddQuestMenu = function() end },
}
local env = setmetatable({
	CreateFrame = function()
		return {
			RegisterEvent = function() end,
			SetSize = function() end,
			Hide = function()
				watcherShown = false
			end,
			Show = function()
				watcherShown = true
			end,
			SetScript = function(_, event, fn)
				if event == "OnEvent" then
					mouseEvent = fn
				elseif event == "OnUpdate" then
					updateWatcher = fn
				end
			end,
		}
	end,
	IsAltKeyDown = function()
		return alt
	end,
	WorldMapFrame = {
		IsShown = function()
			return shown
		end,
		ScrollContainer = {
			IsMouseOver = function()
				return overMap
			end,
		},
		GetMapID = function()
			return 1440
		end,
		GetNormalizedCursorPosition = function()
			return 0.25, 0.75
		end,
		AddCanvasClickHandler = function(_, fn)
			canvasClick = fn
		end,
		AddGlobalPinMouseActionHandler = function(_, fn)
			handler = fn
		end,
	},
	Minimap = { HookScript = function() end },
	Menu = {
		ModifyMenu = function(tag, fn)
			if tag == "MENU_QUEST_OBJECTIVE_TRACKER" then
				questTrackerMenu = fn
			elseif tag == "MENU_QUEST_MAP_LOG_TITLE" then
				questMapLogMenu = fn
			end
		end,
	},
	MapCanvasMixin = { MouseAction = { Click = 3 } },
	C_Map = {
		GetWorldPosFromMapPos = function(_, pos)
			return 1, {
				GetXY = function()
					return pos.x, pos.y
				end,
			}
		end,
		GetMapInfo = function()
			return { mapType = 3 }
		end,
	},
	Enum = { UIMapType = { Continent = 2 } },
	CreateVector2D = function(x, y)
		return { x = x, y = y }
	end,
	IsShiftKeyDown = function()
		return shift
	end,
	ChatEdit_GetActiveWindow = function()
		return chatBox
	end,
	GetMouseFoci = function()
		return { pin }
	end,
}, { __index = _G })
local chunk = assert(loadfile("Journey/JourneyInput.lua"))
setfenv(chunk, env)("ShortestPathForever", ns)
assert(canvasClick(env.WorldMapFrame, "LeftButton"))
assert(destination and destination.x == 0.25 and destination.y == 0.75, "mouse mode starts immediately")
destination, gamepad = nil, true
assert(canvasClick(env.WorldMapFrame, "LeftButton"))
assert(watcherShown and destination == nil, "gamepad mode queues the destination")
local watcher = {
	Hide = function()
		watcherShown = false
	end,
}
updateWatcher(watcher)
assert(watcherShown and destination == nil, "do not start while the map is open")
shown = false
updateWatcher(watcher)
assert(not watcherShown and destination and destination.x == 0.25 and destination.y == 0.75)
destination = nil
updateWatcher(watcher)
assert(destination == nil, "consume the queued destination once")
shown, gamepad = true, false
assert(handler(map, 3, "LeftButton"), "Shift-clicking a flight-master pin must start a journey")
assert(destination.map == 1 and destination.x == 100 and destination.y == 200)
assert(destination.label == "Astranaar" and destination.pinBadge, "keep the clicked icon's corner marker")
assert(ns.TaxiNodes[26].label == nil, "do not mutate the shared taxi node")
destination, shift = nil, false
assert(not handler(map, 3, "LeftButton") and destination == nil)
shift = true
assert(not handler(map, 3, "RightButton") and destination == nil)
pin.GetMap = function()
	return {}
end
assert(not handler(map, 3, "LeftButton") and destination == nil)
pin.GetMap = function()
	return map
end
pin.pinTemplate, pin.poiInfo = "AreaPOIPinTemplate", { name = "Camp" }
pin.GetGlobalPosition = function()
	return 0.3, 0.4
end
assert(handler(map, 3, "LeftButton") and destination.x == 0.3 and destination.y == 0.4)
assert(destination.label == "Camp" and destination.pinBadge, "other point icons keep their corner tag")
pin.GetGlobalPosition = function() end
destination = nil
assert(not handler(map, 3, "LeftButton") and destination == nil, "non-point pins cannot start journeys")

-- The addon's own pins (UI/MapCanvas.lua) are not the map's: their Shift-click comes through MapCanvas.OnClick.
local own = {
	marker = "flight",
	poiInfo = { nodeID = 26, name = "Astranaar" },
	GetMap = function()
		return map
	end,
	GetPosition = function()
		return 0.6, 0.7
	end,
}
destination = nil
assert(ownClick(own, "LeftButton") and destination.x == 100 and destination.label == "Astranaar", "own flight pin")
assert(destination.pinBadge, "keep the clicked icon's corner marker")
own.marker, own.poiInfo, destination = "dock", nil, nil
assert(ownClick(own, "LeftButton") and destination.x == 0.6 and destination.y == 0.7, "a dock by where it stands")
own.marker, destination = "stop", nil
assert(not ownClick(own, "LeftButton") and destination == nil, "clicking a route stop must preserve the itinerary")
own.marker, shift = "portal", false
assert(not ownClick(own, "LeftButton") and destination == nil, "a plain click is the pin's own")
shift, chatBox = true, {}
assert(not ownClick(own, "LeftButton") and destination == nil, "an open chat box takes the Shift-click")
chatBox = nil
assert(not ownClick(own, "RightButton") and destination == nil)
print("journey input ok")

-- The global mouse event still fires over a Questie-owned icon that swallowed canvas clicks.
alt, shift, destination = true, false, nil
mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(
	destination and destination.x == 0.25 and destination.y == 0.75,
	"Alt-click uses the exact map cursor over icons"
)
-- TomTom v4.3.13 CreateWorldMapClickHandler passes LeftButton through even while its modifier matches.
-- Its waypoint gesture is right-click, so active or stale saved options must not disable our left-click.
for _, options in ipairs({
	{ profiles = { Default = { worldmap = { clickcreate = true, create_modifier = "A" } } } },
	{ profile = { worldmap = { clickcreate = true, create_modifier = "C" } } },
	{ profiles = { Default = { worldmap = { clickcreate = false } } } },
	{},
}) do
	env.TomTomDB, destination = options, nil
	mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
	assert(destination and destination.x == 0.25, "TomTom options must not claim Alt-left-click")
	destination = nil
	mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "RightButton")
	assert(destination == nil, "TomTom keeps its right-click gesture")
end
env.TomTomDB = nil
shift, destination = true, nil
mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(destination == nil, "Shift with Alt leaves journey handling to the existing Shift-click path")
shift = false
for _, state in ipairs({ { false, true, true }, { true, false, true }, { true, true, false } }) do
	alt, overMap, shown = unpack(state)
	destination = nil
	mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
	assert(destination == nil, "ordinary clicks and clicks outside the visible map remain untouched")
end
chatBox = {}
destination = nil
assert(not handler(map, 3, "LeftButton") and destination == nil, "Shift+click must share to an open chat box")
chatBox = nil

-- A spot inside a dungeon has no walking map: from outside, the journey goes to its door, named in the game's
-- language, and a label the caller gave stands. Inside that dungeon the spot is left as it is.
setmetatable(ns.L, {
	__index = function(_, phrase)
		return phrase
	end,
})
ns.Entrances = { [36] = { name = "Deadmines", map = 0, x = -11207.8, y = 1681.15 } }
local instance, zoneText = 0, "Les Mortemines"
env.GetInstanceInfo = function()
	return "", "none", 0, "", 0, 0, false, instance
end
env.GetRealZoneText = function(id)
	return id == 36 and zoneText or ""
end
env.C_Map.GetWorldPosFromMapPos = function(uiMap, pos)
	return uiMap == 1581 and 36 or 1, {
		GetXY = function()
			return pos.x, pos.y
		end,
	}
end
destination = nil
assert(ns.JourneyToMapPoint(1581, 0.5, 0.5), "a spot in a dungeon plans a journey")
assert(destination.map == 36, "the journey keeps the spot itself; StartJourney sends it to the door")
local stop = { map = 36, x = 1, y = 2, questID = 7, hold = true, radius = 20, shapes = {} }
local door = ns.InstanceEntrance(stop)
assert(door.map == 0 and door.x == -11207.8 and door.y == 1681.15, "it goes to the door")
assert(door.label == "Enter Les Mortemines", "the door is named in the game's language")
assert(door.entrance == 36 and door.stop == stop and door.questID == 7, "the door remembers the stop it stands for")
assert(not door.hold and not door.radius and not door.shapes, "areas and holds inside the dungeon stay behind")
zoneText = ""
assert(ns.InstanceEntrance(stop).label == "Enter Deadmines", "the shipped name stands in")
stop.label = "Van Cleef"
assert(ns.InstanceEntrance(stop).label == "Van Cleef", "a caller's label stands")
assert(ns.Entrances[36].label == nil and ns.Entrances[36].stop == nil, "the shipped entrance is never changed")
assert(ns.InstanceEntrance(door) == door, "a door is already outside")
instance = 36
assert(ns.InstanceEntrance(stop) == stop, "inside the dungeon the spot is left as it is")
assert(ns.WorldPoint(1440, 0.5, 0.5).map == 1, "a spot outside any dungeon is unchanged")
print("journey input: instance entrances ok")

-- The quest log menus: wherever the right-clicked tracker block or map-log title carries a quest id, the entry appears.
local function QuestMenuRoot()
	local root = {}
	function root:CreateButton(label, onClick)
		self.label, self.onClick = label, onClick
	end
	return root
end

local locatable = 4242
ns.Planner = {
	QuestDestination = function(questID)
		return questID == locatable and { uiMapID = 1440, x = 0.5, y = 0.5, label = "Objective" } or nil
	end,
}
env.GetQuestUiMapID = function()
	return 1440
end
env.C_QuestLog = {
	GetNextWaypoint = function()
		return 1440, 0.5, 0.5
	end,
	GetQuestsOnMap = function()
		return {}
	end,
	GetTitleForQuestID = function()
		return "Quest"
	end,
	IsComplete = function()
		return false
	end,
}

local trackerOwner = {}
local trackerModule = {
	GetContextMenuParent = function()
		return trackerOwner
	end,
}
local function Focus(header, block)
	env.GetMouseFoci = function()
		return { header }
	end
	header.GetParent = function()
		return block
	end
	block.HeaderButton = header
end

-- A normal tracker block: parentModule names the same menu owner.
local header, block = {}, { id = locatable, parentModule = trackerModule }
Focus(header, block)
local root = QuestMenuRoot()
assert(questTrackerMenu, "the objective tracker menu must be registered")
questTrackerMenu(trackerOwner, root)
assert(root.label == "Plan journey" and root.onClick, "a located quest offers Plan journey")
destination = nil
root.onClick()
assert(destination and destination.questID == locatable, "the entry plans the right-clicked quest")

-- No quest id anywhere on the header or block: no entry.
header, block = {}, { parentModule = trackerModule }
Focus(header, block)
root = QuestMenuRoot()
questTrackerMenu(trackerOwner, root)
assert(root.onClick == nil, "a block with no quest id adds no entry")

-- EQOT-style replacement: no parentModule, but the block still sits under ObjectiveTrackerFrame.
local trackerFrame = {
	GetParent = function()
		return nil
	end,
}
env.ObjectiveTrackerFrame = trackerFrame
local middle = {
	GetParent = function()
		return trackerFrame
	end,
}
header, block = {}, {
	id = locatable,
	GetParent = function()
		return middle
	end,
}
Focus(header, block)
root = QuestMenuRoot()
questTrackerMenu({}, root)
assert(root.onClick, "a block under ObjectiveTrackerFrame still gets the entry")
destination = nil
root.onClick()
assert(destination and destination.questID == locatable, "the replacement tracker's quest is planned")

-- A replacement tracker of its own (EQOT's frame) is not under ObjectiveTrackerFrame: the menu owner is the ancestry
-- that identifies its block.
local eqotFrame = {
	GetParent = function()
		return nil
	end,
}
local eqotBlock = {
	id = locatable,
	GetParent = function()
		return eqotFrame
	end,
}
header = {}
Focus(header, eqotBlock)
root = QuestMenuRoot()
questTrackerMenu(eqotFrame, root)
assert(root.onClick, "a replacement tracker's own owner still gets the entry")
destination = nil
root.onClick()
assert(destination and destination.questID == locatable, "the replacement owner's quest is planned")

-- A block under some other frame is never taken for the right-clicked one.
local otherFrame = {
	GetParent = function()
		return nil
	end,
}
middle = {
	GetParent = function()
		return otherFrame
	end,
}
header, block = {}, {
	id = locatable,
	GetParent = function()
		return middle
	end,
}
Focus(header, block)
root = QuestMenuRoot()
questTrackerMenu({}, root)
assert(root.onClick == nil, "a block from another frame adds no entry")

-- The header's own questID and the block's questID are accepted too.
header, block = { questID = locatable }, { parentModule = trackerModule }
Focus(header, block)
root = QuestMenuRoot()
questTrackerMenu(trackerOwner, root)
assert(root.onClick, "a header's own quest id is accepted")
header, block = {}, { questID = locatable, parentModule = trackerModule }
Focus(header, block)
root = QuestMenuRoot()
questTrackerMenu(trackerOwner, root)
assert(root.onClick, "a block's questID is accepted")

-- Map-log titles: questID and questId both work; neither means no entry.
root = QuestMenuRoot()
questMapLogMenu({ questID = locatable }, root)
assert(root.onClick, "the map log's questID offers the entry")
root = QuestMenuRoot()
questMapLogMenu({ questId = locatable }, root)
assert(root.onClick, "the map log's questId offers the entry")
root = QuestMenuRoot()
questMapLogMenu({}, root)
assert(root.onClick == nil, "a map-log owner with no quest id adds no entry")

print("journey input: quest menus ok")

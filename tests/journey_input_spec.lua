local handler, destination, mouseEvent, ownClick, canvasClick, canvasPriority, minimapClick
local questTrackerMenu, questMapLogMenu
local alt, overMap, shown = false, true, true
local map = {
	GetMapID = function()
		return 1440
	end,
	GetNormalizedCursorPosition = function()
		return 0.25, 0.75
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
local function Record(tag, fn)
	if tag == "MENU_QUEST_OBJECTIVE_TRACKER" then
		questTrackerMenu = fn
	elseif tag == "MENU_QUEST_MAP_LOG_TITLE" then
		questMapLogMenu = fn
	end
end
local gamepad, tooltipShown = false, nil
local noticed = {}
local ns = {
	db = { journey = true },
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	TaxiNodes = { [26] = { map = 1, x = 100, y = 200 } },
	StartJourney = function(point)
		destination = point
	end,
	Locate = function()
		return { uiMap = 1440, x = 0.5, y = 0.5 }
	end,
	MinimapPoint = function()
		return { map = 1, x = 1, y = 2 }
	end,
	SpawnHeight = function()
		return -10
	end,
	Init = function(fn)
		fn()
	end,
	GamepadUI = function()
		return gamepad
	end,
	Notice = function(message)
		noticed[#noticed + 1] = message
	end,
	-- UI/Canvas.lua: the addon's own pins hand their clicks to this filter.
	Canvas = {
		OnClick = function(fn)
			ownClick = fn
		end,
	},
	AdventureSuggestions = { AddQuestMenu = function() end },
	-- UI/MenuModifier.lua's entry point, which owns the registration; tests/quest_menu_spec.lua checks its gamepad
	-- handling. Here it only records the tag's description builder.
	ModifyMenu = function(tag, _, build)
		Record(tag, build)
	end,
}
local env = setmetatable({
	CreateFrame = function()
		return {
			RegisterEvent = function() end,
			SetSize = function() end,
			Hide = function() end,
			SetScript = function(_, event, fn)
				if event == "OnEvent" then
					mouseEvent = fn
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
		AddCanvasClickHandler = function(_, fn, priority)
			canvasClick, canvasPriority = fn, priority
		end,
		AddGlobalPinMouseActionHandler = function(_, fn)
			handler = fn
		end,
	},
	Minimap = {
		HookScript = function(_, _, fn)
			minimapClick = fn
		end,
	},
	GameTooltip = {
		HookScript = function(_, script, fn)
			assert(script == "OnShow")
			tooltipShown = fn
		end,
	},
	GameTooltip_AddInstructionLine = function(tooltip, text)
		tooltip.lines[#tooltip.lines + 1] = text
	end,
	Menu = { ModifyMenu = Record },
	MapCanvasMixin = { MouseAction = { Click = 3 } },
	C_Map = {
		GetWorldPosFromMapPos = function(_, pos)
			return 1, {
				GetXY = function()
					return pos.x, pos.y
				end,
			}
		end,
		-- No map here is stacked under another, so no spot is over one.
		GetMapPosFromWorldPos = function() end,
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
assert(handler(map, 3, "LeftButton"), "Shift-clicking a flight-master pin must start a journey")
assert(destination.map == 1 and destination.x == 100 and destination.y == 200)
assert(destination.label == "Astranaar")
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
assert(destination.label == "Camp")
pin.GetGlobalPosition = function() end
destination = nil
assert(not handler(map, 3, "LeftButton") and destination == nil, "non-point pins cannot start journeys")

-- The addon's own pins (UI/Canvas.lua) are not the map's: their Shift-click comes through MapCanvas.OnClick.
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

-- Every map pin the journey key plans to ends its tooltip with how (#1078): one line from one producer, naming the
-- chosen key, and only where the click would plan.
do
	local function tooltipFor(owner)
		local tooltip = { lines = {}, shows = 0 }
		function tooltip.GetOwner()
			return owner
		end
		function tooltip.Show(self)
			self.shows = self.shows + 1
		end
		tooltipShown(tooltip)
		return tooltip
	end
	local function blizzardPin(fields)
		local mapPin = { owningMap = env.WorldMapFrame }
		for key, value in pairs(fields) do
			mapPin[key] = value
		end
		function mapPin.IsForbidden()
			return false
		end
		return mapPin
	end
	shown = true
	local hint = "Shift-click to plan a journey here"
	assert(ns.JourneyClickHint() == hint, "the line names the chosen key")
	ns.db.journeyKey = "alt"
	assert(ns.JourneyClickHint() == "Alt-click to plan a journey here", "and follows the setting")
	ns.db.journeyKey = nil
	local quest = tooltipFor(blizzardPin({ pinTemplate = "QuestPinTemplate", questID = 7 }))
	assert(quest.lines[1] == hint and quest.shows == 1, "a quest pin's tooltip gains the line")
	local poi = tooltipFor(blizzardPin({ pinTemplate = "AreaPOIPinTemplate", normalizedX = 0.3 }))
	assert(poi.lines[1] == hint, "an area pin's tooltip gains the line")
	assert(
		not tooltipFor(blizzardPin({ pinTemplate = "AreaPOIPinTemplate" })).lines[1],
		"a pin with no spot plans nothing"
	)
	assert(not tooltipFor(blizzardPin({ pinTemplate = "QuestPinTemplate" })).lines[1], "nor a quest pin with no quest")
	local other = blizzardPin({ pinTemplate = "AreaPOIPinTemplate", normalizedX = 0.3 })
	other.owningMap = {}
	assert(not tooltipFor(other).lines[1], "a pin on another map is not the world map's")
	assert(not tooltipFor({
		IsForbidden = function()
			return false
		end,
	}).lines[1], "a frame that is no pin")
	assert(not tooltipFor(nil).lines[1], "a tooltip with no owner")
	ns.db.journey = false
	assert(ns.JourneyClickHint() == nil and not tooltipFor(poi.GetOwner()).lines[1], "nothing while journeys are off")
	ns.db.journey, gamepad = true, true
	assert(ns.JourneyClickHint() == nil, "nothing under the gamepad interface, which has no key to hold")
	gamepad = false
	env.Minimap.IsForbidden = function()
		return false
	end
	assert(tooltipFor(env.Minimap).lines[1] == hint, "the minimap's tooltip: a click there plans to the spot")
	shown = false
	assert(not tooltipFor(poi.GetOwner()).lines[1], "nothing while the world map is closed")
	shown = true
	print("journey input: pin hints ok")
end

-- With Shift chosen, Alt-click on the map is not a journey gesture: OpenMap's Alt-click deletes its markers, and
-- other icons keep their own Alt-click (#1050).
alt, shift, destination = true, false, nil
mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(destination == nil, "with Shift chosen, Alt-click off a Questie icon is left to other addons")
-- The global mouse event still fires over a Questie-owned icon that swallowed canvas clicks.
local foci = env.GetMouseFoci
_G.Questie = {}
env.GetMouseFoci = function()
	return { { miniMapIcon = false, data = {}, UiMapID = 1440, x = 40, y = 60 } }
end
mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
-- The icon stands away from the map cursor (0.25, 0.75), so this is the icon's spot and not the cursor's.
assert(destination and destination.x == 0.4 and destination.y == 0.6, "Alt-click plans to the Questie icon's spot")
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
	assert(destination and destination.x == 0.4, "TomTom options must not claim Alt-left-click on a Questie icon")
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
_G.Questie, env.GetMouseFoci = nil, foci
chatBox = {}
destination = nil
assert(not handler(map, 3, "LeftButton") and destination == nil, "Shift+click must share to an open chat box")
chatBox = nil

-- The journey key is the player's choice. Shift is the default, and the one chosen key plans every map click: the
-- world map and its pins, our own icons, the minimap, and Questie's icons through the global mouse handler.
ns.db.journeyKey, shift, alt = nil, true, false
assert(ns.JourneyKeyDown() and ns.JourneyKeyName() == "Shift", "Shift plans a journey by default")
shift = false
assert(not ns.JourneyKeyDown() and ns.JourneyKeyName() == "Shift", "the default key is named Shift")
ns.db.journeyKey, shift = "meta", true
assert(ns.JourneyKeyDown() and ns.JourneyKeyName() == "Shift", "an unknown saved key plans with Shift")
ns.db.journeyKey, alt = "alt", true
assert(ns.JourneyKeyDown() and ns.JourneyKeyName() == "Alt", "Alt can be the journey key")

-- The world map: a pin, the canvas, and our own icons all follow the chosen key.
pin.pinTemplate, pin.poiInfo = "FlightPointPinTemplate", { nodeID = 26, name = "Astranaar" }
pin.GetGlobalPosition = nil
shift, destination = false, nil
assert(handler(map, 3, "LeftButton"), "Alt-clicking a flight-master pin with Alt chosen plans a journey")
assert(destination and destination.map == 1, "the pin's own journey is planned")
destination = nil
assert(canvasClick(map, "LeftButton") and destination, "Alt-clicking the map with Alt chosen plans a journey")
assert(destination.x == 0.25 and destination.y == 0.75, "the map click keeps its spot")
-- OpenMap's handler zooms in on every Alt-click at priority 1000, so ours must ask first (#1076).
assert(canvasPriority and canvasPriority > 1000, "the journey key's canvas click runs before OpenMap's")
local cursor = map.GetNormalizedCursorPosition
map.GetNormalizedCursorPosition = function()
	return 1.4, 0.5
end
destination = nil
assert(not canvasClick(map, "LeftButton") and destination == nil, "a click past the map's edge is left to OpenMap")
map.GetNormalizedCursorPosition = cursor
own.marker, destination = "dock", nil
assert(ownClick(own, "LeftButton") and destination, "Alt-clicking our own icon with Alt chosen plans a journey")
destination = nil
minimapClick(nil, "LeftButton")
assert(destination and destination.x == 1 and destination.y == 2, "Alt-clicking the minimap with Alt chosen plans")

-- Shift no longer plans a journey once Alt is chosen.
shift, alt, destination = true, false, nil
assert(not handler(map, 3, "LeftButton") and not canvasClick(map, "LeftButton"), "Shift leaves pins and the map alone")
assert(not ownClick(own, "LeftButton"), "Shift leaves our own icons alone")
minimapClick(nil, "LeftButton")
assert(destination == nil, "Shift leaves the minimap alone")

-- Questie keeps Shift-click on its icons. With Alt chosen, that key plans there instead; with Shift chosen,
-- Alt-click still plans the journey, as it always has.
shown, overMap, shift, alt = true, true, false, false
_G.Questie = {}
env.GetMouseFoci = function()
	return { { miniMapIcon = false, data = {}, UiMapID = 1440, x = 50, y = 50 } }
end
mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(destination == nil, "Shift does not plan over a Questie icon with Alt chosen")
alt = true
mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(
	destination and destination.map == 1 and destination.x == 0.5 and destination.y == 0.5,
	"Alt plans over a Questie icon with Alt chosen"
)
ns.db.journeyKey, shift, alt, destination = "shift", false, true, nil
mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(destination and destination.x == 0.5, "with Shift chosen, Alt-click still plans over a Questie icon")
_G.Questie = nil
ns.db.journeyKey, shift, alt = nil, true, false
env.GetMouseFoci = function()
	return { pin }
end

-- With journeys off, every journey-key click says so on screen and leaves the click to the game (#1076): the map,
-- its pins, our own icons, the minimap, a Questie icon, and the waypoint and tracked quest keys. A click without
-- the key says nothing.
do
	local off = "Journeys are off. Turn on Click the map to plan journeys in settings."
	local function Off(what, click)
		noticed, destination = {}, nil
		local taken = click()
		assert(
			not taken and destination == nil and noticed[1] == off and #noticed == 1,
			what .. " says journeys are off"
		)
	end
	ns.db.journey, ns.db.journeyKey, shift, alt = false, nil, true, false
	Off("a map pin", function()
		return handler(map, 3, "LeftButton")
	end)
	Off("the map", function()
		return canvasClick(map, "LeftButton")
	end)
	own.marker = "dock"
	Off("our own icon", function()
		return ownClick(own, "LeftButton")
	end)
	Off("the minimap", function()
		return minimapClick(nil, "LeftButton")
	end)
	_G.Questie = {}
	local pinFoci = env.GetMouseFoci
	env.GetMouseFoci = function()
		return { { miniMapIcon = false, data = {}, UiMapID = 1440, x = 50, y = 50 } }
	end
	shift, alt = false, true
	Off("a Questie icon", function()
		return mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
	end)
	_G.Questie, env.GetMouseFoci = nil, pinFoci
	Off("the waypoint key", ns.JourneyToUserWaypoint)
	local superTrack = env.C_SuperTrack
	env.C_SuperTrack = {
		GetSuperTrackedQuestID = function()
			return 42
		end,
	}
	Off("the tracked quest key", ns.JourneyToTrackedQuest)
	env.C_SuperTrack = superTrack
	shift, alt, noticed = false, false, {}
	assert(not canvasClick(map, "LeftButton") and not noticed[1], "a plain click says nothing")
	ns.db.journey, shift = true, true
	print("journey input: journeys off says so on screen ok")
end

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
local stop = { map = 36, x = 1, y = 2, questID = 7, questIDs = { 7 }, hold = true, radius = 20, shapes = {} }
local door = ns.InstanceEntrance(stop)
assert(door.map == 0 and door.x == -11207.8 and door.y == 1681.15, "it goes to the door")
assert(door.label == "Enter Les Mortemines", "the door is named in the game's language")
assert(door.entrance == 36 and door.stop == stop and door.questID == 7, "the door remembers the stop it stands for")
assert(door.questIDs == stop.questIDs, "and the quests whose objectives the arrow shows on the way")
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
assert(destination.questIDs[1] == locatable, "the goal names its quest for the live objectives")

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

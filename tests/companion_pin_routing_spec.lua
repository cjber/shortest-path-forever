-- Run from the repository root: luajit tests/companion_pin_routing_spec.lua
local originalLoad = loadfile
loadfile = function(path)
	if path:match("Journey/JourneyInput%.lua$") then
		return function() end
	end
	return originalLoad(path)
end
local driver = assert(originalLoad("tests/journey_driver.lua"))()
loadfile = originalLoad
local ns, env = driver.ns, driver.env
local map = env.WorldMapFrame
local shift, alt, shown = false, false, true
local foci, routed, menus, notices = {}, {}, {}, {}
local nativeClick

env.IsShiftKeyDown = function()
	return shift
end
env.IsAltKeyDown = function()
	return alt
end
env.IsControlKeyDown = function()
	return false
end
env.GetMouseFoci = function()
	return foci
end
env.MapCanvasMixin = { MouseAction = { Click = "click" } }
map.IsShown = function()
	return shown
end
map.GetMapID = function()
	return 1
end
map.ScrollContainer = {
	IsMouseOver = function()
		return false
	end,
}
map.AddGlobalPinMouseActionHandler = function(_, callback)
	nativeClick = callback
end
driver.load("Journey/JourneyInput.lua")
assert(nativeClick, "the native pin handler is installed")
local startJourney = ns.StartJourney
ns.StartJourney = function(point)
	routed[#routed + 1] = point
	return startJourney(point)
end
ns.Notice = function(message)
	notices[#notices + 1] = message
end
local worldPos = env.C_Map.GetWorldPosFromMapPos
local worldConversionAvailable = true
env.C_Map.GetWorldPosFromMapPos = function(mapID, position)
	if mapID == 1441 then
		assert(position.x == 0.54 and position.y == 0.415)
		if worldConversionAvailable then
			return 1, env.CreateVector2D(-5183.6, -2806.9)
		end
		return nil
	end
	return worldPos(mapID, position)
end
driver.load("Data/Zones.lua")
env.C_QuestLog = {
	GetTitleForQuestID = function(id)
		if id == 777 then
			return "Stitched quest"
		end
		assert(id == 1149)
		return nil -- the client need not have loaded an unaccepted quest's title yet
	end,
}
-- Simulate the reverse lookup landing on a continent for a point whose zone was already known.
ns.located = { uiMap = 10, x = 0.5, y = 0.5 }

local function OpenMenu(frame)
	menus[#menus + 1] = frame
end

local function Marker(fields, script)
	local scripts = { [script] = OpenMenu }
	fields.IsForbidden = function()
		return false
	end
	fields.IsProtected = fields.IsForbidden
	fields.GetScript = function(_, key)
		return scripts[key]
	end
	fields.SetScript = function(_, key, callback)
		scripts[key] = callback
	end
	return fields
end

local dungeon = Marker({
	_fdjKey = "dungeon-entrance",
	target = { markerType = "dungeon", mapID = 1, x = 0.2, y = 0.4, label = "Entrance" },
}, "PostClick")
dungeon._fdjCanTarget = true
local pickup = Marker({
	data = {
		place = { mapID = 1441, x = 0.54, y = 0.415 },
		pickups = {
			{
				questID = 1149,
				toTake = {
					quest = { id = 1160, name = "Test of Lore", chainStart = 1149, chainStartName = "Test of Faith" },
				},
			},
		},
	},
}, "OnClick")
local book = Marker({ data = { place = { mapID = 1, x = 0.35, y = 0.55 }, book = { name = "Book" } } }, "OnClick")

env.OpenMapAPI = {
	major = 1,
	version = 2,
	MapAt = function(u, v)
		assert(u == 0.6 and v == 0.4)
		return 7
	end,
	MapFromWorld = function(mapID, u, v)
		assert(mapID == 7 and u == 0.6 and v == 0.4)
		return 0.1, 0.2
	end,
}
local stitched = Marker({
	instances = { { 47, "Razorfen Kraul" } },
	cont = 1,
	x = -4459.4,
	y = -1660.2,
	u = 0.7,
	v = 0.5,
	OnClick = OpenMenu,
}, "OnMouseUp")
local projected = Marker({
	instances = { { 0, "Projected entrance" } },
	u = 0.6,
	v = 0.4,
	OnClick = OpenMenu,
}, "OnMouseUp")
local stitchedQuest = Marker({
	data = { map = 7, id = 777, complete = false },
	questMark = {},
	u = 0.6,
	v = 0.4,
	OnClick = OpenMenu,
}, "OnMouseUp")

local function Press(frame, button)
	foci = { frame }
	driver.fire("GLOBAL_MOUSE_DOWN", button or "LeftButton")
end

local function Release(button)
	driver.fire("GLOBAL_MOUSE_UP", button or "LeftButton")
end

Press(pickup)
pickup:GetScript("OnClick")(pickup, "LeftButton")
assert(#routed == 0 and #menus == 1, "plain left-click opens NeedRoll")
shift = true
Press(pickup)
Release() -- global release may arrive before the frame callback
pickup:GetScript("OnClick")(pickup, "LeftButton")
assert(#menus == 1 and #routed == 1 and #notices == 0, "NeedRoll routes even when the reverse lookup sees a continent")
assert(routed[1].map == 1 and routed[1].x == -5183.6 and routed[1].y == -2806.9)
assert(ns.JourneyGoal().label == "Test of Faith")
assert(pickup:GetScript("OnClick") == OpenMenu, "the original callback is restored after the click")

Press(stitched)
stitched:OnClick() -- OpenMap calls this method from its mouse-up handler, after deciding it was a click
assert(#menus == 1 and #routed == 2 and #notices == 0, "OpenMap routes to its outdoor entrance without projecting it")
assert(routed[2].map == 1 and routed[2].x == -4459.4 and routed[2].y == -1660.2)
assert(ns.JourneyGoal().label == "Razorfen Kraul")
assert(stitched.OnClick == OpenMenu, "OpenMap keeps its callback for the next click")
Press(projected)
projected:OnClick()
assert(#menus == 1 and routed[3].map == 7 and routed[3].label == "Projected entrance")
Press(dungeon)
dungeon:GetScript("PostClick")(dungeon, "LeftButton")
assert(#menus == 1 and routed[4].label == "Entrance")
Press(book)
book:GetScript("OnClick")(book, "LeftButton")
assert(#menus == 1 and routed[5].label == "Book")
assert(not ns.JourneyToMapPoint(10, 0.5, 0.5), "blank continent clicks still reject an unknown zone")

Press(stitched)
Release()
driver.update(0)
assert(stitched.OnClick == OpenMenu and #routed == 5, "a drag with no click restores OpenMap's callback")
Press(pickup, "RightButton")
assert(pickup:GetScript("OnClick") == OpenMenu, "Shift-right is left alone")
alt = true
Press(pickup)
assert(pickup:GetScript("OnClick") == OpenMenu, "combined modifiers are left alone")
alt, shown = false, false
Press(pickup)
assert(pickup:GetScript("OnClick") == OpenMenu, "hidden world maps do not take clicks")
shown = true
worldConversionAvailable = false
Press(pickup)
pickup:GetScript("OnClick")(pickup, "LeftButton")
assert(#menus == 1 and #routed == 6 and #notices == 1, "NeedRoll routes when world conversion is unavailable")
local fallback = ns.JourneyGoal()
assert(fallback.label == "Test of Faith" and fallback.map == 1)
assert(math.abs(fallback.x - -5183.6) < 3 and math.abs(fallback.y - -2806.9) < 3)
Press(stitchedQuest)
stitchedQuest:OnClick()
local questGoal = ns.JourneyGoal()
assert(#menus == 1 and #routed == 7 and questGoal.questID == 777)
assert(questGoal.label == "Stitched quest")
ns.located = nil

local entrance =
	Marker({ pinTemplate = "DungeonEntrancePinTemplate", poiInfo = { name = "Native entrance" } }, "OnClick")
entrance.GetMap = function()
	return map
end
entrance.GetGlobalPosition = function()
	return 0.55, 0.45
end
foci = { entrance }
ns.db.journeyKey = "alt"
assert(not nativeClick(map, "click", "RightButton"), "a native entrance leaves Shift-right click alone")
assert(nativeClick(map, "click", "LeftButton"), "Shift-left routes to a native entrance even if the journey key is Alt")
assert(ns.JourneyGoal().label == "Native entrance")
print("companion marker routing: ok")

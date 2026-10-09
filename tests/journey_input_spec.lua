local handler, destination, mouseEvent
local alt, overMap, shown = false, true, true
local map = {
	GetMapID = function()
		return 1440
	end,
}
local pin = {
	pinTemplate = "ShortestPathForeverFlightPinTemplate",
	GetMap = function()
		return map
	end,
	poiInfo = { nodeID = 26, name = "Astranaar" },
}
local shift = true
local ns = {
	db = { journey = true },
	L = {},
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
}
local env = setmetatable({
	CreateFrame = function()
		return {
			RegisterEvent = function() end,
			SetScript = function(_, _, fn)
				mouseEvent = fn
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
		AddCanvasClickHandler = function() end,
		AddGlobalPinMouseActionHandler = function(_, fn)
			handler = fn
		end,
	},
	Minimap = { HookScript = function() end },
	Menu = { ModifyMenu = function() end },
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
	GetMouseFoci = function()
		return { pin }
	end,
}, { __index = _G })
local chunk = assert(loadfile("Journey/JourneyInput.lua"))
setfenv(chunk, env)("ShortestPathForever", ns)
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
pin.pinTemplate, pin.poiInfo = "FlightPointPinTemplate", { nodeID = 26, name = "Astranaar" }
assert(handler(map, 3, "LeftButton") and destination.label == "Astranaar", "native flight pins work too")
pin.pinTemplate, pin.poiInfo = "AreaPOIPinTemplate", { name = "Camp" }
pin.GetGlobalPosition = function()
	return 0.3, 0.4
end
assert(handler(map, 3, "LeftButton") and destination.x == 0.3 and destination.y == 0.4)
assert(destination.label == "Camp" and destination.pinBadge, "other point icons keep their corner tag")
destination, pin.pinTemplate = nil, "ShortestPathForeverGoalPinTemplate"
assert(not handler(map, 3, "LeftButton") and destination == nil, "clicking a route stop must preserve the itinerary")
pin.pinTemplate = "AreaPOIPinTemplate"
pin.GetGlobalPosition = function() end
destination = nil
assert(not handler(map, 3, "LeftButton") and destination == nil, "non-point pins cannot start journeys")
print("journey input ok")

-- The global mouse event still fires over a Questie-owned icon that swallowed canvas clicks.
alt, destination = true, nil
mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(
	destination and destination.x == 0.25 and destination.y == 0.75,
	"Alt-click uses the exact map cursor over icons"
)
for _, state in ipairs({ { false, true, true }, { true, false, true }, { true, true, false } }) do
	alt, overMap, shown = unpack(state)
	destination = nil
	mouseEvent(nil, "GLOBAL_MOUSE_DOWN", "LeftButton")
	assert(destination == nil, "ordinary clicks and clicks outside the visible map remain untouched")
end

local cursorX, cursorY = 190, 190
local shape, rotate = "SQUARE", "0"
local ns = {
	L = {},
	Canvas = { PinMixin = {} },
	Strokes = { New = function() end },
	Init = function() end,
	JourneyPosition = function()
		return 1000, 2000, 0, 1
	end,
}
local env = setmetatable({
	CreateColor = function()
		return {}
	end,
	WorldMapFrame = {},
	CreateFromMixins = function(mixin)
		return setmetatable({}, { __index = mixin })
	end,
	C_Minimap = {
		GetViewRadius = function()
			return 100
		end,
	},
	Minimap = {
		GetCenter = function()
			return 100, 100
		end,
		GetEffectiveScale = function()
			return 1
		end,
		GetWidth = function()
			return 200
		end,
		GetHeight = function()
			return 200
		end,
	},
	GetCursorPosition = function()
		return cursorX, cursorY
	end,
	GetMinimapShape = function()
		return shape
	end,
	GetCVar = function()
		return rotate
	end,
	GetPlayerFacing = function()
		return math.pi / 4
	end,
	canaccessvalue = function()
		return true
	end,
}, { __index = _G })
setfenv(assert(loadfile("UI/Route.lua")), env)("ShortestPathForever", ns)

local point = assert(ns.MinimapPoint(), "a square minimap accepts a corner click")
assert(point.map == 1 and point.x == 1090 and point.y == 1910, "the corner projects to the expected world point")

rotate = "1"
point = assert(ns.MinimapPoint(), "a rotating square minimap still accepts the same corner")
assert(
	point.map == 1 and math.abs(point.x - (1000 + 90 * math.sqrt(2))) < 1e-9 and math.abs(point.y - 2000) < 1e-9,
	"the corner's world position accounts for facing"
)

shape = "ROUND"
assert(ns.MinimapPoint() == nil, "a round minimap rejects the same click")
env.GetMinimapShape = nil
assert(ns.MinimapPoint() == nil, "the default minimap is round")

shape = "SQUARE"
env.GetMinimapShape = function()
	return shape
end
cursorX, cursorY = 201, 100
assert(ns.MinimapPoint() == nil, "a square minimap rejects clicks beyond its width")
cursorX, cursorY = 100, -1
assert(ns.MinimapPoint() == nil, "a square minimap rejects clicks beyond its height")

print("square minimap click checks passed")

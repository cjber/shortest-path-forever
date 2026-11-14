-- The world map's destination pin at the player's chosen size (#778): 100% draws the pin exactly as it always was,
-- 50% draws it half that size, and at every size the art stays square and its point stays on the destination: the
-- texture's bottom sits on the frame's centre, which the map places on the goal.
local checks = 0
local function check(value, label)
	checks = checks + 1
	assert(value, label)
end

local function texture()
	local t = { alpha = 1 }
	function t:SetPoint(...)
		self.point = { ... }
	end
	function t:ClearAllPoints()
		self.point = nil
	end
	function t:SetSize(width, height)
		self.width, self.height = width, height
	end
	function t:SetShown(shown)
		self.shown = shown
	end
	function t:SetAlpha(alpha)
		self.alpha = alpha
	end
	function t:SetText(text)
		self.text = text
	end
	function t.SetTextColor() end
	function t:SetDesaturated(value)
		self.desaturated = value
	end
	function t.SetVertexColor() end
	function t:SetAtlas(atlas)
		self.atlas, self.file = atlas, nil
	end
	function t:SetTexture(file)
		self.file, self.atlas = file, nil
	end
	function t.SetTexCoord() end
	function t.SetAllPoints() end
	function t.AdjustPointsOffset() end
	return t
end

local ns = {
	db = { destinationPinSize = 100 },
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	Canvas = { PinMixin = {} },
	Strokes = { New = function() end },
	StopSize = 20,
	LaterAlpha = 0.6,
	Init = function() end,
}
local env = setmetatable({
	NORMAL_FONT_COLOR = {},
	ORANGE_FONT_COLOR = {},
	CreateColor = function()
		return {}
	end,
	WorldMapFrame = {},
	CreateFromMixins = function(mixin)
		return setmetatable({}, { __index = mixin })
	end,
}, { __index = _G })

-- The real scale helper, then the real goal pin, as the client loads them (UI/Art.lua, UI/Route.lua, UI/StopPin.lua).
for _, file in ipairs({ "UI/Art.lua", "UI/Route.lua", "UI/StopPin.lua" }) do
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end

local function pin()
	local p = setmetatable({}, { __index = ns.GoalPinMixin })
	function p.CreateFontString()
		return texture()
	end
	function p:SetPoint(...)
		self.anchor = { ... }
	end
	function p:SetSize(width, height)
		self.width, self.height = width, height
	end
	function p:GetWidth()
		return self.width
	end
	function p:SetPosition(x, y)
		self.x, self.y = x, y
	end
	function p:SetHitRectInsets(left, right, top, bottom)
		self.insets = { left, right, top, bottom }
	end
	function p.UseFrameLevelType() end
	function p.SetIgnoreGlobalPinScale() end
	function p.SetScalingLimits() end
	p.Texture, p.Icon, p.Disc, p.Button = texture(), texture(), texture(), texture()
	p.Number, p.Arrow, p.HighlightTexture = texture(), texture(), texture()
	p:OnLoad()
	return p
end

-- 100%: the stock 29-unit pin, its art square and its point on the frame's centre.
ns.db.destinationPinSize = 100
check(ns.DestinationPinScale() == 1, "100% is the stock size")
local stock = pin()
stock:OnAcquired(0.5, 0.5, nil, nil, nil, false, nil, nil, nil, nil)
check(stock.width == 29 and stock.height == 29, "the stock frame is 29 square")
check(stock.Texture.width == 29 and stock.Texture.height == 29, "the stock art is 29 square")
check(stock.Texture.point[1] == "BOTTOM", "the pin's point is its art's bottom")
check(
	stock.Texture.point[2] == stock and stock.Texture.point[3] == "CENTER",
	"the art's bottom sits on the frame's centre"
)
check(stock.insets[3] == -14.5 and stock.insets[4] == 14.5, "the clickable rect rises with the art")

-- 50%: half the art, still square, and the point stays on the same centre.
ns.db.destinationPinSize = 50
check(ns.DestinationPinScale() == 0.5, "50% is half")
local small = pin()
small:OnAcquired(0.5, 0.5, nil, nil, nil, false, nil, nil, nil, nil)
check(small.width == 14.5 and small.height == 14.5, "the small frame is half the stock size")
check(small.Texture.width == 14.5 and small.Texture.height == 14.5, "the small art keeps its square shape")
check(small.Texture.point[1] == "BOTTOM", "the small pin's point is still its art's bottom")
check(
	small.Texture.point[2] == small and small.Texture.point[3] == "CENTER",
	"the small pin's point stays on the destination"
)
check(small.insets[3] == -7.25 and small.insets[4] == 7.25, "the small clickable rect follows the art")

-- A value from another client or an older save: the slider's 50 to 100 bounds still hold, and a missing or odd value
-- draws the pin as it always was.
for value, expected in pairs({ [10] = 0.5, [75] = 0.75, [500] = 1, [100] = 1 }) do
	ns.db.destinationPinSize = value
	check(ns.DestinationPinScale() == expected, "the size is clamped to the slider's range")
end
ns.db.destinationPinSize = nil
check(ns.DestinationPinScale() == 1, "an old save without the setting keeps the stock pin")
ns.db.destinationPinSize = "75"
check(ns.DestinationPinScale() == 1, "a value that is not a number keeps the stock pin")

print(string.format("destination pin size: %d checks passed", checks))

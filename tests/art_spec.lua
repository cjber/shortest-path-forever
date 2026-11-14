-- Run from the repository root: luajit tests/art_spec.lua
-- Art.lua on its own, with a stub C_Texture.GetAtlasInfo and a stub texture that keeps an atlas's crop as the
-- client does: an atlas fits its box at its own aspect, and a file icon is drawn whole.
local checks = 0
local function check(value, label)
	checks = checks + 1
	assert(value, label)
end

-- The Forever build's sizes (UiTextureAtlasMember, 1.60.1.69913).
local atlases = {
	["poi-door-arrow-up"] = { width = 13, height = 14 },
	SideInProgressquesticon = { width = 16, height = 18 },
	["adventureguide-ring"] = { width = 94, height = 95 },
}

local function texture()
	local t = {}
	function t:SetAtlas(atlas)
		self.atlas, self.file = atlas, nil
		-- The client leaves the atlas's place on its sheet as the texture's coordinates until they are set again.
		self.crop = atlas
	end
	function t:SetTexture(file)
		self.file, self.atlas = file, nil
	end
	function t:SetTexCoord(left, right, top, bottom)
		assert(left == 0 and right == 1 and top == 0 and bottom == 1, "the whole file")
		self.crop = nil
	end
	function t:SetSize(width, height)
		self.width, self.height = width, height
	end
	return t
end

local ns = {}
local env = setmetatable({
	C_Texture = {
		GetAtlasInfo = function(atlas)
			return atlases[atlas]
		end,
	},
}, { __index = _G })
-- NumberFile serves ForeverCore's step markers, so the real shared module is loaded, as the client loads it.
local Core = dofile("tests/forever_core.lua")
local coreArt = Core.load(env, "ForeverCore", { "UI/Art.lua" }).Art
env.ForeverCore = { Art = coreArt }
setfenv(assert(loadfile("UI/Art.lua")), env)("ShortestPathForever", ns)
local Art = ns.Art

-- Fit: an atlas keeps its native shape inside the box, whichever side is longer.
local arrow = texture()
check(Art.Fit(arrow, "poi-door-arrow-up", 15, 15), "the lift's floor arrow")
check(arrow.height == 15 and math.abs(arrow.width / arrow.height - 13 / 14) < 1e-9, "a 13 by 14 arrow stays 13 by 14")
check(Art.Fit(arrow, "SideInProgressquesticon", 40, 9) and arrow.height == 9 and arrow.width == 8, "fits a wide box")
check(Art.Fit(arrow, "adventureguide-ring", 22, 22) and arrow.height == 22, "the ring fills the box's height")
check(math.abs(arrow.width / arrow.height - 94 / 95) < 1e-9, "a 94 by 95 ring is not squared")
check(not Art.Fit(arrow, "no-such-atlas", 15, 15) and arrow.atlas == "adventureguide-ring", "missing art left alone")
check(arrow.height == 22, "and at the size it had")

-- Icon: a file over a texture that drew an atlas is drawn whole, not through the atlas's crop.
local icon = texture()
Art.Fit(icon, "poi-door-arrow-up", 15, 15)
check(icon.crop == "poi-door-arrow-up", "an atlas leaves its crop")
Art.Icon(icon, "Interface\\AddOns\\ShortestPathForever\\media\\Zeppelin", 18)
check(icon.file == "Interface\\AddOns\\ShortestPathForever\\media\\Zeppelin" and icon.atlas == nil, "the file")
check(icon.crop == nil, "the crop is reset")
check(icon.width == 18 and icon.height == 18, "square at its size")

-- NumberFile: ForeverCore's shipped numbered markers, 1 to 25; above the art, nothing, so the caller keeps the font.
check(ns.NumberFile(1) == "Interface\\AddOns\\ForeverCore\\media\\Numbers\\1", "the first marker is ForeverCore's own")
check(ns.NumberFile(1) == coreArt.Marker(1), "NumberFile serves the shared module's marker")
check(ns.NumberFile(25) == "Interface\\AddOns\\ForeverCore\\media\\Numbers\\25", "the last")
check(ns.NumberFile(26) == nil, "above 25 there is no marker art")
check(ns.NumberFile(0) == nil and ns.NumberFile(nil) == nil, "no marker for an impossible number")
check(ns.NumberFile(1.5) == nil, "whole numbers only")

-- The goal pin has a bronze twin, media/PinInactive.tga, for a goal Guide is not tracking. Both ship at the same
-- square native size, so neither is stretched to stand in for the other.
local PIN = "Interface\\AddOns\\ShortestPathForever\\media\\Pin"
local INACTIVE = "Interface\\AddOns\\ShortestPathForever\\media\\PinInactive"
check(ns.PIN_FILE == PIN, "the gold goal pin")
check(ns.PIN_INACTIVE_FILE == INACTIVE, "the bronze untracked goal pin")
check(ns.GoalPinFile(true) == PIN, "a tracked goal is gold")
check(ns.GoalPinFile(false) == INACTIVE, "an untracked goal is bronze")
ns.IsJourneyGuided = function()
	return false
end
check(ns.GoalPinFile() == INACTIVE, "with no answer from the caller, Guide decides")
ns.IsJourneyGuided = function()
	return true
end
check(ns.GoalPinFile() == PIN, "a guided journey asks for gold")

-- A TGA header states its width and height in two little-endian bytes each, at offsets 12 and 14.
local function TgaSize(path)
	local handle = assert(io.open(path, "rb"), path .. " ships")
	local header = assert(handle:read(18))
	handle:close()
	local width = header:byte(13) + header:byte(14) * 256
	local height = header:byte(15) + header:byte(16) * 256
	return width, height
end
local goldWidth, goldHeight = TgaSize("media/Pin.tga")
local inactiveWidth, inactiveHeight = TgaSize("media/PinInactive.tga")
check(goldWidth == 128 and goldHeight == 128, "the gold pin is 128 by 128")
check(inactiveWidth == goldWidth and inactiveHeight == goldHeight, "the bronze pin keeps the gold pin's native size")

print(string.format("art_spec: %d checks passed", checks))

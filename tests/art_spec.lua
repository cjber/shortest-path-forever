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
Art.Icon(icon, "Interface\\Minimap\\Tracking\\Class", 18)
check(icon.file == "Interface\\Minimap\\Tracking\\Class" and icon.atlas == nil, "the file")
check(icon.crop == nil, "the crop is reset")
check(icon.width == 18 and icon.height == 18, "square at its size")

print(string.format("art_spec: %d checks passed", checks))

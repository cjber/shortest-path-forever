---@class SPFNamespace
local ns = select(2, ...)

-- Art at its native aspect (AGENTS.md: never stretch art). An atlas is sized from C_Texture.GetAtlasInfo to fit
-- inside its box, and a file icon is drawn whole. Every other file sets art only where its line says why its shape is
-- right (tools/lint_art.py).

-- The addon's own goal pin, media/Pin.tga: a square file whose point is the bottom centre of the square.
ns.PIN_FILE = "Interface\\AddOns\\ShortestPathForever\\media\\Pin"
-- The bronze twin of the goal pin, media/PinInactive.tga, for a goal the journey does not currently track.
ns.PIN_INACTIVE_FILE = "Interface\\AddOns\\ShortestPathForever\\media\\PinInactive"
-- The numbered markers, media/Numbers/<n>.tga: gold notched rings with the numeral painted in. Stops and turns
-- above this many keep the font.
local MAX_NUMBER_ART = 25

---@class SPFArt
local Art = {}
ns.Art = Art

-- The numbered marker for `number`, or nil when there is no art for it.
---@param number integer?
---@return string?
function ns.NumberFile(number)
	if type(number) ~= "number" or number < 1 or number > MAX_NUMBER_ART or number % 1 ~= 0 then
		return nil
	end
	return string.format("Interface\\AddOns\\ShortestPathForever\\media\\Numbers\\%d", number)
end

---@type table<string, AtlasInfo|false>
local infos = {}

-- The client's size for `atlas`, asked once; nil when the client lacks it.
---@param atlas string
---@return AtlasInfo?
function Art.Info(atlas)
	local info = infos[atlas]
	if info == nil then
		info = C_Texture.GetAtlasInfo(atlas) or false
		infos[atlas] = info
	end
	return info or nil
end

-- `atlas` at its native shape, as large as fits in `width` by `height`. The caller anchors the texture by one point,
-- so it stays centred in its box. False, leaving the texture alone, when the client lacks it.
---@param texture Texture
---@param atlas string
---@param width number
---@param height number
---@return boolean
function Art.Fit(texture, atlas, width, height)
	local info = Art.Info(atlas)
	if not info then
		return false
	end
	texture:SetAtlas(atlas)
	local scale = math.min(width / info.width, height / info.height)
	texture:SetSize(info.width * scale, info.height * scale)
	return true
end

-- A file icon, square as every one is, `size` across and whole: a texture that drew an atlas before keeps that
-- atlas's crop until it is reset.
---@param texture Texture
---@param file string|integer
---@param size number
function Art.Icon(texture, file, size)
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetTexture(file)
	texture:SetSize(size, size)
end

-- `atlas` over the whole of a `width` by `height` box at its own aspect, the overflow cropped evenly from both sides
-- (SetTexCoord within the atlas's own coordinates on its sheet).
---@param texture Texture
---@param atlas string
---@param width number
---@param height number
function Art.Cover(texture, atlas, width, height)
	texture:SetAtlas(atlas)
	local info = C_Texture.GetAtlasInfo(atlas)
	if not (info and info.width > 0 and info.height > 0 and width > 0 and height > 0) then
		return
	end
	local left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local box, native = width / height, info.width / info.height
	if native > box then
		local cut = (right - left) * (1 - box / native) / 2
		left, right = left + cut, right - cut
	else
		local cut = (bottom - top) * (1 - native / box) / 2
		top, bottom = top + cut, bottom - cut
	end
	texture:SetTexCoord(left, right, top, bottom)
end

-- Art.Cover for a texture sized by its anchors: `frame`'s size less `trimWidth` and `trimHeight`, again whenever
-- the frame's size changes. Hooked, so the frame's own OnSizeChanged must be set before this.
---@param frame Frame
---@param texture Texture
---@param atlas string
---@param trimWidth number
---@param trimHeight number
function Art.CoverFrame(frame, texture, atlas, trimWidth, trimHeight)
	local function Lay(width, height)
		Art.Cover(texture, atlas, width - trimWidth, height - trimHeight)
	end
	Lay(frame:GetSize())
	frame:HookScript("OnSizeChanged", function(_, width, height)
		Lay(width, height)
	end)
end

-- The Who list's row atlases are 169x69 (WhoList.xml:8, 9 and 59) with 14-pixel horizontal slice margins and none
-- top or bottom: the client draws them at that height on its 69-high rows.
local ROW_ART = 69

-- `atlas` across `row` at the atlas's native 69 height, scaled uniformly to the row's height the way the client scales
-- art (Texture:SetScale, as ActionButtonComponentTemplate.xml's scale="0.8"): the texture keeps the art's own shape,
-- and its width follows so the row is still spanned. SetAllPoints would squash it. The offsets are in the texture's
-- own units too, hence over the scale; it is laid out again whenever the row's size changes.
---@param row Button
---@param atlas string
---@param layer DrawLayer
---@param x? number
---@param y? number
---@return Texture
function Art.RowTexture(row, atlas, layer, x, y)
	local texture = row:CreateTexture(nil, layer)
	texture:SetAtlas(atlas) -- art-ok: at the atlas's native height, scaled uniformly to the row below
	local offsetX, offsetY = x or 0, y or 0
	local function Lay(width, height)
		if height <= 0 then
			return
		end
		local scale = height / ROW_ART
		texture:SetScale(scale)
		texture:SetSize(width / scale, ROW_ART)
		texture:ClearAllPoints()
		texture:SetPoint("TOPLEFT", row, "TOPLEFT", offsetX / scale, offsetY / scale)
	end
	Lay(row:GetSize())
	row:HookScript("OnSizeChanged", function(_, width, height)
		Lay(width, height)
	end)
	return texture
end

-- The nearby rows' art: the Who list's row, with its hover added over it in the HIGHLIGHT layer.
---@param row Button
function Art.RowArt(row)
	Art.RowTexture(row, "common-button-list-large", "BACKGROUND")
	local hover = Art.RowTexture(row, "common-button-list-large-hover", "HIGHLIGHT")
	hover:SetBlendMode("ADD")
end

-- A nine-slice band across its anchored box, like the quest log's own list header: such art stretches by design.
---@param texture Texture
---@param atlas string
function Art.Band(texture, atlas)
	texture:SetAtlas(atlas) -- art-ok: the stock list header's own nine-slice, stretched across its row
	texture:SetAllPoints()
end

-- Whether the goal is tracked right now: Guide owns a waypoint and the client super-tracks it. A planned route, a
-- paused guide, a yielded one and a guide turned off are all untracked, as the game's own waypoint pin reports it.
---@return boolean
function ns.GoalPinActive()
	if ns.JourneyPinTracked then
		return ns.JourneyPinTracked()
	end
	if ns.IsJourneyGuided then
		return ns.IsJourneyGuided()
	end
	return true
end

-- The goal pin a journey wears: gold while Guide tracks it, bronze while the route is planned but not guided.
-- `active` lets a caller say which state it draws, so a spec needs no live journey; nil asks Guide.
---@param active boolean?
---@return string
function ns.GoalPinFile(active)
	if active == nil then
		active = ns.GoalPinActive()
	end
	return active and ns.PIN_FILE or (ns.PIN_INACTIVE_FILE or ns.PIN_FILE)
end

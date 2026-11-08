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

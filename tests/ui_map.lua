-- Continues tests/ui_client.lua: the world map, Blizzard's own map providers, and the addon loaded in TOC order.
local zoom, mapID, visible = 0, 1414, false
cursorX, cursorY = 0.5, 0.5
local pins, pools, active, providers = {}, {}, {}, {}
local canvas = { width = 1000, height = 700 }
function canvas:GetWidth()
	return self.width
end
function canvas:GetHeight()
	return self.height
end
local map = setmetatable({
	GetMapID = function()
		return mapID
	end,
	IsVisible = function()
		return visible
	end,
	GetCanvas = function()
		return canvas
	end,
	GetCanvasZoomPercent = function()
		assert(visible, "zoomLevels nil")
		return zoom
	end,
	GetGlobalPinScale = function()
		return 1.4
	end,
	GetCanvasScale = function()
		assert(visible, "zoomLevels nil")
		return 0.5 + zoom * 1.5
	end,
	GetNormalizedCursorPosition = function()
		return cursorX, cursorY
	end,
}, mt)
function map:RemoveAllPinsByTemplate(template)
	pools[template] = pools[template] or {}
	for _, pin in ipairs(active[template] or {}) do
		pin:Hide()
		pin.anchor = nil
		pin:OnReleased()
		pools[template][#pools[template] + 1] = pin
	end
	active[template] = {}
	if template:match("Dock") then
		pins = active[template]
	end
	if template:match("Portal") then
		portalPins = active[template]
	end
end
function map:AcquirePin(template, ...)
	pools[template], active[template] = pools[template] or {}, active[template] or {}
	local pin = table.remove(pools[template])
	if not pin then
		pin = stubframe()
		pin.Icon = pin:CreateTexture()
		pin.Label = setmetatable({}, fontmt)
		pin.Glow, pin.Texture, pin.HighlightTexture = setmetatable({}, mt), setmetatable({}, mt), setmetatable({}, mt)
		function pin.Texture:SetAtlas(atlas)
			self.atlas = atlas
		end
		pin.Disc, pin.Button, pin.Numeral = pin:CreateTexture(), pin:CreateTexture(), pin:CreateTexture()
		-- A template with no mixin of its own (the ping pin) inherits the client's MapPinPingTemplate instead.
		local mixin = _G[template:gsub("Template$", "Mixin")]
		if mixin then
			for k, v in pairs(mixin) do
				pin[k] = v
			end
		end
		pin:OnLoad()
	end
	active[template][#active[template] + 1] = pin
	if template:match("Dock") then
		pins = active[template]
	end
	if template:match("Portal") then
		portalPins = active[template]
	end
	pin:Show()
	pin:OnAcquired(...)
	if template:match("Transport") then
		assert(pin.anchor, "pooled transport geometry must restore its anchor")
	end
	return pin
end
portalPins = {}
_G.MapCanvasPinMixin = {
	OnReleased = noop,
	-- MapCanvas_DataProviderBase.lua:233/284: clicks reach OnMouseClickAction; right clicks pass through to zoom out.
	OnClick = function(self, button)
		if self:ShouldMouseButtonBePassthrough(button) then
			return
		end
		if self.OnMouseClickAction then
			self:OnMouseClickAction(button)
		end
	end,
	ShouldMouseButtonBePassthrough = function(_, button)
		return button == "RightButton"
	end,
	UseFrameLevelType = function(self, level)
		self.frameLevelType = level
	end,
	GetMap = function()
		return map
	end,
	GetEffectiveScale = function(self)
		return uiScale * map:GetCanvasScale() * (self.scale or 1)
	end,
	SetScalingLimits = function(self, factor, start, finish)
		self.scaleFactor, self.startScale, self.endScale = factor, start, finish
	end,
	SetIgnoreGlobalPinScale = function(self, v)
		self.ignoreGlobalPinScale = v
	end,
	SetScaleStyle = function(self, style)
		assert(style == 3)
		self.scale = self.ignoreGlobalPinScale and 1 or map:GetGlobalPinScale()
	end,
	SetPosition = function(self, x, y)
		self.x, self.y = x, y
		local scale = rawget(self, "scale") or 1
		self:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * x / scale, -canvas:GetHeight() * y / scale)
	end,
}
_G.MapCanvasDataProviderMixin = {
	GetMap = function()
		return map
	end,
}
_G.BaseMapPoiPinMixin = {
	CreateSubPin = function(_, level)
		return CreateFromMixins(MapCanvasPinMixin, {
			OnLoad = function(self)
				self:UseFrameLevelType(level)
			end,
			SetTexture = function(self, info)
				self.Texture:SetAtlas((info.textureKit and info.textureKit .. "-" or "") .. info.atlasName)
			end,
		})
	end,
}
BaseMapPoiPinMixin.SetTexture = function(self, info)
	self.Texture:SetAtlas((info.textureKit and info.textureKit .. "-" or "") .. info.atlasName)
end
_G.SuperTrackablePoiPinMixin = {
	OnAcquired = function(self, info)
		self.poiInfo = info
		self:SetTexture(info)
		self:SetPosition(info.position:GetXY())
	end,
}
_G.MapPinTags = { FlightPoint = 1 }
assert(loadfile(BLIZZARD_UI .. "Blizzard_SharedMapDataProviders/FlightPointDataProvider.lua"))()
local clickHandlers, pinHandlers = {}, {}
_G.WorldMapFrame = setmetatable({
	dataProviders = {},
	shown = true,
	IsShown = function(self)
		return self.shown
	end,
	IsVisible = function()
		return visible
	end,
	EnumeratePinsByTemplate = function(_, template)
		local i, list = 0, active[template] or {}
		return function()
			i = i + 1
			return list[i]
		end
	end,
	AddDataProvider = function(self, provider)
		providers[#providers + 1] = provider
		self.dataProviders[provider] = true
		provider:RefreshAllData()
	end,
	RemoveDataProvider = function(self, provider)
		provider:RemoveAllData()
		self.dataProviders[provider] = nil
		for i = #providers, 1, -1 do
			if providers[i] == provider then
				table.remove(providers, i)
			end
		end
	end,
	AddCanvasClickHandler = function(_, fn)
		clickHandlers[#clickHandlers + 1] = fn
	end,
	AddGlobalPinMouseActionHandler = function(_, fn)
		pinHandlers[#pinHandlers + 1] = fn
	end,
	GetMapID = function()
		return mapID
	end,
}, mt)
_G.ObjectiveTrackerManager = setmetatable({}, {
	__index = function(_, key)
		error("addon entered native tracker manager: " .. key)
	end,
})
_G.UIParent = CreateFrame("Frame")
_G.UIParent:SetSize(1920, 1080)
_G.ObjectiveTrackerFrame = CreateFrame("Frame", nil, UIParent)
_G.ObjectiveTrackerFrame:SetSize(250, 600)
_G.CreateFramePoolCollection = function()
	return {
		GetOrCreatePool = function()
			error("native pooling is exercised by tracker_host_spec")
		end,
	}
end
_G.hooksecurefunc = function(t, name, f)
	if type(t) ~= "table" then
		return
	end
	local original = t[name]
	t[name] = function(...)
		local r = original(...)
		f(...)
		return r
	end
end
_G.GameTooltip = setmetatable({
	SetOwner = function(self, owner)
		self.owner = owner
	end,
	IsOwned = function(self, owner)
		return self.owner == owner
	end,
	IsShown = function(self)
		return self.shown
	end,
	Show = function(self)
		self.shown = true
	end,
	Hide = function(self)
		self.shown = false
		self.owner = nil
	end,
}, mt)
local nativeProvider = CreateFromMixins(FlightPointDataProviderMixin)
WorldMapFrame:AddDataProvider(nativeProvider)
_G.canaccessvalue = function()
	return true
end
-- Use Blizzard's acquisition and event paths so pin visibility tests also cover pooled frames.
_G.SlashCommandUtil = { CheckAddSlashCommand = noop }
_G.SLASH_COMMAND, _G.SLASH_COMMAND_CATEGORY = { MAPPIN = 1 }, { MAP = 1 }
_G.EventRegistry = { RegisterCallback = noop, UnregisterCallback = noop }
assert(loadfile(BLIZZARD_UI .. "Blizzard_SharedMapDataProviders/WaypointLocationDataProvider.lua"))()
local waypointProvider = CreateFromMixins(WaypointLocationDataProviderMixin)
do
	local events = stubframe()
	events:SetScript("OnEvent", function(_, event)
		waypointProvider:OnEvent(event)
	end)
	function waypointProvider:RegisterEvent(event)
		events:RegisterEvent(event)
	end
	function waypointProvider:UnregisterEvent(event)
		events:UnregisterEvent(event)
	end
	function waypointProvider:OnMapChanged()
		self:RefreshAllData()
	end
end
waypointProvider:OnShow()
WorldMapFrame:AddDataProvider(waypointProvider)
local ns = {}
for line in io.lines("ShortestPathForever.toc") do
	if line:match("%.lua$") then
		assert(loadfile((line:gsub("\\", "/"))))("ShortestPathForever", ns)
	end
end
local actualPath = ns.Path
ns.Path = nil -- Terrain scheduling is exercised with controlled callbacks below.
fireEvent("ADDON_LOADED", "ShortestPathForever")
fireEvent("PLAYER_ENTERING_WORLD")
assert(#errors == 0, table.concat(errors, "\n"))

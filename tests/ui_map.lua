-- Continues tests/ui_client.lua: the world map, Blizzard's own map providers, and the addon loaded in TOC order.
local zoom, mapID, visible = 0, 1414, false
cursorX, cursorY = 0.5, 0.5
local providers = {}
-- What the addon's map frames (UI/MapCanvas.lua) ask of a frame beyond the shared stub.
local function frameExtras(f)
	function f:GetScript(n)
		return self.scripts[n]
	end
	-- The client moves a frame under another without a script; a hidden parent hides it with no OnHide of its own.
	function f:SetParent(parent)
		for index, child in ipairs(self.parent and self.parent.children or {}) do
			if child == self then
				table.remove(self.parent.children, index)
				break
			end
		end
		self.parent = parent
		if parent then
			parent.children = parent.children or {}
			parent.children[#parent.children + 1] = self
		end
	end
	function f:SetScale(value)
		self.scale = value
	end
	function f:GetScale()
		return self.scale or 1
	end
	function f:ClearAllPoints()
		self.anchor = nil
	end
	return f
end
-- The flight point a map click super-tracks (SuperTrackablePinMixin), as its type and node.
local trackedPinType, trackedPinID
function C_SuperTrack.GetSuperTrackedMapPin()
	return trackedPinType, trackedPinID
end
function C_SuperTrack.SetSuperTrackedMapPin(kind, id)
	trackedPinType, trackedPinID = kind, id
	fireEvent("SUPER_TRACKING_CHANGED")
end
function C_SuperTrack.ClearAllSuperTracked()
	trackedPinType, trackedPinID, trackedQuest, supertracked = nil, nil, 0, false
	fireEvent("SUPER_TRACKING_CHANGED")
end
Enum.SuperTrackingMapPinType = { TaxiNode = 2 }
-- The map's canvas, a frame the addon's own pins sit on (UI/MapCanvas.lua).
local canvas = frameExtras(stubframe())
canvas.width, canvas.height = 1000, 700
-- The canvas shows and hides with the map; the client runs OnUpdate only on a visible frame.
function canvas.IsShown()
	return visible
end
function canvas.IsVisible()
	return visible
end
-- The scroll container scales the canvas by the zoom (MapCanvasScrollControllerMixin:SetCanvasScale).
function canvas.GetEffectiveScale()
	return uiScale * (0.5 + zoom * 1.5)
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
	-- MapCanvas_PinFrameLevelsManager.lua: a read of the level a pin type is given.
	GetPinFrameLevelsManager = function()
		return {
			GetValidFrameLevel = function(_, levelType, index)
				return 2000 + #levelType + (index or 1)
			end,
		}
	end,
}, mt)
-- The addon's pin templates (UI/Map.xml), each with the art its XML gives it.
local createFrame = CreateFrame
_G.CreateFrame = function(frameType, name, parent, template)
	local pin = frameExtras(createFrame(frameType, name, parent, template))
	if type(template) == "string" and template:match("^ShortestPathForever.*PinTemplate$") then
		pin.Icon = pin:CreateTexture()
		pin.Glow, pin.Texture, pin.HighlightTexture = pin:CreateTexture(), pin:CreateTexture(), pin:CreateTexture()
		pin.Glow:Hide()
		pin.SuperTrackGlow, pin.SuperTrackMarker = pin:CreateTexture(), pin:CreateTexture()
		pin.Disc, pin.Button, pin.Numeral = pin:CreateTexture(), pin:CreateTexture(), pin:CreateTexture()
		-- The blob widget's own methods (FrameAPIBlob), recorded: the quests drawn since the last DrawNone, and on
		-- which map.
		if template:match("AreaPin") then
			assert(frameType == "QuestPOIFrame" and blobWidget, "no QuestPOIFrame on this client")
			function pin:SetFillTexture(texture)
				self.fill = texture
			end
			function pin:SetBorderTexture(texture)
				self.border = texture
			end
			function pin:SetMapID(id)
				self.blobMap = id
			end
			function pin:DrawNone()
				self.blobs = {}
			end
			function pin:DrawBlob(questID, draw)
				assert(draw == true)
				self.blobs[#self.blobs + 1] = questID
			end
		end
	end
	return pin
end
-- Blizzard's own pins, for its own providers: the addon's pins build on none of these.
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
-- Blizzard's own pins, which its own providers acquire (the flight points and the user waypoint). The addon draws on
-- frames of its own (UI/MapCanvas.lua) and never acquires one: a template of its own here fails the check.
local nativePools, nativeActive = {}, {}
-- Once the addon has loaded, adding or removing a data provider fails the check (#158).
local addonLoaded = false
_G.WorldMapFrame = setmetatable({
	dataProviders = {},
	shown = true,
	IsShown = function(self)
		return self.shown
	end,
	EnumeratePinsByTemplate = function(_, template)
		local i, list = 0, nativeActive[template] or {}
		return function()
			i = i + 1
			return list[i]
		end
	end,
	RemoveAllPinsByTemplate = function(_, template)
		assert(not template:match("^ShortestPathForever"), "the addon released a map pin of its own: " .. template)
		nativePools[template] = nativePools[template] or {}
		for _, pin in ipairs(nativeActive[template] or {}) do
			pin:Hide()
			pin:OnReleased()
			nativePools[template][#nativePools[template] + 1] = pin
		end
		nativeActive[template] = {}
	end,
	AcquirePin = function(_, template, ...)
		assert(not template:match("^ShortestPathForever"), "the addon acquired a map pin: " .. template)
		nativePools[template], nativeActive[template] = nativePools[template] or {}, nativeActive[template] or {}
		local pin = table.remove(nativePools[template])
		if not pin then
			pin = stubframe()
			pin.Texture, pin.Icon = pin:CreateTexture(), pin:CreateTexture()
			function pin.Texture:SetAtlas(atlas)
				self.atlas = atlas
			end
			local mixin = _G[template:gsub("Template$", "Mixin")]
			for k, v in pairs(mixin or {}) do
				pin[k] = v
			end
			pin.pinTemplate = template
			if pin.OnLoad then
				pin:OnLoad()
			end
		end
		nativeActive[template][#nativeActive[template] + 1] = pin
		pin:Show()
		if pin.OnAcquired then
			pin:OnAcquired(...)
		end
		return pin
	end,
	AddDataProvider = function(self, provider)
		assert(not addonLoaded, "the addon added a data provider to the world map")
		providers[#providers + 1] = provider
		self.dataProviders[provider] = true
		provider:RefreshAllData()
	end,
	RemoveDataProvider = function()
		error("the addon removed a data provider from the world map")
	end,
	AddCanvasClickHandler = function(_, fn)
		clickHandlers[#clickHandlers + 1] = fn
	end,
	AddGlobalPinMouseActionHandler = function(_, fn)
		pinHandlers[#pinHandlers + 1] = fn
	end,
}, mt)
-- One map: the canvas reads above are the world map's own.
for key, value in pairs(map) do
	rawset(WorldMapFrame, key, value)
end
map = WorldMapFrame
_G.ObjectiveTrackerManager = setmetatable({}, {
	__index = function(_, key)
		error("addon entered native tracker manager: " .. key)
	end,
})
_G.UIParent = CreateFrame("Frame")
_G.UIParent:SetSize(1920, 1080)
_G.ObjectiveTrackerFrame = CreateFrame("Frame", nil, UIParent)
_G.ObjectiveTrackerFrame:SetSize(250, 600)
-- The shared stub gives every frame a bare Header table; the real tracker header is a frame, and the host asks
-- whether it is shown before it moves it. A hidden header keeps the smoke run off the native layout path.
_G.ObjectiveTrackerFrame.Header.IsShown = function()
	return false
end
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
-- The walking search answers with the straight line when a check calls settle().
local path = assert(loadfile("tests/path_fake.lua"))()()
local settle = path.settle
local ns = {}
for line in io.lines("ShortestPathForever.toc") do
	-- The packager writes CRLF; tools/check_package.py runs this on its output.
	line = line:gsub("\r$", "")
	if line:match("%.lua$") then
		assert(loadfile((line:gsub("\\", "/"))))("ShortestPathForever", ns)
	end
end
local actualPath = ns.Path
ns.Path = path.Path
fireEvent("ADDON_LOADED", "ShortestPathForever")
fireEvent("PLAYER_ENTERING_WORLD")
assert(#errors == 0, table.concat(errors, "\n"))
addonLoaded = true
-- The addon's pins on the world map, by pool (its template name): the active ones and the free ones.
-- The addon's pools are listed by key, so a check can walk them; Blizzard's own pins are looked up by template.
local active = setmetatable({}, {
	__index = function(_, key)
		return nativeActive[key]
	end,
})
for key, pool in pairs(ns.MapCanvas.Pools(WorldMapFrame)) do
	active[key] = pool.active
end
local pools = setmetatable({}, {
	__index = function(_, key)
		local pool = ns.MapCanvas.Pools(WorldMapFrame)[key]
		return pool and pool.free
	end,
})
-- One frame of the map's view (UI/MapCanvas.lua), as the client runs its OnUpdate while the map is shown.
local function mapTick()
	ns.MapCanvas.Update(WorldMapFrame)
end
-- The world map opened or closed. Closing hides the canvas, and with it the view's frame (its OnHide); opening runs
-- the view's first frame, as the client would.
local function setMapShown(shown)
	local was = visible
	visible, WorldMapFrame.shown = shown, shown
	if was and not shown then
		for _, child in ipairs(canvas.children or {}) do
			if child.scripts.OnHide then
				child.scripts.OnHide(child)
			end
		end
	elseif shown then
		mapTick()
	end
end
-- The map closed and opened again: the addon's layers redraw as they do on the map's show, and Blizzard's own
-- providers refresh as MapCanvasMixin:OnShow has them.
local function refreshMap()
	if visible then
		setMapShown(false)
		setMapShown(true)
	end
	for _, provider in ipairs(providers) do
		provider:RefreshAllData()
	end
end
-- The canvas zoomed (or its pin scale changed): the view tells the layers on its next frame.
local function canvasScaled()
	ns.MapCanvas.Watch(WorldMapFrame).scale = nil
	mapTick()
end
-- A click on one of the addon's pins, as the press and release of a mouse button over it make one.
local function clickPin(pin, button)
	ns.MapCanvas.Click(pin, button)
end

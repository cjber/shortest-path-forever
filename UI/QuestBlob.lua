---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- The minimap draws every watched quest's objective area itself (MinimapFrameAPI). Its inside and outside texture
-- setters are global: they repaint every watched quest's area at once, so the addon never calls them (#680). Only the
-- edge a super-tracked quest wears has a setter of its own, SetQuestBlobOutsideSelectedTexture, and that is the only
-- part this recolours: standing in the area of a quest the held stop names turns the tracked quest's edge to the
-- bonus objective's gold, and the moment that stops being true the stock edge comes back. The two selected edges are
-- client files (FileDataIDs 1083696 and 1388127). A client without that setter keeps the stock blue, and Route.lua
-- keeps the stop's ring and line on the minimap because nothing there can show the goal otherwise.
--
-- The ring is not part of this. It is the minimap's own edge ring, drawn around the whole map rather than around the
-- quest's area, so recolouring it puts a second, larger gold outline around the blue area the player is in (#504).
-- The stock blue edge the super-tracked quest wears, and the bonus objective's gold area and edges.
local QUEST = {
	outsideSelected = "Interface\\Minimap\\UI-QuestBlobMinimap-OutsideSelected",
}
local BONUS = {
	inside = "Interface\\Minimap\\UI-BonusObjectiveBlob-Inside",
	outside = "Interface\\Minimap\\UI-BonusObjectiveBlob-Outside",
	outsideSelected = "Interface\\Minimap\\UI-BonusObjectiveBlob-OutsideSelected",
}

-- A client without the selected-edge setter keeps the minimap untouched.
local minimap = Minimap

local tinted

-- Whether this client's minimap can wear the gold edge, the one blob setter that changes a single quest's area rather
-- than every watched quest's.
---@return boolean
function ns.AreaBlobRecolours()
	return minimap ~= nil and minimap.SetQuestBlobOutsideSelectedTexture ~= nil
end

-- Recolours the super-tracked quest's edge: true wears the gold while the player stands in the area, false hands the
-- stock blue back. Repeated calls with the same state cost nothing, and a client without the setter is never touched.
---@param on boolean
function ns.SetAreaBlob(on)
	on = on == true
	if not ns.AreaBlobRecolours() then
		tinted = nil
		return
	end
	if tinted == on then
		return
	end
	tinted = on
	minimap:SetQuestBlobOutsideSelectedTexture(on and BONUS.outsideSelected or QUEST.outsideSelected)
end

-- The world map draws the tracked quest's area with a pin of the blob widget, sized to the canvas
-- (QuestBlobPinMixin in Blizzard_SharedMapDataProviders/QuestBlobDataProvider.lua). This pin is the addon's own
-- widget of that kind for the quests a held stop names, set up as the stock pin sets itself up but wearing the gold
-- set, so the world map shows the goal's area in the guide's colour whether or not the minimap can recolour its own
-- blob: its border is the gold edge and its fill uses the gold set's inside texture, which is clear. The player's
-- tracked quest and the stock pin are never touched.
---@class SPFAreaPin : SPFCanvasPin
---@field quests? number[]
---@field blob boolean -- whether this client's widget has every blob method the pin calls
---@field SetFillTexture fun(self: SPFAreaPin, asset: string)
---@field SetBorderTexture fun(self: SPFAreaPin, asset: string)
---@field SetFillAlpha fun(self: SPFAreaPin, alpha: number)
---@field SetBorderAlpha fun(self: SPFAreaPin, alpha: number)
---@field SetBorderScalar fun(self: SPFAreaPin, scalar: number)
---@field SetMapID fun(self: SPFAreaPin, mapID: number)
---@field DrawNone fun(self: SPFAreaPin)
---@field DrawBlob fun(self: SPFAreaPin, questID: number, draw: boolean)
local AreaPin = CreateFromMixins(ns.Canvas.PinMixin)
-- Route.lua's pool puts it on.
ns.AreaPinMixin = AreaPin

-- FrameAPIBlob's methods the pin calls.
local BLOB_METHODS = {
	"SetFillTexture",
	"SetBorderTexture",
	"SetFillAlpha",
	"SetBorderAlpha",
	"SetBorderScalar",
	"SetMapID",
	"DrawNone",
	"DrawBlob",
}

function AreaPin:OnLoad()
	self.blob = true
	for _, method in ipairs(BLOB_METHODS) do
		self.blob = self.blob and self[method] ~= nil
	end
	if not self.blob then
		return
	end
	-- A blob's fill covers the quest's area and its border runs along the area's edge, so both stretch by design.
	self:SetFillTexture(BONUS.inside)
	self:SetBorderTexture(BONUS.outside)
	self:SetFillAlpha(128)
	self:SetBorderAlpha(192)
	self:SetBorderScalar(1.0)
	self:SetIgnoreGlobalPinScale(true)
	self:UseFrameLevelType("PIN_FRAME_LEVEL_QUEST_BLOB")
end

-- Every named quest's area the client has on the map being viewed, as the stock pin's Refresh draws several.
function AreaPin:Refresh()
	self:SetScript("OnUpdate", nil)
	self:SetMapID(self:GetMap():GetMapID() --[[@as number]])
	self:DrawNone()
	for _, questID in ipairs(self.quests) do
		self:DrawBlob(questID, true)
	end
end

---@param quests number[]
function AreaPin:OnAcquired(quests)
	if not self.blob then
		return
	end
	self.quests = quests
	self:OnCanvasSizeChanged()
	self:SetPosition(0.5, 0.5)
	self:Refresh()
end

function AreaPin:OnReleased()
	if self.blob then
		self:SetScript("OnUpdate", nil)
		self:DrawNone()
	end
	self.quests = nil
end

function AreaPin:OnCanvasSizeChanged()
	local canvas = self:GetMap():GetCanvas()
	self:SetSize(canvas:GetWidth(), canvas:GetHeight())
end

-- The blob is redrawn once the frame's zoom has settled, as the stock pin waits for the end of the frame.
function AreaPin:OnCanvasScaleChanged()
	self:SetScript("OnUpdate", self.Refresh)
end

ns.Init(function()
	-- Disabling the addon reloads the UI, so a logout inside the area hands the blue back before the client paints.
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGOUT")
	frame:SetScript("OnEvent", function()
		ns.SetAreaBlob(false)
	end)
end)

---@class SPFNamespace
local ns = select(2, ...)

-- The minimap draws a quest's objective area itself (MinimapFrameAPI). Standing in the area of a quest the held
-- stop names recolours the game's own blob to the bonus objective's gold by swapping the stock quest textures for
-- the stock bonus objective set; the moment that stops being true the quest set comes back, so the minimap is never
-- left altered. Both sets are client files (FileDataIDs 533893 to 533895 and 1117897 to 1117899, with their selected
-- edges at 1083696 and 1388127). The world map's own bonus objective set (Interface\WorldMap\UI-BonusObjectiveBlob-
-- Inside and -Outside) is green, so the world map's area wears the minimap's gold set too.
--
-- The ring is not part of this. It is the minimap's own edge ring, drawn around the whole map rather than around the
-- quest's area, so recolouring it puts a second, larger gold outline around the blue area the player is in (#504).
-- The area itself is the inside and outside textures, and the edge a super-tracked quest wears is the selected
-- outside texture; where a client has no setter for that one, the ordinary area remains as it was.
local QUEST = {
	inside = "Interface\\Minimap\\UI-QuestBlobMinimap-Inside",
	outside = "Interface\\Minimap\\UI-QuestBlobMinimap-Outside",
	outsideSelected = "Interface\\Minimap\\UI-QuestBlobMinimap-OutsideSelected",
}
local BONUS = {
	inside = "Interface\\Minimap\\UI-BonusObjectiveBlob-Inside",
	outside = "Interface\\Minimap\\UI-BonusObjectiveBlob-Outside",
	outsideSelected = "Interface\\Minimap\\UI-BonusObjectiveBlob-OutsideSelected",
}

-- A client without the blob setters keeps the minimap untouched.
local minimap = Minimap
local supported = minimap and minimap.SetQuestBlobInsideTexture and minimap.SetQuestBlobOutsideTexture
-- The selected edge is not on every client's Minimap; the ordinary area is still recoloured without it.
local setOutsideSelected = minimap and minimap.SetQuestBlobOutsideSelectedTexture

local tinted

-- Recolours the minimap's quest area: true wears the gold while the player stands in the area, false hands the
-- stock blue back. The area textures are applied on every call while inside, since a quest update can rebuild the
-- client's blob from the stock set while the player has not moved; the stock set is restored only once.
---@param on boolean
function ns.SetAreaBlob(on)
	on = on == true
	if not supported then
		return
	end
	if not on and not tinted then
		return
	end
	tinted = on
	local textures = on and BONUS or QUEST
	minimap:SetQuestBlobInsideTexture(textures.inside)
	minimap:SetQuestBlobOutsideTexture(textures.outside)
	if setOutsideSelected then
		minimap:SetQuestBlobOutsideSelectedTexture(textures.outsideSelected)
	end
end

-- The world map draws the tracked quest's area with a pin of the blob widget, sized to the canvas
-- (QuestBlobPinMixin in Blizzard_SharedMapDataProviders/QuestBlobDataProvider.lua). This pin is the addon's own
-- widget of that kind for the quests a held stop names, set up as the stock pin sets itself up but wearing the
-- minimap's gold set, so both maps show one area in one colour: its border is the gold edge and its fill is clear,
-- as on the minimap. The player's tracked quest and the stock pin are never touched.
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
local AreaPin = CreateFromMixins(ns.MapCanvas.PinMixin)
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
	self:SetMapID(self:GetMap():GetMapID())
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

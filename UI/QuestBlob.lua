---@class SPFNamespace
local ns = select(2, ...)

-- The minimap draws a quest's objective area itself (MinimapFrameAPI). Standing in the held stop's area recolours
-- the game's own blob to the bonus objective's gold by swapping the stock quest textures for the stock bonus
-- objective set; the moment that stops being true the quest set comes back, so the minimap is never left altered.
local QUEST = {
	inside = "Interface\\Minimap\\UI-QuestBlobMinimap-Inside",
	outside = "Interface\\Minimap\\UI-QuestBlobMinimap-Outside",
	ring = "Interface\\Minimap\\UI-QuestBlob-MinimapRing",
}
local BONUS = {
	inside = "Interface\\Minimap\\UI-BonusObjectiveBlob-Inside",
	outside = "Interface\\Minimap\\UI-BonusObjectiveBlob-Outside",
	ring = "Interface\\Minimap\\UI-BonusObjectiveBlob-MinimapRing",
}

-- A client without the blob setters keeps the minimap untouched.
local minimap = Minimap
local supported = minimap
	and minimap.SetQuestBlobInsideTexture
	and minimap.SetQuestBlobOutsideTexture
	and minimap.SetQuestBlobRingTexture

local tinted

-- Recolours the minimap's quest blob: true wears the gold while the player stands in the area, false hands the
-- stock blue back. Repeated calls with the same state cost nothing.
---@param on boolean
function ns.SetAreaBlob(on)
	on = on == true
	if not supported or tinted == on then
		return
	end
	tinted = on
	local textures = on and BONUS or QUEST
	minimap:SetQuestBlobInsideTexture(textures.inside)
	minimap:SetQuestBlobOutsideTexture(textures.outside)
	minimap:SetQuestBlobRingTexture(textures.ring)
end

ns.Init(function()
	-- Disabling the addon reloads the UI, so a logout inside the area hands the blue back before the client paints.
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGOUT")
	frame:SetScript("OnEvent", function()
		ns.SetAreaBlob(false)
	end)
end)

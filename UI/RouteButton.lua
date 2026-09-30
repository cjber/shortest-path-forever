---@class SPFNamespace
local ns = select(2, ...)
local L = ns.L

-- A round button on the minimap, wearing the game's own minimap button plate and the addon's own icon, that
-- starts and stops the route in one click and turns gold while a route is on. It is a shortcut for Journey's
-- own Guide toggle, the one the tracker header uses, so the journey stays the single owner of the route: the
-- button draws that state, it never keeps one of its own.
--
-- Degrees round the minimap from its right edge. 225 is the lower left, where the family's other addons put
-- their buttons; 315 is the lower right, clear of the clock, mail and tracking buttons at the top right.
local ANGLE, GAP, SIZE = 315, 6, 24
-- The Forever build's own plate (UiTextureAtlasMember 1.60.1.69913: 20 by 18), drawn at its native size.
local PLATE = "ui-hud-minimap-button"
local PLATE_WIDTH, PLATE_HEIGHT = 20, 18
-- The addon's icon (WFA-8's `## IconTexture`), at native aspect, and the game's own gold for an active state.
local ICON = "Interface\\AddOns\\ShortestPathForever\\media\\Icon"
local GOLD = { 1, 0.82, 0 }

---@class SPFRouteButton : Button
---@field Plate Texture
---@field Icon Texture
---@field active? boolean
---@type SPFRouteButton?
local button

local function Place(self)
	local radius = Minimap:GetWidth() / 2 + GAP
	local angle = math.rad(ANGLE)
	self:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function Tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, L["Route"])
	-- The game's own instruction line, as its clickable pins use.
	if not ns.HasJourney() then
		GameTooltip_AddInstructionLine(GameTooltip, L["Shift-click the world map or minimap to plan one."])
	elseif ns.IsJourneyGuided() then
		GameTooltip_AddInstructionLine(GameTooltip, L["The route is on. Click to stop."])
	else
		GameTooltip_AddInstructionLine(GameTooltip, L["Click to start the route."])
	end
	GameTooltip_AddInstructionLine(GameTooltip, L["Middle-click for nearby services."])
	GameTooltip:Show()
end

local function OnClick(_, mouseButton)
	if mouseButton == "RightButton" then
		ns.OpenSettings()
		return
	end
	if mouseButton == "MiddleButton" then
		ns.OpenNearby()
		return
	end
	ns.ToggleJourneyGuide()
end

-- The game's gold while a route is on, and the plate's own colours when there is none. Only journey changes
-- reach here, so this is at most one write per change.
local function Paint(self)
	local active = ns.IsJourneyGuided() == true
	if self.active == active then
		return
	end
	self.active = active
	self.Plate:SetVertexColor(active and GOLD[1] or 1, active and GOLD[2] or 1, active and GOLD[3] or 1)
end

---@return SPFRouteButton
local function Create()
	local frame = CreateFrame("Button", "ShortestPathForeverRouteButton", Minimap)
	---@cast frame SPFRouteButton
	button = frame
	frame:SetSize(SIZE, SIZE)
	frame:SetFrameStrata("MEDIUM")
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	local plate = frame:CreateTexture(nil, "BACKGROUND")
	ns.FitAtlas(plate, PLATE, PLATE_WIDTH, PLATE_HEIGHT)
	plate:SetPoint("CENTER")
	frame.Plate = plate
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(SIZE * 0.6, SIZE * 0.6)
	icon:SetPoint("CENTER")
	frame.Icon = icon
	-- The game's own hover glow, as its minimap buttons wear.
	frame:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	frame:SetScript("OnClick", OnClick)
	frame:SetScript("OnEnter", Tooltip)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	Place(frame)
	return frame
end

-- Journey.lua starts and stops the guide through Tracker.lua's refresh, which calls this; the setting calls it
-- too. The frame is built on the first refresh with the setting on, so turning it off never builds it at all.
function ns.RefreshRouteButton()
	if not ns.db.routeButton then
		if button then
			button:Hide()
		end
		return
	end
	local frame = button or Create()
	frame:Show()
	Paint(frame)
end

ns.Init(ns.RefreshRouteButton)

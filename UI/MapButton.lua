---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L
local Art = ns.Art
local Canvas = ns.Canvas

-- Quick map button for Nearby services (#1342): sits in the world map's top-right column as our own frame
-- (Canvas.FrameUnder, never AddOverlayFrame, #158). Left-click opens the Nearby services panel; right-click opens
-- a checkbox menu bound to the same per-service map filters the panel uses.
local BUTTON_SIZE = 32
local ICON_SIZE = 22
local BUTTON_GAP = -32
local LEGACY_GAP = -46
local MENU_EXTENT = 20 * 20
local UP_ATLAS = "common-button-square-gray-up"
local DOWN_ATLAS = "common-button-square-gray-down"
local ICON_ATLAS = "Banker"

local STATUS = {
	building = L["Loading QuestieDB…"],
	missing = L["Nearby services need the QuestieDB addon."],
	failed = L["Nearby services could not read QuestieDB."],
}

---@class SPFMapButton : SPFPressable, Button
---@field Background Texture
---@field Icon Texture
---@field Highlight Texture

---@type SPFMapButton?
local mapButton

---@param map SPFMapCanvas
---@return Frame
local function Container(map)
	local container = map.GetCanvasContainer and map:GetCanvasContainer()
	if type(container) == "table" then
		return container
	end
	if type(map.ScrollContainer) == "table" then
		return map.ScrollContainer
	end
	return map
end

-- Below any shown top-right buttons on the map's canvas container, reading only without touching map state.
---@param map SPFMapCanvas
---@param own Frame
---@return number
local function TopRightOffset(map, own)
	local offsetY = -2
	local overlays = map.overlayFrames
	if type(overlays) == "table" then
		for _, frame in ipairs(overlays) do
			if frame ~= own and frame:IsShown() and frame:GetPoint(1) == "TOPRIGHT" then
				offsetY = offsetY + BUTTON_GAP
			end
		end
	end
	local index = 1
	local other = rawget(_G, "Krowi_WorldMapButtons" .. index)
	while other do
		if other:IsShown() and other:GetPoint(1) == "TOPRIGHT" then
			offsetY = offsetY + BUTTON_GAP
			break
		end
		index = index + 1
		other = rawget(_G, "Krowi_WorldMapButtons" .. index)
	end
	if rawget(_G, "LegacyForeverMapButtonMixin") then
		offsetY = offsetY + LEGACY_GAP
	end
	return offsetY
end

---@param button SPFMapButton
local function Position(button)
	local map = WorldMapFrame
	if not map then
		return
	end
	button:ClearAllPoints()
	button:SetPoint("TOPRIGHT", Container(map), "TOPRIGHT", -4, TopRightOffset(map, button))
end

---@param button SPFMapButton
---@param down boolean
local function SetPressed(button, down)
	Art.Fit(button.Background, down and DOWN_ATLAS or UP_ATLAS, BUTTON_SIZE, BUTTON_SIZE)
	Canvas.Press(button, button.pressRegions, down)
end

---@param _ Region
---@param root ForeverMenuDescription
local function BuildMenu(_, root)
	root:CreateTitle(L["Nearby services"])
	root:SetScrollMode(MENU_EXTENT)
	local nearby = ns.NearbyServices
	nearby.Request()
	local state = nearby.State and nearby.State() or "ready"
	if state ~= "ready" then
		root:CreateTitle(STATUS[state] or STATUS.building)
	else
		local sections = ns.NearbyGroups and ns.NearbyGroups.sections or {}
		local currentSection
		for _, group in ipairs(nearby.Groups()) do
			local shown = ns.ServiceOnMap(group)
			if
				shown ~= nil
				and not (group.skill and ns.NearbyProfessions and not ns.NearbyProfessions.Shown(group))
			then
				if group.section ~= currentSection then
					currentSection = group.section
					local heading = sections[currentSection]
					if heading then
						root:CreateTitle(heading)
					end
				end
				root:CreateCheckbox(group.label, function()
					return ns.ServiceOnMap(group) == true
				end, function()
					ns.SetServiceOnMap(group, not ns.ServiceOnMap(group))
				end)
			end
		end
	end
	if ns.TownServiceChoices then
		root:CreateDivider()
		local submenu = root:CreateButton(L["Town services"])
		-- menu-scroll-ok: the four town levels are fixed
		for _, choice in ipairs(ns.TownServiceChoices) do
			submenu:CreateRadio(choice.label, function()
				return ns.db.townServices == choice.key
			end, function()
				ns.SetOption("townServices", choice.key)
			end)
		end
	end
end

---@param button SPFMapButton
local function OpenMenu(button)
	if ns.GamepadUI() then
		ns.Notice(L["This menu needs mouse and keyboard."])
		return
	end
	ForeverCore.ContextMenu(button, BuildMenu)
end

function ns.RefreshMapButton()
	if not mapButton then
		return
	end
	local shown = not ns.db or ns.db.nearbyMapButton ~= false
	mapButton:SetShown(shown)
	if shown then
		Position(mapButton)
	elseif GameTooltip and not GameTooltip:IsForbidden() and GameTooltip:IsOwned(mapButton) then
		GameTooltip:Hide()
	end
end

ns.Init(function()
	if not WorldMapFrame then
		return
	end
	local button = Canvas.FrameUnder("Button", WorldMapFrame) --[[@as SPFMapButton]]
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetFrameStrata("HIGH")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("CENTER")
	Art.Fit(background, UP_ATLAS, BUTTON_SIZE, BUTTON_SIZE)
	button.Background = background

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER")
	Art.Fit(icon, ICON_ATLAS, ICON_SIZE, ICON_SIZE)
	button.Icon = icon

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetPoint("CENTER")
	Art.Fit(highlight, UP_ATLAS, BUTTON_SIZE, BUTTON_SIZE)
	highlight:SetBlendMode("ADD")
	highlight:SetAlpha(0.4)
	button.Highlight = highlight

	button.pressRegions = { icon }

	-- No OnShow or OnHide script on a frame under WorldMapFrame (#158); Canvas.Watch reports open, turn, size and hide.
	button:SetScript("OnMouseDown", function(self)
		SetPressed(self --[[@as SPFMapButton]], true)
	end)
	button:SetScript("OnMouseUp", function(self)
		SetPressed(self --[[@as SPFMapButton]], false)
	end)
	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "LeftButton" then
			ns.NearbyServices.Open()
		elseif mouseButton == "RightButton" then
			OpenMenu(self --[[@as SPFMapButton]])
		end
	end)
	button:SetScript("OnEnter", function(self)
		if GameTooltip:IsForbidden() then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip_SetTitle(GameTooltip, L["Nearby services"])
		GameTooltip_AddInstructionLine(GameTooltip, L["Left-click to open Nearby services."])
		GameTooltip_AddInstructionLine(GameTooltip, L["Right-click to choose map services."])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		SetPressed(self --[[@as SPFMapButton]], false)
		if not GameTooltip:IsForbidden() and GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)

	mapButton = button
	ns.nearbyMapButton = button
	Canvas.Watch(WorldMapFrame, function(_, what)
		if what == "show" or what == "map" or what == "size" then
			if button:IsShown() then
				Position(button)
			end
		elseif what == "hide" then
			SetPressed(button, false)
			if GameTooltip and not GameTooltip:IsForbidden() and GameTooltip:IsOwned(button) then
				GameTooltip:Hide()
			end
		end
	end)
	ns.RefreshMapButton()
end)

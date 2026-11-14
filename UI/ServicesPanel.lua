---@type string, SPFNamespace
local _, ns = ...

if ns.broken then
	return
end
local L = ns.L
local Art = ns.Art

-- The quest log's own search bar and list geometry, as Adventure Guide's panel uses them. The header is the pouch
-- item's icon, the panel's title and the player's zone; below it the Vendors, Trainers and Services sections.
local TOP_BAR = 29
local PAD = 6
local HEADER_HEIGHT = 22
local HEADER_GAP = 4
local GROUP_GAP = 6
local ROW_HEIGHT = 44
local ROW_GAP = 2
local ICON = 30
-- A better trip (NearbyServices.Better: better goods for your level, farther away) is a row of one line, indented
-- under its group's row, its item icon wearing the client's own upgrade mark at the top left, as a bag slot's does
-- (Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml:109, and Forever's Camelot/EquipmentFlyout.xml:12).
local BETTER_HEIGHT = 28
local BETTER_ICON = 22
local BETTER_INDENT = 16
local UPGRADE_ATLAS = "bags-greenarrow"
local BADGE_WIDTH, BADGE_HEIGHT = 11, 12
-- The line between your professions and the other trainers: the quest log's own separator, stretched across the
-- list at its 15 height as the quest log stretches it (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.xml:541).
local DIVIDER_ATLAS = "QuestLog-frame-devider"
local DIVIDER_HEIGHT = 15
-- The tab and the title wear the client's own bank bags glyph, cut out like the quest log's other tab icons; the tab
-- draws it at 32: the bags fill their atlas edge to edge, so 32 shows them about as large as the stock quest glyph
-- and the Adventure Guide compass, which keep a margin inside theirs.
local SERVICES_ATLAS = "Banker"
local TAB_ICON = 32
local LIST_TOP = 4 + 34 + 6
local SHORTLIST = 5
-- The panel re-ranks every so often while it stays open, so a walk or a boat changing under the player is reflected.
local TICK = 10

local STATUS = {
	building = L["Loading QuestieDB…"],
	missing = L["Nearby services need the QuestieDB addon."],
	failed = L["Nearby services could not read QuestieDB."],
}

---@type Frame?
local panel
-- Whether the player can see the panel, as the tab module's `shown` reports it. No script under the world map says so.
local visible = false
---@type SPFScrollFrame?
local scroll
---@type Frame?
local scrollContent
---@type Frame?
local content
---@type Frame?
local list
---@type SPFSearchBox?
local searchBox
---@type FontString?
local headerTitle
---@type FontString?
local subtitle
---@type FontString?
local emptyText
---@type SPFServicesHeader[]
local headers = {}
---@type SPFServicesRow[]
local rows = {}
---@type SPFServicesBetterRow[]
local betterRows = {}
---@type Frame[]
local dividers = {}
---@type table<string, SPFServicesRow>
local rowsByKey = {}
---@type SPFNearbySection[]
local sections = {}
-- Collapsed sections are per session, as the stock quest log's group folds are.
---@type table<string, boolean>
local collapsed = {}
-- The planner's answer per row id (the group's key, or its better trip's), from the queue below. A row with neither
-- still shows its straight-line nearest.
---@type table<string, number>
local estimates = {}
---@type table<string, SPFNearbyPlace>
local chosen = {}
---@type SPFNearbyRank[]?
local rankQueue
local rankAt = 1
---@type table?
local ticker
local query = ""
-- Defined below its builders; the search box's handler needs them.
local Refresh, Queue

---@class SPFScrollFrame : ScrollFrame
---@field ScrollBar Slider

---@class SPFSearchBox : EditBox
---@field Instructions FontString

---@class SPFCollapseButton : Button
---@field UpdateCollapsedState fun(self: SPFCollapseButton, collapsed: boolean)
---@class SPFServicesHeader : Button
---@field key string
---@field Name FontString
---@field Count FontString
---@field CollapseButton SPFCollapseButton

---@class SPFServicesRow : Button
---@field id string the row's own id in the section (SPFNearbyRow.id), which its estimate is kept by
---@field key string the group's key, which the journey goes by
---@field group SPFNearbyGroup
---@field place SPFNearbyPlace
---@field seconds number?
---@field query string
---@field itemID integer? the goods the row names first (NearbyServices.Goods), which its icon shows
---@field Item Button the icon's hover and click: the item's own tooltip, and Shift-click links it
---@field Icon Texture
---@field Label FontString
---@field Detail FontString
---@field Time FontString
---@field Badge? Texture on a better trip's row only, the upgrade arrow over its icon
---@class SPFServicesBetterRow : SPFServicesRow

-- An item's icon from the client's item data, which it holds for every item whether or not it is cached; the
-- question mark if the client has no such item.
local QUESTION_MARK = 134400
---@param itemID integer
---@return integer
local function ItemIcon(itemID)
	return C_Item.GetItemIconByID(itemID) or QUESTION_MARK
end

---@param row SPFServicesRow
local function PaintRow(row)
	local group, place = row.group, row.place
	local goods = ns.NearbyServices.Goods(group.key, place, row.query)
	row.itemID = goods and goods[1]
	local icon = group.icon
	if row.itemID then
		Art.Icon(row.Icon, ItemIcon(row.itemID), ICON)
	elseif type(icon) == "number" then
		Art.Icon(row.Icon, ItemIcon(icon), ICON)
	else
		Art.Fit(row.Icon, icon, ICON, ICON)
	end
	row.Label:SetText(group.label)
	row.Detail:SetText(ns.NearbyServices.Detail(group.key, place, row.query))
	row.Time:SetText(row.seconds and ns.FormatCountdown(row.seconds * 1000) or "")
end

-- A better trip's row: its goods in their quality's colour and the zone they are sold in; who sells them is in its
-- tooltip.
---@param row SPFServicesBetterRow
local function PaintBetterRow(row)
	local goods = ns.NearbyServices.Goods(row.group.key, row.place)
	row.itemID = goods and goods[1]
	Art.Icon(row.Icon, row.itemID and ItemIcon(row.itemID) or QUESTION_MARK, BETTER_ICON)
	local name = row.itemID and ns.NearbyServices.ItemName(row.itemID) or row.place.name
	local quality = row.itemID and C_Item.GetItemQualityByID(row.itemID)
	local hex = quality and select(4, C_Item.GetItemQualityColor(quality)) -- multi-value: the hex string is fourth
	if hex then
		name = ("|c%s%s|r"):format(hex, name)
	end
	local zone = ns.NearbyServices.Zone(row.place)
	row.Label:SetText(zone and L["%s · %s"]:format(name, zone) or name)
	row.Time:SetText(row.seconds and ns.FormatCountdown(row.seconds * 1000) or "")
end

---@param row SPFServicesRow
local function Paint(row)
	if row.Badge then
		PaintBetterRow(row --[[@as SPFServicesBetterRow]])
	else
		PaintRow(row)
	end
end

-- Over a row's icon, the goods the row names show their own tooltip, as a merchant's or a quest reward's do; the row
-- keeps its hover light meanwhile, and a click that links nothing still starts the journey.
---@param row SPFServicesRow
---@param size number
local function AddItemButton(row, size)
	row.Item = CreateFrame("Button", nil, row)
	row.Item:SetSize(size, size)
	row.Item:SetPoint("CENTER", row.Icon)
	row.Item:SetScript("OnEnter", function(self)
		row:LockHighlight()
		if row.itemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(row.itemID)
			GameTooltip:Show()
		end
	end)
	row.Item:SetScript("OnLeave", function(self)
		row:UnlockHighlight()
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)
	row.Item:SetScript("OnClick", function()
		local link = row.itemID and select(2, C_Item.GetItemInfo(row.itemID)) -- multi-value: the link is second
		if not (link and HandleModifiedItemClick(link)) then
			ns.NearbyServices.Navigate(row.key, row.place)
		end
	end)
end

---@param parent Frame
---@return SPFServicesRow
local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent) --[[@as SPFServicesRow]]
	row:SetHeight(ROW_HEIGHT)
	Art.RowArt(row)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetPoint("LEFT", 8, 0)
	AddItemButton(row, ICON)
	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
	row.Label:SetJustifyH("LEFT")
	row.Label:SetWordWrap(false)
	row.Time = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Time:SetPoint("TOPRIGHT", -8, -8)
	row.Time:SetJustifyH("RIGHT")
	row.Label:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, 4)
	row.Label:SetPoint("RIGHT", row.Time, "LEFT", -6, 0)
	row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Detail:SetPoint("TOPLEFT", row.Label, "BOTTOMLEFT", 0, -4)
	row.Detail:SetPoint("RIGHT", row.Time, "LEFT", -6, 0)
	row.Detail:SetJustifyH("LEFT")
	row.Detail:SetWordWrap(false)
	row:SetScript("OnClick", function(self)
		ns.NearbyServices.Navigate(self.key, self.place)
	end)
	return row
end

---@param parent Frame
---@return SPFServicesBetterRow
local function CreateBetterRow(parent)
	local row = CreateFrame("Button", nil, parent) --[[@as SPFServicesBetterRow]]
	row:SetHeight(BETTER_HEIGHT)
	Art.RowArt(row)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetPoint("LEFT", 6, 0)
	local badge = row:CreateTexture(nil, "OVERLAY")
	badge:SetPoint("TOPLEFT", row.Icon)
	Art.Fit(badge, UPGRADE_ATLAS, BADGE_WIDTH, BADGE_HEIGHT)
	row.Badge = badge
	AddItemButton(row, BETTER_ICON)
	row.Time = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Time:SetPoint("RIGHT", -8, 0)
	row.Time:SetJustifyH("RIGHT")
	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.Label:SetPoint("LEFT", row.Icon, "RIGHT", 8, 0)
	row.Label:SetPoint("RIGHT", row.Time, "LEFT", -6, 0)
	row.Label:SetJustifyH("LEFT")
	row.Label:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		if self.itemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			ns.NearbyServices.BetterTooltip(GameTooltip, self.itemID, self.place)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end)
	row:SetScript("OnClick", function(self)
		ns.NearbyServices.Navigate(self.key, self.place)
	end)
	return row
end

---@param parent Frame
---@return Frame
local function CreateDivider(parent)
	local divider = CreateFrame("Frame", nil, parent)
	divider:SetHeight(DIVIDER_HEIGHT)
	Art.Band(divider:CreateTexture(nil, "OVERLAY"), DIVIDER_ATLAS)
	return divider
end

---@param parent Frame
---@return SPFServicesHeader
local function CreateHeader(parent)
	local header = CreateFrame("Button", nil, parent) --[[@as SPFServicesHeader]]
	header:SetHeight(HEADER_HEIGHT)
	for _, layer in ipairs({ "BACKGROUND", "HIGHLIGHT" }) do
		local art = header:CreateTexture(nil, layer)
		Art.Band(art, "common-button-list-collapseExpand")
		if layer == "HIGHLIGHT" then
			art:SetBlendMode("ADD")
			art:SetAlpha(0.4)
		end
	end
	header.CollapseButton = CreateFrame("Button", nil, header, "CollapseButtonTemplate") --[[@as SPFCollapseButton]]
	header.CollapseButton:SetPoint("RIGHT", -6, 0)
	header.Count = header:CreateFontString(nil, "ARTWORK", "Game15Font_Shadow")
	header.Count:SetPoint("RIGHT", -28, 0)
	header.Count:SetJustifyH("RIGHT")
	header.Name = header:CreateFontString(nil, "ARTWORK", "Game15Font_Shadow")
	header.Name:SetPoint("LEFT", 8, 0)
	header.Name:SetPoint("RIGHT", header.Count, "LEFT", -4, 0)
	header.Name:SetJustifyH("LEFT")
	header.Name:SetWordWrap(false)
	header.Name:SetMaxLines(1)
	for _, text in ipairs({ header.Name, header.Count }) do
		text:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	end
	local function Toggle()
		collapsed[header.key] = not collapsed[header.key]
		Refresh()
		Queue()
	end
	header:SetScript("OnClick", Toggle)
	header.CollapseButton:SetScript("OnClick", Toggle)
	return header
end

---@param parentFrame Frame
local function BuildTopBar(parentFrame)
	searchBox = CreateFrame("EditBox", nil, parentFrame, "SearchBoxTemplate") --[[@as SPFSearchBox]]
	searchBox.Instructions:SetText(L["Search services and goods"])
	searchBox:SetHeight(20)
	searchBox:SetPoint("TOPLEFT", 6, -2)
	searchBox:SetPoint("TOPRIGHT", -3, -2)
	searchBox:SetMaxLetters(60)
	searchBox:HookScript("OnTextChanged", function()
		local text = searchBox:GetText() or ""
		if text == query then
			return
		end
		query = text
		estimates, chosen = {}, {}
		Refresh()
		if scroll then
			scroll:SetVerticalScroll(0)
		end
		Queue()
	end)
end

---@param parent Frame
local function BuildHeader(parent)
	local header = CreateFrame("Frame", nil, parent)
	header:SetPoint("TOPLEFT", 8, -4)
	header:SetPoint("TOPRIGHT", -8, -4)
	header:SetHeight(34)
	local icon = header:CreateTexture(nil, "ARTWORK")
	Art.Fit(icon, SERVICES_ATLAS, ICON, ICON)
	icon:SetPoint("LEFT", 2, 0)
	headerTitle = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge2")
	headerTitle:SetPoint("TOP", 0, -1)
	headerTitle:SetText(L["Nearby services"])
	subtitle = header:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	subtitle:SetPoint("TOP", headerTitle, "BOTTOM", 0, -2)
	return header
end

---@param parentFrame Frame
local function BuildContent(parentFrame)
	BuildTopBar(parentFrame)
	local body = CreateFrame("Frame", nil, parentFrame)
	body:SetPoint("TOPLEFT", 0, -TOP_BAR)
	body:SetPoint("BOTTOMRIGHT")
	CreateFrame("Frame", nil, body, "QuestLogBorderFrameTemplate")
	local viewport = CreateFrame("Frame", nil, body)
	viewport:SetPoint("TOPLEFT")
	viewport:SetPoint("BOTTOMRIGHT", 0, 0)
	scroll = CreateFrame("ScrollFrame", nil, viewport, "ScrollFrameTemplate") --[[@as SPFScrollFrame]]
	scroll:SetAllPoints()
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 2)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, -4)
	scrollContent = CreateFrame("Frame", nil, scroll)
	scroll:SetScrollChild(scrollContent)
	scroll:SetScript("OnSizeChanged", function(_, width)
		scrollContent:SetWidth(width)
	end)
	content = CreateFrame("Frame", nil, scrollContent)
	content:SetPoint("TOPLEFT")
	content:SetPoint("TOPRIGHT")
	local header = BuildHeader(content)
	list = CreateFrame("Frame", nil, content)
	-- The list's bottom follows the content, whose height Refresh sets: a frame with no height is not drawn, nor
	-- anything on it.
	list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	list:SetPoint("BOTTOMRIGHT")
	emptyText = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", 10, -8)
	emptyText:SetPoint("TOPRIGHT", -10, -8)
	emptyText:SetJustifyH("LEFT")
end

-- The player's own zone and subzone, as the client names them: "Auberdine, Darkshore", or the zone alone.
local function Where()
	local zone = GetZoneText and GetZoneText() or ""
	local subzone = GetSubZoneText and GetSubZoneText() or ""
	if zone == "" then
		return nil
	elseif subzone ~= "" then
		return L["%s, %s"]:format(subzone, zone)
	end
	return zone
end

-- The queued estimate for one row landed: paint the row with the planner's choice and time.
---@param key string
local function UpdateRow(key)
	local row = rowsByKey[key]
	if not row or not row:IsShown() then
		return
	end
	row.place = chosen[key] or row.place
	row.seconds = estimates[key]
	Paint(row)
end

-- One Estimate a frame, only while the panel is shown. The frame script is cleared as soon as the queue empties,
-- so nothing runs idle (AGENTS.md).
local function StepQueue()
	if not panel then
		return
	end
	local rank = rankQueue and rankQueue[rankAt]
	if not rank then
		rankQueue = nil
		panel:SetScript("OnUpdate", nil)
		return
	end
	local place, seconds, more = rank:Step()
	if place then
		chosen[rank.key] = place
	end
	if seconds then
		estimates[rank.key] = seconds
	end
	if not more then
		UpdateRow(rank.key)
		rankAt = rankAt + 1
	end
	if rankAt > #rankQueue then
		rankQueue = nil
		panel:SetScript("OnUpdate", nil)
		-- Every row has its travel time now: the dungeons and raids reorder by it, once.
		Refresh()
	end
end

-- Rank each shown group's shortlist through the queue: one Estimate per frame, cheapest wins once it lands.
function Queue()
	if not visible then
		return
	end
	---@cast panel -?
	rankQueue, rankAt = nil, 1
	panel:SetScript("OnUpdate", nil)
	local world = ns.NearbyServices.PlayerWorld()
	local map, x, y = ns.NearbyServices.PlayerUi()
	local api = ShortestPathForever and ShortestPathForever.API
	if not (world and map and x and y and api and api.Estimate) then
		return
	end
	local queue = {}
	for _, section in ipairs(sections) do
		if not section.collapsed then
			for _, entry in ipairs(section.rows) do
				local candidates = ns.NearbyServices.Shortlist(entry.group.key, world, SHORTLIST, query, entry.tier)
				if #candidates > 0 then
					local rank = ns.NearbyServices.Rank(candidates, api.Estimate, map, x, y)
					rank.key = entry.id
					queue[#queue + 1] = rank
				end
			end
		end
	end
	if #queue == 0 then
		return
	end
	rankQueue = queue
	panel:SetScript("OnUpdate", StepQueue)
end

-- A fresh look at the player's place: zones change and the ticker both come through here.
function Refresh()
	if not visible then
		return
	end
	---@cast panel -?
	---@cast list -?
	---@cast emptyText -?
	---@cast content -?
	local state = ns.NearbyServices.State()
	local world = ns.NearbyServices.PlayerWorld()
	sections = world and state == "ready" and ns.NearbyServices.Sections(world, query, collapsed, estimates) or {}
	rowsByKey = {}
	local top = 0
	local rowAt, betterAt, headerAt, dividerAt = 0, 0, 0, 0
	for _, section in ipairs(sections) do
		headerAt = headerAt + 1
		local header = headers[headerAt] or CreateHeader(list)
		headers[headerAt] = header
		header.key = section.section
		header.Name:SetText(section.label)
		header.Count:SetText(tostring(section.count))
		header.CollapseButton:UpdateCollapsedState(section.collapsed)
		header:SetPoint("TOPLEFT", 6, -top)
		header:SetPoint("TOPRIGHT", -6, -top)
		header:Show()
		top = top + HEADER_HEIGHT + HEADER_GAP
		if not section.collapsed then
			for _, entry in ipairs(section.rows) do
				if entry.apart then
					dividerAt = dividerAt + 1
					local divider = dividers[dividerAt] or CreateDivider(list)
					dividers[dividerAt] = divider
					divider:SetPoint("TOPLEFT", 6, -top)
					divider:SetPoint("TOPRIGHT", -6, -top)
					divider:Show()
					top = top + DIVIDER_HEIGHT
				end
				local row, indent, height
				if entry.tier then
					betterAt = betterAt + 1
					row = betterRows[betterAt] or CreateBetterRow(list)
					betterRows[betterAt] = row
					indent, height = BETTER_INDENT, BETTER_HEIGHT
				else
					rowAt = rowAt + 1
					row = rows[rowAt] or CreateRow(list)
					rows[rowAt] = row
					indent, height = 0, ROW_HEIGHT
				end
				row.id = entry.id
				row.key = entry.group.key
				row.group = entry.group
				row.place = chosen[entry.id] or entry.npc
				row.seconds = estimates[entry.id]
				row.query = query
				rowsByKey[entry.id] = row
				Paint(row)
				row:SetPoint("TOPLEFT", 6 + indent, -top)
				row:SetPoint("TOPRIGHT", -6, -top)
				row:Show()
				top = top + height + ROW_GAP
			end
		end
	end
	for at = rowAt + 1, #rows do
		rows[at]:Hide()
	end
	for at = betterAt + 1, #betterRows do
		betterRows[at]:Hide()
	end
	for at = headerAt + 1, #headers do
		headers[at]:Hide()
	end
	for at = dividerAt + 1, #dividers do
		dividers[at]:Hide()
	end
	-- An empty list says why: still loading, QuestieDB missing or broken, or here is nothing to offer.
	local status
	if state ~= "ready" then
		status = STATUS[state]
	elseif not world then
		status = L["Your position is unavailable"]
	elseif #sections == 0 then
		status = L["No services nearby."]
	end
	emptyText:SetText(status or "")
	emptyText:SetShown(status ~= nil)
	if status then
		local y = top > 0 and -top - GROUP_GAP or -8
		emptyText:SetPoint("TOPLEFT", 10, y)
		emptyText:SetPoint("TOPRIGHT", -10, y)
	end
	---@cast content -?
	content:SetHeight(LIST_TOP + top + PAD)
	if scrollContent then
		scrollContent:SetSize(panel:GetWidth(), LIST_TOP + top + PAD)
	end
	---@cast subtitle -?
	local where = Where()
	subtitle:SetShown(where ~= nil)
	subtitle:SetText(where or "")
end

---@param shown boolean
local function StartTicker(shown)
	if shown then
		if not ticker then
			ticker = C_Timer.NewTicker(TICK, function()
				if visible then
					Refresh()
					Queue()
				end
			end)
		end
	elseif ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- Re-queue after a zone change or on opening: the old straight-line and planner choices were for another place.
local function Requeue()
	estimates, chosen = {}, {}
	Refresh()
	Queue()
end

-- Whether the Nearby services tab sits in the shared quest log column. Another addon may need that space, and the
-- column belongs to ForeverCore, so it is asked to take our tab out rather than the tab frame being hidden: the key
-- stays registered, so /spfnear and the tracking menu still open the panel (cjber/forever-core#583).
function ns.RefreshNearbyTab()
	ForeverCore.QuestLogTabs.SetTabShown("services", not ns.db or ns.db.nearbyTab ~= false)
end

local function Attach()
	local map = QuestMapFrame
	panel = CreateFrame("Frame", "ShortestPathForeverServicesPanel", map)
	panel:SetPoint("TOPLEFT", map.ContentsAnchor)
	panel:SetPoint("BOTTOMRIGHT", map.ContentsAnchor, -22, 0)
	panel:SetFrameLevel(map:GetFrameLevel() + 20)
	panel:EnableMouse(true)
	panel:Hide()
	local background = panel:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("TOPLEFT", 0, -TOP_BAR)
	background:SetPoint("BOTTOMRIGHT")
	BuildContent(panel)
	Art.CoverFrame(panel, background, "QuestLog-main-background", 0, TOP_BAR)
	panel:RegisterEvent("ZONE_CHANGED")
	panel:RegisterEvent("ZONE_CHANGED_INDOORS")
	panel:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	panel:SetScript("OnEvent", function()
		if visible then
			Requeue()
		end
	end)
	-- The panel sets no show or hide script because it lives under the world map (#158); the tab module reports when
	-- the player can see it through `shown`.
	local function Shown(shown)
		visible = shown
		if shown then
			Requeue()
			StartTicker(true)
		else
			rankQueue = nil
			panel:SetScript("OnUpdate", nil)
			StartTicker(false)
		end
	end
	local tab = ForeverCore.QuestLogTabs.Register("services", {
		name = "ShortestPathForeverServicesTab",
		tooltip = L["Nearby services"],
		panel = panel,
		order = 20,
		shown = Shown,
		safeCall = ns.core.SafeCall,
	})
	ns.RefreshNearbyTab()
	Art.Fit(tab.Icon, SERVICES_ATLAS, TAB_ICON, TAB_ICON)
	ns.NearbyServices.OnReady(function()
		if visible then
			Requeue()
		end
	end)
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Attach)
end

-- The saved setting arrives with the character, after this file loads: apply it once it is there, so a tab turned off
-- stays off when the map loads later.
ns.Init(ns.RefreshNearbyTab)

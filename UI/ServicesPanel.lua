---@type string, SPFNamespace
local _, ns = ...
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
---@type table<string, SPFServicesRow>
local rowsByKey = {}
---@type SPFNearbySection[]
local sections = {}
-- Collapsed sections are per session, as the stock quest log's group folds are.
---@type table<string, boolean>
local collapsed = {}
-- The planner's answer per group, from the queue below. A group with neither still shows its straight-line nearest.
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
---@field key string
---@field group SPFNearbyGroup
---@field place SPFNearbyPlace
---@field seconds number?
---@field query string
---@field Icon Texture
---@field Label FontString
---@field Detail FontString
---@field Time FontString

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
	local icon = group.icon
	if type(icon) == "number" then
		Art.Icon(row.Icon, ItemIcon(icon), ICON)
	else
		Art.Fit(row.Icon, icon, ICON, ICON)
	end
	row.Label:SetText(group.label)
	row.Detail:SetText(ns.NearbyServices.Detail(group.key, place, row.query))
	row.Time:SetText(row.seconds and ns.FormatCountdown(row.seconds * 1000) or "")
end

---@param parent Frame
---@return SPFServicesRow
local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent) --[[@as SPFServicesRow]]
	row:SetHeight(ROW_HEIGHT)
	Art.RowArt(row)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetPoint("LEFT", 8, 0)
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
	PaintRow(row)
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
				local candidates = ns.NearbyServices.Shortlist(entry.group.key, world, SHORTLIST, query)
				if #candidates > 0 then
					local rank = ns.NearbyServices.Rank(candidates, api.Estimate, map, x, y)
					rank.key = entry.group.key
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
	sections = world and state == "ready" and ns.NearbyServices.Sections(world, query, collapsed) or {}
	rowsByKey = {}
	local top = 0
	local rowAt, headerAt = 0, 0
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
				rowAt = rowAt + 1
				local row = rows[rowAt] or CreateRow(list)
				rows[rowAt] = row
				row.key = entry.group.key
				row.group = entry.group
				row.place = chosen[entry.group.key] or entry.npc
				row.seconds = estimates[entry.group.key]
				row.query = query
				rowsByKey[entry.group.key] = row
				PaintRow(row)
				row:SetPoint("TOPLEFT", 6, -top)
				row:SetPoint("TOPRIGHT", -6, -top)
				row:Show()
				top = top + ROW_HEIGHT + ROW_GAP
			end
		end
	end
	for at = rowAt + 1, #rows do
		rows[at]:Hide()
	end
	for at = headerAt + 1, #headers do
		headers[at]:Hide()
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
	local tab = ns.QuestLogTabs.Register("services", {
		name = "ShortestPathForeverServicesTab",
		tooltip = L["Nearby services"],
		panel = panel,
		order = 20,
		shown = Shown,
	})
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

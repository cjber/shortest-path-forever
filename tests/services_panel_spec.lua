-- UI/ServicesPanel.lua against a stub quest log and client: the tab registers once with its order, selecting the tab
-- shows the panel, a refresh keeps the ScrollFrame's offset and only a new search query scrolls back to the top.
local created, tickers = {}, {}
local panel

local fontStrings = {}

local function region()
	local r = { points = {}, shown = true }
	function r:SetPoint(...)
		self.points[#self.points + 1] = { ... }
	end
	function r:ClearAllPoints()
		self.points = {}
	end
	function r:SetText(text)
		self.text = text
	end
	function r:GetText()
		return self.text
	end
	function r.SetTextColor() end
	function r.SetJustifyH() end
	function r.SetWordWrap() end
	function r.SetMaxLines() end
	function r:SetAtlas(atlas)
		self.atlas = atlas
	end
	function r:SetTexture(file)
		self.file = file
	end
	function r:SetSize(width, height)
		self.width, self.height = width, height
	end
	function r.SetScale() end
	function r.SetBlendMode() end
	function r.SetAlpha() end
	function r:SetShown(shown)
		self.shown = shown
	end
	function r:Show()
		self.shown = true
	end
	function r:Hide()
		self.shown = false
	end
	function r:IsShown()
		return self.shown
	end
	function r.SetAllPoints() end
	function r.SetTexCoord() end
	return r
end

local function frame(frameType, name, parent, template)
	local f = {
		frameType = frameType,
		name = name,
		parent = parent,
		template = template,
		scripts = {},
		scriptHooks = {},
		setScriptCalls = {},
		hookScriptCalls = {},
		points = {},
		sized = template ~= nil,
		shown = true,
		width = 300,
		height = 40,
		events = {},
	}
	function f:SetScript(event, callback)
		self.scripts[event] = callback
		self.setScriptCalls[event] = (self.setScriptCalls[event] or 0) + 1
	end
	function f:HookScript(event, callback)
		self.scriptHooks[event] = self.scriptHooks[event] or {}
		self.scriptHooks[event][#self.scriptHooks[event] + 1] = callback
		self.hookScriptCalls[event] = (self.hookScriptCalls[event] or 0) + 1
	end
	function f:GetScript(event)
		return self.scripts[event]
	end
	function f:Show()
		self.shown = true
		if self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
		for _, handler in ipairs(self.scriptHooks.OnShow or {}) do
			handler(self)
		end
	end
	function f:Hide()
		self.shown = false
		if self.scripts.OnHide then
			self.scripts.OnHide(self)
		end
		for _, handler in ipairs(self.scriptHooks.OnHide or {}) do
			handler(self)
		end
	end
	function f:SetShown(shown)
		if shown then
			self:Show()
		else
			self:Hide()
		end
	end
	function f:IsShown()
		return self.shown
	end
	function f:SetPoint(...)
		self.points[#self.points + 1] = { ... }
	end
	function f:ClearAllPoints()
		self.points = {}
	end
	function f:SetSize(width, height)
		self.width, self.height, self.sized = width, height, true
	end
	function f:LockHighlight()
		self.highlightLocked = true
	end
	function f:UnlockHighlight()
		self.highlightLocked = false
	end
	function f:GetSize()
		return self.width, self.height
	end
	function f:SetWidth(width)
		self.width = width
	end
	function f:GetWidth()
		return self.width
	end
	function f:SetHeight(height)
		self.height, self.sized = height, true
	end
	function f:GetHeight()
		return self.height
	end
	function f:SetAllPoints()
		self.sized = true
	end
	function f:SetFrameLevel(level)
		self.level = level
	end
	function f.GetFrameLevel()
		return 1
	end
	function f.EnableMouse() end
	function f:RegisterEvent(event)
		self.events[event] = true
	end
	function f.CreateTexture()
		return region()
	end
	function f.CreateFontString()
		local text = region()
		fontStrings[#fontStrings + 1] = text
		return text
	end
	if template == "SearchBoxTemplate" then
		f.Instructions = region()
		f.text = ""
		function f:SetText(text)
			self.text = text
			if self.scripts.OnTextChanged then
				self.scripts.OnTextChanged(self)
			end
			for _, handler in ipairs(self.scriptHooks.OnTextChanged or {}) do
				handler(self)
			end
		end
		function f:GetText()
			return self.text
		end
		function f.SetMaxLetters() end
	elseif template == "ScrollFrameTemplate" then
		f.ScrollBar = frame("Slider", nil, f)
		f.scroll = 0
		function f:SetScrollChild(child)
			self.child = child
		end
		function f:SetVerticalScroll(value)
			self.scroll = value
		end
		function f:GetVerticalScroll()
			return self.scroll
		end
	elseif template == "CollapseButtonTemplate" then
		function f:UpdateCollapsedState(collapsed)
			self.collapsed = collapsed
		end
	end
	created[#created + 1] = f
	return f
end

local function byTemplate(template)
	for _, f in ipairs(created) do
		if f.template == template then
			return f
		end
	end
end

local ns = {
	Init = function() end,
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
}
ns.FormatCountdown = function(ms)
	local seconds = math.ceil(ms / 1000)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local groups = {
	{ section = "vendors", key = "arrows", label = "Arrows", icon = 2512 },
	{ section = "vendors", key = "bank", label = "Bank", icon = 4496 },
	{ section = "trainers", key = "class", label = "Class trainer", icon = "Class" },
}
local places = {
	arrows = { { id = 1, name = "Dalmond", title = "General Goods", map = 100, x = 0.1, y = 0.1 } },
	bank = { { id = 2, name = "Karus", title = "Banker", map = 100, x = 0.2, y = 0.2 } },
	class = { { id = 3, name = "Mage trainer", title = "Mage Trainer", map = 100, x = 0.3, y = 0.3 } },
}
-- The better trip under Arrows: Jagged Arrow from a vendor farther off, with a time of its own.
local far = { id = 4, name = "Jin'sora", title = "Bow Merchant", map = 1454, x = 0.5, y = 0.5 }
local shortlisted = {}
local navigated
-- The item tooltip a row's icon shows, and Shift-click's link.
local shift, linked = false, nil
local tooltip = { shown = false }
function tooltip:SetOwner(owner)
	self.owner = owner
end
function tooltip:SetItemByID(itemID)
	self.itemID = itemID
end
function tooltip:SetBetter(itemID, place)
	self.better = { itemID = itemID, place = place }
end
function tooltip:Show()
	self.shown = true
end
function tooltip:Hide()
	self.shown, self.owner = false, nil
end
function tooltip:IsOwned(owner)
	return self.owner == owner
end
ns.Art = {
	Icon = function(texture, file)
		texture.icon = file
	end,
	Fit = function(texture, atlas, width, height)
		texture.fit = { atlas = atlas, width = width, height = height }
	end,
	RowArt = function() end,
	Band = function() end,
	CoverFrame = function() end,
}
ns.NearbyServices = {
	State = function()
		return "ready"
	end,
	PlayerWorld = function()
		return { map = 1, x = 0, y = 0 }
	end,
	PlayerUi = function()
		return 100, 0.1, 0.1
	end,
	Sections = function(_, query)
		local list = {}
		for _, section in ipairs({ "vendors", "trainers" }) do
			local rows = {}
			for _, group in ipairs(groups) do
				local place = places[group.key][1]
				local match = query == "" or group.label:lower():find(query:lower(), 1, true) ~= nil
				if group.section == section and match then
					rows[#rows + 1] = { id = group.key, group = group, npc = place }
					if group.key == "arrows" and query == "" then
						rows[#rows + 1] = { id = "better:arrows", group = group, npc = far, tier = 40 }
					end
				end
			end
			if #rows > 0 then
				list[#list + 1] = { section = section, label = section, count = 0, collapsed = false, rows = rows }
			end
		end
		return list
	end,
	Shortlist = function(key, _, _, _, tier)
		shortlisted[#shortlisted + 1] = { key = key, tier = tier }
		return { tier and far or { id = 1, name = "Dalmond", title = "General Goods", map = 100, x = 0.1, y = 0.1 } }
	end,
	Rank = function(candidates)
		return {
			Step = function()
				return candidates[1], candidates[1] == far and 372 or 31, false
			end,
		}
	end,
	Detail = function(_, place)
		return place.name
	end,
	-- The arrow row names Razor Arrow, as a level 25 hunter's would; the others name no goods.
	Goods = function(key, place)
		return key == "arrows" and { place == far and 11285 or 3030 } or nil
	end,
	ItemName = function(itemID)
		return itemID == 11285 and "Jagged Arrow" or "Razor Arrow"
	end,
	Zone = function(place)
		return place == far and "Orgrimmar" or nil
	end,
	BetterTooltip = function(tip, itemID, place)
		tip:SetBetter(itemID, place)
	end,
	Navigate = function(key, place)
		navigated = { key = key, place = place }
	end,
	OnReady = function() end,
}
ns.core = { SafeCall = function() end }
local QuestLogTabs = {
	Register = function(key, spec)
		ns.registered = { key = key, spec = spec }
		ns.tab = { Icon = region() }
		return ns.tab
	end,
	Select = function(key)
		if ns.registered and ns.registered.key == key then
			ns.registered.spec.panel:Show()
			if ns.registered.spec.shown then
				ns.registered.spec.shown(true)
			end
		end
	end,
}
local map = frame("Frame", "QuestMapFrame")
map.ContentsAnchor = frame("Frame", "ContentsAnchor", map)
map.sized, map.ContentsAnchor.sized = true, true
local loaded
local env = setmetatable({
	QuestMapFrame = map,
	CreateFrame = frame,
	C_Item = {
		GetItemIconByID = function(itemID)
			return "icon:" .. itemID
		end,
		GetItemInfo = function(itemID)
			return "Razor Arrow", "|Hitem:" .. itemID .. "|h[Razor Arrow]|h"
		end,
		GetItemQualityByID = function()
			return 1
		end,
		GetItemQualityColor = function(quality)
			assert(quality == 1)
			return 1, 1, 1, "ffffffff"
		end,
	},
	GameTooltip = tooltip,
	HandleModifiedItemClick = function(link)
		if shift then
			linked = link
			return true
		end
		return false
	end,
	C_Timer = {
		NewTicker = function(seconds, callback)
			local ticker = { seconds = seconds, callback = callback, cancelled = false }
			function ticker:Cancel()
				self.cancelled = true
			end
			tickers[#tickers + 1] = ticker
			return ticker
		end,
		After = function() end,
	},
	EventUtil = {
		ContinueOnAddOnLoaded = function(name, callback)
			assert(name == "Blizzard_WorldMap", name)
			loaded = callback
		end,
	},
	GetZoneText = function()
		return "Darkshore"
	end,
	GetSubZoneText = function()
		return "Auberdine"
	end,
	NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 },
	ShortestPathForever = {
		API = {
			Estimate = function()
				return 10
			end,
			Navigate = function() end,
		},
	},
	InCombatLockdown = function()
		return false
	end,
}, { __index = _G })
env._G = env
env.ForeverCore = { QuestLogTabs = QuestLogTabs }
setfenv(assert(loadfile("UI/ServicesPanel.lua")), env)("ShortestPathForever", ns)
assert(loaded, "the panel waits for Blizzard_WorldMap")
loaded()
panel = ns.registered and ns.registered.spec.panel
assert(ns.registered.key == "services", "registered under its own key")
assert(ns.registered.spec.order == 20, "its tab order")
assert(ns.registered.spec.name == "ShortestPathForeverServicesTab", "its tab name")
local fit = ns.tab.Icon.fit
assert(fit and fit.atlas == "Banker" and fit.width == 32 and fit.height == 32, "the tab shows the bank bags at 32")
assert(ns.registered.spec.tooltip == "Nearby services", "its tooltip")
assert(panel and not panel:IsShown(), "the panel starts hidden")

local search = assert(byTemplate("SearchBoxTemplate"), "a search box")
local scroll = assert(byTemplate("ScrollFrameTemplate"), "a scroll frame")
assert(search.Instructions.text == "Search services and goods", "the search placeholder")
env.ForeverCore.QuestLogTabs.Select("services")
assert(panel:IsShown(), "selecting the tab shows the panel")
assert(#created > 4, "the panel built its frames")

-- The client draws a frame, and everything on it, only once it can work out its height: from SetHeight, SetSize or
-- SetAllPoints, or from anchors on two different rows (a top corner and a bottom corner, say). A frame stretched by
-- its two top corners alone has none, so the list and its rows vanished in game.
local ROWS = { TOPLEFT = "top", TOP = "top", TOPRIGHT = "top", LEFT = "middle", CENTER = "middle", RIGHT = "middle" }
for _, f in ipairs(created) do
	if not f.sized and f.frameType ~= "ScrollFrame" and f.frameType ~= "Slider" then
		local rows, count = {}, 0
		for _, point in ipairs(f.points) do
			local row = ROWS[point[1]] or "bottom"
			if not rows[row] then
				rows[row], count = true, count + 1
			end
		end
		assert(count >= 2, "a panel frame has a height: " .. tostring(f.name or f.frameType))
	end
end
assert(#tickers == 1 and tickers[1].seconds == 10, "a ten second ticker starts while shown")
assert(panel.scripts.OnUpdate, "ranking starts while shown")

-- A refresh while open, from a zone change, leaves the player's scroll offset alone.
scroll:SetVerticalScroll(42)
assert(panel.scripts.OnEvent, "zone changes are registered")
panel.scripts.OnEvent(panel, "ZONE_CHANGED")
assert(scroll:GetVerticalScroll() == 42, "a refresh keeps the scroll offset")

-- Only a change of the search query scrolls back to the top.
search:SetText("bank")
assert(scroll:GetVerticalScroll() == 0, "a new query scrolls back to the top")
assert(panel:IsShown(), "searching keeps the panel open")
assert(tickers[1].cancelled == false, "the ticker still runs while shown")
assert(panel.scripts.OnUpdate, "searching requeues the ranking")

-- A row's icon is the goods it names: over it, the item's own tooltip with the row still lit; Shift-click links the
-- item, a plain click goes there. A row that names no goods keeps its group's icon and shows no tooltip.
search:SetText("")
local arrowRow, bankRow
for _, f in ipairs(created) do
	if f.key == "arrows" and f.Item and not f.Badge then
		arrowRow = f
	elseif f.key == "bank" and f.Item then
		bankRow = f
	end
end
assert(arrowRow and arrowRow.itemID == 3030 and arrowRow.Icon.icon == "icon:3030", "the arrow row shows Razor Arrow")
arrowRow.Item.scripts.OnEnter(arrowRow.Item)
assert(tooltip.shown and tooltip.itemID == 3030 and tooltip:IsOwned(arrowRow.Item), "its icon shows the item tooltip")
assert(arrowRow.highlightLocked, "and keeps the row lit")
arrowRow.Item.scripts.OnLeave(arrowRow.Item)
assert(not tooltip.shown and not arrowRow.highlightLocked, "leaving hides both")
shift = true
arrowRow.Item.scripts.OnClick(arrowRow.Item)
assert(linked and linked:find("Hitem:3030", 1, true) and not navigated, "Shift-click links the item")
shift = false
arrowRow.Item.scripts.OnClick(arrowRow.Item)
assert(navigated and navigated.key == "arrows", "a plain click on the icon goes there")
navigated = nil
assert(bankRow and bankRow.itemID == nil, "the bank row names no goods")
bankRow.Item.scripts.OnEnter(bankRow.Item)
assert(not tooltip.shown and bankRow.highlightLocked, "and its icon shows no tooltip, only the row's light")
bankRow.Item.scripts.OnLeave(bankRow.Item)

-- Better goods farther away: a one-line row right under Arrows, its item icon wearing the client's upgrade arrow, its
-- goods and their zone, and a time of its own from its own ranking.
local betterRow
for _, f in ipairs(created) do
	if f.Badge and f:IsShown() then
		betterRow = f
	end
end
assert(betterRow and betterRow.id == "better:arrows" and betterRow.key == "arrows", "a better trip's row")
assert(betterRow.height == 28 and betterRow.Icon.icon == "icon:11285", "one line, with Jagged Arrow's icon")
local badge = betterRow.Badge.fit
assert(badge and badge.atlas == "bags-greenarrow" and badge.width == 11, "and the upgrade arrow on it")
assert(betterRow.Label.text == "|cffffffffJagged Arrow|r · Orgrimmar", "the goods in their colour, and the zone")
local under = betterRow.points[1]
assert(under[1] == "TOPLEFT" and under[2] == 22 and under[3] == -(22 + 4 + 44 + 2), "indented under Arrows")
for _ = 1, 10 do
	if panel.scripts.OnUpdate then
		panel.scripts.OnUpdate(panel)
	end
end
local tiers = {}
for _, call in ipairs(shortlisted) do
	tiers[call.key .. ":" .. tostring(call.tier)] = true
end
assert(tiers["arrows:40"] and tiers["arrows:nil"], "the trip is ranked at its tier, apart from the row above")
assert(arrowRow.Time.text == "0:31" and betterRow.Time.text == "6:12", "each shows its own time")
betterRow.scripts.OnEnter(betterRow)
assert(tooltip.shown and tooltip.better.itemID == 11285 and tooltip.better.place == far, "it says why, and where")
betterRow.scripts.OnLeave(betterRow)
assert(not tooltip.shown, "leaving hides it")
betterRow.Item.scripts.OnEnter(betterRow.Item)
assert(tooltip.itemID == 11285 and betterRow.highlightLocked, "its icon shows the item's own tooltip")
betterRow.Item.scripts.OnLeave(betterRow.Item)
betterRow.scripts.OnClick(betterRow)
assert(navigated and navigated.key == "arrows" and navigated.place == far, "a click goes to the farther vendor")
navigated = nil
search:SetText("bank")
assert(not betterRow:IsShown(), "a search with no trip hides the row")
search:SetText("")

-- The tab module reports the panel hidden when another tab, Quests or the map takes it away.
ns.registered.spec.shown(false)
assert(tickers[1].cancelled, "shown(false) cancels the ticker")
assert(panel.scripts.OnUpdate == nil, "shown(false) drops the queue")
assert(#tickers == 1, "shown(false) starts no ticker")

-- A zone event follows the reported visibility, not the panel frame's own shown flag.
scroll:SetVerticalScroll(42)
panel.scripts.OnEvent(panel, "ZONE_CHANGED")
assert(panel.scripts.OnUpdate == nil and scroll:GetVerticalScroll() == 42, "a zone change while hidden does nothing")

-- Nothing under the world map may carry a show or hide script (#158), and a resize must not refresh the panel.
for _, event in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do
	assert(panel.setScriptCalls[event] == nil, "the panel set a " .. event .. " script")
	assert(panel.hookScriptCalls[event] == nil, "the panel hooked " .. event)
end
-- The loading line sits under the title: every edge the header, list and line stretch by is a top edge, since a bare
-- RIGHT anchor also pins a frame's vertical middle and pulled the header over the line while the list was short.
env.ForeverCore.QuestLogTabs.Select("services")
ns.NearbyServices.State = function()
	return "building"
end
panel.scripts.OnEvent(panel, "ZONE_CHANGED")
local loading
for _, text in ipairs(fontStrings) do
	if text.text == "Loading QuestieDB…" then
		loading = text
	end
end
assert(loading and loading.shown ~= false, "the loading line shows while QuestieDB loads")
local edges = {}
for _, point in ipairs(loading.points) do
	edges[point[1]] = point
	assert(point[1] ~= "RIGHT", "the loading line stretches by its top edge")
end
assert(edges.TOPLEFT and edges.TOPRIGHT, "the loading line spans the list by its top corners")
assert(edges.TOPLEFT[3] == edges.TOPRIGHT[3], "both corners sit on one line")
assert(ns.registered.spec.panel == panel, "the tab keeps the one panel")
assert(not navigated, "a build never navigates by itself")
print("services_panel: tab registration, shown, scroll preservation and query reset: ok")

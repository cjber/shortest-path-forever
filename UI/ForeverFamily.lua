---@type string, ForeverFamilyNamespace
local _, ns = ...

-- The Forever addons, and the quiet hints one shows for another the player doesn't have. This file is
-- byte-identical in all five addons (tests/forever_family_spec.lua pins it): the first copy to load sets the
-- `ForeverFamily` global and later copies use it, unless a later copy is newer (a higher VERSION), which takes over
-- so an addon updated first never runs on an older copy. It holds no addon's own code; each addon passes in its saved
-- variables (`db`) and its own folder. Nothing here is protected, hooks Blizzard code, runs in combat or reaches
-- the network: a hint is a grey line, a menu entry or a settings row that shows a link to copy.

---@class ForeverFamilyNamespace
---@field L? table<string, string>
---@field Family? ForeverFamilyAPI

---@class ForeverFamilyDB
---@field suggestFamily? boolean false when the player turned the hints off; on by default
---@field familyDismissed? table<string, boolean> hints the player chose never to see again, by key

---@class ForeverFamilyAddon
---@field name string
---@field folder string
---@field url string
---@field line string what it does, in one line

---@alias ForeverFamilyState "on"|"off"|"missing"
---@alias ForeverFamilySaved ForeverFamilyDB|fun(): ForeverFamilyDB?

---@class ForeverFamilyAPI
---@field VERSION integer raised with every change to this file
---@field ADDONS ForeverFamilyAddon[]
---@field State fun(folder: string): ForeverFamilyState
---@field Hint fun(db?: ForeverFamilyDB, key: string, folder: string): boolean
---@field Once fun(key: string): boolean
---@field ShowLink fun(db?: ForeverFamilyDB, key?: string, folder: string, onDismiss?: fun()): boolean
---@field CreatePanel fun(parent?: Frame, db: ForeverFamilySaved, current?: string): ForeverFamilyPanel

---@class ForeverFamilyPanel : Frame
---@field Refresh fun(self: ForeverFamilyPanel)
---@field OnRefresh fun(self: ForeverFamilyPanel)
---@field OnDefault fun(self: ForeverFamilyPanel)

-- PortraitFrameTemplate's own members this file uses (Mainline/SharedUIPanelTemplates.xml).
---@class ForeverFamilyLinkWindow : Frame
---@field SetTitle fun(self: ForeverFamilyLinkWindow, title: string)
---@field GetPortrait fun(self: ForeverFamilyLinkWindow): Texture

local VERSION = 1
if ForeverFamily and (tonumber(ForeverFamily.VERSION) or 0) >= VERSION then
	ns.Family = ForeverFamily
	return
end

-- Every addon's L takes English phrases as keys; one that has no entry for a phrase shows the phrase itself.
---@type table<string, string>
local L = setmetatable({}, {
	__index = function(_, phrase)
		local text = ns.L and ns.L[phrase]
		return type(text) == "string" and text or phrase
	end,
})

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local LINK_NAME = "ForeverFamilyLink"

---@class ForeverFamilyAPI
local Family = { VERSION = VERSION }
Family.ADDONS = {
	{
		name = "Shortest Path Forever",
		folder = "ShortestPathForever",
		url = "https://www.curseforge.com/wow/addons/shortest-path-forever",
		line = L["Plans the quickest way anywhere and guides you there, with live boat and zeppelin times."],
	},
	{
		name = "Adventure Guide Forever",
		folder = "AdventureGuideForever",
		url = "https://www.curseforge.com/wow/addons/adventure-guide-forever",
		line = L["Picks quests for your level and plans them into one journey."],
	},
	{
		name = "SkillUp Forever",
		folder = "SkillUpForever",
		url = "https://www.curseforge.com/wow/addons/skillup-forever",
		line = L["Plans the cheapest route to your next profession rank."],
	},
	{
		name = "Legacy Forever",
		folder = "LegacyForever",
		url = "https://www.curseforge.com/wow/addons/legacy-forever",
		line = L["Shows the Legacy challenges you can advance in each zone."],
	},
	{
		name = "Tweaks Forever",
		folder = "TweaksForever",
		url = "https://www.curseforge.com/wow/addons/tweaks-forever",
		line = L["Quest automation, rare alerts and merchant handling for the default UI."],
	},
}

-- An installed addon's own icon; files load from a folder whether or not its addon is switched on.
---@param folder string
---@param state ForeverFamilyState
---@return string
local function Icon(folder, state)
	return state == "missing" and QUESTION or ("Interface\\AddOns\\" .. folder .. "\\media\\Icon")
end

---@param folder string
---@return ForeverFamilyAddon?
local function Find(folder)
	for _, addon in ipairs(Family.ADDONS) do
		if addon.folder == folder then
			return addon
		end
	end
end

-- The client may answer with a secret value in a restricted state; testing one raises, so the test happens
-- inside the pcall and a failed read means "don't know".
---@param question fun(): boolean
---@return boolean?
local function Ask(question)
	local ok, answer = pcall(question)
	if ok then
		return answer
	end
end

-- "off" covers every installed copy that isn't running: switched off, out of date or failed to load. An answer
-- the client won't give also reads as "off", so no hint shows for an addon the player may have.
---@param folder string
---@return ForeverFamilyState
function Family.State(folder)
	local api = C_AddOns
	if type(api) ~= "table" then
		return "off"
	end
	local loaded = Ask(function()
		return api.IsAddOnLoaded(folder) and true or false
	end)
	if loaded ~= false then
		return loaded and "on" or "off"
	end
	local exists = Ask(function()
		if api.DoesAddOnExist then
			return api.DoesAddOnExist(folder) and true or false
		end
		local _, _, _, _, reason = api.GetAddOnInfo(folder)
		return reason ~= "MISSING"
	end)
	return exists == false and "missing" or "off"
end

-- Whether the hint `key` for `folder` may show: hints are on, the addon isn't installed at all (one the player
-- switched off was their choice), and they haven't dismissed this hint. Passive places ask on every show.
---@param db? ForeverFamilyDB
---@param key string
---@param folder string
---@return boolean
function Family.Hint(db, key, folder)
	if type(db) ~= "table" or db.suggestFamily == false then
		return false
	end
	local dismissed = db.familyDismissed
	if type(dismissed) == "table" and dismissed[key] then
		return false
	end
	return Family.State(folder) == "missing"
end

local claimed = {}
-- True the first time `key` asks this session, for the places that draw attention (the tracker footer). Keys are
-- shared by every Forever addon, so each starts with its own addon's name.
---@param key string
---@return boolean
function Family.Once(key)
	if claimed[key] then
		return false
	end
	claimed[key] = true
	return true
end

---@type ForeverFamilyLinkWindow?
local window
local parts = {}
local shownURL = ""
---@type { db?: ForeverFamilyDB, key?: string, onDismiss?: fun() }
local showing = {}

---@param edit EditBox
local function Select(edit)
	edit:SetFocus()
	edit:HighlightText()
end

---@return ForeverFamilyLinkWindow
local function Window()
	if window then
		return window
	end
	local frame = CreateFrame("Frame", LINK_NAME, UIParent, "PortraitFrameTemplate") --[[@as ForeverFamilyLinkWindow]]
	-- Escape closes it like any panel (an addon-owned frame).
	table.insert(UISpecialFrames, LINK_NAME)
	frame:SetSize(400, 186)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

	local line = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	line:SetPoint("TOPLEFT", 70, -32)
	line:SetPoint("RIGHT", -16, 0)
	line:SetJustifyH("LEFT")

	local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate") --[[@as EditBox]]
	edit:SetPoint("TOPLEFT", 76, -78)
	edit:SetPoint("RIGHT", -20, 0)
	edit:SetHeight(24)
	edit:SetAutoFocus(false)
	-- Read-only: typing puts the address back, still selected, so a stray key never changes what is copied.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(shownURL)
			Select(self)
		end
	end)
	edit:SetScript("OnEditFocusGained", edit.HighlightText)
	edit:SetScript("OnEscapePressed", function()
		frame:Hide()
	end)

	local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	hint:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -6, -6)
	hint:SetPoint("RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText(L["Copy the address, then open it in your browser."])

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(96, 22)
	close:SetPoint("BOTTOMRIGHT", -14, 14)
	close:SetText(L["Close"])
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local never = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	never:SetSize(190, 22)
	never:SetPoint("RIGHT", close, "LEFT", -8, 0)
	never:SetText(L["Don't suggest this again"])
	never:SetScript("OnClick", function()
		local db, key, onDismiss = showing.db, showing.key, showing.onDismiss
		if db and key then
			db.familyDismissed = type(db.familyDismissed) == "table" and db.familyDismissed or {}
			db.familyDismissed[key] = true
		end
		frame:Hide()
		if onDismiss then
			onDismiss()
		end
	end)

	parts.line, parts.edit, parts.never = line, edit, never
	window = frame
	return frame
end

-- A small window with `folder`'s name, line and store address, selected for Ctrl+C. With a hint `key` it also
-- offers "Don't suggest this again", which dismisses that hint in `db` and then calls `onDismiss`. Never opens in
-- combat; returns whether it opened.
---@param db? ForeverFamilyDB
---@param key? string
---@param folder string
---@param onDismiss? fun()
---@return boolean
function Family.ShowLink(db, key, folder, onDismiss)
	local addon = Find(folder)
	if not addon or InCombatLockdown() then
		return false
	end
	local frame = Window()
	showing.db, showing.key, showing.onDismiss = db, key, onDismiss
	shownURL = addon.url
	frame:SetTitle(addon.name)
	-- art-ok: a square icon in the template's round portrait
	frame:GetPortrait():SetTexture(Icon(folder, Family.State(folder)))
	parts.line:SetText(addon.line)
	parts.edit:SetText(addon.url)
	parts.never:SetShown(db ~= nil and key ~= nil)
	frame:Show()
	Select(parts.edit)
	return true
end

local STATE_TEXT = {
	on = L["On"],
	off = L["Installed, turned off"],
	missing = L["Not installed"],
}
local ROW_HEIGHT = 52

-- The "Forever addons" settings page: the hint setting, then a row per addon with its icon, line, state and a
-- Copy link button. `db` is the addon's saved variables, or a function that returns them once they load;
-- `current` is the addon's own folder, whose row says "This addon". The rows are built the first time it shows
-- and their states read again each time. Defaults turns the hints back on, dismissed ones included.
---@param parent? Frame
---@param db ForeverFamilySaved
---@param current? string
---@return ForeverFamilyPanel
function Family.CreatePanel(parent, db, current)
	local panel = CreateFrame("Frame", nil, parent) --[[@as ForeverFamilyPanel]]
	-- Hidden until the settings panel shows it, so its OnShow always fires.
	panel:Hide()
	---@return ForeverFamilyDB?
	local function Saved()
		if type(db) == "function" then
			return db()
		end
		return db
	end
	local check
	local rows = {}

	local function Build()
		local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 16, -16)
		title:SetText(L["Forever addons"])

		check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate") --[[@as CheckButton]]
		check:SetPoint("TOPLEFT", 12, -44)
		check:SetScript("OnClick", function(self)
			local saved = Saved()
			if saved then
				saved.suggestFamily = self:GetChecked() and true or false
			else
				self:SetChecked(true)
			end
		end)
		local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		label:SetPoint("LEFT", check, "RIGHT", 4, 0)
		label:SetText(L["Suggest my other Forever addons"])
		local about = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		about:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 30, 2)
		about:SetPoint("RIGHT", -16, 0)
		about:SetJustifyH("LEFT")
		about:SetText(
			L["Show a quiet line where one of my other Forever addons would help. Only for addons you don't have."]
		)

		for index, addon in ipairs(Family.ADDONS) do
			local top = -100 - (index - 1) * ROW_HEIGHT
			local icon = panel:CreateTexture(nil, "ARTWORK")
			icon:SetSize(32, 32)
			icon:SetPoint("TOPLEFT", 16, top)
			local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
			button:SetSize(110, 22)
			button:SetPoint("TOPRIGHT", -16, top - 5)
			button:SetText(L["Copy link"])
			button:SetScript("OnClick", function()
				Family.ShowLink(nil, nil, addon.folder)
			end)
			local state = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			state:SetPoint("RIGHT", button, "LEFT", -10, 0)
			state:SetWidth(140)
			state:SetJustifyH("RIGHT")
			local name = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
			name:SetText(addon.name)
			local line = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
			line:SetPoint("RIGHT", state, "LEFT", -10, 0)
			line:SetJustifyH("LEFT")
			line:SetText(addon.line)
			rows[index] = { addon = addon, icon = icon, state = state, button = button }
		end
	end

	local function Refresh()
		if not check then
			Build()
		end
		local saved = Saved()
		check:SetChecked(not (saved and saved.suggestFamily == false))
		for _, row in ipairs(rows) do
			local folder = row.addon.folder
			local state = Family.State(folder)
			local own = folder == current
			-- art-ok: square icons at 32x32
			row.icon:SetTexture(Icon(folder, state))
			row.state:SetText(own and L["This addon"] or STATE_TEXT[state])
			row.button:SetShown(not own)
		end
	end
	panel.Refresh, panel.OnRefresh = Refresh, Refresh
	function panel.OnDefault()
		local saved = Saved()
		if saved then
			saved.suggestFamily, saved.familyDismissed = true, nil
		end
		Refresh()
	end
	panel:SetScript("OnShow", Refresh)
	return panel
end

ForeverFamily = Family -- taint-ok: addon-owned registry shared by the Forever addons
ns.Family = Family

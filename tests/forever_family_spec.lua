-- UI/ForeverFamily.lua is byte-identical in all five Forever addons, and so is this spec. A change to the module is
-- made in Shortest Path Forever first, then copied unchanged to the other four with this spec and its new pin.
local PINNED = "59852f2b801d864dce6a8341bbeb13927182c28d31d0cdfc3e283cb0c2df9eab"
local PATH = "UI/ForeverFamily.lua"

local bit = require("bit")
local band, bxor, bnot, rshift, lshift, ror, tobit =
	bit.band, bit.bxor, bit.bnot, bit.rshift, bit.lshift, bit.ror, bit.tobit

local checks = 0
local function check(value, message)
	assert(value, message)
	checks = checks + 1
end

-- SHA-256 (FIPS 180-4) in LuaJIT's bit library, so the pin needs no tool outside the spec harness.
-- stylua: ignore
local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local function sha256(message)
	local bits = #message * 8
	local length = ""
	for shift = 7, 0, -1 do
		length = length .. string.char(math.floor(bits / 2 ^ (shift * 8)) % 256)
	end
	message = message .. "\128" .. string.rep("\0", (55 - #message) % 64) .. length
	local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
	for chunk = 1, #message, 64 do
		local w = {}
		for i = 0, 15 do
			local b1, b2, b3, b4 = message:byte(chunk + i * 4, chunk + i * 4 + 3)
			w[i] = tobit(lshift(b1, 24) + lshift(b2, 16) + lshift(b3, 8) + b4)
		end
		for i = 16, 63 do
			local x, y = w[i - 15], w[i - 2]
			local s0 = bxor(ror(x, 7), ror(x, 18), rshift(x, 3))
			local s1 = bxor(ror(y, 17), ror(y, 19), rshift(y, 10))
			w[i] = tobit(w[i - 16] + s0 + w[i - 7] + s1)
		end
		local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
		for i = 0, 63 do
			local s1 = bxor(ror(e, 6), ror(e, 11), ror(e, 25))
			local choice = bxor(band(e, f), band(bnot(e), g))
			local t1 = tobit(h + s1 + choice + K[i + 1] + w[i])
			local s0 = bxor(ror(a, 2), ror(a, 13), ror(a, 22))
			local majority = bxor(band(a, b), band(a, c), band(b, c))
			h, g, f, e, d, c, b, a = g, f, e, tobit(d + t1), c, b, a, tobit(t1 + s0 + majority)
		end
		H[1], H[2], H[3], H[4] = tobit(H[1] + a), tobit(H[2] + b), tobit(H[3] + c), tobit(H[4] + d)
		H[5], H[6], H[7], H[8] = tobit(H[5] + e), tobit(H[6] + f), tobit(H[7] + g), tobit(H[8] + h)
	end
	local hex = {}
	for i = 1, 8 do
		hex[i] = bit.tohex(H[i], 8)
	end
	return table.concat(hex)
end
check(sha256("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 of nothing")
check(sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 of abc")
check(
	sha256(string.rep("a", 1000)) == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",
	"sha256 across several blocks"
)

local file = assert(io.open(PATH, "rb"))
local source = file:read("*a")
file:close()
local actual = sha256(source)
check(
	actual == PINNED,
	PATH
		.. " changed (sha256 "
		.. actual
		.. "). It is shared byte for byte by all five Forever addons: make the change in Shortest Path Forever, "
		.. "update PINNED here, then copy both files unchanged to the others."
)

-- A headless client: frames remember what the module sets and tests read back; every other method does nothing.
local frames, named = {}, {}
local function noop() end
local Widget = {}
Widget.__index = function(_, key)
	return Widget[key] or noop
end
function Widget:SetScript(event, fn)
	self.scripts[event] = fn
end
function Widget:GetScript(event)
	return self.scripts[event]
end
function Widget:SetText(text)
	self.text = text
	if self.scripts.OnTextChanged then
		self.scripts.OnTextChanged(self, false)
	end
end
function Widget:GetText()
	return self.text
end
function Widget:Show()
	self.shown = true
	if self.scripts.OnShow then
		self.scripts.OnShow(self)
	end
end
function Widget:Hide()
	self.shown = false
end
function Widget:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end
function Widget:IsShown()
	return self.shown
end
function Widget:SetChecked(checked)
	self.checked = checked
end
function Widget:GetChecked()
	return self.checked
end
function Widget:SetTexture(path)
	self.texture = path
end
function Widget:SetTitle(title)
	self.title = title
end
function Widget:GetPortrait()
	return self.portrait
end
function Widget:SetFocus()
	self.focused = true
end
function Widget:HighlightText()
	self.highlighted = true
end
function Widget:Click()
	self.scripts.OnClick(self)
end
function Widget:Type(text)
	self.text = text
	self.highlighted = false
	self.scripts.OnTextChanged(self, true)
end
local function Create(kind, parent, template)
	local widget = setmetatable(
		{ kind = kind, parent = parent, template = template, scripts = {}, shown = true, children = {} },
		Widget
	)
	if parent then
		parent.children[#parent.children + 1] = widget
	end
	return widget
end
function Widget:CreateFontString()
	return Create("FontString", self)
end
function Widget:CreateTexture()
	return Create("Texture", self)
end
local function Children(widget, kind, template)
	local found = {}
	for _, child in ipairs(widget.children) do
		if child.kind == kind and (template == nil or child.template == template) then
			found[#found + 1] = child
		end
	end
	return found
end
local function Texts(widget)
	local found = {}
	for _, child in ipairs(Children(widget, "FontString")) do
		found[#found + 1] = child.text
	end
	return table.concat(found, "\n")
end

local combat = false
local addons -- folder -> "on" | "off" | nil (missing)
local env
local function Client()
	addons = {}
	env = setmetatable({
		UIParent = Create("Frame"),
		UISpecialFrames = {},
		InCombatLockdown = function()
			return combat
		end,
		CreateFrame = function(kind, name, parent, template)
			local widget = Create(kind, parent, template)
			if template == "PortraitFrameTemplate" then
				widget.portrait = Create("Texture", widget)
			end
			frames[#frames + 1] = widget
			if name then
				named[name] = widget
			end
			return widget
		end,
		C_AddOns = {
			IsAddOnLoaded = function(folder)
				return addons[folder] == "on"
			end,
			DoesAddOnExist = function(folder)
				return addons[folder] ~= nil
			end,
			GetAddOnInfo = function(folder)
				return folder, folder, "", addons[folder] ~= nil, addons[folder] == nil and "MISSING" or "DISABLED"
			end,
		},
	}, { __index = _G })
	return env
end
local function Load(ns)
	setfenv(assert(loadfile(PATH)), env)("Test", ns)
	return ns.Family
end
local function PhraseLocale()
	return setmetatable({}, {
		__index = function(_, phrase)
			return phrase
		end,
	})
end

-- The first copy loaded is the one every addon uses.
Client()
local first = { L = PhraseLocale() }
local Family = Load(first)
check(Family and env.ForeverFamily == Family, "the first copy sets the shared global")
local count = #frames
local second = { L = PhraseLocale() }
check(Load(second) == Family, "a later copy joins the first")
check(#frames == count and count == 0, "loading builds no frames; the window and page wait until they're needed")
check(type(Family.VERSION) == "number" and Family.VERSION >= 1, "the module says which version it is")
local older = { VERSION = Family.VERSION - 1 }
env.ForeverFamily = older
local newer = { L = PhraseLocale() }
check(Load(newer) ~= older and env.ForeverFamily == newer.Family, "a newer copy takes over from an older one")
env.ForeverFamily = Family

-- The five addons, in order, with their store pages.
local expected = {
	{ "Shortest Path Forever", "ShortestPathForever", "shortest-path-forever" },
	{ "Adventure Guide Forever", "AdventureGuideForever", "adventure-guide-forever" },
	{ "SkillUp Forever", "SkillUpForever", "skillup-forever" },
	{ "Legacy Forever", "LegacyForever", "legacy-forever" },
	{ "Tweaks Forever", "TweaksForever", "tweaks-forever" },
}
check(#Family.ADDONS == #expected, "five addons")
for index, row in ipairs(expected) do
	local addon = Family.ADDONS[index]
	check(addon.name == row[1] and addon.folder == row[2], "addon " .. index .. " is " .. row[1])
	check(addon.url == "https://www.curseforge.com/wow/addons/" .. row[3], row[1] .. " links to its CurseForge page")
	check(type(addon.line) == "string" and addon.line ~= "" and not addon.line:find("!"), row[1] .. " has a plain line")
end

-- State: running, installed but not running, or not installed.
addons.AdventureGuideForever, addons.LegacyForever = "on", "off"
check(Family.State("AdventureGuideForever") == "on", "a loaded addon is on")
check(Family.State("LegacyForever") == "off", "an installed addon that isn't loaded is off")
check(Family.State("SkillUpForever") == "missing", "an addon that isn't there is missing")
local exists = env.C_AddOns.DoesAddOnExist
env.C_AddOns.DoesAddOnExist = nil
check(Family.State("SkillUpForever") == "missing", "without DoesAddOnExist, GetAddOnInfo's MISSING says so")
check(Family.State("LegacyForever") == "off", "and an installed one is still off")
env.C_AddOns.DoesAddOnExist = exists
local loaded = env.C_AddOns.IsAddOnLoaded
env.C_AddOns.IsAddOnLoaded = function()
	error("attempt to compare a secret value")
end
check(Family.State("SkillUpForever") == "off", "an answer the client won't give never reads as missing")
env.C_AddOns.IsAddOnLoaded = loaded
local api = env.C_AddOns
env.C_AddOns = nil
check(Family.State("SkillUpForever") == "off", "no C_AddOns: no hints")
env.C_AddOns = api

-- Hint: on by default, only for a missing addon, never once dismissed or switched off.
local db = {}
check(Family.Hint(db, "Test.skillup", "SkillUpForever"), "a missing addon's hint shows by default")
check(not Family.Hint(db, "Test.agf", "AdventureGuideForever"), "no hint for an addon that's on")
check(not Family.Hint(db, "Test.legacy", "LegacyForever"), "no hint for one the player switched off")
check(not Family.Hint(nil, "Test.skillup", "SkillUpForever"), "no hint before saved variables load")
db.suggestFamily = false
check(not Family.Hint(db, "Test.skillup", "SkillUpForever"), "the setting turns every hint off")
db.suggestFamily = true
db.familyDismissed = { ["Test.skillup"] = true }
check(not Family.Hint(db, "Test.skillup", "SkillUpForever"), "a dismissed hint stays away")
check(Family.Hint(db, "Test.other", "SkillUpForever"), "dismissing one hint leaves the others")

-- Once: at most once a session per key.
check(Family.Once("Test.footer"), "the first ask is yes")
check(not Family.Once("Test.footer"), "the second is no")
check(Family.Once("Test.other"), "keys are separate")

-- ShowLink: never in combat, built once, selected for copying.
combat = true
check(not Family.ShowLink(db, "Test.tweaks", "TweaksForever"), "no window in combat")
check(#frames == 0, "and nothing is built")
combat = false
check(not Family.ShowLink(db, "Test.x", "NotAForeverAddon"), "an unknown folder opens nothing")
check(Family.ShowLink(db, "Test.tweaks", "TweaksForever"), "the window opens out of combat")
local window = named.ForeverFamilyLink
check(window and window:IsShown() and window.title == "Tweaks Forever", "it shows the addon's name")
check(env.UISpecialFrames[1] == "ForeverFamilyLink", "Escape closes it")
check(window.portrait.texture == "Interface\\Icons\\INV_Misc_QuestionMark", "a missing addon gets a neutral icon")
local edit = Children(window, "EditBox")[1]
check(edit.text == "https://www.curseforge.com/wow/addons/tweaks-forever", "the address is in the box")
check(edit.focused and edit.highlighted, "and selected for Ctrl+C")
edit:Type("x")
check(
	edit.text == "https://www.curseforge.com/wow/addons/tweaks-forever" and edit.highlighted,
	"typing can't change it"
)
local texts = Texts(window)
check(texts:find("Copy the address, then open it in your browser.", 1, true), "it says what to do")
check(texts:find(Family.ADDONS[5].line, 1, true), "with the addon's line")
local buttons = Children(window, "Button", "UIPanelButtonTemplate")
local close, never = buttons[1], buttons[2]
check(close.text == "Close" and never.text == "Don't suggest this again", "Close and Don't suggest this again")
check(never:IsShown(), "a hint's window offers to dismiss it")
close:Click()
check(not window:IsShown(), "Close closes it")
local dismissed = 0
Family.ShowLink(db, "Test.tweaks", "TweaksForever", function()
	dismissed = dismissed + 1
end)
never:Click()
check(db.familyDismissed["Test.tweaks"] and dismissed == 1 and not window:IsShown(), "dismissing saves and closes")
check(not Family.Hint(db, "Test.tweaks", "TweaksForever"), "and the hint is gone")
local fresh = {}
Family.ShowLink(fresh, "Test.tweaks", "TweaksForever")
never:Click()
check(fresh.familyDismissed and fresh.familyDismissed["Test.tweaks"], "a first dismissal makes the table")
count = #frames
check(Family.ShowLink(nil, nil, "AdventureGuideForever"), "a link with no hint behind it")
check(#frames == count, "the window is reused")
check(not never:IsShown(), "and has nothing to dismiss")
check(
	window.portrait.texture == "Interface\\AddOns\\AdventureGuideForever\\media\\Icon",
	"an installed addon shows its own icon"
)

-- CreatePanel: the settings page, built on first show and read again each time.
local saved = {}
local parent = Create("Frame")
local panel = Family.CreatePanel(parent, function()
	return saved
end, "LegacyForever")
check(#panel.children == 0 and not panel.shown, "the page starts hidden and empty until it shows")
panel:Show()
check(Texts(panel):find("Forever addons", 1, true), "the page has its title")
local check_ = Children(panel, "CheckButton")[1]
check(check_ and check_.checked, "Suggest my other Forever addons starts on")
check(Texts(panel):find("Suggest my other Forever addons", 1, true), "the setting is labelled")
check(
	Texts(panel):find("Only for addons you don't have.", 1, true),
	"and says it only covers addons the player doesn't have"
)
check_.checked = false
check_:Click()
check(saved.suggestFamily == false, "unticking turns the hints off")
check_.checked = true
check_:Click()
check(saved.suggestFamily == true, "ticking turns them on")
local copies = Children(panel, "Button", "UIPanelButtonTemplate")
local icons = Children(panel, "Texture")
check(#copies == 5 and #icons == 5, "a row per addon")
local text = Texts(panel)
check(text:find("This addon", 1, true), "the addon's own row says so")
check(text:find("On", 1, true) and text:find("Not installed", 1, true), "the others show their state")
check(copies[4].shown == false and copies[1].shown, "no Copy link on the addon's own row")
check(icons[2].texture == "Interface\\AddOns\\AdventureGuideForever\\media\\Icon", "an installed addon's icon")
check(icons[3].texture == "Interface\\Icons\\INV_Misc_QuestionMark", "a missing one's is neutral")
addons.SkillUpForever = "off"
panel:Show()
check(Texts(panel):find("Installed, turned off", 1, true), "the states are read again on each show")
check(icons[3].texture == "Interface\\AddOns\\SkillUpForever\\media\\Icon", "and the icons")
copies[3]:Click()
check(window:IsShown() and window.title == "SkillUp Forever", "Copy link opens that addon's address")
saved.suggestFamily = false
panel:Show()
check(not check_.checked, "the box shows the saved setting")
saved.familyDismissed = { ["Test.footer"] = true }
panel:OnDefault()
check(saved.suggestFamily == true and check_.checked, "Defaults turns the hints back on")
check(saved.familyDismissed == nil, "including the dismissed ones")
local unloaded = Family.CreatePanel(nil, function() end)
unloaded:Show()
local early = Children(unloaded, "CheckButton")[1]
early.checked = false
early:Click()
check(early.checked, "before saved variables load, the box can't be changed")
local tableDb = { suggestFamily = false }
local plain = Family.CreatePanel(nil, tableDb)
plain:Show()
check(not Children(plain, "CheckButton")[1].checked, "a plain table works as the saved variables too")
check(not Texts(plain):find("This addon", 1, true), "with no current addon, no row says This addon")

-- Translations: an addon whose L holds only some phrases, or no metatable at all, still reads every line.
Client()
local agf = { L = { ["Not installed"] = "Nicht installiert" } }
local Translated = Load(agf)
check(Translated ~= Family and env.ForeverFamily == Translated, "a fresh client loads a fresh copy")
check(Translated.ADDONS[1].line == Family.ADDONS[1].line, "an untranslated phrase reads as English")
local page = Translated.CreatePanel(nil, {}, nil)
page:Show()
check(Texts(page):find("Nicht installiert", 1, true), "a translated phrase is used")
check(Texts(page):find("Copy link", 1, true) == nil, "button labels aren't font strings")
check(Children(page, "Button")[1].text == "Copy link", "and fall back to English")

print(("forever_family_spec: %d checks passed"):format(checks))

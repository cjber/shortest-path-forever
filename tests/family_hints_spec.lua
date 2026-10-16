-- Shortest Path's hints for my other Forever addons (UI/FamilyHints.lua), run through the shared module.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks = checks + 1
end
local function noop() end

local installed = {} -- folder -> "on" | "off"; absent is missing
local combat, now = false, 100
local timers, hooks, links = {}, {}, {}
local refreshed = 0
local tooltipLines = {}
local env = setmetatable({
	C_AddOns = {
		IsAddOnLoaded = function(folder)
			return installed[folder] == "on"
		end,
		DoesAddOnExist = function(folder)
			return installed[folder] ~= nil
		end,
	},
	InCombatLockdown = function()
		return combat
	end,
	GetTime = function()
		return now
	end,
	C_Timer = {
		After = function(delay, fn)
			timers[#timers + 1] = { delay = delay, fn = fn }
		end,
	},
	hooksecurefunc = function(target, name, fn)
		hooks[#hooks + 1] = { target = target, name = name, fn = fn }
	end,
	GRAY_FONT_COLOR = {
		WrapTextInColorCode = function(_, text)
			return "|cff808080" .. text .. "|r"
		end,
	},
	GameTooltip_AddColoredLine = function(tooltip, text, color)
		tooltipLines[#tooltipLines + 1] = { tooltip = tooltip, text = text, color = color }
	end,
}, { __index = _G })
env.GRAY_FONT_COLOR.r = 0.5

local goal, owner
local caught, printed = {}, {}
local ns = {
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	db = {},
	Init = function(fn)
		fn()
	end,
	JourneyGoal = function()
		return goal
	end,
	HasJourney = function()
		return goal ~= nil
	end,
	JourneyOwner = function()
		return owner
	end,
	PlaceLabel = function(point)
		return point.label
	end,
	RefreshTracker = function()
		refreshed = refreshed + 1
	end,
	JourneyChanged = noop,
	-- Core/SafeCall.lua: pcall's answers, with each failure kept as the report keeps it.
	SafeCall = function(label, fn, ...)
		local results = { pcall(fn, ...) }
		if not results[1] then
			caught[#caught + 1] = label
		end
		return unpack(results)
	end,
	Print = function(text)
		printed[#printed + 1] = text
	end,
}
setfenv(assert(loadfile("UI/ForeverFamily.lua")), env)("ShortestPathForever", ns)
-- The window itself is the shared module's, covered by tests/forever_family_spec.lua; here it records its calls.
ns.Family.ShowLink = function(db, key, folder, _, locale)
	if combat then
		return false
	end
	links[#links + 1] = { db = db, key = key, folder = folder, locale = locale }
	return true
end
setfenv(assert(loadfile("UI/FamilyHints.lua")), env)("ShortestPathForever", ns)
local Hints = ns.FamilyHints
check(#hooks == 1 and hooks[1].target == ns and hooks[1].name == "JourneyChanged", "follows journeys through ns")
local JourneyChanged = hooks[1].fn

-- The quest menus: a grey entry under Plan journey while Adventure Guide is missing.
local function Menu()
	local buttons = {}
	Hints.AddQuestMenu({
		CreateButton = function(_, text, fn)
			buttons[#buttons + 1] = { text = text, fn = fn }
		end,
	})
	return buttons
end
local buttons = Menu()
check(#buttons == 1, "one entry with Adventure Guide missing")
check(
	buttons[1].text == "|cff808080Suggest quests for my level: Adventure Guide Forever|r",
	"grey, saying what it would do"
)
buttons[1].fn()
check(
	links[1].folder == "AdventureGuideForever" and links[1].key == "ShortestPathForever.questMenu",
	"it opens Adventure Guide's link, dismissable"
)
check(links[1].db == ns.db and links[1].locale == ns.L, "with Shortest Path's settings and translations")
installed.AdventureGuideForever = "on"
check(#Menu() == 0, "nothing with Adventure Guide on")
installed.AdventureGuideForever = "off"
check(#Menu() == 0, "nothing with Adventure Guide installed but switched off")
installed.AdventureGuideForever = nil
ns.db.suggestFamily = false
check(#Menu() == 0, "nothing with Suggest my other Forever addons off")
ns.db.suggestFamily = nil
ns.db.familyDismissed = { ["ShortestPathForever.questMenu"] = true }
check(#Menu() == 0, "nothing once dismissed")
ns.db.familyDismissed = nil
check(#Menu() == 1, "and back when it applies again")

-- A dungeon or raid door's stop: a grey line for Legacy.
local tooltip = {}
goal = { label = "Enter Deadmines", entrance = 36 }
Hints.AddEntranceLine(tooltip)
check(#tooltipLines == 1, "a door gets the Legacy line with Legacy missing")
check(
	tooltipLines[1].text == "Legacy Forever shows the Legacy challenges this counts toward."
		and tooltipLines[1].color == env.GRAY_FONT_COLOR
		and tooltipLines[1].tooltip == tooltip,
	"grey, on the pin's tooltip"
)
goal = { label = "Goldshire" }
Hints.AddEntranceLine(tooltip)
check(#tooltipLines == 1, "no line on a stop that isn't a door")
goal = { label = "Enter Deadmines", entrance = 36 }
installed.LegacyForever = "on"
Hints.AddEntranceLine(tooltip)
check(#tooltipLines == 1, "none with Legacy on")
installed.LegacyForever = "off"
Hints.AddEntranceLine(tooltip)
check(#tooltipLines == 1, "none with Legacy switched off")
installed.LegacyForever = nil
ns.db.familyDismissed = { ["ShortestPathForever.entrance"] = true }
Hints.AddEntranceLine(tooltip)
check(#tooltipLines == 1, "none once dismissed")
ns.db.familyDismissed = nil
ns.db.suggestFamily = false
Hints.AddEntranceLine(tooltip)
check(#tooltipLines == 1, "none with the setting off")
ns.db.suggestFamily = nil
goal = nil
Hints.AddEntranceLine(tooltip)
check(#tooltipLines == 1, "none with no journey")

-- The tracker's arrival footer: once a session, only when the journey arrived with nothing more planned.
check(Hints.Footer() == nil, "no footer before any journey")
local stop1, stop2 = { label = "Goldshire" }, { label = "Stormwind" }
goal = stop1
JourneyChanged(stop1)
JourneyChanged(stop2)
goal = nil
JourneyChanged(nil, "cleared")
check(Hints.Footer() == nil, "no footer when the player clears a journey")
goal = stop1
JourneyChanged(stop1)
local before = Hints.Version()
installed.AdventureGuideForever = "on"
goal = nil
JourneyChanged(nil, "arrived")
check(Hints.Footer() == nil and Hints.Version() == before, "no footer with Adventure Guide on")
installed.AdventureGuideForever = nil
-- A guide or another addon driving the journey has its own next step.
owner = "RestedXP"
goal = stop2
JourneyChanged(stop2)
owner = nil
goal = nil
JourneyChanged(nil, "arrived")
check(Hints.Footer() == nil and Hints.Version() == before, "no footer after another addon's journey")
-- Nor with the journey hidden from the tracker.
ns.db.journeyTracker = false
goal = stop2
JourneyChanged(stop2)
goal = nil
JourneyChanged(nil, "arrived")
check(Hints.Footer() == nil and Hints.Version() == before, "no footer with the journey hidden from the tracker")
ns.db.journeyTracker = nil
owner = "Shortest Path Forever"
goal = stop2
JourneyChanged(stop2)
owner = nil
goal = nil
JourneyChanged(nil, "arrived")
local footer = Hints.Footer()
check(footer and footer.key == "family", "the footer shows after arriving with Adventure Guide missing")
check(footer.title == "Journey to Stormwind", "under the finished journey's title")
check(
	#footer.rows == 1
		and footer.rows[1].grey
		and footer.rows[1].text == "What next? Adventure Guide Forever suggests quests for your level.",
	"one grey line"
)
check(Hints.Version() ~= before, "the tracker's change check sees it")
check(timers[#timers].delay == 120 and timers[#timers].fn == ns.RefreshTracker, "the tracker looks again later")
now = now + 60
check(Hints.Footer() ~= nil, "it stays a while")
-- A new journey takes it away.
goal = stop1
check(Hints.Footer() == nil, "a new journey replaces it")
-- Once a session: a second arrival shows nothing.
JourneyChanged(stop1)
goal = nil
JourneyChanged(nil, "arrived")
check(Hints.Footer() == nil, "at most once a session")

-- A fresh session, for the footer's other endings.
local function Session()
	env.ForeverFamily, ns.Family = nil, nil
	setfenv(assert(loadfile("UI/ForeverFamily.lua")), env)("ShortestPathForever", ns)
	ns.Family.ShowLink = function(db, key, folder, _, locale)
		if combat then
			return false
		end
		links[#links + 1] = { db = db, key = key, folder = folder, locale = locale }
		return true
	end
	hooks = {}
	setfenv(assert(loadfile("UI/FamilyHints.lua")), env)("ShortestPathForever", ns)
	Hints = ns.FamilyHints
	JourneyChanged = hooks[1].fn
	goal = stop2
	JourneyChanged(stop2)
	goal = nil
	JourneyChanged(nil, "arrived")
	assert(Hints.Footer(), "a fresh session shows the footer again")
end
Session()
now = now + 120
check(Hints.Footer() == nil, "it goes after two minutes")
Session()
ns.db.suggestFamily = false
check(Hints.Footer() == nil, "turning the setting off takes it away")
ns.db.suggestFamily = nil
Session()
combat = true
Hints.OpenFooter()
check(Hints.Footer() ~= nil, "a click in combat leaves it, as the window can't open")
combat = false
local count, refreshedBefore = #links, refreshed
Hints.OpenFooter()
check(#links == count + 1 and links[#links].key == "ShortestPathForever.arrival", "clicking it opens the link")
check(refreshed == refreshedBefore + 1, "and redraws the tracker without it")
check(links[#links].folder == "AdventureGuideForever", "for Adventure Guide")
check(Hints.Footer() == nil, "and takes the footer away")
Hints.OpenFooter()
check(#links == count + 1, "with no footer, a click does nothing")
Session()
ns.db.familyDismissed = { ["ShortestPathForever.arrival"] = true }
check(Hints.Footer() == nil, "Don't suggest this again takes it away")
ns.db.familyDismissed = nil
Session()
ns.db.journeyTracker = false
check(Hints.Footer() == nil, "hiding the journey from the tracker takes it away")
ns.db.journeyTracker = nil

-- Adventure Guide on: its suggestions in the quest menus, from an AGF stub with API.Suggestions (minor 2).
local function Entries()
	local entries = {}
	Hints.AddQuestMenu({
		CreateTitle = function(_, text)
			entries[#entries + 1] = { title = text }
		end,
		CreateButton = function(_, text, fn)
			entries[#entries + 1] = { text = text, fn = fn }
		end,
	})
	return entries
end
local cards = {
	{ id = "story:1413", title = "The Barrens story", level = 10, kind = "story", map = 1413 },
	{ id = "carry", title = "Quests in your log", kind = "carry", map = 1413 },
	{ id = "zone:1440", title = "Head to Ashenvale", level = 18, kind = "nextzone", map = 1440 },
	{ id = "zone:1421", title = "Head to Silverpine Forest", level = 10, kind = "nextzone", map = 1421 },
}
local asked, started = {}, {}
local agf = {
	Suggestions = function(limit)
		asked[#asked + 1] = limit
		local list = {}
		for index = 1, math.min(limit or 5, #cards) do
			list[index] = cards[index]
		end
		return list
	end,
	StartSuggestion = function(id)
		started[#started + 1] = id
		return true
	end,
}
installed.AdventureGuideForever = "on"
env.AdventureGuideForever = { API = agf }
local entries = Entries()
check(asked[#asked] == 3, "asks for three")
check(#entries == 4 and entries[1].title == "Adventure Guide suggests", "a titled section with three rows")
check(entries[2].text == "[10] The Barrens story", "[level] title")
check(entries[3].text == "Quests in your log", "a card with no level shows its title alone")
check(entries[4].text == "[18] Head to Ashenvale", "in Adventure Guide's order")
entries[4].fn()
check(started[1] == "zone:1440", "clicking one starts it in Adventure Guide")
ns.db.suggestFamily = false
check(#Entries() == 4, "the suggestions are a feature, not a hint: the hint setting leaves them")
ns.db.suggestFamily = nil
agf.Suggestions = function()
	return nil
end
check(#Entries() == 0, "nothing while Adventure Guide is still working out its route")
agf.Suggestions = function()
	return {}
end
check(#Entries() == 0, "nothing when it has no suggestions")
agf.Suggestions = function()
	error("broken")
end
check(#Entries() == 0, "an error in Adventure Guide shows nothing")
check(caught[#caught] == "Adventure Guide suggestions", "and is reported, not swallowed")
agf.Suggestions = function()
	return {
		{ id = 3, title = "bad" },
		{ id = "a", title = "A", level = 0 / 0 },
		{ id = "b", title = "B", level = 12.5 },
		{ id = "c", title = "C", level = 20 },
		{ id = "d", title = "D" },
	}
end
entries = Entries()
check(#entries == 4, "a malformed card is skipped without using up a row")
check(entries[2].text == "A" and entries[3].text == "B", "a level that isn't a whole number isn't shown")
check(entries[4].text == "[20] C", "three rows at most")
agf.StartSuggestion = function()
	return false
end
entries[2].fn()
check(
	printed[#printed] == "Adventure Guide couldn't start that just now. Choose it again from its guide.",
	"a start Adventure Guide refuses says so"
)
local said = #printed
agf.StartSuggestion = function()
	error("broken")
end
entries[2].fn()
check(caught[#caught] == "Adventure Guide start" and #printed == said, "an error starting one is reported")
env.AdventureGuideForever = { API = { CurrentStop = noop } }
check(#Entries() == 0, "an older Adventure Guide without Suggestions shows nothing, and no hint")
env.AdventureGuideForever = nil
check(#Entries() == 0, "on but with no API at all: nothing")
installed.AdventureGuideForever = "off"
entries = Entries()
check(#entries == 0, "switched off (so not loaded): neither suggestions nor the hint")
installed.AdventureGuideForever = nil
env.AdventureGuideForever = nil
entries = Entries()
check(#entries == 1 and entries[1].text:find("Adventure Guide Forever", 1, true), "missing: the grey hint again")

print(("family_hints_spec: %d checks passed"):format(checks))

-- Issue #718: with Kaliel's Tracker installed the client's MENU_QUEST_OBJECTIVE_TRACKER menu never opens, because its
-- own tracker draws the quest list and builds the right-click menu itself (Core/Modules/Tracker/Quests.lua). Every
-- quest menu it builds ends with KT:SendSignal("CONTEXT_MENU_UPDATE", info, "quest", questID); Core/KalielsTracker.lua
-- takes that signal from the client's EventRegistry and adds the same Plan journey entry there.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env

-- The client's EventRegistry, where Kaliel's Tracker's embedded MSA-Event-1.0 publishes its signal.
local signal, owner
env.EventRegistry = {
	RegisterCallback = function(_, name, fn, from)
		if name == "!KalielsTracker.CONTEXT_MENU_UPDATE" then
			signal, owner = fn, from
		end
	end,
}
-- Which optional addons the client has loaded, and a timer that runs as soon as the client's would.
local loaded = {}
env.C_AddOns = {
	IsAddOnLoaded = function(folder)
		return loaded[folder] == true
	end,
}
env.C_Timer = {
	After = function(_, fn)
		fn()
	end,
}

-- MSA-DropDownMenu-1.0, as it builds the open menu: the entries and separators Kaliel's quest menu receives.
local buttons, separators = {}, 0
env.MSA_DROPDOWNMENU_MENU_LEVEL = 1
env.MSA_DropDownMenu_CreateInfo = function()
	return {}
end
env.MSA_DropDownMenu_AddButton = function(info, level)
	buttons[#buttons + 1] = {
		text = info.text,
		title = info.isTitle == true,
		func = info.func,
		notCheckable = info.notCheckable == true,
		level = level,
	}
end
env.MSA_DropDownMenu_AddSeparator = function()
	separators = separators + 1
end

-- The one quest the planner can locate, and the client data PlanQuest reads for it.
local locatable = 4242
local planned = ns.Planner.QuestDestination
ns.Planner.QuestDestination = function(questID)
	return questID == locatable and { uiMapID = 1440, x = 0.5, y = 0.5, label = "Objective" } or nil
end
env.GetQuestUiMapID = function()
	return 1440
end
env.C_QuestLog = {
	GetNextWaypoint = function()
		return 1440, 0.5, 0.5
	end,
	GetQuestsOnMap = function()
		return {}
	end,
	GetTitleForQuestID = function()
		return "Quest"
	end,
	IsComplete = function()
		return false
	end,
}
-- UI/FamilyHints.lua is not loaded here; its own suggestions go through the same menu description.
ns.FamilyHints = {
	AddQuestMenu = function(root)
		root:CreateTitle("Adventure Guide suggests")
		root:CreateButton("Suggestion", function() end)
	end,
}
local destination
ns.StartJourney = function(point)
	destination = point
end

-- The frame Core/KalielsTracker.lua makes to wait for the addons it follows.
local watcher
local create = env.CreateFrame
env.CreateFrame = function(...)
	local frame = create(...)
	watcher = frame
	return frame
end

driver.load("Core/KalielsTracker.lua")
assert(watcher and watcher.OnEvent, "the addon waits for login and for Kaliel's Tracker to load")
assert(signal == nil, "nothing is taken before the client has loaded the addons")

-- Loaded while the client is still logging in, its own enable and signal registration run at login, so nothing is
-- taken before then; an unrelated addon's load takes nothing either.
watcher:OnEvent("ADDON_LOADED", "!KalielsTracker")
watcher:OnEvent("ADDON_LOADED", "SomeOtherAddon")
assert(signal == nil, "nothing is taken while the client is still loading")

-- Without Kaliel's Tracker, login takes no signal, and neither does its name turning up without it.
watcher:OnEvent("PLAYER_LOGIN")
watcher:OnEvent("ADDON_LOADED", "!KalielsTracker")
assert(signal == nil, "a client without Kaliel's Tracker gets no menu callback")

-- Loaded later than login, its own enable and signal registration run from its ADDON_LOADED, a frame before ours.
loaded["!KalielsTracker"] = true
watcher:OnEvent("ADDON_LOADED", "!KalielsTracker")
assert(signal, "Kaliel's Tracker's quest menu signal is taken")
assert(owner == ns, "the callback belongs to this addon")

-- A quest menu as Kaliel's builds it: its own title and entries, then the signal with the quest.
local function KalielsMenu(kind, questID)
	local info = { notCheckable = true, isNotRadio = true }
	signal(ns, info, kind, questID)
	return info
end

buttons, separators = {}, 0
local info = KalielsMenu("quest", locatable)
assert(separators == 1, "the addon's entries join the menu after one separator")
assert(buttons[1] and buttons[1].text == "Plan journey", "the quest menu offers Plan journey")
assert(not buttons[1].title and buttons[1].notCheckable, "it is an ordinary, uncheckable entry")
assert(buttons[1].level == 1, "it is added to the open menu's level")
assert(buttons[2] and buttons[2].text == "Adventure Guide suggests" and buttons[2].title, "titles pass through")
assert(buttons[3] and buttons[3].text == "Suggestion" and buttons[3].func, "so do the family hints' entries")
assert(info.KTmenuExtended, "later extensions group after the same separator")
destination = nil
buttons[1].func()
assert(destination and destination.questID == locatable, "the entry plans the right-clicked quest")
assert(destination.label == "Objective", "the goal keeps the planner's label")

-- The quest log's list and the quest details send the same signal: the entry shows in each.
buttons, separators = {}, 0
KalielsMenu("quest", locatable)
assert(separators == 1 and buttons[1].text == "Plan journey", "another quest menu gets its own entry")

-- Another kind of menu, a quest menu with no quest, and journeys off: nothing is added at all.
buttons, separators = {}, 0
KalielsMenu("spell", locatable)
assert(#buttons == 0 and separators == 0, "a profession recipe's menu is left alone")
KalielsMenu("quest", nil)
assert(#buttons == 0 and separators == 0, "a menu with no quest is left alone")
ns.db.journey = false
KalielsMenu("quest", locatable)
assert(#buttons == 0 and separators == 0, "journeys off leaves the menu as Kaliel's made it")
ns.db.journey = true

-- A quest the planner cannot place still offers the entry, as the client's own menus do.
buttons, separators = {}, 0
KalielsMenu("quest", 7)
assert(buttons[1] and buttons[1].text == "Plan journey", "an unplaceable quest still offers the entry")

ns.Planner.QuestDestination = planned
print("kaliel's tracker ok")

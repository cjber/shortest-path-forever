---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Kaliel's Tracker (folder !KalielsTracker) replaces the objective tracker with its own frames and its own quest
-- menus, so the client's MENU_QUEST_OBJECTIVE_TRACKER menu never opens and Journey/JourneyInput.lua's entry in it never
-- shows. Right-clicking a quest in its list opens an MSA-DropDownMenu-1.0 dropdown built by
-- Core/Modules/Tracker/Quests.lua (Mainline/Modules/QuestLog.lua for the quest log's list, and the quest details too),
-- and every quest menu ends with KT:SendSignal("CONTEXT_MENU_UPDATE", info, "quest", questID), the callback its own
-- addon integrations extend (Core/Modules/Addons/BtWQuests.lua). The tracker keeps its addon table private, so the
-- signal is taken from the client's EventRegistry, where its embedded MSA-Event-1.0 publishes it under its addon name.
local ADDON = "!KalielsTracker"
local SIGNAL = ADDON .. ".CONTEXT_MENU_UPDATE"

-- One entry of the open dropdown, as Kaliel's Menu_AddTitle and Menu_AddButton add them
-- (Core/System/Subsystems/Menu.lua): its own info table, added to the level being built.
---@param text string
---@param onClick? fun()
---@param title? boolean
local function AddButton(text, onClick, title)
	local info = MSA_DropDownMenu_CreateInfo()
	info.text, info.isTitle, info.notCheckable = text, title, true
	info.func = onClick
	MSA_DropDownMenu_AddButton(info, MSA_DROPDOWNMENU_MENU_LEVEL)
end

-- The menu description Journey/JourneyInput.lua's ns.AddQuestMenuEntry fills, in the dropdown's own terms.
local MENU_ROOT = {
	---@param _ table
	---@param text string
	CreateTitle = function(_, text)
		AddButton(text, nil, true)
	end,
	---@param _ table
	---@param text string
	---@param onClick fun()
	CreateButton = function(_, text, onClick)
		AddButton(text, onClick, false)
	end,
}

---@param _ table the registry's owner, this namespace
---@param info SPFKalielsTrackerMenuInfo Kaliel's menu info, shared with its own extensions (KTmenuExtended groups
---them after one separator)
---@param kind string what the menu was opened for: a quest's, a profession recipe's
---@param questID number?
local function OnContextMenu(_, info, kind, questID)
	if kind ~= "quest" or not questID or not ns.db.journey then
		return
	end
	-- Kaliel's own extensions and BtWQuests group their entries after one separator; ours joins that group.
	if not info.KTmenuExtended then
		info.KTmenuExtended = true
		MSA_DropDownMenu_AddSeparator(MSA_DROPDOWNMENU_MENU_LEVEL)
	end
	ns.AddQuestMenuEntry(MENU_ROOT, questID)
end

local registered = false

-- With Kaliel's Tracker loaded, take its quest menus' signal. Without it, nothing is registered and no menu changes.
local function Register()
	if registered or not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(ADDON)) then
		return
	end
	registered = true
	EventRegistry:RegisterCallback(SIGNAL, OnContextMenu, ns)
end

ns.Init(function()
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_LOGIN")
	watcher:RegisterEvent("ADDON_LOADED")
	local loggedIn = false
	watcher:SetScript("OnEvent", function(_, event, name)
		if event == "PLAYER_LOGIN" then
			loggedIn = true
		elseif event ~= "ADDON_LOADED" or name ~= ADDON or not loggedIn then
			-- Loaded before login, Kaliel's Tracker is taken once login's own events have run.
			return
		end
		-- Kaliel's Tracker registers its own menu handlers from OnEnable, which the same event runs, so the signal is
		-- taken a frame later to follow them.
		C_Timer.After(0, Register)
	end)
end)

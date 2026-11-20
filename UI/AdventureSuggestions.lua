---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- With Adventure Guide on, its suggestions in the quest menus, under Plan journey.

-- At most this many Adventure Guide suggestions in a quest menu.
local SUGGESTIONS = 3

---@class SPFAdventureSuggestions
local Suggestions = {}
ns.AdventureSuggestions = Suggestions

-- With Adventure Guide loaded, its top suggestions (AdventureGuideForever.API.Suggestions, API minor 2), each started
-- as the guide's own Start does. Found by the functions, not a version. An answer other than a list of cards shows
-- nothing; an error shows nothing too, and goes to the error handler and /path report through ns.core.SafeCall.
---@param root table the menu description being built
---@param api SPFAdventureSuggestionsAPI
local function AddSuggestions(root, api)
	local ok, suggestions = ns.core.SafeCall("Adventure Guide suggestions", api.Suggestions, SUGGESTIONS)
	if not ok or type(suggestions) ~= "table" then
		return
	end
	local shown = 0
	for _, suggestion in ipairs(suggestions) do -- menu-scroll-ok: stops after SUGGESTIONS (3) entries
		if shown == SUGGESTIONS then
			break
		end
		if type(suggestion) == "table" and type(suggestion.id) == "string" and type(suggestion.title) == "string" then
			if shown == 0 then
				root:CreateTitle(L["Adventure Guide suggests"])
			end
			shown = shown + 1
			local id, level = suggestion.id, suggestion.level
			local whole = type(level) == "number" and level >= 1 and level <= 1000 and level % 1 == 0
			local text = whole and L["[%d] %s"]:format(level, suggestion.title) or suggestion.title
			root:CreateButton(text, function()
				local started, accepted = ns.core.SafeCall("Adventure Guide start", api.StartSuggestion, id)
				-- Its route changed since the menu opened, or RestedXP waits out combat.
				if started and not accepted then
					ns.Print(L["Adventure Guide couldn't start that just now. Choose it again from its guide."])
				end
			end)
		end
	end
end

-- Adventure Guide's API when it offers suggestions.
---@return SPFAdventureSuggestionsAPI?
local function SuggestionsAPI()
	local guide = AdventureGuideForever
	local api = type(guide) == "table" and guide.API or nil
	if type(api) == "table" and type(api.Suggestions) == "function" and type(api.StartSuggestion) == "function" then
		return api --[[@as SPFAdventureSuggestionsAPI]]
	end
end

-- The quest menus, under Plan journey: Adventure Guide's suggestions when it offers them.
---@param root table the menu description being built
function Suggestions.AddQuestMenu(root)
	local api = SuggestionsAPI()
	if api then
		AddSuggestions(root, api)
	end
end

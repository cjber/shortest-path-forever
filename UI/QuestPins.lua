---@class SPFNamespace
local ns = select(2, ...)

-- The game's own quest pins repeat a journey's stops (#472): QuestDataProvider's QuestPinTemplate draws a dark circle
-- with "..." or "?" for each quest on the map, and a stop that marks the same quest draws its number beside it. While
-- the stop is drawn, the game's pin goes; a quest no stop marks keeps its pin; and every pin hidden here comes back
-- when its stop is passed, the journey ends, or journey drawing is turned off. Pins are hidden one by one through
-- their own Hide: the questPOI CVar and the quest data provider stay as the player and other addons set them.

-- The map's quest pins this module has hidden, so only those are shown again: a pin another addon hid stays hidden.
---@type table<SPFMapPin, boolean>
local hidden = setmetatable({}, { __mode = "k" })
-- The providers this module hooked, once each, and whether the map is hooked for the providers it gains later.
---@type table<SPFMapProvider, boolean>
local hookedProviders = setmetatable({}, { __mode = "k" })
local hookedMap = false
-- The pin template the game's quest data provider draws, the exact thing its mixin defines: the same template this
-- module's own pass walks (EnumeratePinsByTemplate below).
local QUEST_PINS = "QuestPinTemplate"

-- The quests the drawn stops mark: the stops from the one being travelled to, as Route.lua draws them, and a lone
-- destination. A corpse run's goal marks no quest.
---@return table<number, boolean>
local function Marked()
	local marked = {}
	local goal = ns.JourneyGoal()
	if not (goal and ns.db and ns.db.journey and not goal.corpse) then
		return marked
	end
	---@param point SPFPoint?
	local function Add(point)
		if not point or point.corpse then
			return
		end
		if point.questID then
			marked[point.questID] = true
		end
		for _, questID in ipairs(point.questIDs or {}) do
			marked[questID] = true
		end
		-- A quest handed in at the stop has no objective area here: its pin is hidden all the same, so the game's "?"
		-- does not sit over the stop.
		for _, questID in ipairs(point.handins or {}) do
			marked[questID] = true
		end
	end
	local points, index = ns.JourneyStops()
	if points then
		for i = index or 1, #points do
			Add(points[i])
		end
	else
		Add(goal)
	end
	return marked
end

-- QuestDataProvider:RefreshAllData re-acquires every pin, so hiding again after it keeps the stops covered. The
-- provider's own refresh runs first and is never replaced; only the pins it just drew are looked at. Mixin copies the
-- mixin's functions into each provider before this addon loads (#483), so the mixin table is not on the path: every
-- live provider is hooked on its own.
---@param provider SPFMapProvider
local function HookProvider(provider)
	if hookedProviders[provider] or type(provider.GetPinTemplate) ~= "function" then
		return
	end
	-- The quest provider is the one carrying QuestDataProviderMixin:GetPinTemplate itself: Mixin copies function
	-- references, so a provider mixed from the quest mixin, directly or through another mixin, holds that exact
	-- function. Never call GetPinTemplate on an unknown provider to identify it: a vignette provider's reads its
	-- argument (#491).
	local questMixin = QuestDataProviderMixin
	if
		not (
			questMixin
			and provider.GetPinTemplate == questMixin.GetPinTemplate
			and type(provider.RefreshAllData) == "function"
		)
	then
		return
	end
	hookedProviders[provider] = true
	hooksecurefunc(provider, "RefreshAllData", function() -- taint-ok: post-hook only; the refresh runs first
		ns.RefreshQuestPins()
	end)
end

-- Every quest provider the map holds, and any it gains later (WorldMapFrame:AddDataProvider), each hooked once.
local function Hook()
	if hookedMap then
		return
	end
	local map = WorldMapFrame
	if not (map and map.dataProviders and type(map.AddDataProvider) == "function") then
		return
	end
	for provider in pairs(map.dataProviders) do
		HookProvider(provider)
	end
	hooksecurefunc(map, "AddDataProvider", function(_, provider) -- taint-ok: post-hook only; the map's add runs first
		HookProvider(provider)
	end)
	-- Only a completed hook disables the next attempt: a failure above leaves this false, so the next quest pin
	-- refresh tries again rather than leaving the game's pins over the stops for the session.
	hookedMap = true
end

-- One pass over the map's quest pins: hide the marked quests, bring back the pins this module hid before, and forget
-- the pins the provider has released (its pool already hid those).
function ns.RefreshQuestPins()
	Hook()
	local map = WorldMapFrame
	if not (map and map.EnumeratePinsByTemplate) then
		return
	end
	local marked = Marked()
	local seen = {}
	for pin in map:EnumeratePinsByTemplate(QUEST_PINS) do
		---@cast pin SPFQuestPin
		seen[pin] = true
		local questID = ns.QuestPinID(pin, map)
		if questID and marked[questID] then
			hidden[pin] = true
			pin:Hide()
		elseif hidden[pin] then
			hidden[pin] = nil
			pin:Show()
		end
	end
	for pin in pairs(hidden) do
		if not seen[pin] then
			hidden[pin] = nil
		end
	end
end

ns.Init(Hook)

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
local hooked = false

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
-- provider's own refresh runs first and is never replaced; only the pins it just drew are looked at.
local function Hook()
	if hooked or not QuestDataProviderMixin or type(QuestDataProviderMixin.RefreshAllData) ~= "function" then
		return
	end
	hooked = true
	local provider = QuestDataProviderMixin
	hooksecurefunc(provider, "RefreshAllData", function() -- taint-ok: provider data, refresh observed only
		ns.RefreshQuestPins()
	end)
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
	for pin in map:EnumeratePinsByTemplate("QuestPinTemplate") do
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

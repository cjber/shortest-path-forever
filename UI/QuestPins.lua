---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- The game's own quest pins repeat a journey's stops (#472): QuestDataProvider's QuestPinTemplate draws a dark circle
-- with "..." or "?" for each quest on the map, and a stop that marks the same quest draws its number beside it. While
-- the stop is drawn, the game's pin goes; a quest no stop marks keeps its pin; and every pin hidden here comes back
-- when its stop is passed, the journey ends, or journey drawing is turned off. Pins are hidden one by one through
-- their own Hide: the questPOI CVar and the quest data provider stay as the player and other addons set them.
--
-- This module never hooks or calls into a data provider (WFA-38, #486): whichever provider acquired a pin, its own
-- methods stay untouched, so pins are found only through the map's read-only pin enumeration. The provider re-acquires
-- every pin on its events and on the map changing, so a refresh of ours is deferred one frame after those to walk the
-- pins it has just drawn.

-- The map's quest pins this module has hidden, so only those are shown again: a pin another addon hid stays hidden.
---@type table<SPFMapPin, boolean>
local hidden = setmetatable({}, { __mode = "k" })
-- The pin template the game's quest data provider draws, the exact thing its mixin defines: the same template this
-- module's own pass walks (EnumeratePinsByTemplate below).
local QUEST_PINS = "QuestPinTemplate"
-- The events QuestDataProvider refreshes its pins on (Blizzard_SharedMapDataProviders/QuestDataProvider.lua), plus
-- SUPER_TRACKING_CHANGED, the event behind the Supertracking.OnChanged callback it registers. CVAR_UPDATE comes
-- through too, but only the questPOI setting redraws the pins.
local PROVIDER_EVENTS = {
	"QUEST_LOG_UPDATE",
	"QUEST_WATCH_LIST_CHANGED",
	"QUEST_POI_UPDATE",
	"SUPER_TRACKING_CHANGED",
	"CVAR_UPDATE",
}

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

-- One pass over the map's quest pins: hide the marked quests, bring back the pins this module hid before, and forget
-- the pins the provider has released (its pool already hid those).
function ns.RefreshQuestPins()
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

-- A provider's refresh runs first and re-acquires every pin; ours waits a frame so the walk sees the new pins. Many
-- events in one frame share one pass.
---@type boolean?
local refreshQueued
local function QueueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = nil
		ns.RefreshQuestPins()
	end)
end

ns.Init(function()
	local events = CreateFrame("Frame")
	for _, event in ipairs(PROVIDER_EVENTS) do
		events:RegisterEvent(event)
	end
	events:SetScript("OnEvent", function(_, event, cvar)
		if event == "CVAR_UPDATE" and cvar ~= "questPOI" then
			return
		end
		QueueRefresh()
	end)

	local map = WorldMapFrame
	if not map then
		return
	end
	-- The map re-acquires its quest pins when it opens and when its map changes: its own OnShow, and the
	-- MapCanvas.MapSet callback its scroll container triggers on every map change. The provider also refreshes for a
	-- focused quest, through its map's SetFocusedQuestID and ClearFocusedQuestID callbacks.
	if map.HookScript then
		map:HookScript("OnShow", QueueRefresh)
	end
	if EventRegistry then
		EventRegistry:RegisterCallback("MapCanvas.MapSet", QueueRefresh, ns)
	end
	if map.RegisterCallback then
		map:RegisterCallback("SetFocusedQuestID", QueueRefresh, ns)
		map:RegisterCallback("ClearFocusedQuestID", QueueRefresh, ns)
	end
end)

-- Run from the repository root: luajit tests/quest_pin_spec.lua
-- The game's own quest pins on the world map (#472): while a journey stop marks a quest, that quest's pin is hidden
-- and the pins for quests no stop marks stay; clearing the journey and a quest data provider's refresh bring every
-- pin back or hide the marked ones again.
local dir = arg[0]:match("^(.*)/") or "tests"

local probe = "tools/.cache/blizzard-ui/Interface/AddOns/Blizzard_SharedXML/Spinner.lua"
do
	local handle = io.open(probe)
	if handle then
		handle:close()
	else
		local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
		assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture for tests/quest_pin_spec.lua")
	end
end

local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

assert(loadstring(source .. [==[
-- The quest data provider's own pins: the fixture's map enumerates whatever a test puts here, as the provider's
-- RefreshAllData acquires a fresh pin for every quest on the map.
local function QuestPins(questIDs)
	local pins = {}
	for _, questID in ipairs(questIDs) do
		local pin = stubframe()
		pin.pinTemplate = "QuestPinTemplate"
		function pin.GetMap()
			return WorldMapFrame
		end
		function pin.GetQuestID()
			return questID
		end
		pins[#pins + 1] = pin
	end
	nativeActive.QuestPinTemplate = pins
	return pins
end

local refreshes = 0
QuestDataProviderMixin = {
	RefreshAllData = function()
		refreshes = refreshes + 1
		return QuestPins({ 101, 202, 303 })
	end,
}

setMapShown(true)
posX, posY, posMap, facing = 0, 0, 1, 0
mapID, zoom = 1414, 0
local pins = QuestPins({ 101, 202, 303 })
assert(not pins[1].hidden and not pins[2].hidden and not pins[3].hidden, "the game's pins start shown")

-- Two stops, each marking a quest; the third quest is no stop of ours.
assert(ShortestPathForever.API.NavigateRoute("Test", {
	{ map = 1414, x = 0.51, y = 0.5, title = "First", questID = 101 },
	{ map = 1414, x = 0.55, y = 0.5, title = "Second", questID = 202 },
}))
settle()
pins = nativeActive.QuestPinTemplate
assert(pins[1].hidden and pins[2].hidden, "the pins for the marked quests are hidden")
assert(not pins[3].hidden, "a quest no stop marks keeps its pin")

-- The first stop is passed: its pin comes back while the next stop's pin stays hidden.
local points = ns.JourneyStops()
assert(points and #points == 2, "the journey has both stops")
ns.JourneyChanged(points[2])
ns.SetJourneyRoute(points[2])
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden, "the passed stop's pin is restored")
assert(pins[2].hidden and not pins[3].hidden, "the stop still ahead keeps its pin hidden")

-- The quest data provider refreshes and acquires every pin again: the same rule applies to the new pins.
QuestDataProviderMixin.RefreshAllData()
assert(refreshes == 1, "the provider refresh ran")
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden, "an unmarked quest's refreshed pin shows")
assert(pins[2].hidden and not pins[3].hidden, "the refreshed pin for the stop ahead is hidden again")

-- The journey ends: every pin this module hid comes back.
assert(ShortestPathForever.API.Cancel("Test"))
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden and not pins[2].hidden and not pins[3].hidden, "clearing the journey restores every pin")
assert(ns.JourneyGoal() == nil, "the journey is gone")

print("quest pin spec: marked pins hidden, unmarked shown, restored on clear and after provider refresh")
]==]))()

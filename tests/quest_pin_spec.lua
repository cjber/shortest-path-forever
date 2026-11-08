-- Run from the repository root: luajit tests/quest_pin_spec.lua
-- The game's own quest pins on the world map (#472, #483, #484, #491): while a journey stop marks a quest, its pin is
-- hidden and the pins for quests no stop marks stay; clearing the journey, a quest data provider's own refresh and a
-- provider the map gains later bring every pin back or hide the marked ones again; a stop that only hands a quest in
-- hides its pin too; and a map provider whose GetPinTemplate needs an argument is never asked for one while hooking.
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

-- The quest data provider the client builds before this addon loads. Its mixin copies its functions into every
-- provider, as Mixin does, so a hook on the mixin table never runs for the live provider (#483).
local setup = [==[
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
-- Blizzard's quest data provider mixin, as its file writes it: the pin template it acquires and its refresh.
QuestDataProviderMixin = {
	GetPinTemplate = function()
		return "QuestPinTemplate"
	end,
	RefreshAllData = function()
		refreshes = refreshes + 1
		return QuestPins({ 101, 202, 303 })
	end,
}
local function NewProvider()
	return Mixin({}, QuestDataProviderMixin)
end
-- Another mixin in between still carries the quest mixin's own function, because Mixin copies references.
local QuestAliasMixin = CreateFromMixins(QuestDataProviderMixin)
local provider = Mixin({}, QuestAliasMixin)
WorldMapFrame.dataProviders[provider] = true

-- The map's vignette provider: its GetPinTemplate reads the vignette it would draw, so calling it with no argument
-- errors, as VignetteDataProviderMixin does (#491). The count shows whether the addon asked it anything at all.
local vignetteLookups = 0
local vignettes = {
	GetPinTemplate = function(_, vignetteInfo)
		vignetteLookups = vignetteLookups + 1
		return "VignettePinTemplate-" .. vignetteInfo.kind
	end,
	RefreshAllData = function() end,
}
WorldMapFrame.dataProviders[vignettes] = true
]==]
local fixture = source:gsub('fireEvent%("ADDON_LOADED", "ShortestPathForever"%)', function()
	return setup .. '\nfireEvent("ADDON_LOADED", "ShortestPathForever")'
end, 1)

assert(loadstring(fixture .. [==[
-- Hooking the map's providers must not call a provider's GetPinTemplate to identify it: the vignette provider's reads
-- its argument, and its error used to abort the hooking and leave the quest pins uncovered for the session.
assert(vignetteLookups == 0, "the vignette provider is not asked for a pin template while hooking")
assert(#errors == 0, "no provider's GetPinTemplate is called while hooking: " .. tostring(errors[1]))
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
assert(vignetteLookups == 0, "refreshing quest pins does not ask the vignette provider for a template")
assert(#errors == 0, "refreshing quest pins reports no error: " .. tostring(errors[1]))
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

-- The provider refreshes on its own instance, as the client's live providers do: it re-acquires every pin, and the
-- same rule applies to the new pins. A hook on the mixin table alone never runs here.
provider:RefreshAllData()
assert(refreshes == 1, "the provider's own refresh ran")
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden, "an unmarked quest's refreshed pin shows")
assert(pins[2].hidden and not pins[3].hidden, "the refreshed pin for the stop ahead is hidden again")

-- A stop that hands quest 303 in marks it without naming an objective area: its "?" pin goes too.
assert(ShortestPathForever.API.NavigateRoute("Test", {
	{ map = 1414, x = 0.57, y = 0.5, title = "Hand-in", handins = { 303 } },
}))
settle()
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden and not pins[2].hidden, "quests no stop marks keep their pins")
assert(pins[3].hidden, "a quest handed in at the stop has its pin hidden")

-- A quest provider the map gains after the addon loaded is hooked as it arrives, and its own refresh hides again.
local later = NewProvider()
testAddsProvider = true
WorldMapFrame:AddDataProvider(later)
testAddsProvider = false
later:RefreshAllData()
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden and not pins[2].hidden, "the late provider's unmarked pins show")
assert(pins[3].hidden, "the late provider's pin for the hand-in is hidden again")

-- The journey ends: every pin this module hid comes back.
assert(ShortestPathForever.API.Cancel("Test"))
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden and not pins[2].hidden and not pins[3].hidden, "clearing the journey restores every pin")
assert(ns.JourneyGoal() == nil, "the journey is gone")

print("quest pin spec: marked pins hidden, unmarked shown, restored on clear and after provider refreshes")
]==]))()

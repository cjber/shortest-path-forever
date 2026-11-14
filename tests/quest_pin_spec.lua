-- Run from the repository root: luajit tests/quest_pin_spec.lua
-- The game's own quest pins on the world map (#472, #486): while a journey stop marks a quest, its pin is hidden and
-- the pins for quests no stop marks stay; the quest provider's own refreshes (on its events, on the map changing and
-- on the map opening) hide the marked ones again at the end of the same frame, after its event handlers, never on a
-- timer (#783); a stop that only hands a quest in hides its pin too; and a map provider whose GetPinTemplate needs an
-- argument is never asked for one (#491, #494). No provider is hooked or called to find the pins. The switch that
-- hands the game's own markers back keeps every pin and quest area on the map and is on by default (#871).
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

-- The quest data provider the client builds before this addon loads, and a provider shaped like VignetteDataProvider,
-- whose GetPinTemplate takes its vignette and indexes it.
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
-- Its refresh comes from the client's events, as the live provider's does.
local questEvents = CreateFrame("Frame")
function provider:RegisterEvent(event)
	questEvents:RegisterEvent(event)
end
function provider:OnEvent(event)
	if event == "QUEST_LOG_UPDATE" or event == "SUPER_TRACKING_CHANGED" then
		self:RefreshAllData()
	end
end
questEvents:SetScript("OnEvent", function(_, event)
	provider:OnEvent(event)
end)
questEvents:RegisterEvent("QUEST_LOG_UPDATE")
questEvents:RegisterEvent("SUPER_TRACKING_CHANGED")

-- The map's vignette provider: its GetPinTemplate reads the vignette it would draw, so calling it with no argument
-- errors, as VignetteDataProviderMixin does (#491, #494). The count shows whether the addon asked it anything at all.
local vignetteLookups = 0
local vignettes = {
	GetPinTemplate = function(_, vignetteInfo)
		vignetteLookups = vignetteLookups + 1
		return "VignettePinTemplate-" .. vignetteInfo.kind
	end,
	RefreshAllData = noop,
}
WorldMapFrame.dataProviders[vignettes] = true
]==]
local fixture = source:gsub('fireEvent%("ADDON_LOADED", "ShortestPathForever"%)', function()
	return setup .. '\nfireEvent("ADDON_LOADED", "ShortestPathForever")'
end, 1)

assert(loadstring(fixture .. [==[
-- Loading and refreshing must never call a provider's GetPinTemplate: the vignette provider's reads its argument, and
-- calling it used to be the live error (#491, #494).
assert(vignetteLookups == 0, "the vignette provider is not asked for a pin template")
assert(#errors == 0, "loading reports no error: " .. tostring(errors[1]))
setMapShown(true)
runOnUpdate()
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

-- The provider refreshes on QUEST_LOG_UPDATE and re-acquires every pin; our own event frame walks the new pins at the
-- end of the same frame, never a provider method and never on a timer. (Planning the journey super-tracked no quest,
-- which refreshed it once already.)
refreshes = 0
fireEvent("QUEST_LOG_UPDATE")
assert(refreshes == 1, "the provider's own refresh ran on the quest log update")
pins = nativeActive.QuestPinTemplate
assert(not pins[2].hidden, "the provider's refreshed pin starts shown, before our pass")
runPending()
assert(not pins[2].hidden, "the pass is frame work, not a one-shot timer: a due timer still leaves the pin shown")
runOnUpdate()
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

-- Super-tracking a quest refreshes the provider too; our pass follows a frame later.
provider:RefreshAllData()
pins = nativeActive.QuestPinTemplate
assert(not pins[3].hidden, "the refreshed pin starts shown")
fireEvent("SUPER_TRACKING_CHANGED")
runOnUpdate()
pins = nativeActive.QuestPinTemplate
assert(pins[3].hidden, "the super-tracking refresh hides the hand-in's pin again")

-- Only the questPOI CVar redraws the pins; another CVar leaves the refreshed pins alone.
provider:RefreshAllData()
pins = nativeActive.QuestPinTemplate
assert(not pins[3].hidden, "the refreshed pin starts shown again")
fireEvent("CVAR_UPDATE", "notQuestPOI", "0")
runOnUpdate()
assert(not pins[3].hidden, "another CVar's change leaves the refreshed pins alone")
fireEvent("CVAR_UPDATE", "questPOI", "1")
runOnUpdate()
pins = nativeActive.QuestPinTemplate
assert(pins[3].hidden, "the questPOI setting's change hides the hand-in's pin again")

-- A quest provider the map gains after the addon loaded draws pins of its own; the next map change walks them.
local later = NewProvider()
testAddsProvider = true
WorldMapFrame:AddDataProvider(later)
testAddsProvider = false
later:RefreshAllData()
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden and not pins[2].hidden and not pins[3].hidden, "the late provider's pins start shown")
triggerEvent("MapCanvas.MapSet", 1414)
runOnUpdate()
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden and not pins[2].hidden, "unmarked quests keep their pins on a map change")
assert(pins[3].hidden, "the map change hides the hand-in's pin again")

-- Opening the map runs its OnShow, after which the pins are walked again.
provider:RefreshAllData()
assert(not nativeActive.QuestPinTemplate[3].hidden, "the refreshed pin starts shown before the map opens")
setMapShown(true)
runOnUpdate()
assert(nativeActive.QuestPinTemplate[3].hidden, "opening the map hides the hand-in's pin again")

-- A provider whose GetPinTemplate takes its vignette is never called, to identify the quest provider or otherwise.
assert(vignetteLookups == 0, "a provider's GetPinTemplate is never called")

-- A guide step that moves on at the same place changes the stop's quests in place; the map's quest pins follow at
-- once, without waiting for a quest-log event or an unrelated map refresh.
assert(ShortestPathForever.API.NavigateRoute("Test", {
	{ map = 1414, x = 0.57, y = 0.5, title = "Same place", questID = 101 },
}))
settle()
pins = nativeActive.QuestPinTemplate
assert(pins[1].hidden, "the stop's quest pin is hidden")
assert(ns.SetStopQuests("Test", 1, { 202 }))
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden, "the old quest's pin comes back at once")
assert(pins[2].hidden, "the new quest's pin is hidden at once")

-- The journey ends: every pin this module hid comes back.
assert(ShortestPathForever.API.Cancel("Test"))
pins = nativeActive.QuestPinTemplate
assert(not pins[1].hidden and not pins[2].hidden and not pins[3].hidden, "clearing the journey restores every pin")
assert(ns.JourneyGoal() == nil, "the journey is gone")

-- The switch that hands the game's own markers back (#871): on by default, so a journey still hides the quests its
-- stops carry as a lone questID, a questIDs list or a hand-in; off, nothing is marked and a pin hidden before comes
-- back at once from the settings row, with the same saved switch the world map's filter menu reads.
assert(ns.Defaults.hideQuestPins == true, "the game's quest markers hide at journey stops by default")
assert(ShortestPathForever.API.NavigateRoute("Test", {
	{ map = 1414, x = 0.53, y = 0.5, title = "Quests", questID = 101, questIDs = { 202 }, handins = { 303 } },
}))
settle()
pins = nativeActive.QuestPinTemplate
assert(pins[1].hidden and pins[2].hidden and pins[3].hidden, "on, every quest a stop carries keeps its pin hidden")
ns.SetOption("hideQuestPins", false)
pins = nativeActive.QuestPinTemplate
assert(ns.db.hideQuestPins == false, "the settings row saves the switch off")
assert(
	not pins[1].hidden and not pins[2].hidden and not pins[3].hidden,
	"off, the hidden pins come back at once, whatever quest a stop carries"
)
ns.SetOption("hideQuestPins", true)
pins = nativeActive.QuestPinTemplate
assert(ns.db.hideQuestPins == true, "the settings row saves the switch back on")
assert(pins[1].hidden and pins[2].hidden and pins[3].hidden, "on again, the journey's quest pins hide at once")
ns.SetOption("hideQuestPins", false)
pins = nativeActive.QuestPinTemplate
assert(ns.db.hideQuestPins == false and not pins[1].hidden, "off again, the game's markers stay beside the journey")
assert(ShortestPathForever.API.Cancel("Test"))

print("quest pin spec: marked pins hidden, unmarked shown, restored on clear and after provider refreshes")
]==]))()

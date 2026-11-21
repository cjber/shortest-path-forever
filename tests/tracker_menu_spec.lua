-- Exercise SPF's contract through the pinned Core host and its production menu descriptions.
local core = dofile("tests/forever_core.lua")
local directory = core.directory()
local harnessEnv = setmetatable({
	loadfile = function(path)
		return loadfile(directory .. "/" .. path)
	end,
}, { __index = _G })
local harness = setfenv(assert(loadfile(directory .. "/tests/tracker_host_harness.lua")), harnessEnv)()
local t = harness.new()
local env, shared = t.env, t.ns
local function noop() end
core.load(env, "ForeverCore", { "Core/SafeCall.lua" }, shared)
local messages, refused = {}, false
env.DEFAULT_CHAT_FRAME = {
	AddMessage = function(_, message)
		messages[#messages + 1] = message
	end,
}
local journey, corpse, guided = true, false, false
local guide, maps, cleared, hearth, resumes = 0, {}, 0, false, 0
local options = {}
shared.RegisterOpener("ShortestPathForever", function(where)
	if refused then
		return false, "Open the world map to see it."
	end
	maps[#maps + 1] = where
	return true
end, true)
local ns = {
	L = shared.L,
	core = {
		SafeCall = function(_, fn, ...)
			return pcall(fn, ...)
		end,
	},
	db = {},
	Init = function(fn)
		fn()
	end,
	Timetable = {
		OnChange = noop,
		Version = function()
			return 0
		end,
	},
	OnTravelTick = noop,
	NearestDock = noop,
	JourneyInfo = function()
		return journey or nil
	end,
	Corpse = {
		Active = function()
			return corpse
		end,
	},
	IsJourneyGuided = function()
		return guided
	end,
	ToggleJourneyGuide = function()
		guide = guide + 1
	end,
	ToggleHearthstone = function()
		hearth = not hearth
	end,
	HearthstoneEnabled = function()
		return hearth
	end,
	ResumeRestedXP = function()
		return false
	end,
	ResumeGuidelime = function()
		resumes = resumes + 1
		return true
	end,
	ResumeDugi = function()
		resumes = resumes + 1
		return true
	end,
	ClearJourney = function()
		cleared = cleared + 1
	end,
	DockLocation = function(id)
		return { uiMap = id }
	end,
	OpenWorldMap = function(id)
		maps[#maps + 1] = id
	end,
	SetOption = function(key, value)
		assert((key == "tracker" or key == "journeyTracker") and value == false)
		options[key] = value
	end,
}
local create = env.CreateFrame
local module
-- The harness's module supplies the native template methods and frames.
env.CreateFrame = function(kind, name, ...)
	if name == "ShortestPathForeverObjectiveTracker" then
		module = t.module(-3)
		module.SetHeader = noop
		return module
	end
	local frame = create(kind, name, ...)
	frame.SetSize = noop
	return frame
end
env.EventUtil.ContinueAfterAllEvents = function(fn)
	fn()
end
setfenv(assert(loadfile(directory .. "/UI/TrackerSection.lua")), env)("ForeverCore", shared)
env.ForeverCore = {
	TrackerHost = shared.TrackerHost,
	TrackerSection = shared.TrackerSection,
	TrackerLine = shared.TrackerLine,
	Open = shared.Open,
}
t.setCombat(true)
setfenv(assert(loadfile("UI/Tracker.lua")), env)("ShortestPathForever", ns)
t.setCombat(false)
t.drain()
assert(module.trackerMenu and not module.AddHeaderMenuEntries)
env.GuidelimeArrow, env.DugisGuideViewer = {}, { DugisArrow = {} }
local function menu(id)
	if id then
		module:OnBlockHeaderClick(
			{ id = id, HeaderText = {
				GetText = function()
					return "Block title"
				end,
			} },
			"RightButton"
		)
	else
		module.Header.scripts.OnMouseUp(module.Header, "RightButton")
	end
	return t.menus[#t.menus]
end
local function entry(root, text)
	for _, item in ipairs(root.entries) do
		if item.text == text then
			return item
		end
	end
end
local function order(root, expected)
	assert(root.title, "Core supplies Title before the entries")
	local labels = {}
	for _, item in ipairs(root.entries) do
		labels[#labels + 1] = item.text or item.kind
	end
	assert(table.concat(labels, ",") == expected, table.concat(labels, ","))
	local tracker = assert(entry(root, "Tracker"), "Core's Tracker submenu follows the entries")
	local locks = 0
	for _, item in ipairs(root.entries) do
		if item.text == "Lock the tracker" then
			locks = locks + 1
		end
	end
	for _, item in ipairs(tracker.entries) do
		if item.text == "Lock the tracker" then
			locks = locks + 1
		end
	end
	assert(locks == 1, "exactly one Lock the tracker entry")
	assert(not entry(root, "Attach to quest tracker"), "the attach entry is gone with core 1.15.0")
end
local expected = table.concat({
	"Guide me",
	"Use Hearthstone",
	"Resume RestedXP guide",
	"Resume Guidelime guide",
	"Resume Dugi guide",
	"Hide the journey tracker",
	"Show on map",
	"Clear journey",
	"divider",
	"Lock the tracker",
	"Tracker",
}, ",")
local block = menu("journey")
assert(block.title == "Block title")
order(block, expected)
order(menu(), expected)
entry(block, "Guide me").callback()
entry(block, "Use Hearthstone").callback()
assert(entry(block, "Use Hearthstone").kind == "checkbox" and entry(block, "Use Hearthstone").isSelected())
entry(block, "Resume Guidelime guide").callback()
entry(block, "Resume Dugi guide").callback()
for _, name in ipairs({ "RestedXP", "Guidelime", "Dugi" }) do
	ns["Resume" .. name] = function()
		return false
	end
	local accepted, reason = entry(block, "Resume " .. name .. " guide").callback()
	assert(accepted == false and reason == "That guide has no step to follow.", "an empty guide reports why")
end
assert(entry(block, "Show on map").callback() == true and maps[1] == "journey", "the journey menu calls Core's opener")
refused = true
local beforeRefusal = #messages
local accepted, reason = entry(block, "Show on map").callback()
assert(accepted == false and reason == "Open the world map to see it.")
assert(#messages == beforeRefusal + 1 and messages[#messages] == reason, "the menu reports a map refusal once")
refused = false
entry(block, "Clear journey").callback()
entry(block, "Hide the journey tracker").callback()
assert(options.journeyTracker == false, "the journey block turns its own tracker off")
assert(guide == 1 and resumes == 2 and maps[1] == "journey" and cleared == 1)
corpse = true
assert(not entry(menu("journey"), "Clear journey"), "corpse runs cannot be cleared")
corpse = false
module.dockID = 42
local section = menu()
order(section, expected:gsub("Show on map,", "Hide departures,Show on map,"))
entry(section, "Hide departures").callback()
assert(not entry(menu("journey"), "Hide departures"), "Hide departures is section-only")
module.dockID, module.riding = nil, 5
assert(entry(menu(), "Hide departures"), "riding also shows departures")
module.riding = nil
assert(not entry(menu(), "Hide departures"))
module.mapDock = 42
local dock = menu(42)
order(dock, "Show on map,divider,Lock the tracker,Tracker")
assert(entry(dock, "Show on map").callback() == true and maps[#maps] == 42, "the dock menu passes its map ID to Core")
module:OnBlockHeaderClick({ id = 42 }, "LeftButton")
assert(maps[#maps] == 42, "a dock block opens its map even alongside a journey")
module:OnBlockHeaderClick({ id = "journey" }, "LeftButton")
module.Header.scripts.OnMouseUp(module.Header, "LeftButton")
assert(guide == 3, "both journey titles toggle guidance")
local function hint(target, expectedHint)
	assert(module.trackerClickHint(target) == expectedHint)
end
hint({ kind = "block", id = "journey" }, "guide this journey")
guided = true
hint({ kind = "block", id = "journey" }, "stop guiding")
journey = true
hint({ kind = "section" }, "stop guiding")
guided = false
hint({ kind = "section" }, "guide this journey")
hint({ kind = "block", id = 42 }, "show it on the map")
journey, module.mapDock = false, 42
hint({ kind = "section" }, "show it on the map")
order(menu(), "Show on map,divider,Lock the tracker,Tracker")
module.Header.scripts.OnMouseUp(module.Header, "LeftButton")
assert(maps[#maps] == 42)
t.setCombat(true)
local beforeCombat = #messages
local mapCount = #maps
local combatOpen = entry(menu(42), "Show on map")
assert(combatOpen:IsEnabled(), "the named action stays available to explain a refusal")
for _, action in ipairs({ entry(block, "Show on map"), combatOpen }) do
	local combatAccepted, combatReason = action.callback()
	assert(combatAccepted == false and combatReason == "Unavailable in combat")
end
assert(#maps == mapCount, "combat never reaches the opener")
assert(#messages == beforeCombat + 2, "Core reports combat once per click")
assert(messages[beforeCombat + 1] == "Unavailable in combat" and messages[#messages] == "Unavailable in combat")
print("tracker_menu_spec: contract menus and clicks passed")

-- Layout the same line the tracker makes for a proved transport step.
env.ForeverCore.ContextMenu = shared.ContextMenu
env.OBJECTIVE_TRACKER_COLOR = { Normal = {}, NormalHighlight = {} }
env.RED_FONT_COLOR = {}
local line = {
	SetScript = function(self, _, callback)
		self.click = callback
	end,
}
local setInteractive = env.ForeverCore.TrackerLine.SetInteractive
env.ForeverCore.TrackerLine.SetInteractive = noop
local rowBlock = {
	id = "journey",
	HeaderText = {
		GetHeight = function()
			return 12
		end,
		GetText = function()
			return "Journey"
		end,
	},
	SetHeader = noop,
	AddObjective = function()
		return line
	end,
}
module.GetBlock = function()
	return rowBlock
end
module.LayoutBlock = function()
	return true
end
local boat = { mode = "boat", route = 9 }
local plan = { legs = { boat } }
ns.JourneyInfo = function()
	return "Journey", module.blocks[1].rows, plan, 1
end
local entryToAvoid = { kind = "boat", ids = { 9 }, name = "Test boat" }
local avoided
ns.AvoidJourneyTransport = function(leg)
	assert(leg == boat)
	avoided = entryToAvoid
end
ns.UndoAvoidedTransport = function(saved)
	assert(saved == avoided)
	avoided = nil
end
local boarded = false
ns.AvoidTransport = {
	Allowed = function(leg)
		return not (boarded and leg == boat)
	end,
}
module.blocks = { { key = "journey", title = "Journey", rows = { { key = 1, text = "Boat" } } } }
module:LayoutContents()
line.click(line, "RightButton")
local avoid = assert(entry(t.menus[#t.menus], "Avoid this boat"), "the transport row offers Avoid this boat")
local tooltipText
local tooltip = {
	AddLine = function(_, text)
		tooltipText = text
	end,
}
avoid.tooltip(tooltip)
assert(tooltipText:find("new route", 1, true) and tooltipText:find("Settings", 1, true))
avoid.callback()
assert(avoided == entryToAvoid)
avoided = nil

-- Once boarded, the ride cannot be avoided: the row opens the journey's own menu.
boarded = true
local menusBefore = #t.menus
line.click(line, "RightButton")
assert(
	#t.menus == menusBefore or not entry(t.menus[#t.menus], "Avoid this boat"),
	"the boarded step offers no Avoid this boat"
)
boarded = false
avoided = entryToAvoid

plan = nil
module.blocks[1].rows =
	{ { key = "avoided-transport", text = "No route remains without Test boat", undoAvoid = avoided } }
module:LayoutContents()
line.click(line, "RightButton")
local undo = assert(entry(t.menus[#t.menus], "Undo"), "the no-route row offers Undo")
undo.tooltip(tooltip)
assert(tooltipText:find("again", 1, true) and tooltipText:find("new route", 1, true))
undo.callback()
assert(not avoided)
ns.JourneyInfo = function()
	return journey or nil
end

env.ForeverCore.TrackerLine.SetInteractive = setInteractive

-- Reload Core against the existing column, just as another addon or an earlier UI boot leaves it.
t.setCombat(false)
env.ForeverTrackerHost = shared.TrackerHost
setfenv(assert(loadfile(directory .. "/UI/TrackerHost.lua")), env)("ForeverCore", shared)
assert(shared.TrackerHostForeign and not shared.TrackerHost.HandleBlockHeaderClick)
env.ForeverCore.TrackerHost = shared.TrackerHost
env.ForeverCore.ContextMenu = shared.ContextMenu
env.ForeverCore.APIKit = { Hub = noop, NotReady = noop }
env.ForeverCore.Art = { Marker = noop, Diamond = noop }
env.ForeverCore.QuestLogTabs = { SetTabShown = noop }
env.C_AddOns = { GetAddOnMetadata = noop }
ns.ForeverRequire = function(ready)
	assert(ready, "the addon loads with a foreign host")
end
setfenv(assert(loadfile("Core/Require.lua")), env)("ShortestPathForever", ns)
t.setCombat(true)
setfenv(assert(loadfile("UI/Tracker.lua")), env)("ShortestPathForever", ns)
t.setCombat(false)
t.drain()
journey, corpse = true, false
local foreign = menu("journey")
local labels = {}
for _, item in ipairs(foreign.entries) do
	labels[#labels + 1] = item.text
end
local foreignOrder = expected:gsub(",divider,Lock the tracker,Tracker$", "")
assert(table.concat(labels, ",") == foreignOrder, "foreign menus preserve slot order")
local previousGuide, previousCleared = guide, cleared
assert(entry(foreign, "Show on map").callback() == true and maps[#maps] == "journey", "foreign menus use Core too")
entry(foreign, "Guide me").callback()
entry(foreign, "Clear journey").callback()
module:OnBlockHeaderClick({ id = "journey" }, "LeftButton")
module:OnHeaderClick("LeftButton")
assert(guide == previousGuide + 3 and cleared == previousCleared + 1)
assert(not module.trackerMenu, "the foreign Attach wrapper drops the contract")
print("tracker_menu_spec: foreign host loads and keeps journey clicks")

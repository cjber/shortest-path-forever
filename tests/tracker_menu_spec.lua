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
local journey, corpse, guided = true, false, false
local guide, maps, cleared, hearth, resumes = 0, {}, 0, false, 0
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
	ShowJourneyMap = function()
		maps[#maps + 1] = "journey"
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
		assert(key == "tracker" and value == false)
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
env.ForeverCore =
	{ TrackerHost = shared.TrackerHost, TrackerSection = shared.TrackerSection, TrackerLine = shared.TrackerLine }
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
	"Show on map",
	"Clear journey",
	"divider",
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
entry(block, "Show on map").callback()
entry(block, "Clear journey").callback()
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
order(menu(42), "Show on map,divider,Tracker")
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
order(menu(), "Show on map,divider,Tracker")
module.Header.scripts.OnMouseUp(module.Header, "LeftButton")
assert(maps[#maps] == 42)
t.setCombat(true)
assert(not entry(menu(42), "Show on map"):IsEnabled(), "Open is disabled in combat")
assert(entry(block, "Show on map").callback() == false, "an already open menu also refuses combat")
print("tracker_menu_spec: contract menus and clicks passed")

-- Reload Core against the existing column, just as another addon or an earlier UI boot leaves it.
t.setCombat(false)
env.ForeverTrackerHost = shared.TrackerHost
setfenv(assert(loadfile(directory .. "/UI/TrackerHost.lua")), env)("ForeverCore", shared)
assert(shared.TrackerHostForeign and not shared.TrackerHost.HandleBlockHeaderClick)
env.ForeverCore.TrackerHost = shared.TrackerHost
env.ForeverCore.ContextMenu = shared.ContextMenu
env.ForeverCore.APIKit = { Hub = noop, NotReady = noop }
env.ForeverCore.Art = { Marker = noop, Diamond = noop }
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
assert(table.concat(labels, ",") == expected:gsub(",divider,Tracker$", ""), "foreign menus preserve slot order")
local previousGuide, previousCleared = guide, cleared
entry(foreign, "Guide me").callback()
entry(foreign, "Clear journey").callback()
module:OnBlockHeaderClick({ id = "journey" }, "LeftButton")
module:OnHeaderClick("LeftButton")
assert(guide == previousGuide + 3 and cleared == previousCleared + 1)
assert(not module.trackerMenu, "the foreign Attach wrapper drops the contract")
print("tracker_menu_spec: foreign host loads and keeps journey clicks")

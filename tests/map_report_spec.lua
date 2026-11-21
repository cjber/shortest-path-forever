local ns = { charDB = { mapReportMarks = {} }, db = {} }
local function Constant(value)
	return function()
		return value
	end
end

local mapID, goal, plan, origin = 1440
local map = {
	GetMapID = function()
		return mapID
	end,
}
local menu, report, watch, mixin
local drawn = {}
local pool = {
	Acquire = function(_, mark)
		drawn[#drawn + 1] = mark
	end,
	ReleaseAll = function()
		drawn = {}
	end,
}
local world = { map = 1, x = 1.123456789012345, y = -20 }
local tooltip = {
	IsForbidden = Constant(false),
	SetOwner = function(self, owner)
		self.owner = owner
	end,
	Show = function() end,
}

local env = setmetatable({
	C_AddOns = { GetAddOnMetadata = Constant("test-version") },
	GetBuildInfo = function()
		return "1.60.1", "70938"
	end,
	C_Map = { GetMapInfo = Constant({ name = "Kalimdor" }) },
	WorldMapFrame = map,
	CreateFromMixins = Constant({}),
	GameTooltip = tooltip,
	GameTooltip_SetTitle = function(tip, text)
		tip.title = text
	end,
	GameTooltip_AddInstructionLine = function(tip, text)
		tip.instruction = text
	end,
	GameTooltip_AddNormalLine = function(tip, text)
		tip.help = text
	end,
	UnitFactionGroup = Constant("Alliance"),
	UnitClass = function()
		return "Mage", "MAGE"
	end,
	GetUnitSpeed = function()
		return 0, 7
	end,
	canaccessvalue = Constant(true),
}, { __index = _G })
local function Load(file)
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end
Load("Core/Report.lua")
assert(type(ns.MapReportText) == "function", "the addon provides copyable road and wall report text")

local shared = dofile("tests/forever_core.lua").load(env, "ForeverCore", {
	"Core/SafeCall.lua",
	"Core/Log.lua",
	"UI/ContextMenu.lua",
	"UI/Report.lua",
})
ns.core = { Report = shared.ReportFor("ShortestPathForever") }
ns.core.Report.Show = function(value)
	report = value
end
env.ForeverCore = {
	ContextMenu = function(owner, generator)
		assert(owner == map)
		menu = shared.NewMenuDescription("root")
		generator(owner, menu)
	end,
}
ns.Locate = function(point)
	if point == world then
		return { zone = "Ashenvale", uiMap = 1440, x = 0.08, y = 0.09 }
	end
end
ns.JourneyGoal = function()
	return goal
end
ns.JourneyPlan = function()
	return plan
end
ns.JourneySearch = {
	Origin = function()
		return origin
	end,
}
ns.JourneyKeyName = Constant("Alt")
ns.NowMs = Constant(100)
ns.UsableTeleports = function() end
ns.KnownTaxiNodes = Constant({})
ns.Timetable = { Anchors = Constant({}) }
ns.Init = function(fn)
	fn()
end
ns.Canvas = {
	PinMixin = {},
	Pool = function(_, _, pin)
		mixin = pin
		return pool
	end,
	Watch = function(_, callback)
		watch = callback
	end,
}
local canMark = true
ns.WorldPoint = function()
	return canMark and world or nil
end

Load("Locales/enUS.lua")
Load("UI/MapReport.lua")
Load("Core/PlanContext.lua")
local from, to = { map = 0, x = 4, y = 5, z = 6 }, { map = 1, x = 7, y = 8 }
local baseline = ns.PlanContext.Options(from, to)
local function Open(x, y)
	assert(ns.OpenMapReportMenu(map, mapID, x, y))
	for _, entry in ipairs(menu.entries) do
		local tip = {}
		assert(entry.tooltip, entry.text .. " needs a tooltip")
		entry.tooltip(tip)
		assert(tip.help and #tip.help > 0)
	end
	return menu.entries
end
local entries = Open(0.25, 0.75)
assert(#entries == 2 and entries[1].text == "Mark: road missing here" and entries[2].text == "Mark: wall here")
assert(entries[1]:IsEnabled() and entries[2]:IsEnabled())
entries[1].onClick()
local marks = ns.charDB.mapReportMarks
assert(#marks == 1 and marks[1].map == 1440 and marks[1].world == world and drawn[1] == marks[1])
assert(marks[1].kind == "road" and marks[1].x == 0.25 and marks[1].y == 0.75)
mixin.OnMouseEnter({ mark = marks[1] })
assert(tooltip.title == "Mark: road missing here" and tooltip.instruction:find("Alt%-right%-click"))
assert(mixin:ShouldMouseButtonBePassthrough("RightButton"), "hovering a mark still lets the map handle right-click")

mapID = 1414
watch({ mapID = mapID }, "map")
assert(#drawn == 0, "marks are only drawn on their own map")
canMark = false
entries = Open(0.2, 0.3)
assert(not entries[1]:IsEnabled() and not entries[2]:IsEnabled())
assert(#entries == 4, "existing marks can still be copied or cleared")
entries[3].onClick()
local header = "ShortestPathForever test-version | WoW 1.60.1 (70938) | Road and wall report"
local line = "road | map 1440 25.0, 75.0 | map 1 x 1.123456789012345 y -20 z unknown | Ashenvale"
assert(report == header .. "\n" .. line, report)
goal, plan = to, { legs = { { from = from } } }
entries[3].onClick()
local journey = "\nJourney start: map 0 x 4 y 5 z 6\nJourney goal: map 1 x 7 y 8 z unknown\n"
assert(report == header .. journey .. line, report)
plan, origin = nil, from
assert(ns.MapReportText(marks) == header .. journey .. line, "an unsettled journey uses its search origin")

mapID, canMark = 1440, true
for i = 1, 21 do
	Open(i / 100, 0.9)[2].onClick()
end
assert(#marks == 20 and marks[1].x == 0.02 and marks[20].x == 0.21, "the newest 20 marks survive in order")
assert(#drawn == 20 and drawn[20].kind == "wall")
watch({ mapID = mapID }, "show")
assert(#drawn == 20, "reopening the map redraws saved marks")

local options = ns.PlanContext.Options(from, to)
for key in pairs(options) do
	assert(baseline[key] ~= nil, "marks added a planner option: " .. key)
end
for key, value in pairs(baseline) do
	assert(options[key] == value, "marks changed a planner option: " .. key)
end
Open(0.5, 0.5)[4].onClick()
assert(#marks == 0 and #drawn == 0 and #Open(0.5, 0.5) == 2)
print("map report: menu help, persistence list, cap, map visibility, report, planner isolation, and clear ok")

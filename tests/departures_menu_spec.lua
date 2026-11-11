-- Right-clicking the section header while departures show offers to hide them through the module's
-- AddHeaderMenuEntries hook, below the shared column's own attach and lock entries.
local core = dofile("tests/forever_core.lua")
local noop = function() end
local entries = {}
local owner = {}
local ns = {
	db = { tracker = true },
	core = {
		SafeCall = function(_, fn, ...)
			return fn(...)
		end,
	},
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
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
	RefreshTracker = noop,
	SetOption = function(key, value)
		entries.option = { key = key, value = value }
	end,
}
local modules = {}
local env = setmetatable({
	ObjectiveTrackerFrame = {},
	ObjectiveTrackerManager = {},
	CreateFrame = function(_, name)
		local frame = {
			SetSize = noop,
			Hide = noop,
			SetHeader = noop,
			SetScript = noop,
			EnableMouse = noop,
			Header = { EnableMouse = noop, SetScript = noop },
		}
		if name then
			modules[#modules + 1] = frame
		end
		return frame
	end,
	Mixin = function(target, source)
		for key, value in pairs(source) do
			target[key] = value
		end
	end,
	EventUtil = { ContinueAfterAllEvents = noop },
	C_Timer = { After = noop },
	hooksecurefunc = noop,
	InCombatLockdown = function()
		return true
	end,
	ForeverCore = {
		TrackerHost = { Attach = noop },
		ContextMenu = function(_, generator)
			generator(owner, { CreateButton = noop, CreateCheckbox = noop })
		end,
	},
}, { __index = _G })
ns.TrackerHost = env.ForeverCore.TrackerHost
setfenv(assert(loadfile(core.directory() .. "/UI/TrackerSection.lua")), env)("ForeverCore", ns)
env.ForeverCore.TrackerSection, env.ForeverCore.TrackerLine = ns.TrackerSection, ns.TrackerLine
setfenv(assert(loadfile("UI/Tracker.lua")), env)("ShortestPathForever", ns)

local module = modules[1]
assert(module, "the tracker module is made")
module.GetContextMenuParent = function()
	return owner
end
local function Open()
	entries = {}
	module:AddHeaderMenuEntries({
		CreateButton = function(_, text, click)
			entries[text] = { click = click }
		end,
	})
	return entries
end

module.dockID = 1
local menu = Open()
assert(menu["Hide departures"], "a departures section offers to hide them")
menu["Hide departures"].click()
assert(entries.option and entries.option.key == "tracker" and entries.option.value == false, "it turns departures off")

module.dockID, module.riding = nil, 1
assert(Open()["Hide departures"], "riding a boat or lift is departures too")
module.riding = nil
assert(Open()["Hide departures"] == nil, "a section with no departures has no such entry")

print("departures_menu_spec: ok")

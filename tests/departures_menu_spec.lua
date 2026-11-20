-- The section contract offers Hide departures only while departures show.
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
	JourneyInfo = noop,
	SetOption = function(key, value)
		entries.option = { key = key, value = value }
	end,
}
local modules = {}
local contract
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
	EventUtil = {
		ContinueAfterAllEvents = function(fn)
			fn()
		end,
	},
	C_Timer = {
		After = function(delay, fn)
			if delay == 0 then
				fn()
			end
		end,
	},
	hooksecurefunc = noop,
	InCombatLockdown = function()
		return true
	end,
	ForeverCore = {
		TrackerHost = {
			Attach = function(_, _, value)
				contract = value
			end,
		},
		ContextMenu = function(_, generator)
			generator(owner, { CreateButton = noop, CreateCheckbox = noop })
		end,
	},
}, { __index = _G })
ns.TrackerHost = env.ForeverCore.TrackerHost
-- Core's tracker host waits for the world and saved variables before a section attaches; the stand-in host here
-- waits on the same two events.
ns.AfterWorldEvents = function(callback)
	env.EventUtil.ContinueAfterAllEvents(callback, "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED")
end
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
	contract.menu({ kind = "section", module = module }, {
		Open = noop,
		Action = function(_, text, click)
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
module.riding = false
assert(Open()["Hide departures"] == nil, "disabled departures do not count as an active ride")

print("departures_menu_spec: ok")

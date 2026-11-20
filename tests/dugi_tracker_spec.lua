-- The tracker offers *Resume Dugi guide* only when Dugi's viewer publishes its arrow module. Dugi declares the module
-- as a file local and exports `DugisArrowGlobal`; the only field it publishes is `DugisGuideViewer.DugisArrow`, set in
-- the module's Initialize. A gate on a global `DugisArrow` would never open.
local core = dofile("tests/forever_core.lua")
local noop = function() end
local entries, resumed = {}, 0
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
	Corpse = { Active = function() end },
	ResumeDugi = function()
		resumed = resumed + 1
	end,
	SetOption = noop,
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
			generator(owner, {
				CreateButton = function(_, text, click)
					entries[text] = { click = click }
				end,
				CreateCheckbox = noop,
			})
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
	contract.menu({ kind = "block", id = "journey", module = module }, {
		Primary = noop,
		Action = function(_, text, click)
			local entry = { click = click }
			entries[text] = entry
			return entry
		end,
		Open = noop,
		End = noop,
	})
	return entries
end

env.DugisGuideViewer = { DugisArrow = {} }
local menu = Open()
assert(menu["Resume Dugi guide"], "the viewer's published arrow offers Resume Dugi guide")
menu["Resume Dugi guide"].click()
assert(resumed == 1, "and the entry resumes Dugi")

env.DugisGuideViewer = nil
assert(Open()["Resume Dugi guide"] == nil, "no viewer, no Resume Dugi guide")

-- A bare global is not Dugi's published field; the module is a file local in Dugi's source, with only the
-- pre-Initialize alias `DugisArrowGlobal` exported. The initialized module is the viewer field.
env.DugisArrow = {}
assert(Open()["Resume Dugi guide"] == nil, "the nonexistent global is not a gate")
env.DugisArrowGlobal = {}
assert(Open()["Resume Dugi guide"] == nil, "the pre-Initialize alias is not the viewer's published field")

print("dugi_tracker: ok")

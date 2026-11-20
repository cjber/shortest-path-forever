-- Initialization must tolerate either native event order and an addon loaded after login. The section itself is
-- ForeverCore's TrackerSection, loaded from the checkout the specs use.
local core = dofile("tests/forever_core.lua")
local coreDirectory = core.directory()
local checks = 0
local function noop() end
for _, readyAtLoad in ipairs({ false, true }) do
	local callbacks, timers, modules, owners = {}, {}, {}, {}
	local native = {}
	local function region()
		return {
			SetSize = noop,
			Hide = noop,
			SetHeader = noop,
			SetScript = noop,
			EnableMouse = noop,
			Header = { EnableMouse = noop, SetScript = noop },
		}
	end
	local env = setmetatable({
		ObjectiveTrackerFrame = native,
		ObjectiveTrackerManager = setmetatable({}, {
			__index = function()
				error("must not register with native manager")
			end,
		}),
		CreateFrame = function(_, name)
			local frame = region()
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
			ContinueAfterAllEvents = function(fn, first, second)
				assert(first == "PLAYER_ENTERING_WORLD" and second == "VARIABLES_LOADED")
				if readyAtLoad then
					fn()
				else
					callbacks[#callbacks + 1] = fn
				end
			end,
		},
		C_Timer = {
			After = function(delay, fn)
				if delay == 0 then
					timers[#timers + 1] = fn
				end
			end,
		},
		hooksecurefunc = function()
			error("native methods must stay unhooked")
		end,
		InCombatLockdown = function()
			return true
		end,
	}, { __index = _G })
	local host = {
		Attach = function(frame, _, contract)
			frame.trackerMenu, frame.trackerClick, frame.trackerClickHint =
				contract.menu, contract.click, contract.clickHint
			owners[frame] = native
		end,
	}
	local ns = {
		core = {
			SafeCall = function(_, fn, ...)
				return fn(...)
			end,
		},
		db = { trackerHost = { scale = 0.8 }, trackerHeight = 999 },
		TrackerHost = host,
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
	}
	-- The real section API, as ForeverCore publishes it in 1.2.0.
	-- Core's tracker host waits for the world and saved variables before a section attaches; the stand-in host here
	-- waits on the same two events.
	ns.AfterWorldEvents = function(callback)
		env.EventUtil.ContinueAfterAllEvents(callback, "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED")
	end
	setfenv(assert(loadfile(coreDirectory .. "/UI/TrackerSection.lua")), env)("ForeverCore", ns)
	env.ForeverCore = { TrackerHost = host, TrackerSection = ns.TrackerSection, TrackerLine = ns.TrackerLine }
	setfenv(assert(loadfile("UI/Tracker.lua")), env)("Addon", ns)
	local module = assert(modules[1], "the section is made")
	assert(module.uiOrder == -3, "the section keeps its slot above the other Forever addons")
	assert(module.lineTemplate == "ShortestPathForeverTrackerLineTemplate", "and its own line pool")
	assert(module.trackerMaxHeight == 400, "an invalid saved height is clamped before first attachment")
	assert(module.safeCall == ns.core.SafeCall, "its errors go to the addon's journal")
	if not readyAtLoad then
		assert(owners[module] == nil, "nothing attaches before the world and saved variables are ready")
		for _, fn in ipairs(callbacks) do
			fn()
		end
		assert(owners[module] == nil, "the native callbacks cannot attach it early")
	end
	for _, fn in ipairs(timers) do
		fn()
	end
	assert(owners[module] == native, "private ownership survives initialization and late loading")
	assert(module.legacySettings.scale == 0.8, "the old tracker table is offered to the shared column")
	assert(
		ns.SetTrackerHeight(-5) == false and ns.db.trackerHeight == 100,
		"the absent Core setter path still clamps safely"
	)
	assert(ns.db.trackerHost == nil, "and cleared once it is offered")
	assert(module.AddHeaderMenuEntries == nil, "only the declarative menu is registered")
	checks = checks + 1
end
print("tracker_lifecycle_spec: " .. checks .. " load-order cases passed")

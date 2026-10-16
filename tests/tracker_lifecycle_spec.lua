-- Initialization must tolerate either native event order and an addon loaded after login.
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
	local ns = {
		TrackerHost = {
			Attach = function(module)
				owners[module] = native
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
	}
	env.ForeverTrackerHost = ns.TrackerHost
	setfenv(assert(loadfile("UI/Tracker.lua")), env)("Addon", ns)
	if not readyAtLoad then
		assert(owners[modules[1]] == native, "private host attachment is independent of Blizzard")
		for _, fn in ipairs(callbacks) do
			fn()
		end
		assert(owners[modules[1]] == native, "native callbacks cannot change private ownership")
	end
	for _, fn in ipairs(timers) do
		fn()
	end
	assert(owners[modules[1]] == native, "private ownership survives initialization and late loading")
	-- The Journey's right-click menu lets the shared column go, to drag it anywhere, and takes it back.
	local entries, attached = {}, true
	env.MenuUtil = {
		CreateContextMenu = function(_, build)
			build(nil, {
				CreateCheckbox = function(_, text, get, set)
					entries[text] = { get = get, set = set }
				end,
				CreateButton = noop,
			})
		end,
	}
	ns.Corpse = { Active = noop }
	ns.TrackerHost.IsAttachedToQuestTracker = function()
		return attached
	end
	ns.TrackerHost.SetAttached = function(value)
		attached = value
	end
	modules[1]:OnBlockHeaderClick({ id = "journey" }, "RightButton")
	local row = assert(entries["Attach to quest tracker"], "the Journey menu offers to move the tracker")
	assert(row.get() == true)
	row.set()
	assert(attached == false and row.get() == false, "unticking lets the column be dragged")
	row.set()
	assert(attached == true, "ticking attaches it again")
	checks = checks + 1
end
print("tracker_lifecycle_spec: " .. checks .. " load-order cases passed")

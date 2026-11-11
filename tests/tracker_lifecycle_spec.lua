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
		Attach = function(frame)
			owners[frame] = native
		end,
	}
	local ns = {
		core = {
			SafeCall = function(_, fn, ...)
				return fn(...)
			end,
		},
		db = { trackerHost = { scale = 0.8 } },
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
	setfenv(assert(loadfile(coreDirectory .. "/UI/TrackerSection.lua")), env)("ForeverCore", ns)
	env.ForeverCore = { TrackerHost = host, TrackerSection = ns.TrackerSection, TrackerLine = ns.TrackerLine }
	setfenv(assert(loadfile("UI/Tracker.lua")), env)("Addon", ns)
	local module = assert(modules[1], "the section is made")
	assert(module.uiOrder == -3, "the section keeps its slot above the other Forever addons")
	assert(module.lineTemplate == "ShortestPathForeverTrackerLineTemplate", "and its own line pool")
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
	assert(ns.db.trackerHost == nil, "and cleared once it is offered")
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
	-- ForeverCore's menu opener, drawn in its own frames.
	env.ForeverCore.ContextMenu = function(owner, generator)
		return env.MenuUtil.CreateContextMenu(owner, generator)
	end
	host.IsAttachedToQuestTracker = function()
		return attached
	end
	host.SetAttached = function(value)
		attached = value
	end
	local combat = false
	env.InCombatLockdown = function()
		return combat
	end
	module:OnBlockHeaderClick({ id = "journey" }, "RightButton")
	local row = assert(entries["Attach to quest tracker"], "the Journey menu offers to move the tracker")
	assert(row.get() == true)
	row.set()
	assert(attached == false and row.get() == false, "unticking lets the column be dragged")
	row.set()
	assert(attached == true, "ticking attaches it again")
	-- In combat the host cannot switch, so the menu leaves the choice out.
	entries, combat = {}, true
	module:OnBlockHeaderClick({ id = "journey" }, "RightButton")
	assert(entries["Attach to quest tracker"] == nil, "no attach choice in combat")
	-- The grey footer after a journey arrives (UI/FamilyHints.lua) opens its link on a left click.
	local opened = 0
	ns.FamilyHints = {
		OpenFooter = function()
			opened = opened + 1
		end,
		Footer = noop,
		Version = function()
			return 0
		end,
	}
	module:OnBlockHeaderClick({ id = "family" }, "RightButton")
	assert(opened == 0, "a right click on the footer does nothing")
	module:OnBlockHeaderClick({ id = "family" }, "LeftButton")
	assert(opened == 1, "a left click on the footer's title opens its link")
	-- A left click on the section's own header opens the same footer; the shared column owns the right-click menu.
	ns.JourneyInfo = function()
		return nil
	end
	module.mapDock, module.blocks = nil, { { key = "family" } }
	module:OnHeaderClick("LeftButton")
	assert(opened == 2, "a left click on the section header opens its footer")
	module:OnHeaderClick("RightButton")
	assert(opened == 2, "the right click stays with the shared column's menu")
	checks = checks + 1
end
print("tracker_lifecycle_spec: " .. checks .. " load-order cases passed")

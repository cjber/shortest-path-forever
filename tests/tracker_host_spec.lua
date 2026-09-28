-- The host must never enter Blizzard's tracker manager, including through pooled lines.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks = checks + 1
end
local function noop() end
local timers, ready, frames, releases = {}, nil, {}, {}
local combat = false
local function frame()
	local f = { width = 250, height = 0, scripts = {} }
	function f:SetPoint(...)
		self.point = { ... }
	end
	function f:SetWidth(value)
		self.width = value
	end
	function f:GetWidth()
		return self.width
	end
	function f:SetHeight(value)
		self.height = value
	end
	function f:GetHeight()
		return self.height
	end
	function f.GetTop(_self)
		return 640
	end
	function f:SetScript(event, fn)
		self.scripts[event] = fn
	end
	function f:HookScript(event, fn)
		self.scripts[event] = fn
	end
	function f:SetParent(parent)
		self.parent = parent
	end
	f.ClearAllPoints, f.RegisterEvent, f.Show, f.Hide = noop, noop, noop, noop
	frames[#frames + 1] = f
	return f
end
local native, parent = frame(), frame()
local ns = {}
local forbidden = setmetatable({}, {
	__index = function(_, key)
		error("native manager accessed: " .. key)
	end,
})
local env
env = setmetatable({
	ObjectiveTrackerManager = forbidden,
	InCombatLockdown = function()
		return combat
	end,
	ObjectiveTrackerFrame = native,
	UIParent = parent,
	CreateFrame = frame,
	C_Timer = {
		After = function(_, fn)
			timers[#timers + 1] = fn
		end,
	},
	EventUtil = {
		ContinueAfterAllEvents = function(fn)
			ready = fn
		end,
	},
	C_XMLUtil = {
		GetTemplateInfo = function()
			return { type = "Frame" }
		end,
	},
	Mixin = function(target, mixin)
		for key, value in pairs(mixin) do
			target[key] = value
		end
	end,
	CreateFramePoolCollection = function()
		return {
			GetOrCreatePool = function(_, _, _, template)
				return {
					Acquire = function()
						local f = frame()
						if template == "AnimBlock" and env.ObjectiveTrackerAnimBlockMixin then
							env.Mixin(f, env.ObjectiveTrackerAnimBlockMixin)
						end
						if template == "Block" then
							if env.ObjectiveTrackerBlockMixin then
								env.Mixin(f, env.ObjectiveTrackerBlockMixin)
							end
							f.usedLines = {}
							f.GetLine = function()
								error("native GetLine retained")
							end
							function f:GetExistingLine(key)
								return self.usedLines[key]
							end
						end
						return f, true
					end,
				},
					true
			end,
			Release = function(_, f)
				releases[f] = true
			end,
		}
	end,
}, { __index = _G })
local nativeRoot = os.getenv("TRACKER_UI_ROOT")
if nativeRoot then
	env.CreateFromMixins = function(...)
		local result = {}
		for _, mixin in ipairs({ ... }) do
			env.Mixin(result, mixin)
		end
		return result
	end
	env.ObjectiveTrackerSlidingMixin, env.ObjectiveTrackerLineMixin = {}, {}
	env.EnumUtil = {
		MakeEnum = function(...)
			local result = {}
			for i, name in ipairs({ ... }) do
				result[name] = i
			end
			return result
		end,
	}
	env.table = setmetatable({
		wipe = function(t)
			for k in pairs(t) do
				t[k] = nil
			end
		end,
	}, { __index = table })
	for _, name in ipairs({ "Module", "Block", "AnimTemplates" }) do
		setfenv(assert(loadfile(nativeRoot .. "/Blizzard_ObjectiveTracker" .. name .. ".lua")), env)()
	end
end

local function loadHost(namespace)
	setfenv(assert(loadfile("TrackerHost.lua")), env)("Test", namespace)
end
loadHost(ns)
local host = frames[3]
local function module(order)
	local m = frame()
	m.uiOrder, m.ContentsFrame, m.lineTemplate = order, frame(), "Line"
	function m:SetContainer(container)
		self.parentContainer = container
	end
	function m:Update(available)
		self.available, self.updates = available, (self.updates or 0) + 1
	end
	function m.GetContentsHeight(_self)
		return 80
	end
	ns.TrackerHost.Attach(m)
	return m
end
local second, first = module(2), module(1)
check(#timers == 0, "must not render before player and saved data are ready")
ready()
check(#timers == 1, "first layout is deferred")
local function drain()
	local pending = timers
	timers = {}
	for _, fn in ipairs(pending) do
		fn()
	end
end
drain()
check(first.point[5] == 0 and second.point[5] == -90, "sections follow uiOrder")
check(second.available == 510, "remaining space follows screen geometry")
check(ns.TrackerHost.IsAttached(first) and not ns.TrackerHost.IsAttached(nil), "ownership lookup")
ns.TrackerHost.Attach(first)
host:MarkDirty()
host:MarkDirty()
check(#timers == 1, "dirty updates coalesce")
drain()
check(first.updates == 2, "duplicate attach must not duplicate sections")
combat = true
host:MarkDirty()
drain()
check(first.updates == 2, "combat defers layout")
combat = false
host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
drain()
check(first.updates == 3, "leaving combat flushes deferred changes")
local block = first:AcquireFrame("Block")
block.parentModule = first
local line = block:GetLine(1)
check(line.parent == block and line.parentBlock == block and line.used, "line is locally owned")
check(block:GetLine(1) == line, "line reuse")
local replacement = block:GetLine(1, "OtherLine")
check(releases[line] and replacement ~= line, "template changes release old line")
block:FreeLine(replacement)
check(releases[replacement] and block.usedLines[1] == nil, "unused line releases")
local bar = frame()
first.usedProgressBars = { old = bar, active = { used = true } }
function bar:OnFree()
	self.freed = true
end
first:FreeUnusedProgressBars()
check(releases[bar] and bar.freed and first.usedProgressBars.active, "progress cleanup preserves active bars")
local other = {}
loadHost(other)
check(other.TrackerHost == ns.TrackerHost, "addons share a single private host")
check(first:GetContextMenuParent() == host, "menus use private container")
if nativeRoot then
	first.usedBlocks, first.blockTemplate, first.numCachedBlocks = {}, "Block", 0
	first.AnchorBlock = noop
	first.RemoveBlockFromCache = env.ObjectiveTrackerModuleMixin.RemoveBlockFromCache
	first.OnFreeBlock = noop
	local nativeBlock = env.ObjectiveTrackerModuleMixin.GetBlock(first, 42)
	local nativeLine = nativeBlock:GetLine("objective")
	check(nativeLine.parentBlock == nativeBlock, "native GetBlock uses isolated lines")
	first:FreeBlock(nativeBlock)
	check(releases[nativeBlock] and releases[nativeLine], "native Block.Free releases private resources")
	check(first.usedBlocks.Block[42] == nil, "native block removed from module")
	local animated = first:AcquireFrame("AnimBlock")
	animated.parentModule, animated.AddAnim, animated.activeAnim = first, {}, {}
	animated.SetAlpha = function(self, alpha)
		self.alpha = alpha
	end
	first.MarkDirty = function(self)
		self.dirty = true
	end
	animated:OnAnimFinished()
	check(first.dirty and animated.alpha == 0 and not animated.activeAnim, "native animation completes without manager")
end
print("tracker_host_spec: " .. checks .. " checks passed")

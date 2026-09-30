-- The host must never enter Blizzard's tracker manager, including through pooled lines.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks = checks + 1
end
local function noop() end
local timers, ready, frames, releases = {}, nil, {}, {}
local initializationEvents
local combat = false
local parent
local nativeAnchorPoint = "TOPRIGHT"
local function frame()
	local f = { width = 250, height = 0, scripts = {} }
	function f:SetPoint(...)
		self.point = { ... }
	end
	function f.GetPoint(self)
		return unpack(self.point or { nativeAnchorPoint, parent, nativeAnchorPoint, 0, -100 })
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
	function f:GetBottom()
		return (self:GetTop() or 0) - self:GetHeight()
	end
	function f:GetEffectiveScale()
		return self.effectiveScale or 1
	end
	function f:SetScale(value)
		self.scale = value
	end
	function f.GetTop(self)
		return self.top or 640
	end
	function f.GetLeft(self)
		return self.left or 0
	end
	function f.GetRight(self)
		return self.right or self:GetLeft() + self:GetWidth()
	end
	function f.GetBottom(self)
		return self.bottom or self:GetTop() - self:GetHeight()
	end
	function f:IsShown()
		return self.shown ~= false
	end
	function f:SetScript(event, fn)
		self.scripts[event] = fn
	end
	function f:HookScript(event, fn)
		self.scripts[event] = fn
	end
	function f:SetParent(owner)
		self.parent = owner
	end
	function f:ClearAllPoints()
		self.point = nil
	end
	f.RegisterEvent = noop
	f.Show = function(self)
		self.shown = true
	end
	f.Hide = function(self)
		self.shown = false
	end
	frames[#frames + 1] = f
	return f
end
local native = frame()
local minimap = frame()
minimap.left, minimap.right, minimap.top, minimap.bottom, minimap.shown = 900, 1100, 700, 500, false
parent = frame()
native.point = { nativeAnchorPoint, parent, nativeAnchorPoint, 0, -100 }
native.height = 300
parent:SetHeight(1080)
native.effectiveScale, parent.effectiveScale = 1.25, 1
local ns = {}
local forbidden = setmetatable({}, {
	__index = function(_, key)
		error("native manager accessed: " .. key)
	end,
})
local callbacks = {}
local eventRegistry = {
	RegisterCallback = function(_, event, callback, owner)
		callbacks[event] = callbacks[event] or {}
		callbacks[event][#callbacks[event] + 1] = { callback = callback, owner = owner }
	end,
	TriggerEvent = function(_, event, ...)
		for _, entry in ipairs(callbacks[event] or {}) do
			entry.callback(entry.owner, ...)
		end
	end,
}
local editMode = { active = false }
function editMode:IsEditModeActive()
	return self.active
end
local env
env = setmetatable({
	ObjectiveTrackerManager = forbidden,
	InCombatLockdown = function()
		return combat
	end,
	ObjectiveTrackerFrame = native,
	Minimap = minimap,
	UIParent = parent,
	CreateFrame = frame,
	C_Timer = {
		After = function(_, fn)
			timers[#timers + 1] = fn
		end,
	},
	EventUtil = {
		ContinueAfterAllEvents = function(fn, ...)
			initializationEvents = { ... }
			ready = fn
		end,
	},
	EventRegistry = eventRegistry,
	EditModeManagerFrame = editMode,
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
env._G = env
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

local function loadHost(namespace, path)
	path = path or "TrackerHost.lua"
	setfenv(assert(loadfile(path)), env)("Test", namespace)
end
local hostPaths = {}
for path in (os.getenv("AGF_TRACKER_HOSTS") or "TrackerHost.lua"):gmatch("[^\n]+") do
	hostPaths[#hostPaths + 1] = path
end
loadHost(ns, hostPaths[1])
for index = 2, #hostPaths do
	local joining, count = {}, #frames
	loadHost(joining, hostPaths[index])
	check(joining.TrackerHost == ns.TrackerHost, "companion joins the first loaded host")
	check(#frames == count, "companion must not create a second host")
end
local host = frames[4]
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
check(
	initializationEvents[1] == "PLAYER_ENTERING_WORLD"
		and initializationEvents[2] == "VARIABLES_LOADED"
		and #initializationEvents == 2,
	"first rendering waits for both native load events"
)
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
check(native:GetHeight() == 300, "native viewport preserves an externally sized height before clamping")
native:SetHeight(420)
native.scripts.OnSizeChanged(native)
drain()
check(native:GetHeight() == 420, "native viewport adopts an external resize before clamping")
native:SetHeight(700)
native.scripts.OnSizeChanged(native)
drain()
check(native:GetHeight() < 700, "native viewport clamps after an external resize")
native:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
eventRegistry:TriggerEvent("EditMode.SavedLayouts")
drain()
check(native.point[2] == host and native.point[3] == "BOTTOMRIGHT", "private host repairs native reanchor")
editMode.active = true
eventRegistry:TriggerEvent("EditMode.Enter")
check(host.shown == false, "private tracker hides while Edit Mode owns native slot")
editMode.active = false
eventRegistry:TriggerEvent("EditMode.Exit")
drain()
check(host.shown == true, "private tracker returns after Edit Mode")
check(
	native.point[1] == "TOPRIGHT" and native.point[2] == host and native.point[3] == "BOTTOMRIGHT",
	"native objectives follow private sections"
)
check(ns.TrackerHost.IsAttached(first) and not ns.TrackerHost.IsAttached(nil), "ownership lookup")
local updatesBeforeDuplicateAttach = first.updates
ns.TrackerHost.Attach(first)
host:MarkDirty()
host:MarkDirty()
check(#timers == 1, "dirty updates coalesce")
drain()
check(first.updates == updatesBeforeDuplicateAttach + 1, "duplicate attach must not duplicate sections")
local nativeSetPoint, nativeSetHeight, nativeClear = native.SetPoint, native.SetHeight, native.ClearAllPoints
native.SetPoint = function(self, ...)
	assert(not combat, "combat must never reposition the protected native tracker")
	return nativeSetPoint(self, ...)
end
native.SetHeight = function(self, value)
	assert(not combat, "combat must never resize the protected native tracker")
	return nativeSetHeight(self, value)
end
native.ClearAllPoints = function(self)
	assert(not combat, "combat must never clear the protected native tracker anchors")
	return nativeClear(self)
end
combat = true
native.top = 500
nativeSetPoint(native, "TOPRIGHT", parent, "TOPRIGHT", 0, -100)
host.scripts.OnEvent(host, "PLAYER_REGEN_DISABLED")
drain()
check(first.updates == updatesBeforeDuplicateAttach + 1, "combat defers layout")
-- In combat the protected native tracker cannot be restacked, so our column moves above its saved slot instead.
check(
	host.point[1] == "BOTTOMRIGHT" and host.point[2] == native and host.point[3] == "TOPRIGHT",
	"combat lifts our column above the native frame"
)
combat = false
host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
drain()
check(first.updates == updatesBeforeDuplicateAttach + 2, "leaving combat flushes deferred changes")
combat = true
native.top = 10000
nativeSetPoint(native, "TOPRIGHT", parent, "TOPRIGHT", 0, -100)
host.scripts.OnEvent(host, "PLAYER_REGEN_DISABLED")
drain()
check(
	host.point[1] == "TOPRIGHT" and host.point[2] == native and host.point[3] == "TOPLEFT",
	"combat uses the clear side when there is no room above"
)
-- Blizzard's combat restore can temporarily point the protected frame at our host.
-- Collision avoidance must use the saved Edit Mode slot rather than create an anchor cycle.
minimap.shown = true
host.left, host.right, host.top, host.bottom = 700, 950, 640, 300
minimap.left, minimap.right, minimap.top, minimap.bottom = 700, 1100, 900, 0
nativeSetPoint(native, "TOPRIGHT", host, "BOTTOMRIGHT", 0, 0)
host:MarkDirty()
drain()
check(host.point[2] ~= native, "minimap fallback avoids a native-to-host anchor cycle")
check(
	host.point[1] == "TOPRIGHT" and host.point[3] == "TOPRIGHT" and host.point[4] == -258,
	"fallback preserves native slot with a clear-side offset"
)
nativeSetPoint(native, "TOPRIGHT", parent, "TOPRIGHT", 0, -100)
-- A visible minimap collision is tested in scaled screen coordinates, including the native-relative fallback.
minimap.shown = true
minimap.left, minimap.right, minimap.top, minimap.bottom = 0, 400, 900, 0
native.top = 500
native.effectiveScale, minimap.effectiveScale, parent.effectiveScale = 1.5, 1.25, 1
nativeSetPoint(native, "TOPRIGHT", parent, "TOPRIGHT", 0, -100)
host:MarkDirty()
drain()
check(host.point[1] == "BOTTOMRIGHT", "scaled non-overlap keeps above-native placement")
minimap.left, minimap.right = 400, 680
host:MarkDirty()
drain()
check(
	host.point[1] == "TOPRIGHT" and host.point[2] == native and host.point[3] == "TOPLEFT",
	"scaled minimap overlap moves private column beside native objectives"
)
minimap.shown = false
host:MarkDirty()
drain()
check(host.point[1] == "BOTTOMRIGHT", "hidden minimap does not alter native-relative fallback")
minimap.shown = true
minimap.left, minimap.right, minimap.top, minimap.bottom = 900, 1100, 700, 500
host:MarkDirty()
drain()
check(host.point[1] == "BOTTOMRIGHT", "non-overlapping minimap leaves fallback unchanged")
native.effectiveScale, parent.effectiveScale = 1.25, 1
host:MarkDirty()
drain()
combat = false
host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
drain()
local hostPointBeforeNativeResize = host.point[5]
native:SetHeight(900)
host:MarkDirty()
drain()
check(host.point[5] == hostPointBeforeNativeResize, "native frame height does not move private content")
first.GetContentsHeight = function()
	return 700
end
host.top = 300
native:SetHeight(500)
host:MarkDirty()
drain()
check(host.point[5] > 0, "oversized column shifts upward into the visible viewport")
check(native:GetHeight() < 500, "native height is clamped to the visible remainder")
first.GetContentsHeight = function()
	return 80
end
host.top = 700
host:MarkDirty()
drain()
check(native:GetHeight() <= 500, "native height remains within the visible remainder")
check(host.scale == 1.25, "companion matches native effective scale")
nativeAnchorPoint = "BOTTOMRIGHT"
nativeSetPoint(native, nativeAnchorPoint, parent, nativeAnchorPoint, 0, -100)
host:MarkDirty()
drain()
check(native.point[1] == "TOPRIGHT" and native.point[3] == "BOTTOMRIGHT", "bottom anchor still stacks objectives below")
nativeAnchorPoint = "CENTER"
nativeSetPoint(native, nativeAnchorPoint, parent, nativeAnchorPoint, 0, -100)
host:MarkDirty()
drain()
check(native.point[1] == "TOP" and native.point[3] == "BOTTOM", "center anchor uses centered top stack")
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

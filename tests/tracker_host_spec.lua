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
		return self.effectiveScale or (self.scale or 1)
	end
	function f:GetScale()
		return self.scale or 1
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
	f.SetMovable, f.RegisterForDrag = noop, noop
	f.clamped = true
	function f:SetClampedToScreen(value)
		self.clamped = value
	end
	function f:IsClampedToScreen()
		return self.clamped
	end
	function f.CreateFontString(_)
		return { SetPoint = noop, SetText = noop }
	end
	function f:SetShown(value)
		self.shown = value
	end
	function f:StartMoving()
		self.moving = true
	end
	function f:StopMovingOrSizing()
		self.moving = false
	end
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
parent.width = 1200
native.point = { nativeAnchorPoint, parent, nativeAnchorPoint, 0, -100 }
native.height = 300
parent:SetHeight(1080)
native.effectiveScale, parent.effectiveScale = 1.25, 1
local nativeHeader = frame()
nativeHeader.shown = false
nativeHeader.point = { "TOPLEFT", native, "TOPLEFT", 0, 0 }
local minimizeButton = frame()
nativeHeader.MinimizeButton = minimizeButton
native.Header = nativeHeader
-- The native container anchors this to the bottom of its last shown module; scenarios set it to the content bottom.
native.NineSlice = {
	bottom = 0,
	GetBottom = function(self)
		return self.bottom
	end,
}
-- Blizzard's tracker re-anchors its header at the end of every update.
function native.UpdateHeaderPosition()
	nativeHeader:SetPoint("TOPLEFT", native, "TOPLEFT", 0, 0)
end
-- The managed-frame layout calls this after it re-anchors the frame to its saved slot.
function native.UpdateHeight() end
-- A native tracker update re-anchors the frame to its saved slot and finishes at the header.
function native.RestoreSavedAnchor()
	native:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -100)
	native:UpdateHeaderPosition()
end
local ns = { L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
}) }
local hostSettings = { attached = true }
function ns.TrackerHostSettings()
	return hostSettings
end
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
local editMode = { active = false, shown = false, scripts = {} }
function editMode:IsEditModeActive()
	return self.active
end
function editMode:IsShown()
	return self.shown
end
function editMode:HookScript(kind, fn)
	self.scripts[kind] = fn
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
	hooksecurefunc = function(target, name, callback)
		local original = target[name]
		target[name] = function(...)
			local result = original(...)
			callback(...)
			return result
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
	path = path or "UI/TrackerHost.lua"
	setfenv(assert(loadfile(path)), env)("Test", namespace)
end
local hostPaths = {}
for path in (os.getenv("AGF_TRACKER_HOSTS") or "UI/TrackerHost.lua"):gmatch("[^\n]+") do
	hostPaths[#hostPaths + 1] = path
end
loadHost(ns, hostPaths[1])
for index = 2, #hostPaths do
	local joining, count = {}, #frames
	loadHost(joining, hostPaths[index])
	check(joining.TrackerHost == ns.TrackerHost, "companion joins the first loaded host")
	check(#frames == count, "companion must not create a second host")
end
local host = frames[6]
local grip = frames[7]
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
check(second.available == 518, "remaining space follows screen geometry")
check(native:GetHeight() == 300, "native viewport preserves an externally sized height before clamping")
native:SetHeight(420)
native.scripts.OnSizeChanged(native)
drain()
check(native:GetHeight() == 420, "native viewport adopts an external resize before clamping")
native:SetHeight(700)
native.scripts.OnSizeChanged(native)
drain()
check(native:GetHeight() == 700, "native container keeps its externally sized height")
native:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
eventRegistry:TriggerEvent("EditMode.SavedLayouts")
drain()
check(native.point[1] == "TOPLEFT" and native.point[2] == parent, "private host repairs native reanchor independently")
editMode.active, editMode.shown = true, true
eventRegistry:TriggerEvent("EditMode.Enter")
check(host.shown == false, "private tracker hides while Edit Mode owns native slot")
check(native.clamped == true, "Edit Mode gets the native frame's screen clamp back")
-- CheckHideAndLockEditMode hides the manager without exiting it: active stays true and no EditMode.Exit runs.
check(editMode.scripts.OnHide ~= nil, "private tracker follows the Edit Mode manager's own hide")
editMode.shown = false
editMode.scripts.OnHide(editMode)
drain()
check(host.shown == true, "private tracker returns when a locked Edit Mode hides its manager")
editMode.active, editMode.shown = false, false
eventRegistry:TriggerEvent("EditMode.Exit")
drain()
check(host.shown == true, "private tracker returns after Edit Mode")
check(native.clamped == false, "restacking after Edit Mode unclamps the native frame again")
check(native.point[1] == "TOPLEFT" and native.point[2] == parent, "native objectives stay independently anchored")
check(ns.TrackerHost.IsAttached(first) and not ns.TrackerHost.IsAttached(nil), "ownership lookup")
local attachmentChanges = 0
ns.TrackerHost.OnAttachmentChanged(function(value)
	attachmentChanges = attachmentChanges + 1
	check(value == false or value == true, "attachment callback receives desired state")
end)
local nativeHeightBeforeDetach = native:GetHeight()
local requestedHeightBeforeDetach = 700
local firstUpdatesBeforeDetach, secondUpdatesBeforeDetach = first.updates, second.updates
ns.TrackerHost.SetAttached(false)
drain()
check(native.point[2] ~= host, "detach restores native parent anchor")
check(
	native:GetHeight() == requestedHeightBeforeDetach and native:GetHeight() >= nativeHeightBeforeDetach,
	"detach restores native requested height"
)
check(
	first.updates > firstUpdatesBeforeDetach and second.updates > secondUpdatesBeforeDetach,
	"detach lays out every shared module"
)
check(grip.shown and first.point[5] == -24, "detached grip reserves space above modules")
-- Until it is dragged, a detached column sits beside the native tracker, never over it.
local nativeLeft, nativeRight, nativeTop
local function besideNative()
	local scale = native:GetEffectiveScale() / host:GetEffectiveScale()
	nativeLeft, nativeRight, nativeTop = native:GetLeft() * scale, native:GetRight() * scale, native:GetTop() * scale
	local left, right = host.point[4], host.point[4] + host:GetWidth()
	return host.point[1] == "TOPLEFT"
		and host.point[2] == parent
		and left >= 0
		and right <= parent:GetWidth()
		and (right <= nativeLeft or left >= nativeRight)
end
check(besideNative() and host.point[4] >= nativeRight, "an undragged detached column sits right of a left-side tracker")
local screenHeight = parent:GetHeight() * parent:GetEffectiveScale() / host:GetEffectiveScale()
check(host.point[5] == nativeTop - screenHeight, "an undragged detached column is level with the tracker")
native.left, native.right = 700, 950
host:MarkDirty()
drain()
check(besideNative() and host.point[4] < nativeLeft, "an undragged detached column sits left of a right-side tracker")
native.left, native.right = nil, nil
grip.scripts.OnDragStart(grip)
check(host.moving, "detached grip starts moving")
host.left, host.top = 96, 880
grip.scripts.OnDragStop(grip)
drain()
check(not host.moving and hostSettings.x == 120 and hostSettings.y == 20, "drag stop saves screen coordinates")
check(not ns.TrackerHost.IsAttachedToQuestTracker(), "all modules detach from the native tracker")
ns.TrackerHost.SavePosition(80, -120)
drain()
check(host.point[1] == "TOPLEFT" and host.point[4] == 64 and host.point[5] == -96, "detached position persists")
ns.TrackerHost.SetAttached(true)
drain()
check(
	ns.TrackerHost.IsAttachedToQuestTracker() and attachmentChanges == 2,
	"reattach restores the shared native column"
)
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
local clampedBeforeCombatDetach = native:GetHeight()
combat = true
nativeSetPoint(native, "TOPRIGHT", parent, "TOPRIGHT", 0, 0)
ns.TrackerHost.SetAttached(false)
check(not ns.TrackerHost.IsAttachedToQuestTracker(), "desired attachment changes during combat")
combat = false
host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
drain()
check(not ns.TrackerHost.IsAttachedToQuestTracker(), "deferred attachment applies after combat")
check(
	native:GetHeight() == 700 and native:GetHeight() == clampedBeforeCombatDetach,
	"post-combat detach preserves the native container height"
)
local detachedUpdates = first.updates
combat = true
host:MarkDirty()
drain()
check(first.updates > detachedUpdates, "detached modules refresh in combat without native writes")
grip.scripts.OnDragStart(grip)
check(not host.moving, "combat blocks dragging")
ns.TrackerHost.SetAttached(true)
drain()
check(host.point[2] == parent and grip.shown, "reattach stays physically detached until combat ends")
combat = false
host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
drain()
check(
	native.point[2] == parent and native.point[1] == "TOPLEFT" and not grip.shown,
	"combat exit applies independent reattachment"
)

ns.TrackerHost.SetAttached(true)
drain()
check(
	native.clamped == false,
	"stacking unclamps the native frame so its restored height cannot push it over our column"
)
combat = true
local stackedPoint = host.point
host.scripts.OnEvent(host, "PLAYER_REGEN_DISABLED")
drain()
check(host.point == stackedPoint, "combat leaves our column alone while the native frame stays stacked below it")
local updatesBeforeCombat = first.updates
-- Blizzard restores the protected frame to its saved slot in combat. The header goes back to the native frame and
-- our sections sit directly below the native content, so the column reads header, native modules, then ours.
native.top = 500
native.NineSlice.bottom = 420
nativeSetPoint(native, "TOPRIGHT", parent, "TOPRIGHT", 0, -100)
host.scripts.OnEvent(host, "PLAYER_REGEN_DISABLED")
drain()
check(first.updates == updatesBeforeCombat + 1, "combat re-lays our sections below the native content")
check(
	host.point[1] == "TOP" and host.point[2] == native and host.point[3] == "BOTTOM",
	"combat puts our column directly below the native content"
)
check(nativeHeader.point[2] == native, "the one column hands the header back to the native frame")
-- When that column would run off the bottom of the screen, it falls back above the native frame.
native.NineSlice.bottom = 0
host:MarkDirty()
drain()
check(
	host.point[1] == "BOTTOMRIGHT" and host.point[2] == native and host.point[3] == "TOPRIGHT",
	"an off-screen one column falls back above the native frame"
)
combat = false
host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
drain()
check(first.updates == updatesBeforeCombat + 3, "leaving combat flushes deferred changes")
combat = true
native.top = 10000
native.left, native.right = 900, 1150
nativeSetPoint(native, "TOPRIGHT", parent, "TOPRIGHT", 0, -100)
host.scripts.OnEvent(host, "PLAYER_REGEN_DISABLED")
drain()
check(
	host.point[1] == "TOPRIGHT" and host.point[2] == native and host.point[3] == "TOPLEFT",
	"combat uses the screen-left side when the native tracker is on the right"
)
native.left, native.right = 0, 250
nativeSetPoint(native, "CENTER", parent, "CENTER", 0, -100)
host:MarkDirty()
drain()
check(
	host.point[1] == "TOPLEFT" and host.point[2] == native and host.point[3] == "TOPRIGHT",
	"combat uses the screen-right side when a centered native tracker is moved left"
)
-- Blizzard's combat restore can temporarily point the protected frame at our host.
-- Collision avoidance must use the saved Edit Mode slot rather than create an anchor cycle.
nativeSetPoint(native, "TOPRIGHT", parent, "TOPRIGHT", 0, -100)
host:MarkDirty()
drain()
minimap.shown = true
host.left, host.right, host.top, host.bottom = 560, 760, 640, 300
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
check(native:GetHeight() == 500, "native container owns its height below the companion column")
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
check(native.point[1] == "TOPLEFT" and native.point[2] == parent, "bottom anchor stacks objectives independently")
nativeAnchorPoint = "CENTER"
nativeSetPoint(native, nativeAnchorPoint, parent, nativeAnchorPoint, 0, -100)
host:MarkDirty()
drain()
check(native.point[1] == "TOPLEFT" and native.point[2] == parent, "center anchor stacks objectives independently")
-- The native header leads the shared column: header, then the Forever sections, then the game's modules.
minimap.shown = false
host.top, host.bottom, host.left, host.right = nil, nil, nil, nil
native.top, native.left, native.right, native.bottom = nil, nil, nil, nil
native.effectiveScale, parent.effectiveScale = 1, 1
nativeSetPoint(native, "TOPRIGHT", parent, "TOPRIGHT", 0, -100)
host:MarkDirty()
drain()
local function nativeOffset(reserve)
	return host:GetBottom() + reserve - parent:GetHeight()
end
check(
	nativeHeader.point[2] == native and native.point[5] == nativeOffset(0),
	"a hidden header leaves the host as it was"
)
nativeHeader:Show()
host:MarkDirty()
drain()
check(
	nativeHeader.point[2] == host and nativeHeader.point[1] == "TOPLEFT",
	"the native header moves to the top of the shared column"
)
check(nativeHeader.point[4] == 0 and nativeHeader.point[5] == 0, "the header sits flush with the host top")
check(first.point[5] == -38, "the first section leaves the header its room")
check(second.point[5] == -128, "sections keep their order below the header")
check(native.point[5] == nativeOffset(38), "the native frame moves up by the header it no longer holds")
-- Blizzard re-anchors the header at the end of each update; the secure post-hook puts it back on the host.
native:UpdateHeaderPosition()
check(nativeHeader.point[2] == host, "the header is re-anchored after a native tracker update")
-- A native update that restores the frame's saved slot must mark the host so it restacks below the column.
native.RestoreSavedAnchor()
drain()
check(
	native.point[1] == "TOPLEFT" and native.point[2] == parent,
	"a native restore re-stacks the native frame below the shared column"
)
check(nativeHeader.point[2] == host, "the header stays at the top of the column after a native restore")
-- The managed frame containers re-anchor through their own layout and report the new height for it.
native:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -100)
native:UpdateHeight()
drain()
check(
	native.point[1] == "TOPLEFT" and native.point[2] == parent,
	"a managed frame update re-stacks the native frame below the shared column"
)
-- A neighbour showing or hiding makes the container lay the native frame out again with no update of its own.
native:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -100)
drain()
check(
	native.point[1] == "TOPLEFT" and native.point[2] == parent,
	"a managed frame update re-stacks the native frame below the shared column"
)
check(nativeHeader.point[2] == host, "the header stays at the top of the column after a managed frame update")
first.GetContentsHeight = function()
	return 0
end
second.GetContentsHeight = function()
	return 0
end
host:MarkDirty()
drain()
check(
	nativeHeader.point[2] == native and native.point[5] == nativeOffset(0),
	"an empty host gives the header back to the native frame"
)
check(host:GetHeight() == 1 and host.shown ~= false, "an empty host keeps no reserved gap")
first.GetContentsHeight = function()
	return 80
end
second.GetContentsHeight = function()
	return 80
end
host:MarkDirty()
drain()
check(nativeHeader.point[2] == host, "sections bring the header back to the shared column")
ns.TrackerHost.SetAttached(false)
drain()
check(
	nativeHeader.point[2] == native and native.point[2] == parent,
	"detaching returns the header and the native frame exactly"
)
ns.TrackerHost.SetAttached(true)
drain()
check(nativeHeader.point[2] == host, "reattaching returns the header to the shared column")
combat = true
host.scripts.OnEvent(host, "PLAYER_REGEN_DISABLED")
drain()
check(nativeHeader.point[2] == host, "combat keeps the header at the top of the shared column")
check(nativeHeader.point[4] == 0 and nativeHeader.point[5] == 0, "the header stays flush with the host top in combat")
check(
	native.point[1] == "TOPLEFT" and native.point[2] == parent,
	"combat never re-anchors the protected native frame for the header"
)
native.top = 500
native.NineSlice.bottom = 420
nativeSetPoint(native, "TOPRIGHT", parent, "TOPRIGHT", 0, -100)
host.scripts.OnEvent(host, "PLAYER_REGEN_DISABLED")
drain()
check(nativeHeader.point[2] == native, "a native move in combat hands the header back to the native frame")
check(
	host.point[1] == "TOP" and host.point[2] == native and host.point[3] == "BOTTOM",
	"a native move in combat puts our column below the native content"
)
check(first.point[5] == 0, "the one column drops the header's reserved room")
native.top = nil
combat = false
host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
drain()
check(nativeHeader.point[2] == host, "the header returns to the shared column after combat")
check(first.point[5] == -38, "leaving combat restores the header's room")
native.isCollapsed = true
minimizeButton.scripts.OnClick(minimizeButton)
drain()
check(host.shown == false, "collapsing All Objectives hides the shared sections")
check(
	nativeHeader.point[2] == native and native.point[5] == nativeOffset(0),
	"collapsing returns the header and its room to the native frame"
)
native.isCollapsed = false
minimizeButton.scripts.OnClick(minimizeButton)
drain()
check(host.shown == true, "expanding shows the shared sections again")
check(nativeHeader.point[2] == host and first.point[5] == -38, "expanding returns the header and the header's room")
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
-- A native resize schedules the managed container to restore its Edit Mode anchor next frame.
local rawNativeSetHeight = native.SetHeight
function native:SetHeight(value)
	rawNativeSetHeight(self, value)
	timers[#timers + 1] = function()
		rawNativeSetHeight(native, 900)
		native:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -26)
		native:UpdateHeight()
	end
end
combat = false
native:SetHeight(900)
host:MarkDirty()
for _ = 1, 10 do
	drain()
end
check(
	native.point[1] == "TOPLEFT" and native.point[2] == parent,
	"attached tracker settles below the host after a managed resize"
)
native.SetHeight = rawNativeSetHeight

-- The tracker scale rides on the shared host settings: one stored value, read by whichever addon loaded the
-- host first. It enlarges the private column only, converting the native slot's offsets so the placement stays
-- put, and the attached restack waits for combat to end rather than moving the protected frame while locked.
native.effectiveScale, parent.effectiveScale = 1.25, 1
host:MarkDirty()
drain()
check(host.scale == 1.25, "companion matches native effective scale")
local nativeAnchorY = host.point[5]
ns.TrackerHost.SetScale(1.5)
drain()
check(host.scale == 1.875, "tracker scale multiplies the native scale")
check(hostSettings.scale == 1.5, "tracker scale persists on the shared host settings")
check(ns.TrackerHost.GetScale() == 1.5, "tracker scale reads back from the shared host")
check(
	host.point[5] == nativeAnchorY * (1.25 / 1.875),
	"attached offsets convert from the native scale to the scaled host"
)
combat = true
ns.TrackerHost.SetScale(0.75)
drain()
check(host.scale == 1.875, "tracker scale waits while the native tracker is locked")
check(hostSettings.scale == 0.75, "the requested scale is saved immediately")
combat = false
host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
drain()
check(host.scale == 0.9375, "tracker scale applies after combat")
ns.TrackerHost.SetScale(1)
drain()
check(host.scale == 1.25, "tracker scale returns to the native size")

-- A fresh host after /reload resolves persisted owner settings only after load events.
combat = false
native.effectiveScale, parent.effectiveScale = 1, 1
nativeSetPoint(native, "TOPLEFT", parent, "TOPLEFT", 0, -100)
hostSettings = { attached = false, x = 140, y = -180 }
local beforeReload = #frames
ns = {
	L = ns.L,
	TrackerHostSettings = function()
		return hostSettings
	end,
}
env.ForeverTrackerHost = nil
combat = true
loadHost(ns, hostPaths[1])
local reloadedHost, reloadedGrip = frames[beforeReload + 1], frames[beforeReload + 2]
local coldModule = module(1)
check(coldModule.updates == nil, "saved detached tracker waits for player readiness")
ready()
drain()
check(
	reloadedHost.point[2] == parent and reloadedHost.point[4] == 140 and reloadedHost.point[5] == -180,
	"reload restores saved detached position"
)
check(
	native.point[2] == parent and reloadedGrip.shown and coldModule.updates == 1,
	"saved detached bootstrap renders module without moving native tracker"
)
combat = false
reloadedHost.effectiveScale = 1.5
hostSettings.x, hostSettings.y = 150, -180
reloadedHost:MarkDirty()
drain()
check(reloadedHost.point[4] == 100 and reloadedHost.point[5] == -120, "saved offsets divide by effective UI scale")
reloadedGrip.scripts.OnDragStart(reloadedGrip)
reloadedHost.left, reloadedHost.top = 100, 600
reloadedGrip.scripts.OnDragStop(reloadedGrip)
drain()
check(hostSettings.x == 150 and hostSettings.y == -180, "scaled drag round trip preserves screen offsets")
hostSettings.x, hostSettings.y = math.huge, 0 / 0
reloadedHost:MarkDirty()
drain()
check(hostSettings.x == nil and hostSettings.y == nil, "non-finite saved coordinates normalize")
hostSettings.attached = "bad"
check(ns.TrackerHost.GetSettings().attached == true, "malformed attachment defaults to attached")
print("tracker_host_spec: " .. checks .. " checks passed")

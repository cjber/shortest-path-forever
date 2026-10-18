-- The shared host beside a quest tracker addon that replaces the game's own (Questie), and its optional background.
-- Shared byte for byte with tracker_host_spec.lua's companions; anchors resolve to screen pixels so overlap is real.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks = checks + 1
end
local function noop() end
local function fraction(point)
	local x = point:find("LEFT", 1, true) and 0 or point:find("RIGHT", 1, true) and 1 or 0.5
	local y = point:find("BOTTOM", 1, true) and 0 or point:find("TOP", 1, true) and 1 or 0.5
	return x, y
end
-- Screen-pixel left, top, width, height and bottom, following anchors and the screen clamp.
local function bounds(frame, seen)
	local scale = frame:GetEffectiveScale()
	if frame.root then
		return 0, frame.height * scale, frame.width * scale, frame.height * scale, 0
	end
	seen = seen or {}
	assert(not seen[frame], "anchor dependency cycle")
	seen[frame] = true
	local point, relative, relativePoint, x, y = unpack((assert(frame.point, "missing anchor")))
	local rl, rt, rw, _, rb = bounds(relative, seen)
	local rx, ry = fraction(relativePoint)
	local fx, fy = fraction(point)
	local width, height = frame.width * scale, frame.height * scale
	local left = rl + rx * rw + (x or 0) * scale - fx * width
	local anchorY = ry == 0 and rb or ry == 1 and rt or (rt + rb) / 2
	local bottom = anchorY + (y or 0) * scale - fy * height
	if frame.clamped then
		local screen = frame.screen
		local sw, sh = screen.width * screen:GetEffectiveScale(), screen.height * screen:GetEffectiveScale()
		left = math.max(0, math.min(left, sw - width))
		bottom = math.max(0, math.min(bottom, sh - height))
	end
	seen[frame] = nil
	return left, bottom + height, width, height, bottom
end
-- Touching edges are clear, floating point included.
local function clears(a, b)
	local al, at, aw, _, ab = bounds(a)
	local bl, bt, bw, _, bb = bounds(b)
	return not (al < bl + bw - 0.01 and al + aw > bl + 0.01 and ab < bt - 0.01 and at > bb + 0.01)
end

local function scenario(uiScale, userScale)
	local frames, timers, ready, combat = {}, {}, nil, false
	local screen
	local function frame(_, name, parent)
		local f = { name = name, parent = parent, width = 250, height = 1, scripts = {}, hooks = {} }
		function f:GetEffectiveScale()
			return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1)
		end
		function f:SetScale(value)
			self.scale = value
		end
		function f:SetPoint(...)
			self.point = { ... }
		end
		function f:GetPoint()
			return unpack(self.point or {})
		end
		function f:ClearAllPoints()
			self.point = nil
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
		function f:GetLeft()
			return (bounds(self)) / self:GetEffectiveScale()
		end
		function f:GetTop()
			return select(2, bounds(self)) / self:GetEffectiveScale()
		end
		function f:GetRight()
			local left, _, width = bounds(self)
			return (left + width) / self:GetEffectiveScale()
		end
		function f:GetBottom()
			return select(5, bounds(self)) / self:GetEffectiveScale()
		end
		function f:SetClampedToScreen(value)
			self.clamped, self.screen = value, screen
		end
		function f:IsClampedToScreen()
			return self.clamped
		end
		function f:SetScript(event, fn)
			self.scripts[event] = fn
		end
		function f:HookScript(event, fn)
			self.hooks[event] = self.hooks[event] or {}
			table.insert(self.hooks[event], fn)
		end
		function f:Fire(event)
			for _, fn in ipairs(self.hooks[event] or {}) do
				fn(self)
			end
		end
		function f:SetShown(value)
			self.shown = value
		end
		function f:Hide()
			self.shown = false
		end
		function f:Show()
			self.shown = true
		end
		function f:IsShown()
			return self.shown ~= false
		end
		function f.CreateFontString(_)
			return { SetPoint = noop, SetText = noop }
		end
		function f:CreateTexture()
			local texture = { SetPoint = noop }
			self.textures = self.textures or {}
			self.textures[#self.textures + 1] = texture
			function texture.SetColorTexture(_, r, g, b, a)
				texture.color = { r, g, b, a }
			end
			function texture.SetShown(_, value)
				texture.shown = value
			end
			return texture
		end
		f.SetMovable, f.RegisterForDrag, f.RegisterEvent = noop, noop, noop
		frames[#frames + 1] = f
		return f
	end
	screen = frame()
	screen.root, screen.width, screen.height, screen.scale = true, 1200, 1080, uiScale
	-- Questie's tracker removes the game's quest watches: the native tracker is shown but holds nothing.
	local native = frame(nil, "native", screen)
	native.height = 300
	native:SetPoint("TOPRIGHT", screen, "TOPRIGHT", -24, -100)
	local header = frame(nil, "header", native)
	header:SetPoint("TOPLEFT", native, "TOPLEFT", 0, 0)
	native.Header = header
	local rawPoint, rawClear = native.SetPoint, native.ClearAllPoints
	function native:SetPoint(...)
		assert(not combat, "protected combat reposition")
		rawPoint(self, ...)
	end
	function native:ClearAllPoints()
		assert(not combat, "protected combat clear")
		rawClear(self)
	end
	-- Questie draws its list at the native tracker's own point.
	local questie = frame(nil, "Questie_BaseFrame", screen)
	questie.width, questie.height = 280, 200
	questie:SetPoint("TOPRIGHT", screen, "TOPRIGHT", -24, -100)
	local settings = { attached = true, scale = userScale }
	local ns = {
		L = setmetatable({}, {
			__index = function(_, key)
				return key
			end,
		}),
		TrackerHostSettings = function()
			return settings
		end,
	}
	local env = setmetatable({
		UIParent = screen,
		ObjectiveTrackerFrame = native,
		CreateFrame = frame,
		InCombatLockdown = function()
			return combat
		end,
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
		EventRegistry = { RegisterCallback = noop },
		Mixin = function(target, mixin)
			for key, value in pairs(mixin) do
				target[key] = value
			end
		end,
		CreateFramePoolCollection = function()
			return {}
		end,
	}, { __index = _G })
	env._G = env
	setfenv(assert(loadfile(os.getenv("TRACKER_HOST_SOURCE") or "UI/TrackerHost.lua")), env)("Test", ns)
	local host
	for _, f in ipairs(frames) do
		host = host or (f.name == "ForeverTrackerCompanion" and f) or nil
	end
	local api = ns.TrackerHost
	local content = 150
	local module = frame()
	module.uiOrder = 1
	module.SetContainer = function(self, container)
		self.parentContainer = container
	end
	module.Update = noop
	module.GetContentsHeight = function()
		return content
	end
	api.Attach(module)
	local function drain()
		for _ = 1, 4 do
			local pending = timers
			timers = {}
			for _, fn in ipairs(pending) do
				fn()
			end
		end
	end
	ready()
	drain()
	local label = ("ui %.2f, scale %.2f: "):format(uiScale, userScale)
	local nativeSlot = { "TOPRIGHT", screen, "TOPRIGHT", -24, -100 }
	local function nativeInOwnSlot()
		for i = 1, 5 do
			if native.point[i] ~= nativeSlot[i] then
				return false
			end
		end
		return true
	end

	-- Before Questie builds its tracker the column stacks in the native slot, as it always has.
	check(host.shown ~= false and not clears(host, questie), label .. "without the hook the column sat under Questie")
	check(not nativeInOwnSlot(), label .. "the native tracker is stacked below the column")

	-- Questie's frame appears after login: the next reflow finds it and moves the column clear of it.
	env.Questie_BaseFrame = questie
	host:MarkDirty()
	drain()
	check(host.shown ~= false and host.point[2] == questie, label .. "the column follows Questie's tracker")
	check(clears(host, questie), label .. "the column no longer sits behind Questie's list")
	check(host.point[1] == "TOPRIGHT" and host.point[3] == "BOTTOMRIGHT", label .. "below a right-side Questie")
	check(nativeInOwnSlot(), label .. "the native tracker goes back to its own slot")
	check(header.point[2] == native, label .. "the native header stays on the native tracker")
	check(questie.point[2] == screen and questie.width == 280, label .. "Questie's own frame is never moved or sized")
	for _, script in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do
		check(#(questie.hooks[script] or {}) == 1, label .. "Questie's " .. script .. " reflows the column once")
	end

	-- A tall list leaves no room below or above, so the column sits beside it.
	questie.height = 900
	questie:Fire("OnSizeChanged")
	check(#timers == 1, label .. "Questie's resize queues a reflow")
	drain()
	check(clears(host, questie), label .. "beside a tall Questie list")
	check(host.point[1] == "TOPRIGHT" and host.point[3] == "TOPLEFT", label .. "to the left of a right-side list")

	-- Near the bottom of the screen, the column goes above it instead.
	questie.height = 200
	questie:SetPoint("BOTTOMLEFT", screen, "BOTTOMLEFT", 24, 40)
	questie:Fire("OnSizeChanged")
	drain()
	check(clears(host, questie), label .. "above a low Questie list")
	check(host.point[1] == "BOTTOMLEFT" and host.point[3] == "TOPLEFT", label .. "aligned to a left-side list")

	-- Collapsing the empty native tracker does not hide the Forever sections while they follow Questie.
	native.isCollapsed = true
	host:MarkDirty()
	drain()
	check(host.shown ~= false and not host:IsCollapsed(), label .. "the native collapse does not hide them")
	native.isCollapsed = nil

	-- In combat the column still follows Questie: every frame it moves is addon-owned (native moves assert).
	questie:SetPoint("TOPRIGHT", screen, "TOPRIGHT", -24, -100)
	combat = true
	content = 220
	questie:Fire("OnSizeChanged")
	drain()
	check(clears(host, questie) and host.height == 230, label .. "the column follows Questie in combat")
	combat = false

	-- Hiding Questie's tracker brings the column back to the native slot.
	questie:Hide()
	questie:Fire("OnHide")
	drain()
	check(host.point[2] ~= questie and not nativeInOwnSlot(), label .. "with Questie hidden the column restacks")

	-- Questie appearing in combat waits while the native tracker is stacked: it cannot move until combat ends.
	combat = true
	questie:Show()
	questie:Fire("OnShow")
	drain()
	check(host.point[2] ~= questie, label .. "a stacked native tracker keeps the combat layout")
	combat = false
	host:MarkDirty()
	drain()
	check(host.point[2] == questie and nativeInOwnSlot(), label .. "after combat the column moves clear of Questie")

	-- Detached and not dragged yet, the column starts beside Questie's list, not the empty native tracker.
	native:SetPoint("TOPRIGHT", screen, "TOPRIGHT", -24, -300)
	api.SetAttached(false)
	drain()
	check(host.point[2] == screen and clears(host, questie), label .. "a detached column starts beside Questie")

	return api, settings, host
end

for _, case in ipairs({ { 1, 1 }, { 0.75, 1 }, { 1, 1.5 }, { 0.8, 0.75 } }) do
	scenario(case[1], case[2])
end

-- The optional background: off by default, an opacity slider capped at 80%, on the shared host settings. It is one
-- texture on the private host, so it changes straight away, in combat too.
local api, settings, host = scenario(1, 1)
local backdrop = host.textures and host.textures[1]
check(backdrop and #host.textures == 1, "the host owns one background texture")
check(api.GetBackground() == 0 and settings.background == 0, "no background by default")
check(backdrop.shown == false and backdrop.color[4] == 0, "the background starts hidden")
api.SetBackground(0.5)
check(settings.background == 0.5 and backdrop.shown and backdrop.color[4] == 0.5, "the slider shows the background")
check(backdrop.color[1] == 0 and backdrop.color[2] == 0 and backdrop.color[3] == 0, "the background is dark")
api.SetBackground(5)
check(api.GetBackground() == 0.8 and backdrop.color[4] == 0.8, "the background never goes solid")
api.SetBackground(-1)
check(api.GetBackground() == 0 and backdrop.shown == false, "zero hides the background")
api.SetBackground("x")
check(api.GetBackground() == 0 and backdrop.shown == false, "a malformed value turns the background off")
settings.background = 0 / 0
check(api.GetSettings().background == 0, "a NaN saved background is off")
print("tracker_host_compat_spec: " .. checks .. " checks passed")

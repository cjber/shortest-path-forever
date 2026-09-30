-- Resolve anchors recursively in screen pixels, including native screen clamping.
-- Nominal GetPoint anchors remain unchanged when Blizzard clamps a frame.
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
local function bounds(frame, seen)
	if frame.root then
		local scale = frame:GetEffectiveScale()
		return 0, frame.height * scale, frame.width * scale, frame.height * scale, 0
	end
	seen = seen or {}
	assert(not seen[frame], "anchor dependency cycle")
	seen[frame] = true
	local point, relative, relativePoint, x, y = unpack((assert(frame.point, "missing anchor")))
	local left, top, rw, _, relativeBottom = bounds(relative, seen)
	local rx, ry = fraction(relativePoint)
	local fx, fy = fraction(point)
	local scale = frame:GetEffectiveScale()
	local width, height = frame.width * scale, frame.height * scale
	left = left + rx * rw + (x or 0) * scale - fx * width
	local anchorY = ry == 0 and relativeBottom or ry == 1 and top or (top + relativeBottom) / 2
	local bottom = anchorY + (y or 0) * scale - fy * height
	top = fy == 1 and anchorY + (y or 0) * scale or bottom + height
	if frame.clamped then
		left = math.max(0, math.min(left, frame.screen.width * frame.screen:GetEffectiveScale() - width))
		local clampedTop = math.max(height, math.min(top, frame.screen.height * frame.screen:GetEffectiveScale()))
		if clampedTop ~= top then
			bottom = clampedTop - height
		end
		top = clampedTop
	end
	seen[frame] = nil
	return left, top, width, height, bottom
end
local function overlaps(a, b)
	local al, at, aw, _, ab = bounds(a)
	local bl, bt, bw, _, bb = bounds(b)
	return al < bl + bw and al + aw > bl and ab < bt and at > bb
end
local function scenario(anchor, scale, uiScale)
	local frames, timers, ready, combat = {}, {}, nil, false
	local screen
	local function frame(_, name, parent)
		local f = { name = name, parent = parent, width = 250, height = 1, scripts = {} }
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
			local left = bounds(self)
			return left / self:GetEffectiveScale()
		end
		function f:GetTop()
			local _, top = bounds(self)
			return top / self:GetEffectiveScale()
		end
		function f:GetRight()
			local left, _, width = bounds(self)
			return (left + width) / self:GetEffectiveScale()
		end
		function f:GetBottom()
			local _, _, _, _, bottom = bounds(self)
			return bottom / self:GetEffectiveScale()
		end
		function f:SetClampedToScreen(value)
			self.clamped, self.screen = value, screen
		end
		function f:SetScript(event, fn)
			self.scripts[event] = fn
		end
		function f:HookScript(event, fn)
			self.scripts[event] = fn
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
		f.SetMovable, f.RegisterForDrag, f.RegisterEvent = noop, noop, noop
		frames[#frames + 1] = f
		return f
	end
	screen = frame()
	screen.root, screen.width, screen.height, screen.scale = true, 1200, 1080, uiScale
	local native = frame(nil, "native", screen)
	native.scale, native.height = scale, 300
	native:SetClampedToScreen(true)
	local x = anchor:find("LEFT", 1, true) and 24 or anchor:find("RIGHT", 1, true) and -24 or 0
	local y = anchor:find("BOTTOM", 1, true) and 180 or -100
	native:SetPoint(anchor, screen, anchor, x, y)
	local rawPoint, rawClear, rawHeight = native.SetPoint, native.ClearAllPoints, native.SetHeight
	function native:SetPoint(...)
		assert(not combat, "protected combat reposition")
		rawPoint(self, ...)
	end
	function native:ClearAllPoints()
		assert(not combat, "protected combat clear")
		rawClear(self)
	end
	function native:SetHeight(value)
		assert(not combat, "protected combat resize")
		rawHeight(self, value)
	end
	local settings = { attached = true }
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
	local host = frames[3]
	local module = frame()
	module.uiOrder = -1
	module.SetContainer, module.Update = noop, noop
	module.GetContentsHeight = function()
		return 227
	end
	ns.TrackerHost.Attach(module)
	local function drain()
		local pending = timers
		timers = {}
		for _, fn in ipairs(pending) do
			fn()
		end
	end
	ready()
	drain()
	local left, top = bounds(native)
	local _, hostTop, _, hostHeight = bounds(host)
	check(math.abs(top - (hostTop - hostHeight)) < 0.01, "native starts below guide at effective scale")
	for _ = 1, 3 do
		host:MarkDirty()
		drain()
	end
	local nextLeft, nextTop = bounds(native)
	check(math.abs(left - nextLeft) < 0.01 and math.abs(top - nextTop) < 0.01, "repeated layout does not drift")
	combat = true
	rawHeight(native, 800)
	host.scripts.OnEvent(host, "PLAYER_REGEN_DISABLED")
	drain()
	check(
		not overlaps(host, native),
		"combat height clamp must not overlap guide and objectives: "
			.. anchor
			.. " scale "
			.. scale
			.. " ui "
			.. uiScale
			.. " host "
			.. table.concat({ bounds(host) }, ",")
			.. " native "
			.. table.concat({ bounds(native) }, ",")
			.. " hp "
			.. tostring(host.point[1])
	)
	local nl, nt = bounds(native)
	for _ = 1, 3 do
		host:MarkDirty()
		drain()
	end
	local settledLeft, settledTop = bounds(native)
	check(
		math.abs(nl - settledLeft) < 0.01 and math.abs(nt - settledTop) < 0.01,
		"moving guide cannot move native tracker"
	)
	check(not overlaps(host, native), "repeated combat refresh stays separated")
	combat = false
	host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
	drain()
	ns.TrackerHost.SetAttached(false)
	drain()
	local p, rel, rp, restoredX, restoredY = native:GetPoint()
	check(
		p == anchor and rel == screen and rp == anchor and restoredX == x and restoredY == y,
		"detach restores original edit mode anchor"
	)
end
for _, scale in ipairs({ 0.75, 1, 1.25 }) do
	for _, anchor in ipairs({ "TOPRIGHT", "TOPLEFT", "TOP", "CENTER", "BOTTOM", "BOTTOMRIGHT" }) do
		scenario(anchor, scale, 1)
		scenario(anchor, scale, 0.8)
	end
end
print("tracker_geometry_spec: " .. checks .. " checks passed")

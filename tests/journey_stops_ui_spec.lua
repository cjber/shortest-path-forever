-- Native templates are represented by stateful client stubs, not a client capture.
-- The real shared Core art module is loaded through the same Core harness as other specs.
local frames, timers = {}, {}
local function region()
	local r = { points = {} }
	function r:SetPoint(...)
		self.points[#self.points + 1] = { ... }
	end
	function r:ClearAllPoints()
		self.points = {}
	end
	function r:SetText(value)
		self.text = value
	end
	function r:GetText()
		return self.text
	end
	function r:SetSize(w, h)
		self.width, self.height = w, h
	end
	function r:SetTexCoord(...)
		self.coords = { ... }
	end
	function r:SetTexture(value)
		self.texture = value
	end
	function r.SetJustifyH() end
	return r
end
local function frame(kind, name, parent, template)
	local f = region()
	f.kind, f.name, f.parent, f.template = kind, name, parent, template
	f.scripts, f.children, f.shown, f.enabled = {}, {}, true, true
	function f:SetScript(event, fn)
		self.scripts[event] = fn
	end
	function f:SetHeight(h)
		self.height = h
	end
	function f:SetWidth(w)
		self.width = w
	end
	function f:SetEnabled(enabled)
		self.enabled = enabled
	end
	function f:SetChecked(checked)
		self.checked = checked
	end
	function f:GetChecked()
		return self.checked
	end
	function f:SetScrollChild(child)
		self.child = child
	end
	function f:SetVerticalScroll(offset)
		self.offset = offset
	end
	function f:GetVerticalScroll()
		return self.offset or 0
	end
	function f:SetTitle(title)
		self.title = title
	end
	function f:GetPortrait()
		self.portrait = self.portrait or region()
		return self.portrait
	end
	function f:SetFrameStrata(value)
		self.strata = value
	end
	function f.SetClampedToScreen() end
	function f:RegisterEvent(event)
		self.events = self.events or {}
		self.events[event] = true
	end
	function f:UnregisterAllEvents()
		self.events = {}
	end
	function f:LockHighlight()
		self.highlighted = true
	end
	function f:UnlockHighlight()
		self.highlighted = false
	end
	function f:IsShown()
		return self.shown and (not self.parent or not self.parent.IsShown or self.parent:IsShown())
	end
	function f:Show()
		local changed = not self.shown
		self.shown = true
		if changed and self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
	end
	function f:Hide()
		local changed = self.shown
		self.shown = false
		if changed and self.scripts.OnHide then
			self.scripts.OnHide(self)
		end
	end
	function f:Click()
		if not self.enabled or not self:IsShown() then
			return
		end
		if self.kind == "CheckButton" then
			self.checked = not self.checked
		end
		self.scripts.OnClick(self)
	end
	function f:CreateFontString()
		local text = region()
		self.children[#self.children + 1] = text
		return text
	end
	frames[#frames + 1] = f
	return f
end
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
local dead, combat = false, false
env.CreateFrame, env.UISpecialFrames, env.UIParent = frame, {}, {}
env.InCombatLockdown = function()
	return combat
end
env.UnitIsDeadOrGhost = function()
	return dead
end
env.C_Timer = {
	After = function(_, fn)
		timers[#timers + 1] = fn
	end,
}
env.C_AddOns = {
	GetAddOnMetadata = function()
		return "Interface\\AddOns\\ShortestPathForever\\media\\Icon"
	end,
}
driver.load("UI/Looks.lua")
driver.load("UI/Art.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
driver.load("Journey/StopOrder.lua")
driver.load("UI/JourneyStops.lua")
local checks = 0
local function eq(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function find(text)
	for _, f in ipairs(frames) do
		if f.text == text then
			return f
		end
	end
	error("Missing control " .. text)
end
local function flush()
	local pending = timers
	timers = {}
	for _, fn in ipairs(pending) do
		fn()
	end
end
local function waypoint(x)
	env.C_Map.SetUserWaypoint({ uiMapID = 1, position = { x = x, y = 0.5 } })
end
ns.ShowJourneyStops()
local window, scroll
for _, f in ipairs(frames) do
	if f.name == "ShortestPathForeverJourneyStops" then
		window = f
	end
	if f.kind == "ScrollFrame" then
		scroll = f
	end
	eq(f.scripts.OnUpdate, nil, "no idle UI loop")
end
eq(window.template, "PortraitFrameTemplate", "native host")
eq(window.width, 560, "host width")
eq(window.height, 560, "host height")
eq(#env.UISpecialFrames, 1, "Escape registration")
eq(find("Start").enabled, false, "empty start disabled")
waypoint(0.502)
find("Add map waypoint"):Click()
eq(find("Start").enabled, true, "native waypoint added")
waypoint(0.503)
find("Add map waypoint"):Click()
find("Up"):Click()
find("Down"):Click()
find("Remove"):Click()
find("Clear"):Click()
eq(find("Start").enabled, false, "clear")
combat = true
window.scripts.OnEvent(window, "PLAYER_REGEN_DISABLED")
eq(find("Start").enabled, false, "combat event disables start")
combat = false
window.scripts.OnEvent(window, "PLAYER_REGEN_ENABLED")
eq(find("Start").enabled, false, "empty draft still disabled after combat")
-- Default automatic order runs one real Estimate on each deferred frame.
waypoint(0.502)
find("Add map waypoint"):Click()
waypoint(0.503)
find("Add map waypoint"):Click()
dead = true
window.scripts.OnEvent(window, "PLAYER_DEAD")
eq(find("Start").enabled, false, "death event disables start")
dead = false
window.scripts.OnEvent(window, "PLAYER_UNGHOST")
eq(find("Start").enabled, true, "alive event restores start without polling")
local api, estimates = env.ShortestPathForever.API, 0
debug.sethook(function(event)
	if event == "call" and debug.getinfo(2, "f").func == api.Estimate then
		estimates = estimates + 1
	end
end, "c")
find("Start"):Click()
eq(estimates, 0, "start never bursts estimates")
eq(ns.HasJourney(), false, "order first")
for _ = 1, 3 do
	local before = estimates
	flush()
	eq(estimates - before <= 1, true, "one estimate per deferred frame")
end
debug.sethook()
eq(ns.HasJourney(), true, "finite ordinary journey submitted")
eq(find("Add map waypoint").enabled, false, "own route locks editing")
find("Pause"):Click()
eq(find("Resume").enabled, true, "paused controls")
find("Resume"):Click()
find("Close"):Click()
eq(ns.HasJourney(), true, "close preserves guidance")
local count = #frames
ns.ShowJourneyStops()
eq(#frames, count, "reopen reuses host and rows")
eq(find("Pause").enabled, true, "reopen observes same route")
find("Stop"):Click()
eq(ns.HasJourney(), false, "stop owns cancellation")
eq(find("Start").enabled, true, "stop retains draft")
-- Close cancels pending ordering; stale callbacks cannot submit when reopened.
find("Start"):Click()
find("Close"):Click()
ns.ShowJourneyStops()
for _ = 1, 5 do
	flush()
end
eq(ns.HasJourney(), false, "hidden order cancelled")
-- A route that arrives while hidden is observed accurately on reopening.
find("Start"):Click()
for _ = 1, 3 do
	flush()
end
find("Close"):Click()
driver.move({ map = 1, x = 0, y = -100, z = 0 })
for _ = 1, 3 do
	driver.update(0.1)
end
driver.move({ map = 1, x = 0, y = -150, z = 0 })
for _ = 1, 3 do
	driver.update(0.1)
end
ns.ShowJourneyStops()
eq(ns.HasJourney(), false, "hidden finite route completes")
eq(find("Stop").enabled, false, "terminal controls cleared")
-- External replacement is protected even after a queued automatic Start.
find("Start"):Click()
eq(api.Navigate("External", 1, 0.52, 0.5), true, "external arrives during order")
for _ = 1, 4 do
	flush()
end
eq(api.CurrentStop("External"), 1, "queued start preserves external owner")
eq(find("Start").enabled, false, "external disables start")
eq(find("Stop").enabled, false, "external cannot be stopped")
api.Cancel("External")
flush()
-- Overflow uses the native scroll child without moving the host.
find("Clear"):Click()
for i = 1, 30 do
	waypoint(0.5 + i / 1000)
	find("Add map waypoint"):Click()
end
scroll:SetVerticalScroll(90)
local height = window.height
find("Up"):Click()
eq(scroll:GetVerticalScroll(), 90, "reorder preserves scroll")
eq(window.height, height, "reorder preserves host height")
eq(scroll.child.height >= 30 * 28, true, "overflow scroll content")
find("Close"):Click()
for _ = 1, 3 do
	flush()
end
eq(#timers, 0, "closed controller leaves no timer chain")
eq(next(window.events), nil, "hidden window unregisters native events")
eq(api.Navigate("Hidden external", 1, 0.52, 0.5), true, "journey changes while editor hidden")
eq(#timers, 0, "hidden editor has unsubscribed from API changes")
api.Cancel("Hidden external")
eq(#timers, 0, "hidden cancellation schedules no UI refresh")
print("journey_stops_ui_spec: " .. checks .. " checks passed")

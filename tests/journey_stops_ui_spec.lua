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
	function f.SetToplevel() end
	function f:SetMovable(value)
		self.movable = value
	end
	function f:EnableMouse(value)
		self.mouseEnabled = value
	end
	function f:RegisterForDrag(button)
		self.dragButton = button
	end
	function f:StartMoving()
		self.moving = true
	end
	function f:StopMovingOrSizing()
		self.moving = false
	end
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
ns.db.mapPinRoutes = false
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
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
driver.load("Journey/Resume.lua")
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
	-- The frame's path jobs run after its timers, as the pump's do.
	driver.path.runAll()
end
local function waypoint(x)
	env.C_Map.SetUserWaypoint({ uiMapID = 1, position = { x = x, y = 0.5 } })
end
local function trackedWaypoint(x)
	waypoint(x)
	env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
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
eq(window.movable and window.mouseEnabled and window.dragButton, "LeftButton", "window can be dragged")
window.scripts.OnDragStart(window)
eq(window.moving, true, "drag moves the window off the map")
window.scripts.OnDragStop(window)
eq(window.moving, false, "release places the window")
eq(find("Start").enabled, false, "empty start disabled")
local controller = ns.JourneyStopsEditor.Current()
find("Close"):Click()
waypoint(0.502)
ns.ShowJourneyStops()
eq(#controller.stops, 0, "opening does not add the existing pin")
find("Add map waypoint"):Click()
eq(find("Start").enabled, true, "the Add button still takes the existing pin")
waypoint(0.503)
eq(#controller.stops, 2, "placing a pin adds a stop with pin routing off")
eq(ns.HasJourney(), false, "a pin added to the list starts no journey with routing off")
eq(window.children[2].text:find("Place pins on the map to add stops.", 1, true), 1, "the window explains pin capture")
eq(controller.stops[2].x, 0.503, "the placed pin's coordinates are saved")
eq(ns.charDB.journeyStops.stops[2].x, 0.503, "captured stops persist through the draft save")
eq(find(("2. %s (50.3, 50.0)"):format(controller.stops[2].title)):IsShown(), true, "the new row appears immediately")
waypoint(0.503)
eq(#controller.stops, 2, "the same pin reported twice adds one stop")
eq(controller.state, "idle", "a duplicate report does not disturb the editor")
env.C_Map.ClearUserWaypoint()
eq(#controller.stops, 2, "clearing a pin does not remove a captured stop")
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
waypoint(0.503)
dead = true
window.scripts.OnEvent(window, "PLAYER_DEAD")
eq(find("Start").enabled, false, "death event disables start")
dead = false
window.scripts.OnEvent(window, "PLAYER_UNGHOST")
eq(find("Start").enabled, true, "alive event restores start without polling")
ns.db.mapPinRoutes = true
find("Close"):Click()
waypoint(0.504)
flush()
local pinGoal = ns.JourneyGoal()
eq(pinGoal ~= nil, true, "a pin placed while closed starts a player journey")
ns.ShowJourneyStops()
eq(#controller.stops, 2, "the closed window did not capture the pin")
eq(find("Start").enabled, true, "a player journey leaves Start enabled")
waypoint(0.505)
eq(#controller.stops, 3, "placing a pin adds a stop with pin routing on")
eq(ns.JourneyGoal(), pinGoal, "adding a stop preserves the running player journey")
find("Remove"):Click()
ns.db.mapPinRoutes = false
local api, estimates = env.ShortestPathForever.API, 0
debug.sethook(function(event)
	local func = debug.getinfo(2, "f").func
	if event == "call" and (func == api.Estimate or func == ns.EstimateIn) then
		estimates = estimates + 1
	end
end, "c")
find("Start"):Click()
eq(estimates, 0, "start never bursts estimates")
eq(ns.JourneyGoal(), pinGoal, "the pin journey continues while stops are ordered")
for _ = 1, 3 do
	local before = estimates
	flush()
	eq(estimates - before <= 1, true, "one estimate per deferred frame")
end
debug.sethook()
eq(ns.HasJourney(), true, "finite ordinary journey submitted")
eq(ns.JourneyGoal() == pinGoal, false, "the ordered journey replaces the pin journey")
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
ns.JourneyStopsEditor.Restore({ { map = 1, x = 0.504, y = 0.5, title = "Remaining" } })
ns.ShowJourneyStops()
eq(window.children[2].text:find("Stop 1 of 1.", 1, true), 1, "progress counts the remaining route")
eq(find("1. Remaining (50.4, 50.0)"):IsShown(), true, "the remaining route is visible")
eq(find("Pause").enabled, true, "resumed route can be paused")
find("Pause"):Click()
eq(find("Resume").enabled, true, "resumed route can be resumed from pause")
find("Stop"):Click()
eq(ns.HasJourney(), false, "resumed route can be stopped")
driver.move({ map = 1, x = 0, y = 0, z = 0 })
ns.JourneyStopsEditor.Restore({
	{ map = 1, x = 0.502, y = 0.5, title = "Near" },
	{ map = 1, x = 0.504, y = 0.5, title = "Far" },
})
driver.path.settle()
driver.move({ map = 1, x = 0, y = -100, z = 0 })
for _ = 1, 4 do
	driver.update(0.1)
end
find("Close"):Click()
ns.ShowJourneyStops()
eq(window.children[2].text:find("Stop 2 of 2.", 1, true), 1, "progress follows the next stop")
find("Stop"):Click()

-- The native pin and its later super-tracking report must both leave a guided player route in progress.
find("Clear"):Click()
ns.db.mapPinRoutes = true
ns.StartJourney({ map = 1, x = 0, y = -1200 })
local guidedGoal = ns.JourneyGoal()
local placeGuidePin
ns.PointGuideArrow = function(_, place)
	placeGuidePin = place
end
ns.JourneyGuide.To(guidedGoal, { guidedGoal }, guidedGoal)
assert(placeGuidePin(guidedGoal), "the journey writes its native guide pin")
eq(#controller.stops, 0, "Shortest Path's synchronous guide pin is not a stop")
trackedWaypoint(0.506)
driver.update(0)
eq(#controller.stops, 1, "placing a player pin next to a guide pin adds one stop")
eq(ns.JourneyGoal(), guidedGoal, "a player pin leaves the original goal in place")
eq(ns.IsJourneyGuided(), true, "the current route keeps its guidance")
eq(env.C_Map.GetUserWaypoint().position.x, 0.506, "guidance leaves the placed pin in the slot")
-- The player removes the captured pin.
env.C_SuperTrack.SetSuperTrackedUserWaypoint(false)
env.C_Map.ClearUserWaypoint()
driver.update(0)
eq(ns.IsJourneyGuided(), true, "removing a captured pin keeps the route guided")
eq(ns.JourneyGoal(), guidedGoal, "removing a captured pin keeps the goal")
trackedWaypoint(0.506)
driver.update(0)
ns.ClearJourney()
eq(env.C_SuperTrack.IsSuperTrackingUserWaypoint(), true, "ending guidance leaves the captured pin tracked")
ns.PointGuideArrow = function() end

-- Explicit actions keep planning a journey while the window is open.
eq(ns.JourneyToUserWaypoint(), true, "the map pin binding still starts a journey")
eq(ns.JourneyGoal().y < -299, true, "the binding routes to the captured pin")
eq(#controller.stops, 1, "the binding does not add a stop")
for _, key in ipairs({ "shift", "alt" }) do
	ns.db.journeyKey = key
	env.IsShiftKeyDown = function()
		return key == "shift"
	end
	env.IsAltKeyDown = function()
		return key == "alt"
	end
	local before = ns.JourneyGoal()
	eq(driver.click({ map = 1, x = 0, y = -500 }), true, key .. "-click is handled")
	eq(ns.JourneyGoal() ~= before, true, key .. "-click still starts a journey")
	eq(#controller.stops, 1, key .. "-click does not add a stop")
end
ns.ClearJourney()

for _, paused in ipairs({ false, true }) do
	find("Close"):Click()
	assert(ns.JourneyStopsEditor.Restore({ { map = 1, x = 0.509, y = 0.5 } }))
	ns.ShowJourneyStops()
	if paused then
		find("Pause"):Click()
		eq(find("Resume").enabled, true, "the route is paused before placing a pin")
	end
	eq(find("Add map waypoint").enabled, false, "the active route locks the list")
	local old = ns.JourneyGoal()
	waypoint(paused and 0.508 or 0.507)
	eq(#controller.stops, 1, "a locked list never captures pins")
	eq(ns.JourneyGoal() ~= old, true, "a locked list leaves pin routing enabled")
	ns.ClearJourney()
end

-- RestedXP records its ownership after the client's synchronous waypoint event.
driver.load("Core/RestedXP.lua")
local element = { zone = 1 }
env.RXP = { RXPFrame = { activeSteps = { { elements = { element } } } } }
flush()
find("Clear"):Click()
eq(#controller.stops, 0, "the RestedXP case starts with an empty draft")
trackedWaypoint(0.51)
eq(#controller.stops, 0, "the editor waits for RestedXP's ownership record")
local position = env.C_Map.GetUserWaypointPositionForMap(element.zone)
element.waypointSet, element.zx, element.zy = true, position.x, position.y
driver.update(0)
flush()
eq(#controller.stops, 0, "the deferred RestedXP step pin is not a stop")
eq(ns.HasJourney(), false, "the RestedXP step pin starts no player journey")
trackedWaypoint(0.511)
waypoint(0.511)
eq(#controller.stops, 0, "an unclaimed pin waits for the same ownership decision")
driver.update(0)
flush()
eq(#controller.stops, 1, "a deferred player pin is added after RestedXP declines ownership")
eq(controller.state, "idle", "duplicate held reports do not disturb the editor")
eq(ns.HasJourney(), false, "the deferred player pin starts no journey")

-- A journey that ends inside the held frame does not drop the pin from the list.
ns.StartJourney({ map = 1, x = 0, y = -1200 })
waypoint(0.5115)
ns.ClearJourney()
driver.update(0)
flush()
eq(#controller.stops, 2, "a held pin survives the journey ending in the same frame")
find("Remove"):Click()

find("Close"):Click()
waypoint(0.512)
ns.ShowJourneyStops()
flush()
eq(#controller.stops, 1, "a pin placed before opening stays out of the list even when its report is held")
eq(ns.HasJourney(), true, "the held pin placed while closed keeps ordinary pin routing")
ns.ClearJourney()
waypoint(0.513)
find("Close"):Click()
ns.ShowJourneyStops()
flush()
eq(#controller.stops, 1, "a held report from a previous opening does not add to the reopened window")
eq(ns.HasJourney(), true, "a held report after closing keeps ordinary pin routing")
print("journey_stops_ui_spec: " .. checks .. " checks passed")

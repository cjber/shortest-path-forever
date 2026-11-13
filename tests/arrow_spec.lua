-- A frame callback already queued by the client can run after guidance has stopped.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, frame = driver.ns, nil
local env = driver.env
local create = env.CreateFrame
local createFontString
env.CreateFrame = function(...)
	frame = create(...)
	createFontString = createFontString or frame.CreateFontString
	frame.CreateFontString = function(self, ...)
		local text = createFontString(self, ...)
		local setText = text.SetText
		text.SetText = function(fontString, value)
			fontString.text = value
			fontString.sets = (fontString.sets or 0) + 1
			return setText(fontString, value)
		end
		return text
	end
	frame.GetEffectiveScale = function(self)
		return self.scale or 1
	end
	frame.SetScale = function(self, scale)
		self.scale = scale
	end
	frame.SetPoint = function(self, ...)
		self.point = { ... }
	end
	frame.GetCenter = function(self)
		return self.centerX, self.centerY
	end
	-- As the client does: setting a mouse script or registering for drag turns the frame's mouse on.
	local setScript = frame.SetScript
	frame.SetScript = function(self, name, fn)
		setScript(self, name, fn)
		if fn and (name:find("^OnMouse") or name == "OnEnter" or name == "OnLeave" or name:find("^OnDrag")) then
			self.mouse = true
		end
	end
	frame.RegisterForDrag = function(self)
		self.mouse = true
	end
	frame.EnableMouse = function(self, enabled)
		self.mouse = enabled
	end
	frame.IsMouseEnabled = function(self)
		return self.mouse == true
	end
	frame.SetShown = function(self, shown)
		if shown then
			self:Show()
		else
			self:Hide()
		end
	end
	return frame
end
driver.load("UI/Art.lua")
driver.load("UI/Mover.lua")
driver.load("UI/TurnAround.lua")
driver.load("UI/Arrow.lua")
local points = { { map = 1, x = 0, y = 0 }, { map = 1, x = 200, y = 0 } }
local placed = 0
local function place()
	placed = placed + 1
end
ns.PointGuideArrow(points, place)
assert(placed == 1 and not frame.hidden, "a live route updates its arrow")
local queued = frame.OnUpdate
ns.PointGuideArrow(nil)
queued(frame, 0.1)
assert(frame.hidden and placed == 1 and ns.GuideTargets() == nil, "a queued tick cannot revive cleared guidance")

ns.RefreshCompass = function()
	ns.RefreshCompass = nil
	ns.PointGuideArrow(nil)
end
ns.PointGuideArrow(points, place)
assert(frame.hidden and ns.GuideTargets() == nil, "a nested stop during compass refresh wins")
queued(frame, 0.1)

local replacement = { { map = 1, x = 400, y = 100 } }
ns.PointGuideArrow(points, function()
	ns.PointGuideArrow(replacement, place)
	return true
end)
assert(ns.GuideTargets() == replacement[1] and not frame.hidden, "replacement inside waypoint placement wins")
ns.PointGuideArrow(points, function()
	ns.PointGuideArrow(nil)
end)
assert(frame.hidden and ns.GuideTargets() == nil, "stopping inside waypoint placement leaves the arrow hidden")
queued(frame, 0.1)
ns.PointGuideArrow({}, place)
queued(frame, 0.1)
assert(frame.hidden, "empty routes leave no active arrow")
ns.PointGuideArrow(replacement, place)
assert(not frame.hidden and ns.GuideTargets() == replacement[1], "guidance can restart after cancellation")
local near = { { map = 1, x = 10, y = 0 } }
local nativeHidden
ns.PointGuideArrow(near, function(_, hidden)
	nativeHidden = hidden
	return false
end)
assert(frame.alpha == 1 and nativeHidden == false, "arrow remains visible at the destination")

-- The game's marker leads only while the client draws it: with in-game navigation off, which Camelot has no setting
-- for, the client keeps the marker at no alpha, so the arrow stays.
local cvars = { showInGameNavigation = "1" }
env.GetCVarBool = function(name)
	return cvars[name] == "1"
end
env.C_Navigation = {
	GetFrame = function()
		return {}
	end,
}
local function native()
	return true
end
ns.PointGuideArrow(replacement, native)
assert(frame.alpha == 0, "the game's marker leads while it is drawn")
cvars.showInGameNavigation = "0"
ns.PointGuideArrow(points, native)
assert(frame.alpha == 1, "with in-game navigation off, the arrow leads")
env.C_Navigation = { GetFrame = function() end }

-- It eases round to a new bearing over a few frames, by the shorter way, as the compass does.
local facing = 0
env.GetPlayerFacing = function()
	return facing
end
ns.PointGuideArrow({ { map = 1, x = 0, y = 200 } }, place)
assert(frame.angle, "an angle is drawn")
local settled = frame.angle
facing = 1
frame.OnUpdate(frame, 1 / 60)
local eased = frame.angle
assert(math.abs(eased - settled) > 0 and math.abs(eased - settled) < 1, "a turn eases, not jumps")
for _ = 1, 120 do
	frame.OnUpdate(frame, 1 / 60)
end
-- Due north of you with your back turned one radian: the bearing is a quarter turn less one.
assert(math.abs(((frame.angle - (math.pi / 2 - 1)) + math.pi) % (2 * math.pi) - math.pi) < 0.01, "and settles on it")
-- Still and settled, it stops its every-frame update and only the slow poll runs.
for _ = 1, 30 do
	if rawget(frame, "OnUpdate") then
		frame.OnUpdate(frame, 1 / 60)
	end
end
assert(rawget(frame, "OnUpdate") == nil, "a still, settled arrow has no OnUpdate")

-- Facing away: the whole arrow window dims to DestinationPin's behind alpha, with the same 120/100 hysteresis as
-- the compass, and returns when the bend is ahead again.
driver.move({ map = 1, x = 0, y = 0, z = 0 })
ns.PointGuideArrow({ { map = 1, x = 0, y = 0 }, { map = 1, x = 100, y = 0 } }, place)
local function face(degrees)
	facing = degrees * math.pi / 180
	frame.OnUpdate(frame, 1 / 60)
end
face(130)
assert(frame.alpha == 0.4, "past 120 degrees the arrow window dims")
face(110)
assert(frame.alpha == 0.4, "once dimmed it is kept at 110 degrees")
face(100.1)
assert(frame.alpha == 0.4, "and just past 100 degrees it is still kept")
face(99)
assert(frame.alpha == 1, "under 100 degrees it returns to full strength")
face(110)
assert(frame.alpha == 1, "and it does not dim until the bend is past 120 again")
face(130)
assert(frame.alpha == 0.4, "past 120 degrees it dims again")

-- Move the arrow: dragged, saved in screen pixels, scaled, and reset with a right-click.
assert(not frame.mouse, "click-through until Move the arrow is on")
ns.MoveArrow(true)
assert(frame.mouse, "takes the mouse while it is being placed")
assert(ns.ArrowMoving() and not frame.hidden and frame.alpha == 1, "shown to be dragged")
frame.centerX, frame.centerY = 300, 400
frame.OnDragStop(frame)
assert(ns.db.arrowX == 300 and ns.db.arrowY == 400, "the place is saved")
assert(frame.point[1] == "CENTER" and frame.point[4] == 300 and frame.point[5] == 400)
ns.SetArrowScale(200)
assert(frame.scale == 2 and frame.point[4] == 150 and frame.point[5] == 200, "a bigger arrow keeps its place on screen")
ns.SetArrowScale(100)
frame.OnMouseUp(frame, "RightButton")
assert(ns.db.arrowX == nil and frame.point[1] == "TOP", "right-click puts it back")
ns.MoveArrow(false)
assert(not ns.ArrowMoving() and not frame.mouse, "click-through again once placed")
-- With the arrow turned off, finishing moving it hides it again even mid-journey.
ns.db.arrow = false
ns.PointGuideArrow({ { map = 1, x = 0, y = 200 } }, place)
ns.MoveArrow(true)
ns.MoveArrow(false)
assert(frame.hidden, "a turned-off arrow goes away after moving it")
ns.db.arrow = true
-- The label can show the journey's time left, or both, with the same time the tracker's header shows.
local clock = 0
env.GetTime = function()
	return clock
end
local journeyTime = "2:32"
ns.JourneyLeft = function()
	return journeyTime, "1.1k yd"
end
local function ArrowText(value)
	ns.SetArrowLabel(value)
	return frame.Distance.text
end
driver.move({ map = 1, x = 0, y = 0, z = 0 })
facing = 0
clock = 100
local labelPoints = { { map = 1, x = 0, y = 0 }, { map = 1, x = 200, y = 0 } }
ns.PointGuideArrow(labelPoints, place)
assert(frame.Distance.text == "200 yd", "the arrow's label starts with the distance")
assert(ArrowText("distance") == "200 yd", "the distance choice keeps the distance alone")
assert(ArrowText("time") == "2:32", "the time choice shows the header's time left")
assert(ArrowText("both") == "2:32 · 200 yd", "both puts the time first, then the distance")
journeyTime = nil
assert(ArrowText("time") == "200 yd" and ArrowText("both") == "200 yd", "with no time yet, the distance stands alone")
journeyTime = "2:32"
assert(ArrowText("time") == "2:32")
local sets = frame.Distance.sets
journeyTime = "2:31"
clock = 101
frame.OnUpdate(frame, 0.1)
assert(frame.Distance.text == "2:31", "the label follows the time as it counts down")
assert(frame.Distance.sets == sets + 1, "a changed label is written once")
sets = frame.Distance.sets
frame.OnUpdate(frame, 0.1)
assert(frame.Distance.sets == sets, "a label that has not changed is not written again")
-- No route: no every-frame update.
ns.PointGuideArrow(nil)
frame.OnUpdate(frame, 1 / 60)
assert(rawget(frame, "OnUpdate") == nil, "nothing to point at, nothing every frame")
-- "Mark only where steps end" thins the map marks, never the walk the arrow follows: the arrow still points at the
-- next bend while the map and compass mark the step's end (#817).
driver.move({ map = 1, x = 0, y = 0, z = 0 })
facing = 0
ns.db.guideStops = true
ns.SetArrowLabel("distance")
local marks = {}
local bends = { { map = 1, x = 0, y = 0 }, { map = 1, x = 200, y = 0 }, { map = 1, x = 200, y = 200 } }
frame.angle = nil
ns.PointGuideArrow(bends, function(point)
	marks[#marks + 1] = point
	return false
end)
assert(math.abs(frame.angle) < 1e-9, "the arrow points at the next bend, not the step's end")
assert(frame.Distance.text == "400 yd", "the distance counts the walk to the step's end, bend by bend")
assert(marks[#marks] == bends[#bends], "the map still marks only the step's end")
assert(select(1, ns.GuideTargets()) == bends[#bends], "the compass marks only the step's end too")
print("arrow_spec: ok")

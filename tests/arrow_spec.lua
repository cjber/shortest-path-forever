-- A frame callback already queued by the client can run after guidance has stopped.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, frame = driver.ns, nil
local env = driver.env
local create = env.CreateFrame
local createFontString, createTexture
env.CreateFrame = function(...)
	frame = create(...)
	createFontString = createFontString or frame.CreateFontString
	createTexture = createTexture or frame.CreateTexture
	frame.CreateTexture = function(self, ...)
		local texture = createTexture(self, ...)
		texture.SetTexture = function(drawn, file)
			drawn.texture = file
		end
		texture.SetTexCoord = function(drawn, ...)
			drawn.coords = { ... }
		end
		texture.SetSize = function(drawn, width, height)
			drawn.width, drawn.height = width, height
		end
		return texture
	end
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
driver.load("UI/CastButton.lua")
driver.load("UI/Arrow.lua")

-- Clearing or disabling guidance must also work before the lazy arrow frame exists.
ns.PointGuideArrow(nil)
assert(frame == nil, "clearing initial guidance must not create an arrow")
ns.db.arrow = false
ns.PointGuideArrow({ { map = 1, x = 200, y = 0 } })
assert(frame == nil, "initial disabled guidance must not create an arrow")
ns.db.arrow = true
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

-- Turning directions off must also retire callbacks the client already queued (#881).
ns.PointGuideArrow(points, place)
local beforeOff, queuedOff = placed, frame.OnUpdate
ns.db.arrow = false
ns.PointGuideArrow(points, place)
queuedOff(frame, 0.1)
assert(placed == beforeOff, "a queued tick with the arrow off cannot place a native marker")
assert(frame.hidden and rawget(frame, "OnUpdate") == nil, "disabled directions stop their frame callback")
ns.db.arrow = true
ns.PointGuideArrow(points, place)
assert(placed == beforeOff + 1 and not frame.hidden, "directions resume when enabled again")

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
assert(marks[#marks] == bends[2], "the guide marks the bend the arrow is walking to, not the step's end")
assert(select(1, ns.GuideTargets()) == bends[#bends], "the compass marks only the step's end too")
-- #904: direct bearing is independent of route progress and map marker density.
local goal = { map = 1, x = 300, y = 400 }
ns.PointGuideArrow(bends, function(point)
	marks[#marks + 1] = point
	return false
end, { number = 3 }, goal)
ns.db.arrowDirect = true
frame.angle = nil
ns.ArrowBearingChanged()
assert(frame.Distance.text == "500 yd", "direct distance goes to the final destination, not along the walk")
assert(marks[#marks] == goal, "native guidance uses the same direct destination")
assert(math.abs(frame.angle - math.atan2(400, 300)) < 1e-9, "direct bearing goes to the final destination")
local guideTarget, source, canonical = ns.GuideState()
assert(guideTarget == bends[2] and source == bends and canonical == 2, "direct arrow preserves route guidance")
ns.db.guideStops = false
ns.GuideStopsChanged()
assert(frame.Distance.text == "500 yd", "map mark density does not change direct distance")
assert(select(1, ns.GuideTargets()) == bends[2], "map marks still follow their own setting")
ns.PointGuideArrow(bends, nil, { kind = "dock" }, { map = 2, x = 300, y = 400 })
assert(frame.Distance.text == "282 yd", "a destination across maps points to the active travel step")
ns.db.arrowDirect = false
ns.ArrowBearingChanged()
assert(frame.Distance.text == "400 yd", "route mode restores remaining walking distance")
ns.db.guideStops = true

-- The arrow turns around the next step's numbered marker, the compass's own art; a target with no number wears
-- ForeverCore's ring and diamond (#817).
ns.db.guideStops = false
ns.PointGuideArrow(bends, place, { number = 3 })
assert(frame.Icon.texture == ns.NumberFile(3), "the centre wears the step's numbered marker")
assert(frame.Icon.width == 32 and frame.Icon.height == 32, "at the marker's native 64 pixels")
ns.PointGuideArrow(bends, place, { label = "A corpse" })
assert(frame.Icon.texture == env.ForeverCore.Art.Diamond(), "a target with no step number wears the ring and diamond")
assert(frame.Icon.width == 32 and frame.Icon.height == 32, "at the shared marker's own 64 pixels")
-- The setting swaps which pointer leads at once, not at the next poll.
local pointed = placed
ns.db.guideStops = true
ns.GuideStopsChanged()
assert(placed == pointed + 1, "changing the setting re-points the arrow and the guide's marker at once")
-- Exercise the native placement callback too: disabling clears the owned waypoint, and a queued tick cannot
-- write it back. The same route resumes normally when directions are enabled.
ns.db.guideStops = false
ns.JourneyGuide.Start()
local nativeGoal = { map = 1, x = 1200, y = 0 }
ns.JourneyGuide.To(nativeGoal, { nativeGoal }, nativeGoal)
assert(driver.waypoint() and select(2, driver.waypoint()), "native guidance starts tracked")
local nativeQueued = frame.OnUpdate
ns.db.arrow = false
ns.JourneyGuide.ArrowChanged()
ns.JourneyGuide.To(nativeGoal, { nativeGoal }, nativeGoal)
assert(not driver.waypoint(), "disabling takes the guide's waypoint back")
nativeQueued(frame, 0.1)
assert(not driver.waypoint(), "a queued arrow tick cannot restore the native marker while disabled")
ns.db.arrow = true
ns.JourneyGuide.ArrowChanged()
ns.JourneyGuide.To(nativeGoal, { nativeGoal }, nativeGoal)
assert(driver.waypoint() and select(2, driver.waypoint()), "enabling restores native guidance")
ns.JourneyGuide.Stop()
-- Direct mode through the real JourneyGuide callback, including ownership and map projection.
-- #940: the default stop-only map marks still allow native direct guidance.
ns.db.guideStops = true
cvars.showInGameNavigation = "1"
env.C_Navigation = {
	GetFrame = function()
		return {}
	end,
}
local saved = env.UiMapPoint.CreateFromCoordinates(1, 0.2, 0.3)
env.C_Map.SetUserWaypoint(saved)
env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
ns.db.arrowDirect = true
ns.JourneyGuide.Start()
local directGoal = { map = 1, x = 300, y = 400 }
ns.JourneyGuide.To(bends[#bends], bends, directGoal)
local directWaypoint = assert(driver.waypoint())
local directMap, directWorld = env.C_Map.GetWorldPosFromMapPos(directWaypoint.uiMapID, directWaypoint.position)
assert(
	directMap == 1 and math.abs(directWorld.x - 300) < 1e-8 and math.abs(directWorld.y - 400) < 1e-8,
	"real native placement projects the final direct destination"
)
assert(frame.hidden or frame.alpha == 0, "native direct guidance hides the addon arrow with stop-only marks")
ns.db.arrowDirect = false
ns.ArrowBearingChanged()
assert(driver.waypoint(), "route mode with stop-only marks keeps a waypoint at the step destination")
assert(not frame.hidden and frame.alpha > 0, "the route arrow leads beside the destination waypoint")
ns.db.arrowDirect = true
ns.ArrowBearingChanged()
assert(driver.waypoint(), "direct mode restores native guidance immediately with stop-only marks")
assert(frame.hidden or frame.alpha == 0, "restored native direct guidance hides the addon arrow")
ns.JourneyGuide.Stop()
local restored = assert(driver.waypoint())
assert(
	restored.uiMapID == saved.uiMapID
		and restored.position.x == saved.position.x
		and restored.position.y == saved.position.y
		and select(2, driver.waypoint()),
	"direct guidance restores the saved player waypoint"
)
ns.JourneyGuide.Start()
ns.JourneyGuide.To(bends[#bends], bends, { map = 2, x = 300, y = 400 })
local dockWaypoint = assert(driver.waypoint())
local _, dockWorld = env.C_Map.GetWorldPosFromMapPos(dockWaypoint.uiMapID, dockWaypoint.position)
assert(
	math.abs(dockWorld.x - 200) < 1e-8 and math.abs(dockWorld.y - 200) < 1e-8,
	"real native placement falls back to the active travel endpoint across maps"
)
local playerReplacement = env.UiMapPoint.CreateFromCoordinates(1, 0.7, 0.8)
env.C_Map.SetUserWaypoint(playerReplacement)
env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
ns.ArrowBearingChanged()
assert(driver.waypoint() == playerReplacement, "direct guidance yields immediately to the player's playerReplacement")
ns.JourneyGuide.Stop()
assert(driver.waypoint() == playerReplacement, "stopping direct guidance preserves the player's playerReplacement")
-- Adventure Guide focuses the quest on entering its area. Stop-only guidance owns no native waypoint.
env.C_Map.ClearUserWaypoint()
env.C_SuperTrack.SetSuperTrackedUserWaypoint(false)
env.C_SuperTrack.SetSuperTrackedQuestID(0)
ns.db.arrowDirect = false
-- The quest's area is the arrow's next bend; the step's waypoint stays on its destination beyond it (#1138).
local questBend = { map = 1, x = 1200, y = 0 }
local stepEnd = { map = 1, x = 1200, y = 300 }
ns.JourneyGuide.Start()
ns.JourneyGuide.To(questBend, { questBend }, stepEnd)
assert(frame.alpha == 1, "stop-only guidance leads the bend with the route arrow")
local validScreenPosition = true
env.Enum.NavigationState = { InRange = 2, Occluded = 1 }
env.C_Navigation.GetTargetState = function()
	return env.Enum.NavigationState.InRange
end
env.C_Navigation.HasValidScreenPosition = function()
	return validScreenPosition
end
local markerX, markerY = 0.5, 0.476
env.C_Navigation.GetNextWaypointForMap = function(map)
	assert(map == 1)
	return markerX, markerY
end
env.C_SuperTrack.SetSuperTrackedQuestID(1161)
ns.JourneyGuide.TrackingChanged("SUPER_TRACKING_CHANGED")
frame.OnUpdate(frame, 0.1)
assert(frame.alpha == 0, "the matching native quest marker replaces the route arrow")
assert(ns.ArrowLeads(), "the matching native quest marker keeps other guide arrows handed over")
assert(ns.JourneyGuide.Yielded() and not driver.waypoint(), "tracking changes still yield waypoint ownership")

-- An external addon can change the target while the native frame stays visible and the player stands still.
local poll
env.C_Timer = {
	NewTicker = function(_, callback)
		poll = callback
		return { Cancel = function() end }
	end,
}
frame.OnShow(frame)
frame.OnUpdate(frame, 0.1)
assert(not rawget(frame, "OnUpdate"), "the matching marker leaves only the slow poll")
markerX = 0.51
poll()
assert(frame.alpha == 1, "a quest marker at another location leaves the route arrow visible")
markerX = 0.5
validScreenPosition = false
ns.ArrowBearingChanged()
assert(frame.alpha == 1, "a marker without a valid screen position leaves the route arrow visible")
validScreenPosition = true
cvars.showInGameNavigation = "0"
ns.ArrowBearingChanged()
assert(frame.alpha == 1, "a hidden native quest marker leaves the route arrow visible")
frame.OnHide(frame)
ns.JourneyGuide.Stop()
print("arrow_spec: ok")

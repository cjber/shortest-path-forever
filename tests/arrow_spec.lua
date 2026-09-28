-- A frame callback already queued by the client can run after guidance has stopped.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, frame = driver.ns, nil
local create = driver.env.CreateFrame
driver.env.CreateFrame = function(...)
	frame = create(...)
	return frame
end
driver.load("Arrow.lua")
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
print("arrow_spec: 8 checks passed")

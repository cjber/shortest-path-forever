-- The destination pin: where it sits for a bearing, and when it is drawn at all (a journey,
-- the setting, the player's own zone, and no Waypoint UI navigation in charge).
local root = "."
local driver = assert(loadfile("tests/journey_driver.lua"))(root)
local ns = driver.ns

-- Only the pure placement and the wanted test are reached here: no frame is created.
local loaded = pcall(driver.load, "UI/DestinationPin.lua")
if not loaded then
	-- The module creates its frame lazily, so loading it is enough; a frame error means a
	-- broken module, not an untestable one.
	error("UI/DestinationPin.lua did not load")
end

local function close(a, b)
	return math.abs(a - b) < 0.01
end

-- Dead ahead: above the middle of the screen, at full strength.
local x, y, alpha = ns.PinPlace(0, 0, 500)
assert(close(x, 0) and close(y, -150), "ahead sits at the reach")
assert(close(alpha, 1), "ahead is full strength")

-- To the right: at the side and half way out to the behind reach, half faded between the extremes.
x, y, alpha = ns.PinPlace(math.pi / 2, 0, 500)
assert(close(x, 225) and close(y, 0), "right sits at the side")
assert(alpha < 1 and alpha > 0.4, "the side is neither full nor dimmest")

-- Behind: below the middle, further out and dimmer.
x, y, alpha = ns.PinPlace(math.pi, 0, 500)
assert(close(x, 0) and close(y, 300), "behind sits below, at twice the reach")
assert(close(alpha, 0.4), "behind is dimmest")

-- The bearing is taken relative to facing, and wraps the short way round: turned just past
-- north, north sits a little to your right rather than most of the way round the screen.
local turnedX = ns.PinPlace(0, 2 * math.pi - 0.1, 500)
assert(turnedX > 0 and turnedX < 40, "a small turn puts the pin just to the side")

-- A distance is not needed for placement, but a missing bearing or facing has no answer.
assert(ns.PinPlace(nil, 0, 500) == nil, "no bearing, no pin")
assert(ns.PinPlace(0, nil, 500) == nil, "no facing, no pin")

-- Wanted: only with the setting, a journey, the destination in the player's zone, and no
-- Waypoint UI navigation owning the world pin.
ns.db.destinationPin = false
assert(not ns.DestinationPinWanted(), "off by default")
ns.db.destinationPin = true

local goal = { map = 1, x = 100, y = 100 }
ns.JourneyGoal = function()
	return goal
end
ns.JourneyPosition = function()
	return 2827, -289, nil, 1
end
ns.WaypointUIPinOwned = nil
assert(ns.DestinationPinWanted(), "a journey in this zone wants a pin")

goal = { map = 0, x = 100, y = 100 }
assert(not ns.DestinationPinWanted(), "another map's destination is the tracker's job")

goal = { map = 1, x = 100, y = 100 }
ns.JourneyGoal = function()
	return nil
end
assert(not ns.DestinationPinWanted(), "no journey, no pin")

ns.JourneyGoal = function()
	return goal
end
ns.WaypointUIPinOwned = function()
	return true
end
assert(not ns.DestinationPinWanted(), "Waypoint UI owns the world pin, so ours stands down")

ns.WaypointUIPinOwned = function()
	return false
end
assert(ns.DestinationPinWanted(), "Waypoint UI absent leaves ours in charge")

print("destination pin: ok")

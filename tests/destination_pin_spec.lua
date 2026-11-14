-- The destination pin: where it sits for a bearing, and when it is drawn at all (a journey,
-- the setting, the player's own zone, and no Waypoint UI navigation in charge).
local root = "."
local driver = assert(loadfile("tests/journey_driver.lua"))(root)
local ns = driver.ns
local env = driver.env

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
assert(close(x, 0) and close(y, 150), "ahead sits at the reach")
assert(close(alpha, 1), "ahead is full strength")

-- To the right: at the side and half way out to the behind reach, half faded between the extremes.
x, y, alpha = ns.PinPlace(-math.pi / 2, 0, 500)
assert(close(x, 225) and close(y, 0), "right sits at the side")
assert(alpha < 1 and alpha > 0.4, "the side is neither full nor dimmest")

-- Behind: below the middle, further out and dimmer.
x, y, alpha = ns.PinPlace(math.pi, 0, 500)
assert(close(x, 0) and close(y, -300), "behind sits below, at twice the reach")
assert(close(alpha, 0.4), "behind is dimmest")

-- The bearing is taken relative to facing, and wraps the short way round: turned just past
-- north to the east, north sits a little to your left rather than most of the way round the screen.
local turnedX = ns.PinPlace(0, 2 * math.pi - 0.1, 500)
assert(turnedX < 0 and turnedX > -40, "a small turn puts the pin just to the side")

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

-- The step line under the distance: the current row's wording, the title when no row is current,
-- one short line cut at a word, and nothing at all when there is no wording to show.
assert(
	ns.PinStepText("Journey to Goldshire", { { text = "1. Walk", current = true } }) == "1. Walk",
	"the current row wins"
)
assert(
	ns.PinStepText("Journey to Goldshire", { { text = "1. Walk" }, { text = "2. Fly" } }) == "Journey to Goldshire",
	"no current row falls back to the title"
)
assert(ns.PinStepText(nil, nil) == nil, "no wording, no line")
assert(ns.PinStepText("", {}) == nil, "an empty title is not a line")
local cut = ns.PinStepText(string.rep("word ", 12), nil)
assert(#cut <= 32, "the line is cut to fit the pin")
assert(cut:sub(-3) == "...", "a cut line says so")
assert(not cut:find(" $"), "a cut line never ends on a space")

-- The pin's poll runs while a journey is drawn: with the goal, the position, the facing and the step wording
-- unchanged it returns before building a distance or a step line, so it allocates nothing (#784).
-- Font strings are kept in creation order, the pin's distance line first and its step line second, so the line
-- the pin shows can be read back.
local fontStrings = {}
local create = env.CreateFrame
env.CreateFrame = function(...)
	local f = create(...)
	f.IsShown = function(self)
		return not self.hidden
	end
	f.CreateFontString = function()
		local text = setmetatable({}, getmetatable(f))
		function text:SetText(value)
			self.text = value
		end
		fontStrings[#fontStrings + 1] = text
		return text
	end
	return f
end
ns.db.destinationPin = true
ns.db.metres = false
local steadyGoal = { map = 1, x = 100, y = 100 }
ns.JourneyGoal = function()
	return steadyGoal
end
ns.JourneyPosition = function()
	return 2827, -289, nil, 1
end
ns.WaypointUIPinOwned = nil
ns.GoalPinFile = function()
	return "pin"
end
ns.Art = { Icon = function() end }
-- One table and one index, as the real stops are: a stub that built them per call would count its own allocation.
local stops, stopIndex = { {}, {} }, 1
ns.JourneyStops = function()
	return stops, stopIndex
end
-- The plan and the leg of it being walked, as Journey.lua's JourneyPlan returns them.
local plan, legIndex = {}, 1
ns.JourneyPlan = function()
	return plan, legIndex
end
local rows = { { text = "1. Walk to the inn", current = true } }
local infoBuilds = 0
ns.JourneyInfo = function()
	infoBuilds = infoBuilds + 1
	return "Journey", rows
end
env.GetPlayerFacing = function()
	return 0
end
ns.RefreshDestinationPin()
assert(ns.DestinationPinWanted(), "the steady journey wants its pin")
local formatted = 0
local formatDistance = ns.FormatDistance
ns.FormatDistance = function(...)
	formatted = formatted + 1
	return formatDistance(...)
end
for _ = 1, 100 do
	ns.RefreshDestinationPin()
end
assert(formatted == 0, "an unchanged pin builds no distance string")
assert(infoBuilds == 1, "an unchanged step is not rebuilt")
-- Warm the call and its loop so the JIT's own compilation is not counted as the pin's allocation.
for _ = 1, 2000 do
	ns.RefreshDestinationPin()
end
local function measured(fn)
	for _ = 1, 2000 do
		fn()
	end
	-- Count the code's own allocations, not the JIT's traces: the paths under test are plain Lua work.
	jit.off()
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 1000 do
		fn()
	end
	local grew = collectgarbage("count") - before
	collectgarbage("restart")
	return grew
end
local control = measured(function() end)
local grew = measured(ns.RefreshDestinationPin)
assert(grew - control < 0.5, "an unchanged destination pin allocates nothing (" .. (grew - control) .. " KB)")

-- The stop index moves on while the player stands still (a turn-in at the NPC): the goal, the position and the
-- facing are all as they were, and the next refresh still brings the new step line rather than the old one.
local stepLine = fontStrings[2]
assert(stepLine and stepLine.text == "1. Walk to the inn", "the pin shows the step the route is on")
stopIndex = 2
rows = { { text = "2. Speak to Marshal Dughan", current = true } }
ns.RefreshDestinationPin()
assert(infoBuilds == 2, "the step is rebuilt when the stop index moves on")
assert(stepLine.text == "2. Speak to Marshal Dughan", "a stop index that moves on updates the step line")

-- A journey to one place has no stop index to move on: its walk, lift and flight all lead to the same goal. Finishing
-- a leg still brings the next leg's line, rather than the first leg's wording all the way there.
legIndex = 2
rows = { { text = "3. Lift to the bottom", current = true } }
ns.RefreshDestinationPin()
assert(infoBuilds == 3, "the step is rebuilt when the journey's leg moves on")
assert(stepLine.text == "3. Lift to the bottom", "a leg that moves on updates the step line")
-- A new plan for the same goal (a replan from where the player stands) is a new step line too.
plan, legIndex = {}, 1
rows = { { text = "1. Walk to Tirisfal", current = true } }
ns.RefreshDestinationPin()
assert(infoBuilds == 4, "the step is rebuilt for a new plan")
assert(stepLine.text == "1. Walk to Tirisfal", "a new plan updates the step line")

print("destination pin: ok")

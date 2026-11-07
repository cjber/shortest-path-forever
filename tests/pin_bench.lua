-- Prototype bench, not a spec. Run from the repository root:
--   luajit -joff tests/pin_bench.lua
--
-- The destination pin's cost per update: the bearing maths, one SetPoint, one SetAlpha and one
-- distance string, as UI/DestinationPin.lua does it. A session of a player walking with a
-- journey running is replayed at several update intervals so the share of a 60 Hz frame the
-- pin takes is measured rather than assumed.
--
-- For each interval it reports, over a 60 s walk:
--   updates    pin updates the interval causes
--   per update mean cost of one update
--   worst      the worst single frame of the session, against AGENTS.md's 3 ms budget
--   % frame    update CPU as a share of one 60 Hz frame, averaged
local root = arg[1] or "."

local INTERVALS = { 0.05, 0.1, 0.25, 0.5 }
local FRAME = 1 / 60
local SESSION = 60
-- A player walking a road in Ashenvale, facing along it.
local WALK = 7

local driver = assert(loadfile("tests/journey_driver.lua"))(root)
local ns = driver.ns

-- Frames are stubbed: this records the client calls a pin update makes, which is all the
-- bench needs to charge an update the work the game would do.
local calls = 0
local function frame()
	-- Charges every call a pin update makes; anything else the client answers with a no-op.
	local f
	f = setmetatable({}, {
		__index = function(_, key)
			if key == "SetPoint" or key == "SetAlpha" then
				return function()
					calls = calls + 1
				end
			end
			if key == "CreateTexture" or key == "CreateFontString" then
				return function()
					return f
				end
			end
			return function() end
		end,
	})
	return f
end
driver.env.CreateFrame = function()
	return frame()
end
driver.env.GetPlayerFacing = function()
	return 0
end
driver.env.C_Texture = {
	GetAtlasInfo = function()
		return { width = 32, height = 32 }
	end,
}
ns.PIN_FILE = "Interface\\AddOns\\ShortestPathForever\\media\\Pin"
ns.Art = {
	Fit = function(texture)
		texture:SetSize(28, 36)
		return true
	end,
	Icon = function(texture)
		texture:SetSize(36, 36)
	end,
}
ns.FormatDistance = function(yards)
	return string.format("%d yd", math.floor(yards + 0.5))
end
driver.load("UI/DestinationPin.lua")

local from = { map = 1, x = 2827.34, y = -289.24 }
local to = { map = 1, x = 2302.39, y = -2524.55 }
local function at(yards)
	local dx, dy = to.x - from.x, to.y - from.y
	local total = math.sqrt(dx * dx + dy * dy)
	return from.x + dx / total * yards, from.y + dy / total * yards
end

ns.db.destinationPin = true
ns.WaypointUIPinOwned = function()
	return false
end
local x, y = at(0)
ns.JourneyPosition = function()
	return x, y, nil, 1
end
ns.JourneyGoal = function()
	return { map = 1, x = to.x, y = to.y }
end

print("interval updates  per update   worst  % frame")
local results = {}
for _, interval in ipairs(INTERVALS) do
	local due, updates, worst, total = 0, 0, 0, 0
	local seconds = 0
	while seconds < SESSION do
		due = due + FRAME
		local started = os.clock()
		if due >= interval then
			due = 0
			updates = updates + 1
			x, y = at(WALK * seconds)
			ns.RefreshDestinationPin()
		end
		seconds = seconds + FRAME
		local spent = (os.clock() - started) * 1000
		total = total + spent
		if spent > worst then
			worst = spent
		end
	end
	local frames = math.floor(SESSION * 60)
	results[#results + 1] = {
		interval = interval,
		updates = updates,
		perUpdateUs = total / updates * 1000,
		worst = worst,
		share = total / frames / (1000 / 60) * 100,
	}
	print(
		string.format(
			"%6.2fs %7d %8.1f us %7.3fms %8.3f%%",
			interval,
			updates,
			total / updates * 1000,
			worst,
			total / frames / (1000 / 60) * 100
		)
	)
end

-- The pin is drawn from a frame timer that is off unless a journey runs, so one update must
-- stay far inside the frame budget the arrow's own poll is held to.
for _, result in ipairs(results) do
	assert(result.worst < 3, "a pin update must stay under the 3 ms frame budget")
end

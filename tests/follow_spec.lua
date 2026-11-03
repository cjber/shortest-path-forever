-- Following a party member: the position read, the throttle, the movement deadband, stopping,
-- and the replan landing on a quiet frame rather than in the tick that asks for it.
local root = "."
local driver = assert(loadfile("tests/journey_driver.lua"))(root)
local ns, env = driver.ns, driver.env

for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
}) do
	driver.load(file)
end
for _, map in ipairs({ 0, 1, 2991 }) do
	assert(loadfile("tools/load_nav.lua"))(map)
end
driver.load("Journey/Follow.lua")

-- The unit queries and the map read the client answers for a party member.
local member = { map = 1, x = 2500, y = -900 }
local exists = true
env.UnitExists = function()
	return exists
end
env.UnitName = function()
	return "Wife"
end
env.UnitIsUnit = function()
	return false
end
ns.FollowPoint = function()
	return member and { map = member.map, x = member.x, y = member.y }
end
ns.FollowTick = ns.FollowTick

local printed = {}
ns.Print = function(message)
	printed[#printed + 1] = message
end

-- Next-frame scheduling is this spec's own queue: nothing runs until the spec says so.
local pending = {}
-- Whether a walking search is in flight; the follow replan must wait for a quiet frame.
local busy = false
ns.Path.Busy = function()
	return busy
end
ns.Path.after = function(fn)
	pending[#pending + 1] = fn
end
local function frames()
	local due = pending
	pending = {}
	for _, fn in ipairs(due) do
		fn()
	end
end

local journeys = 0
local startJourney = ns.StartJourney
ns.StartJourney = function(point)
	journeys = journeys + 1
	return startJourney(point)
end

local here = { map = 1, x = 2827.34, y = -289.24 }
driver.move(here)
assert(ns.StartFollowing("party1"), "start following")
-- The walking search settles over the frames after the click, as it does in the game.
for _ = 1, 40 do
	if driver.shown() then
		break
	end
	frames()
	driver.update(0)
end
assert(driver.shown(), "the follow journey plans")
assert(ns.IsFollowing(), "following is on")
assert(journeys == 1, "starting plans once")

-- Inside the throttle nothing is replanned, however far the member walks.
member = { map = 1, x = 2400, y = -1000 }
ns.FollowTick(0.2)
frames()
assert(journeys == 1, "no replan before the throttle is up")

-- Past the throttle, with a visible move, the replan is queued and lands on the next frame.
ns.FollowTick(0.9)
assert(journeys == 1, "the replan waits for a quiet frame")
frames()
assert(journeys == 2, "the queued replan runs on the next frame")

-- Less than a visible step since the last replan: nothing to do.
ns.FollowTick(1)
frames()
assert(journeys == 2, "a member standing still is not replanned")

-- A real move past the throttle replans again.
member = { map = 1, x = 2200, y = -1400 }
ns.FollowTick(1)
frames()
assert(journeys == 3, "a moving member is followed")

-- A walking search in flight keeps the replan off that frame.
member = { map = 1, x = 2000, y = -1800 }
ns.FollowTick(1)
busy = true
frames()
assert(journeys == 3, "a replan never shares a frame with a search slice")
busy = false
ns.FollowTick(1)
frames()
assert(journeys == 4, "the replan lands once the search is quiet")

-- Caught up: following says so once and leaves the journey where it is.
here = { map = 1, x = 2000, y = -1800 }
driver.move(here)
member = { map = 1, x = 2010, y = -1795 }
local caughtUp = 0
for _, message in ipairs(printed) do
	if message:find("caught up", 1, true) then
		caughtUp = caughtUp + 1
	end
end
ns.FollowTick(1)
frames()
assert(caughtUp == 0, "not caught up yet")
assert(journeys == 4, "no replan once we are together")

-- A member the client cannot place keeps the journey it had.
member = nil
ns.FollowTick(1)
frames()
assert(journeys == 4, "an unplaceable member does not replan")
assert(ns.IsFollowing(), "and does not end the follow")

-- The member leaving the group ends it.
member = { map = 1, x = 2000, y = -1800 }
exists = false
ns.FollowTick(1)
assert(not ns.IsFollowing(), "a departed member ends the follow")

print("follow: ok")

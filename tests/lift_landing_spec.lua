-- A lift's landings share a spot on the map, one floor above the other, and the player's height is unknown
-- (UnitPosition's is a placeholder 0). Reaching the bottom landing must not count as having ridden to the top.
local now = 0
local ns = {
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	Docks = {},
	Routes = {},
	NowMs = function()
		return now
	end,
}
assert(loadfile("Data/Transports.lua"))("ShortestPathForever", ns)
assert(loadfile("Journey/JourneySteps.lua"))("ShortestPathForever", ns)

local WEST_LIFT = 206491 -- Undercity, west lift: docks 1010 (bottom) and 1009 (top)
local function Place(id)
	local dock = ns.Docks[id]
	return { kind = "dock", id = id, map = dock.map, x = dock.x, y = dock.y, z = dock.z }
end
local bottom, top = Place(1010), Place(1009)
assert(bottom.x == top.x and bottom.y == top.y and bottom.z < top.z, "the landings stack")

-- Journey.lua's Near: map distance only, as the client gives no height.
local here
local function near(node)
	return here.map == node.map and (here.x - node.x) ^ 2 + (here.y - node.y) ^ 2 <= 15 ^ 2
end
local told
local guide = {
	To = function(point)
		told = point
	end,
	Cast = function() end,
}

local goal = { map = 0, x = 1760, y = 240 }
local RIDE = 3500
local legs, progress
local function Begin()
	legs = {
		{ mode = "walk", from = { kind = "start", map = 0, x = 1568.62, y = 267.97 }, to = bottom },
		{ mode = "lift", route = WEST_LIFT, from = bottom, to = top, depart = now + 5000, arrive = now + 5000 + RIDE },
		{ mode = "walk", from = top, to = goal },
	}
	progress = { index = 1, departed = false }
end
local function Step(at)
	here = at
	told = nil
	ns.AdvanceJourneyProgress(legs, progress, goal, nil, false, near, guide)
	return progress.index
end
local shaft = { map = 0, x = bottom.x - 4, y = bottom.y }
local off = { map = 0, x = bottom.x + 30, y = bottom.y }

-- At the bottom landing the step is still the lift, guiding to the top, however long the wait and the ride.
now = 100000
Begin()
assert(Step(shaft) == 2, "reaching the bottom landing skipped the lift")
assert(told == top and progress.departed)
now = now + 60000
assert(Step(shaft) == 2 and told == top, "standing at the shaft is not proof of the ride")
-- Stepping off at the top after the ride: on to the walk.
now = now + 1000
assert(Step(off) == 3 and told == goal, "stepping off after the ride does not end the lift")
print("lift_landing_spec: the lift step lasts until you step off after the ride")

-- Stepping away before a ride could have happened means you did not ride: back to the landing.
now = 200000
Begin()
assert(Step(shaft) == 2)
now = now + RIDE - 1
assert(Step(off) == 2 and told == top and not progress.departed and not legs[2].reachedAt)
-- Coming back starts the wait afresh.
now = now + 10000
assert(Step(shaft) == 2 and legs[2].reachedAt == now)
now = now + RIDE
assert(Step(off) == 3, "the ride taken later ends the lift")
print("lift_landing_spec: leaving the landing before the ride keeps the lift step")

-- A boat's landings are apart on the map: being there is arriving, as before.
legs = {
	{ mode = "boat", route = 1, from = { map = 0, x = 0, y = 0, z = 0 }, to = { map = 0, x = 900, y = 0, z = 5 } },
}
progress = { index = 1, departed = true }
assert(Step({ map = 0, x = 900, y = 0 }) == 2)
print("lift_landing_spec: a ride between distant landings ends on arrival")

-- Floor.lua follows the player's floor on the shipped Eastern Kingdoms walking map, so a walk from under the Ruins
-- of Lordaeron starts in the Undercity rather than on the ruins above it.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
local swimming, nearDock, inCombat = false, nil, false
_G.UnitOnTaxi = function()
	return false
end
_G.InCombatLockdown = function()
	return inCombat
end
_G.IsSwimming = function()
	return swimming
end
_G.IsIndoors = function()
	return true
end
ns.NearestDock = function()
	if nearDock then
		return nearDock, 5
	end
end
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua", "Routing/Floor.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path, Grid, Floor = ns.Path, ns.PathGrid, ns.Floor

local frames = {}
Path.after = function(fn)
	frames[#frames + 1] = fn
end
local function drain()
	while #frames > 0 do
		table.remove(frames, 1)()
	end
end

local FM = { x = 1568.62, y = 267.97, z = -43.1 } -- Data/Taxi.lua node 11, on the Undercity's floor
local MAGIC = { x = 1773.47, y = 61.121, z = -46.321 } -- the Magic Quarter
local LIFT_TOP = { x = 1596.15, y = 291.8, z = 55.718 } -- Data/Transports.lua dock 1009, in the hall above
local UNDER_HALL = { x = 1588, y = 237 } -- a city cell with the ruins' hall above it

-- Walk the drawn line from a to b, sampling every five yards as the journey's frame would; check is called at each
-- sample with the point, the line's height there and the tracked height.
local function walk(from, to, check)
	local points = assert(Path.FindSync(0, from, to))
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local steps = math.max(1, math.ceil(math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) / 5))
		for j = 1, steps do
			local t = j / steps
			local x, y = a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)
			local z = a.z and b.z and a.z + t * (b.z - a.z) or b.z or a.z
			Floor.Sample(0, x, y)
			drain()
			Floor.Sample(0, x, y)
			check(x, y, z, Floor.Height(0, x, y), a.z, b.z)
		end
	end
end

-- Reading a cell never decodes it: a first sample queues the clusters and knows nothing until they are in.
do
	Path.ClearCaches()
	Floor.Forget()
	Floor.Sample(0, FM.x, FM.y)
	assert(Floor.Height(0, FM.x, FM.y) == nil, "nothing is known before the clusters are decoded")
	assert(#frames > 0, "the clusters are decoded by a queued job")
	drain()
	local st = Grid.State(0)
	local k = Grid.locate(st, FM.x, FM.y)
	assert(st.val[k], "the job decoded the player's cluster, and the idle sweep after it kept it")
end

-- Both ways across the city, from an unknown floor: the floor settles within a few dozen yards and is never another
-- floor than the one the line is drawn on.
for _, ends in ipairs({ { FM, MAGIC }, { MAGIC, FM } }) do
	Floor.Forget()
	local walked, settled, wrong, last = 0, nil, 0, nil
	walk(ends[1], ends[2], function(x, y, z, height, startZ, endZ)
		walked = walked + (last and math.sqrt((x - last.x) ^ 2 + (y - last.y) ^ 2) or 0)
		last = { x = x, y = y }
		if height then
			settled = settled or walked
			-- On a segment the floor is the start's or the end's, or between them on a ramp.
			local atEnd = (startZ and math.abs(height - startZ) <= 10) or (endZ and math.abs(height - endZ) <= 10)
			if z and math.abs(height - z) > 10 and not atEnd then
				wrong = wrong + 1
			end
		end
	end)
	assert(settled and settled < 100, "the floor settles soon: " .. tostring(settled))
	assert(wrong == 0, "the tracked floor is the line's floor: " .. wrong)
end

-- Walked under the hall from the flight master, a walk up to the lift's top starts in the city; without a height it
-- starts on the hall's floor above, the bug this fixes.
do
	Floor.Forget()
	walk(FM, MAGIC, function() end)
	walk(MAGIC, UNDER_HALL, function() end)
	local height = Floor.Height(0, UNDER_HALL.x, UNDER_HALL.y)
	assert(height and height < 0, "under the hall the floor is the city's: " .. tostring(height))
	local guessed = assert(Path.FindSync(0, { x = UNDER_HALL.x, y = UNDER_HALL.y }, LIFT_TOP))
	local tracked = assert(Path.FindSync(0, { x = UNDER_HALL.x, y = UNDER_HALL.y, z = height }, LIFT_TOP))
	assert(guessed[2].z > 0, "with no height the walk starts on the hall's floor")
	assert(math.abs(tracked[2].z - height) <= 10, "with the floor it starts in the city")
end

-- A move further than a step between samples (a hearth, a teleport) forgets the floor: under the hall that leaves
-- two floors, so nothing is known.
do
	Floor.Forget()
	walk(FM, MAGIC, function() end)
	assert(Floor.Height(0, MAGIC.x, MAGIC.y), "known at the Magic Quarter")
	Floor.Sample(0, UNDER_HALL.x, UNDER_HALL.y)
	drain()
	Floor.Sample(0, UNDER_HALL.x, UNDER_HALL.y)
	assert(Floor.Height(0, UNDER_HALL.x, UNDER_HALL.y) == nil, "after a jump the floor is unknown again")
	assert(Floor.Height(0, UNDER_HALL.x + 20, UNDER_HALL.y) == nil, "and Height answers only near the last sample")
end

-- At a lift's landing the floor is unknown: the lift changes it without moving you.
do
	Floor.Forget()
	walk(FM, MAGIC, function() end)
	nearDock = 1009
	Floor.Sample(0, MAGIC.x, MAGIC.y)
	assert(Floor.Height(0, MAGIC.x, MAGIC.y) == nil, "beside a lift the floor is not followed")
	nearDock = nil
end

-- In combat the floor is held, not followed.
do
	Floor.Forget()
	walk(FM, MAGIC, function() end)
	local held = Floor.Height(0, MAGIC.x, MAGIC.y)
	inCombat = true
	Floor.Sample(0, MAGIC.x + 8, MAGIC.y)
	inCombat = false
	assert(Floor.Height(0, MAGIC.x, MAGIC.y) == held, "combat leaves the last floor as it was")
end

-- Journeys: the search starts from the tracked height, and a walk drawn on another floor is not the one you are on.
do
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local jns = driver.ns
	jns.Floor = {
		Sample = function() end,
		Height = function()
			return -42
		end,
	}
	driver.begin({ map = 0, x = 1588, y = 237 }, { map = 0, x = 1700, y = 237 })
	local batch = assert(driver.path.batches[1], "the journey searched")
	assert(batch.from.z == -42, "the walk starts on the tracked floor")

	local line = { { map = 0, x = 0, y = 0, z = 60 }, { map = 0, x = 100, y = 0, z = 60 } }
	assert(jns.OnWalk(line, { map = 0, x = 50, y = 2 }), "with no height a walk above is yours")
	assert(jns.OnWalk(line, { map = 0, x = 50, y = 2, z = 58 }), "on its floor it is yours")
	assert(not jns.OnWalk(line, { map = 0, x = 50, y = 2, z = -42 }), "a floor below it is not on it")
end

-- A goal in the Undercity is not reached from the ruins' hall above it, and is once you stand on its floor; where the
-- floor is unknown the spot alone decides.
do
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local jns = driver.ns
	local tracked = 60
	jns.Floor = {
		Sample = function() end,
		Height = function()
			return tracked
		end,
	}
	driver.move({ map = 0, x = 1588, y = 237 })
	jns.StartJourney({ map = 0, x = 1590, y = 237, z = -43.1 })
	driver.update(0.2)
	assert(jns.JourneyGoal(), "standing in the hall above, the goal below is not reached")
	tracked = -42
	driver.update(0.2)
	assert(not jns.JourneyGoal(), "on the city's floor it is")
	tracked = nil
	jns.StartJourney({ map = 0, x = 1590, y = 237, z = -43.1 })
	driver.update(0.2)
	assert(not jns.JourneyGoal(), "with the floor unknown the spot decides")
end

-- A spot picked on the Undercity's map is on the city's floor; one on Tirisfal's names the surface.
do
	local input = assert(loadfile("tests/journey_driver.lua"))()
	input.env.C_Map.GetWorldPosFromMapPos = function(_, pos)
		return 0, {
			GetXY = function()
				return pos.x, pos.y
			end,
		}
	end
	assert(input.ns.WorldPoint(1458, 0.5, 0.5).z == -43.1, "the Undercity's map is the city")
	assert(input.ns.WorldPoint(1420, 0.5, 0.5).z == nil, "Tirisfal's is the surface")
end

print("floor_spec: ok")

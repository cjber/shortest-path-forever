-- Floor.lua follows the player's floor on the shipped Eastern Kingdoms walking map, so a walk from under the Ruins
-- of Lordaeron starts in the Undercity rather than on the ruins above it.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
local swimming, falling, nearDock, inCombat = false, false, nil, false
_G.UnitOnTaxi = function()
	return false
end
_G.InCombatLockdown = function()
	return inCombat
end
_G.IsSwimming = function()
	return swimming
end
_G.IsFalling = function()
	return falling
end
local tick, journeyAt
ns.OnTravelTick = function(fn)
	tick = fn
end
ns.JourneyPosition = function()
	if journeyAt then
		return journeyAt.x, journeyAt.y, nil, 0
	end
end
ns.NearestDockSpot = function()
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
local QUARTER_CANAL = { x = 1747.3, y = 107.5, z = -62 } -- the canal below the Magic Quarter's ramp
local LIFT_TOP = { x = 1596.15, y = 291.8, z = 55.718 } -- Data/Transports.lua dock 1009, in the hall above
-- A city cell with the ruins' hall above it and one city floor: nearby cells hold the canal's floor and a walkway
-- above it, two city floors the walk cannot tell apart.
local UNDER_HALL = { x = 1604, y = 219 }

-- Walk the drawn line from a to b, sampling every five yards (or spacing) as the journey's frame would; check is
-- called at each sample with the point, the line's height there and the tracked height. A vertical segment is a drop
-- off a ledge: the client shows the fall while you are in the air.
local function walk(from, to, check, spacing)
	local points = assert(Path.FindSync(0, from, to))
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local steps = math.max(1, math.ceil(math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) / (spacing or 5)))
		for j = 1, steps do
			local t = j / steps
			local x, y = a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)
			local z = a.z and b.z and a.z + t * (b.z - a.z) or b.z or a.z
			falling = a.x == b.x and a.y == b.y and a.z and b.z and b.z < a.z or false
			Floor.Sample(0, x, y)
			drain()
			Floor.Sample(0, x, y)
			falling = false
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

-- Both ways across the city, from an unknown floor: the floor settles within a block or so and is never another
-- floor than the one the line is drawn on. A surface the map has no way from is held a few cells, so settling waits
-- for that.
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
	-- From the flight master the canal's bed, its ledges and the walkway above run side by side, each a step from the
	-- next, and a ledge left behind is held REACH cells: about 170 yd on the rebaked map.
	assert(settled and settled < 180, "the floor settles soon: " .. tostring(settled))
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
-- two floors, so nothing is known. It starts on the canal below the Magic Quarter, where one floor is a step away; the
-- quarter itself stands over a lower walkway its ramp reaches, so its floor stays open.
do
	Floor.Forget()
	walk(FM, QUARTER_CANAL, function() end)
	assert(Floor.Height(0, QUARTER_CANAL.x, QUARTER_CANAL.y), "known on the canal")
	Floor.Sample(0, UNDER_HALL.x, UNDER_HALL.y)
	drain()
	Floor.Sample(0, UNDER_HALL.x, UNDER_HALL.y)
	assert(Floor.Height(0, UNDER_HALL.x, UNDER_HALL.y) == nil, "after a jump the floor is unknown again")
	assert(Floor.Height(0, UNDER_HALL.x + 20, UNDER_HALL.y) == nil, "and Height answers only near the last sample")
end

-- Outdoors too (#737): Stormwind's streets stand over open ground the walking map reaches, and with no height a walk
-- from the street below the Keep starts down there. Walking in from the flight master, the travel tick follows the
-- streets.
do
	local SW_FM = { x = -8832.77, y = 478.62, z = 109.6 } -- Data/Taxi.lua node 2
	local STREET = { x = -8485, y = 446 } -- the street below the Keep, z 96
	local guessed = assert(Path.FindSync(0, STREET, SW_FM))
	assert(guessed[2].z < 80, "with no height the walk starts under the city: " .. guessed[2].z)
	Floor.Forget()
	local line = assert(Path.FindSync(0, SW_FM, { x = STREET.x, y = STREET.y, z = 96 }))
	for i = 2, #line do
		local a, b = line[i - 1], line[i]
		local steps = math.max(1, math.ceil(math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) / 5))
		for j = 1, steps do
			journeyAt = { x = a.x + j / steps * (b.x - a.x), y = a.y + j / steps * (b.y - a.y) }
			tick()
			drain()
			tick()
		end
	end
	local height = Floor.Height(0, STREET.x, STREET.y)
	assert(height and height > 85, "the street is followed outdoors: " .. tostring(height))
	local tracked = assert(Path.FindSync(0, { x = STREET.x, y = STREET.y, z = height }, SW_FM))
	for _, p in ipairs(tracked) do
		assert(not p.z or p.z > 85, "from the followed street the walk stays on the streets: " .. tostring(p.z))
	end
	journeyAt = nil
	tick()
	assert(Floor.Height(0, STREET.x, STREET.y) == nil, "with no position the floor is forgotten")
end

-- The Trade District (#1046): the walking map had a cell beside the street that held only the ground under the city,
-- because a stall stood on its centre. The bake now gives a cell every surface covering part of it, so the street
-- runs through that cell. Walking in from the flight master at a run's pace per travel tick, with each decode one
-- frame behind, the street is followed, and a walk from it climbs straight to the roost.
local SW_FM = { x = -8832.77, y = 478.62, z = 109.6 } -- Data/Taxi.lua node 2
local GAP = { x = -8851, y = 589 } -- the street at z 95 over the ground, z 74
local ON_STREET = { x = -8838, y = 580, z = 97 }
local function surfaces(p)
	Path.FindSync(0, { x = p.x, y = p.y }, { x = p.x + 1, y = p.y + 1 })
	local st = Grid.State(0)
	local k, lc = Grid.locate(st, p.x, p.y)
	local val, z, at = st.val[k], st.z[k], st.at[k]
	local out = {}
	if val[lc + 1] ~= 0 then
		out[#out + 1] = z[lc + 1]
	end
	local n = at[-(lc + 1)]
	while n and at[n + 1] == lc do
		out[#out + 1] = z[n + 1]
		n = n + 1
	end
	return out
end
local function walkIn(stop)
	Floor.Forget()
	local line = assert(Path.FindSync(0, SW_FM, ON_STREET))
	line[#line + 1] = stop or GAP
	for i = 2, #line do
		local a, b = line[i - 1], line[i]
		local steps = math.max(1, math.ceil(math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) / 7))
		for j = 1, steps do
			journeyAt = { x = a.x + j / steps * (b.x - a.x), y = a.y + j / steps * (b.y - a.y) }
			tick()
			if frames[1] then
				table.remove(frames, 1)()
			end
		end
	end
	drain()
	tick()
	tick()
end
do
	local gap = surfaces(GAP)
	assert(gap[#gap] > 85, "the gap cell holds the street: " .. table.concat(gap, " "))
	walkIn()
	local height = Floor.Height(0, GAP.x, GAP.y)
	assert(height and height > 85, "the street is followed through the gap cell: " .. tostring(height))
	local route = assert(Path.FindSync(0, { x = GAP.x, y = GAP.y, z = height }, SW_FM))
	for _, p in ipairs(route) do
		assert(not p.z or p.z > 85, "from the followed street the walk stays on the streets: " .. tostring(p.z))
	end
	journeyAt = nil
	tick()
end

-- A ledge on the Trade District's street: the cell north of it holds only the street below, which the walking map
-- reaches from the ledge by a drop. Walking, the ledge is held there; a fall seen at the edge, or a sample before the
-- landing, lands on the street below.
local LEDGE = { x = -8847.8, y = 831.8, z = 106 }
local BELOW = { x = LEDGE.x, y = LEDGE.y + 7.96 } -- z 98
local function offLedge(fall, combat)
	Floor.Forget()
	walk(SW_FM, LEDGE, function() end)
	inCombat, falling = combat or false, fall
	Floor.Sample(0, LEDGE.x, LEDGE.y + 3)
	inCombat, falling = false, false
	Floor.Sample(0, BELOW.x, BELOW.y)
	drain()
	Floor.Sample(0, BELOW.x, BELOW.y)
	return Floor.Height(0, BELOW.x, BELOW.y)
end
do
	local height = offLedge(false)
	assert(height and height > 103, "walking, the ledge is held past its edge: " .. tostring(height))
	height = offLedge(true)
	assert(height and height < 101, "a fall seen a sample before the landing lands below: " .. tostring(height))
end

-- Knocked off a canal's bank into the water, you swim: the floor is the water's, not the street's above it.
do
	local CANAL = { x = -8920, y = 496 } -- the street at z 94 over the canal's water at z 72
	Floor.Forget()
	journeyAt = { x = CANAL.x, y = CANAL.y - 8 }
	tick()
	drain()
	tick()
	swimming = true
	journeyAt = CANAL
	tick()
	drain()
	tick()
	swimming = false
	local height = Floor.Height(0, CANAL.x, CANAL.y)
	assert(height and height < 80, "swimming in the canal: " .. tostring(height))

	-- Followed on the street in the canal's cell, then swimming there without moving cell.
	Floor.Forget()
	journeyAt = { x = CANAL.x, y = CANAL.y - 8 }
	tick()
	drain()
	tick()
	journeyAt = CANAL
	tick()
	drain()
	tick()
	height = Floor.Height(0, CANAL.x, CANAL.y)
	-- The street and the canal's water stack along the bank, so walking it never settles on one; it is never the water.
	assert(not height or height > 85, "walking, the street over the canal: " .. tostring(height))
	swimming = true
	journeyAt = { x = CANAL.x + 0.5, y = CANAL.y }
	tick()
	swimming = false
	height = Floor.Height(0, CANAL.x, CANAL.y)
	assert(height and height < 80, "swimming in the same cell, the water: " .. tostring(height))
	journeyAt = nil
	tick()
end

-- Trade District streets have cells the walking map gives only the ground under the city (z 60, #1046): a street
-- surface that cannot step into one is held, not ruled out, so the floor never settles on the ground beneath you.
-- Ruled out, it did, and a journey planned there walked the ground through the Mage Quarter and replanned as the
-- floor changed. From a fresh start in such a cell, the street around you is held the same way.
do
	local TRADE = { x = -8849, y = 647.9, z = 98 }
	for _, ends in ipairs({
		{ TRADE, { x = -8980.3, y = 941 } }, -- through cell 900,1021 to the Mage Quarter
		{ { x = -8829.9, y = 722.2, z = 98 }, TRADE }, -- from cell 900,1027, the ground's alone
	}) do
		Floor.Forget()
		local wrong = 0
		walk(ends[1], ends[2], function(_, _, z, height, startZ, endZ)
			if height and z and math.abs(height - z) > 10 then
				-- On a ramp the floor may still be the segment's start or end.
				local atEnd = (startZ and math.abs(height - startZ) <= 10) or (endZ and math.abs(height - endZ) <= 10)
				wrong = wrong + (atEnd and 0 or 1)
			end
		end, 3)
		assert(wrong == 0, "on the Trade District's street the floor is never the ground under it: " .. wrong)
	end
end

-- A cluster released from the pin goes as soon as no job runs, not at the next job.
do
	Floor.Forget()
	journeyAt = { x = SW_FM.x, y = SW_FM.y }
	tick()
	drain()
	tick()
	local st = Grid.State(0)
	assert(next(st.used), "the clusters around you are decoded")
	journeyAt = nil
	tick()
	assert(next(st.used) == nil, "with nothing followed they are released")
end

-- At a lift's landing the floor is unknown: the lift changes it without moving you.
do
	Floor.Forget()
	walk(FM, MAGIC, function() end)
	local walkedIn = assert(Floor.Height(0, MAGIC.x, MAGIC.y))
	nearDock = 1009
	Floor.Sample(0, MAGIC.x, MAGIC.y)
	assert(Floor.Height(0, MAGIC.x, MAGIC.y) == nil, "beside a lift the floor is not followed")
	-- The floor you walked onto the landing on names the landing (#1059), and holds while you stand there.
	local at, z = Floor.Landing(0)
	assert(at and z == walkedIn, "the landing keeps the floor you walked in on")
	Floor.Sample(0, MAGIC.x + 1, MAGIC.y)
	at, z = Floor.Landing(0)
	assert(at and z == walkedIn and not Floor.Landing(1), "standing there it holds, on its own map only")
	-- A ride moves you to another landing without moving you on the map: the floor you walked in on goes.
	ns.IsObservingRide = function()
		return true
	end
	Floor.Sample(0, MAGIC.x + 1, MAGIC.y)
	ns.IsObservingRide = nil
	Floor.Sample(0, MAGIC.x + 1, MAGIC.y)
	at, z = Floor.Landing(0)
	assert(at and z == nil, "after a ride the walked-in floor is gone for as long as you stay")
	nearDock = nil
	Floor.Sample(0, MAGIC.x, MAGIC.y)
	assert(not Floor.Landing(0), "walked off the landing, following starts again")
	Floor.Forget()
	walk(FM, MAGIC, function() end)
	nearDock = 1009
	Floor.Sample(0, MAGIC.x, MAGIC.y)
	Floor.Forget()
	assert(not Floor.Landing(0), "forgotten, it goes too")
	-- Arriving at a landing far from the floor last followed (a portal on the same map) names no floor.
	nearDock = nil
	walk(FM, MAGIC, function() end)
	nearDock = 1009
	Floor.Sample(0, MAGIC.x + 40, MAGIC.y)
	at, z = Floor.Landing(0)
	assert(at and z == nil, "a floor followed elsewhere does not name the landing")
	nearDock = nil
end

-- Knocked off the ledge in combat, the fall still counts where you land once it ends.
do
	local height = offLedge(true, true)
	assert(height and height < 101, "a fall in combat lands below: " .. tostring(height))
end

-- A finished decode wakes the travel clock, so a player standing still is weighed without moving again.
do
	local woken = 0
	ns.WakeTravel = function()
		woken = woken + 1
	end
	Floor.Forget()
	Grid.Idle()
	Floor.Sample(0, SW_FM.x, SW_FM.y)
	drain()
	ns.WakeTravel = nil
	assert(woken > 0, "the decode woke the travel clock")
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

-- A spot picked on the Undercity's map is on the city's floor; one on Tirisfal's names the surface, and one on Tirisfal
-- away from the city names nothing, since only the city's own corner of that map lies over it.
do
	local input = assert(loadfile("tests/journey_driver.lua"))()
	input.env.C_Map.GetWorldPosFromMapPos = function(_, pos)
		return 0, {
			GetXY = function()
				return pos.x, pos.y
			end,
		}
	end
	-- The Undercity's map, 1458, covers world x 0.4 to 0.6 and y 0.4 to 0.6 in this small client (Data/Zones.lua).
	input.env.C_Map.GetMapPosFromWorldPos = function(_, world, id)
		local x, y = world:GetXY()
		return id, {
			GetXY = function()
				return (x - 0.4) / 0.2, (y - 0.4) / 0.2
			end,
		}
	end
	assert(input.ns.WorldPoint(1458, 0.5, 0.5).z == -43.1, "the Undercity's map is the city")
	assert(input.ns.WorldPoint(1420, 0.5, 0.5).z == 55.718, "Tirisfal over the city is the Ruins above it")
	assert(input.ns.WorldPoint(1420, 0.8, 0.8).z == nil, "Tirisfal away from the city is the open surface")
end

-- A ramp's link can climb from a cell whose base step in the same direction stays on the floor below. Every surface
-- the step reaches stays a candidate, so the tracked floor never settles on the floor below while you climb the ramp.
do
	local st = Grid.State(0)
	local C = st.C
	local gx0, gy0 = math.floor((1400 - st.x0) / st.cs), math.floor((100 - st.y0) / st.cs)
	local gx1, gy1 = math.floor((1800 - st.x0) / st.cs), math.floor((400 - st.y0) / st.cs)
	local checked, wrong = 0, {}
	for gx = gx0, gx1 do
		for gy = gy0, gy1 do
			local k, lc = math.floor(gx / C) * st.ny + math.floor(gy / C), (gx % C) * C + gy % C
			local val = Grid.grid(st, k)
			local l = val and val[lc + 1] ~= 0 and st.links[k][lc + 1]
			for e = 1, l and #l or 0 do
				local entry = l[e]
				local dx, dy = entry % 16 - 8, math.floor(entry / 16) % 16 - 8
				local tx, ty = gx + dx, gy + dy
				local tk, tlc = math.floor(tx / C) * st.ny + math.floor(ty / C), (tx % C) * C + ty % C
				local v = (dx ~= 0 or dy ~= 0)
					and math.abs(dx) <= 1
					and math.abs(dy) <= 1
					and Grid.surface(st, tk, tlc, math.floor(entry / 256) % 64 - 1, st.z[k][lc + 1])
				if v and v >= C * C then
					local z = st.z[tk][v + 1]
					local x, y = st.x0 + (gx + 0.5) * st.cs, st.y0 + (gy + 0.5) * st.cs
					Floor.Forget()
					Floor.Sample(0, x, y)
					drain()
					Floor.Sample(0, x, y)
					local h = Floor.Height(0, x, y)
					if h and math.abs(h - st.z[k][lc + 1]) <= 3 then
						checked = checked + 1
						local nx, ny = x + dx * st.cs, y + dy * st.cs
						Floor.Sample(0, nx, ny)
						drain()
						Floor.Sample(0, nx, ny)
						local after = Floor.Height(0, nx, ny)
						if after and math.abs(after - z) > 3 then
							wrong[#wrong + 1] = ("(%.1f, %.1f) z %s to z %s, tracked %s"):format(
								x,
								y,
								st.z[k][lc + 1],
								z,
								after
							)
						end
					end
				end
			end
		end
	end
	assert(checked > 0, "the Undercity has ramps to climb")
	assert(
		#wrong == 0,
		("%d of %d ramp steps leave the tracked floor below the ramp: %s"):format(
			#wrong,
			checked,
			table.concat(wrong, "; ", 1, math.min(#wrong, 3))
		)
	)
end

print("floor_spec: ok")

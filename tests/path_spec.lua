local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path = ns.Path

local frames = {}
Path.after = function(fn)
	frames[#frames + 1] = fn
end
local function drain()
	local n = 0
	while #frames > 0 do
		table.remove(frames, 1)()
		n = n + 1
	end
	return n
end

local function dist(ax, ay, bx, by)
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Nearest approach of the polyline to a point.
local function passes(points, x, y)
	local best = math.huge
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local dx, dy = b.x - a.x, b.y - a.y
		local len2 = dx * dx + dy * dy
		local t = len2 > 0 and math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / len2)) or 0
		best = math.min(best, dist(a.x + t * dx, a.y + t * dy, x, y))
	end
	return best
end

local GOLDSHIRE = { x = -9459, y = 43 }
local NORTHSHIRE = { x = -8914, y = -135 }
local STORMWIND_FM = { x = -8840.56, y = 489.7 } -- Data/Taxi.lua node 2

-- Goldshire to Stormwind goes round by the gate, not over the wall or through the moat.
local pts, len = Path.FindSync(0, GOLDSHIRE, STORMWIND_FM)
assert(pts, len)
local straight = dist(GOLDSHIRE.x, GOLDSHIRE.y, STORMWIND_FM.x, STORMWIND_FM.y)
assert(len > straight * 1.3 and len < 1300, len)
assert(passes(pts, -9068, 417) < 30, "misses the gate")
assert(pts[1].x == GOLDSHIRE.x and pts[#pts].y == STORMWIND_FM.y and pts[1].map == 0)

pts, len = Path.FindSync(0, NORTHSHIRE, GOLDSHIRE)
assert(pts and len > 580 and len < 700, len)

-- Landing at Stormwind's flight master and walking to the Mage Quarter, the pruned entrance graph routes through a
-- border entrance just east of the Trade District; the walk once ran out to it and straight back along one street.
pts = Path.FindSync(0, { x = STORMWIND_FM.x, y = STORMWIND_FM.y, z = 109.61 }, { x = -9100, y = 1200 })
assert(pts)
for i = 2, #pts - 1 do
	local a, b, c = pts[i - 1], pts[i], pts[i + 1]
	local level = a.z and c.z and math.abs(a.z - b.z) < 5 and math.abs(c.z - b.z) < 5
	local ux, uy, vx, vy = b.x - a.x, b.y - a.y, c.x - b.x, c.y - b.y
	local turn = (ux * vx + uy * vy) / (dist(a.x, a.y, b.x, b.y) * dist(b.x, b.y, c.x, c.y))
	assert(not (level and turn < -0.95), ("doubles back at %.0f, %.0f"):format(b.x, b.y))
end

-- A rooftop endpoint moves to the street below instead of failing.
assert(Path.FindSync(0, { x = -9010, y = 870 }, STORMWIND_FM))

-- An addon steering to that rooftop needs the walkable end of the route. The estimate still prices the same walk.
local rooftop = { x = -9010, y = 870 }
local steered, steeredYards, estimatedYards
Path.Find(0, STORMWIND_FM, rooftop, function(points, cost)
	steered, steeredYards = points, cost
end, false, nil, true)
Path.FindMany(0, STORMWIND_FM, { rooftop }, function(costs)
	estimatedYards = costs[1]
end)
drain()
assert(steered and #steered > 1 and steeredYards == estimatedYards, "steering uses the estimated running yards")
assert(steered[1].x == STORMWIND_FM.x and steered[1].y == STORMWIND_FM.y, "steering starts at the requested point")
local endpoint = steered[#steered]
assert(dist(endpoint.x, endpoint.y, rooftop.x, rooftop.y) > 0, "steering ends off the unreachable rooftop")
local legacy = assert(Path.FindSync(0, STORMWIND_FM, rooftop))
assert(legacy[#legacy].x == rooftop.x and legacy[#legacy].y == rooftop.y, "journey paths retain their requested end")

local none, why = Path.FindSync(0, { x = 0, y = 6000 }, GOLDSHIRE)
assert(none == nil and why == "outside", why)
none, why = Path.FindSync(1, { x = 0, y = 0 }, { x = 1, y = 1 })
assert(none == nil and why == "nodata", why)
assert(Path.HasData(0) and not Path.HasData(1))

-- The sliced search gives the sync result and spreads over frames.
local got, gotLen, gotJob
local job = Path.Find(0, GOLDSHIRE, STORMWIND_FM, function(p, l, j)
	got, gotLen, gotJob = p, l, j
end)
Path.budget = 0.05
drain()
Path.budget = 3
local syncPts, syncLen = Path.FindSync(0, GOLDSHIRE, STORMWIND_FM)
assert(gotJob == job and job.frames > 1, job.frames)
assert(math.abs(gotLen - syncLen) < 1e-6 and #got == #syncPts)

local cancelled = false
local first = Path.Find(0, NORTHSHIRE, GOLDSHIRE, function()
	cancelled = true
end)
Path.Cancel(first)
drain()
assert(not cancelled)

-- Cancelling a partially searched route frees the next frame for its replacement.
Path.budget = -1
local abandoned = Path.Find(0, GOLDSHIRE, STORMWIND_FM, function()
	error("cancelled search called back")
end)
table.remove(frames, 1)()
assert(abandoned.frames == 1 and coroutine.status(abandoned.co) == "suspended")
Path.Cancel(abandoned)
local replacement = Path.Find(0, NORTHSHIRE, GOLDSHIRE, function(p)
	assert(p)
end)
table.remove(frames, 1)()
assert(replacement.frames == 1 and abandoned.frames == 1, "cancelled work must not hold up the queue")
Path.budget = 3
drain()

-- A coroutine error reports a terminal result and leaves subsequent jobs runnable.
local previousHandler, reported, failure = rawget(_G, "geterrorhandler")
rawset(_G, "geterrorhandler", function()
	return function(message)
		reported = message
	end
end)
local failed = Path.Find(0, { x = "invalid", y = 0 }, GOLDSHIRE, function(p, reason, finished)
	assert(p == nil and reason == "error")
	assert(not failure, "a failed job completes only once")
	failure = finished
end)
local recovered
Path.Find(0, NORTHSHIRE, GOLDSHIRE, function(p)
	recovered = p
end)
drain()
rawset(_G, "geterrorhandler", previousHandler)
assert(reported and failure == failed and recovered, "errors must not strand Journey's pending count")

-- Coordinates: the navmesh stands where the addon's pins stand (UnitPosition frame, x north, y west).
-- Transport/Taxi.lua Stormwind flight master and Transports.lua tram pin, each with a nearby street point.
for _, pin in ipairs({ { -8840.56, 489.7, 0, -20 }, { -8346.46, 514.031, 8, 0 } }) do
	local p = Path.FindSync(0, { x = pin[1], y = pin[2] }, { x = pin[1] + pin[3], y = pin[2] + pin[4] })
	assert(p, "no mesh at pin " .. pin[1] .. "," .. pin[2])
end

-- Separate doors on one cluster border keep their own entrances even when the rooms join elsewhere (#910).
-- The source collision connects these places through the northeast corridor, not the Military Ward loop.
local EXPLORERS = { x = -4739.1, y = -1248, z = 502 }
local TINKER_TOWN = { x = -4788.7, y = -1249.6, z = 503 }
for _, ends in ipairs({ { EXPLORERS, TINKER_TOWN }, { TINKER_TOWN, EXPLORERS } }) do
	pts, len = Path.FindSync(0, ends[1], ends[2])
	assert(pts and len < 400, len)
	assert(passes(pts, -4804, -1278) < 15, "misses Ironforge's connecting corridor")
end

-- Levels: a road through a tunnel under walkable ground, and a city under a city.
-- Ironforge to Menethil crosses the mountains north, no face steeper than 50 degrees on the way up, rather than round
-- by Arathi (about 18,600 yards on one level).
local IRONFORGE_FM = { x = -4821.78, y = -1155.44, z = 502.21 } -- Data/Taxi.lua node 6
local MENETHIL_FM = { x = -3792.26, y = -783.29, z = 9.06 } -- node 7
pts, len = Path.FindSync(0, IRONFORGE_FM, MENETHIL_FM)
assert(pts and len < 8000, len)
assert(pts[1].z and pts[#pts].z, "points carry heights")
-- The Dun Algaz road, either side of the tunnel, walks through it rather than over the ridge above.
local ALGAZ_SOUTH, ALGAZ_NORTH = { x = -4350.2, y = -2463.7, z = 216 }, { x = -4087.6, y = -2463.7, z = 156 }
for _, ends in ipairs({ { ALGAZ_SOUTH, ALGAZ_NORTH }, { ALGAZ_NORTH, ALGAZ_SOUTH } }) do
	pts = Path.FindSync(0, ends[1], ends[2])
	assert(pts and passes(pts, -4220, -2464) < 30, "misses the Dun Algaz tunnel")
end

-- A walk against its reference: the shortest walk on the raw navmesh the map was baked from (A* over its walkable
-- polys, then funnel string-pulling, horizontal yards; tools/nav_reference.py over the client 1.60.1.70938 tiles).
-- The grid's eight directions make a walk up to 1 / cos 22.5 degrees longer than the straight path, and each end may
-- stand its distance from its cell's centre away from the grid.
local OCTILE = 1 / math.cos(math.pi / 8)
local function nearReference(from, to, reference, what)
	local st = ns.PathGrid.State(0)
	local slack = 0
	for _, p in ipairs({ from, to }) do
		local cx = st.x0 + (math.floor((p.x - st.x0) / st.cs) + 0.5) * st.cs
		local cy = st.y0 + (math.floor((p.y - st.y0) / st.cs) + 0.5) * st.cs
		slack = slack + dist(p.x, p.y, cx, cy)
	end
	local points, cost = Path.FindSync(0, from, to)
	assert(points, what .. " is unreachable")
	assert(
		cost >= reference - slack and cost <= reference * OCTILE + slack,
		("%s costs %.1f, reference %.1f"):format(what, cost, reference)
	)
	return points
end

-- Up the pass from the tunnel to Loch Modan, and on from the Wetlands to Thelsamar: the walk climbs the Dun Algaz road
-- rather than looping round Grim Batol past Stonewrought Dam. The ramp's floor cells once stored a poly centroid's
-- height, five yards off, so one step up read as a climb past 50 degrees and the pass walked one way only (#1011).
local PASS_TOP = { x = -4668.7, y = -2694.5, z = 323 }
nearReference(ALGAZ_SOUTH, PASS_TOP, 486.5, "up the Dun Algaz pass")
nearReference(PASS_TOP, ALGAZ_SOUTH, 486.3, "down the Dun Algaz pass")
pts = nearReference(
	{ x = -3900, y = -2500, z = 108 },
	{ x = -5378, y = -2973, z = 324 },
	2024.4,
	"Wetlands to Thelsamar"
)
assert(passes(pts, -4220, -2464) < 30, "Wetlands to Thelsamar misses the Dun Algaz tunnel")

-- An Ironforge ramp the navmesh walks (ordinary ground) rises 10.5 yards over one 8 yard cell, past 50 degrees: the
-- walk takes it both ways rather than a detour up, as the client does (#1011).
local RAMP_FOOT, RAMP_TOP = { x = -4971.1, y = -991.0, z = 718 }, { x = -4963.2, y = -991.0, z = 728 }
nearReference(RAMP_FOOT, RAMP_TOP, 7.9, "up the Ironforge ramp")
nearReference(RAMP_TOP, RAMP_FOOT, 7.9, "down the Ironforge ramp")

-- Undercity: the flight master stands by the west lift's bottom landing, and its top is a long way round on foot.
local UNDERCITY_FM = { x = 1568.62, y = 267.97, z = -43.1 } -- node 11
local WEST_LIFT = { x = 1596.15, y = 291.8 } -- Data/Transports.lua docks 1009 (top) and 1010 (bottom)
local _, near = Path.FindSync(0, UNDERCITY_FM, { x = WEST_LIFT.x, y = WEST_LIFT.y, z = -40.784 })
local _, far = Path.FindSync(0, UNDERCITY_FM, { x = WEST_LIFT.x, y = WEST_LIFT.y, z = 55.718 })
assert(type(near) == "number" and near < 150, near)
assert(type(far) == "number" and far > 1000, far)
-- From the top, the surface road leads on to Tarren Mill.
assert(Path.FindSync(0, { x = WEST_LIFT.x, y = WEST_LIFT.y, z = 55.718 }, { x = -0.06, y = -859.91, z = 58.83 }))

-- Across Loch Modan: on foot the walk goes round over Stonewrought Dam, walking on water it goes straight over.
local THELSAMAR_SHORE, WEST_SHORE = { x = -5293, y = -3157 }, { x = -5773, y = -3287 }
local round, roundCost = Path.FindSync(0, THELSAMAR_SHORE, WEST_SHORE)
local over, overCost = Path.FindSync(0, THELSAMAR_SHORE, WEST_SHORE, true)
assert(round and over)
assert(round.wet < 50 and over.wet > 300, round.wet .. " " .. over.wet)
assert(overCost < 550 and roundCost > overCost + 100, roundCost .. " " .. overCost)

-- The reported Darkshore route: reachable Felwood points go round the mountains; neighbouring map clicks can
-- miss every walkable surface. Both outcomes must arrive through the sliced callback as well as FindSync.
assert(loadfile("tools/load_nav.lua"))(1)
local AUBERDINE = { x = 6341.38, y = 557.68, z = 16.29 }
for _, target in ipairs({
	{ x = 5068.4, y = -337.22 },
	{ x = 6205.88, y = -1949.63 },
	{ x = 5000, y = -2000 },
	{ x = 5500, y = -1500 },
	{ x = 4800, y = -1200 },
}) do
	local expected, cost = Path.FindSync(1, AUBERDINE, target)
	local done
	Path.Find(1, AUBERDINE, target, function(p, c)
		done = true
		assert(c == cost and (p and #p) == (expected and #expected))
		if p then
			assert(#p > 2 and c > dist(AUBERDINE.x, AUBERDINE.y, target.x, target.y) * 2)
		else
			assert(c == "offmesh")
		end
	end)
	drain()
	assert(done)
end

-- Base-water yards for the flat beach and water fixtures below. Layered routes need their own floor checks.
local function wetYards(map, a, b)
	local Grid, st = ns.PathGrid, ns.PathGrid.State(map)
	local length = dist(a.x, a.y, b.x, b.y)
	local steps = math.max(1, math.ceil(length / 0.5))
	local wet = 0
	for step = 1, steps do
		local t = step / steps
		local k, lc = Grid.locate(st, a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
		local val = k and Grid.grid(st, k)
		if val and val[lc + 1] == 2 then
			wet = wet + length / steps
		end
	end
	return wet
end

-- #742: a walk the router paid for on land must not be drawn as a swim. The Darkshore walk round the bay is drawn
-- along the beach, no slower than the route it replaces; only the water both ends stand in is crossed.
local BAY_EAST, BAY_WEST = { x = 6401.38, y = 597.68 }, { x = 6261.38, y = 617.68 }
local bay, bayCost = Path.FindSync(1, BAY_EAST, BAY_WEST)
assert(bay and bayCost, "the bay walk is found")
assert(#bay > 2, "the walk round the bay is not drawn as one chord")
local swim = ns.PathGrid.State(1).swim
local bayTime = 0
for i = 2, #bay do
	local length, wet = dist(bay[i - 1].x, bay[i - 1].y, bay[i].x, bay[i].y), wetYards(1, bay[i - 1], bay[i])
	bayTime = bayTime + length + wet * (swim - 1)
	if i > 2 and i < #bay then
		assert(wet == 0, "the beach between the two ends is dry")
	end
end
-- The route's cost is the grid's: each end point counts as its own cell. The drawn line starts and ends at the points
-- themselves, so it also walks (or swims) from each point to its cell's centre, which the cost leaves out.
local function cellOffset(map, p)
	local Grid, st = ns.PathGrid, ns.PathGrid.State(map)
	local gx, gy = (p.x - st.x0) / st.cs, (p.y - st.y0) / st.cs
	local yards = math.sqrt((gx - math.floor(gx) - 0.5) ^ 2 + (gy - math.floor(gy) - 0.5) ^ 2) * st.cs
	local k, lc = Grid.locate(st, p.x, p.y)
	return Grid.grid(st, k)[lc + 1] == 2 and yards * st.swim or yards
end
local endOffsets = cellOffset(1, BAY_EAST) + cellOffset(1, BAY_WEST)
assert(
	bayTime <= bayCost + endOffsets,
	("the drawn walk is no slower than its route: %.1f against %.1f and %.1f to the cell centres"):format(
		bayTime,
		bayCost,
		endOffsets
	)
)

-- A drawn segment is charged for each cell it crosses as that cell: half a dry cell and half a wet one is half a
-- walk and half a swim, either way across the shore, never a whole swim or a whole walk.
do
	local Grid, st = ns.PathGrid, ns.PathGrid.State(1)
	local shore
	for gx = 2394, 2412 do
		for gy = 1205, 1220 do
			local k, lc = Grid.locate(st, st.x0 + (gx + 0.5) * st.cs, st.y0 + (gy + 0.5) * st.cs)
			local k2, lc2 = Grid.locate(st, st.x0 + (gx + 1.5) * st.cs, st.y0 + (gy + 0.5) * st.cs)
			local a, b = Grid.grid(st, k)[lc + 1], Grid.grid(st, k2)[lc2 + 1]
			if not shore and a ~= b and (a == 1 or a == 2) and (b == 1 or b == 2) then
				local P = { swim = st.swim }
				local tk, tn, time = Grid.toward(
					st,
					P,
					k,
					lc,
					gx + 0.5,
					gy + 0.5,
					gx + 1.5,
					gy + 0.5,
					true,
					nil,
					math.huge,
					true,
					k2,
					lc2
				)
				if tk == k2 and tn == lc2 then
					shore = time
				end
			end
		end
	end
	local half = st.cs / 2
	assert(shore, "a shore step is found on the bay")
	assert(
		math.abs(shore - (half + half * st.swim)) < 1e-6,
		("a shore cell is half a walk, half a swim: %.3f"):format(shore)
	)
end

-- Distinct points on one water node must pay both connectors even when the grid walk is empty.
local bayGrid = ns.PathGrid
local bayState = bayGrid.State(1)
local bk, bc = bayGrid.locate(bayState, BAY_EAST.x, BAY_EAST.y)
local cx = bayState.x0 + (math.floor(bk / bayState.ny) * bayState.C + math.floor(bc / bayState.C) + 0.5) * bayState.cs
local cy = bayState.y0 + (bk % bayState.ny * bayState.C + bc % bayState.C + 0.5) * bayState.cs
local eastOffset = { x = cx - 1, y = cy, z = bayState.z[bk][bc + 1] }
local westOffset = { x = cx + 2, y = cy, z = eastOffset.z }
local _, withinCell = Path.FindSync(1, eastOffset, westOffset)
assert(withinCell == 3 * swim, ("both water connectors cost %.1f, got %.1f"):format(3 * swim, withinCell))
westOffset.x = cx + 3
local _, shifted = Path.FindSync(1, eastOffset, westOffset)
assert(shifted == 4 * swim, "a new offset in the same cell changes the cached path cost")
local _, walking = Path.FindSync(1, eastOffset, westOffset, true)
assert(walking == 4, "water walking charges the connectors at running speed")
assert(Path.FindManySync(1, eastOffset, { westOffset })[1] == shifted, "forward batch counts both connectors")
assert(
	Path.FindManySync(1, westOffset, { eastOffset }, false, true)[1] == shifted,
	"reverse batch counts both connectors"
)
assert(Path.FindManySync(1, eastOffset, { eastOffset })[1] == 0, "a co-located transfer costs zero")

local batch = { map = 1, from = eastOffset, sourceCluster = bk, sourceNode = bc }
local moved = { map = 1, x = cx, y = cy, z = eastOffset.z }
assert(not Path.ReuseMany(batch, moved), "moving within the cell invalidates its exact batch costs")
assert(Path.ReuseMany(batch, moved, true), "the sliced query can still match a surface for a baked bound")

-- The finer entrance graph finds the dry floor above the strait's water. Its explicit downward landing reaches
-- the shore; sampling only the base water would mistake this layered walk for a swim.
local dryStrait, dryCost = Path.FindSync(0, { x = -14961.19, y = 274.63 }, { x = -14897.51, y = 274.63 })
assert(dryStrait and dryStrait.wet == 0 and dryCost < 140, "the strait's dry floor reaches the shore")
local StraitGrid, straitState = ns.PathGrid, ns.PathGrid.State(0)
local floorK, floorCell = StraitGrid.locate(straitState, -14969.154228856, 282.58706467662)
local floorValues = StraitGrid.grid(straitState, floorK)
local floorNode = StraitGrid.surface(straitState, floorK, floorCell, 1, 14)
assert(floorValues[floorCell + 1] == 2 and floorNode and floorValues[floorNode + 1] == 1)
assert(
	straitState.z[floorK][floorNode + 1] > straitState.z[floorK][floorCell + 1] + 10,
	"the dry floor is above the base water"
)

-- Nearby, a walk that really swims is still pulled straight across the water its own entries swam. The row holds the
-- water entrance on the cluster border at x -14933, so the swim's route is the straight one.
local STRAIT_EAST, STRAIT_WEST = { x = -14961.19, y = 242.83 }, { x = -14897.51, y = 242.83 }
local strait, straitCost = Path.FindSync(0, STRAIT_EAST, STRAIT_WEST)
assert(strait and straitCost and strait.wet > 15, "the strait walk swims")
local swam = 0
for i = 2, #strait do
	swam = math.max(swam, wetYards(0, strait[i - 1], strait[i]))
end
assert(swam > 20, ("the drawn walk crosses the water it swam: %.1f yards"):format(swam))

-- Heights: the player's is unknown (UnitPosition's is a placeholder 0), and a point without one starts from whichever
-- surface at its spot walks cheapest. A Trade District street over the canal walks out by the Valley of Heroes gate,
-- not from the canal bed round the city (the reported loop through Cathedral Square and Old Town).
local TRADE_STREET = { x = -8876.2, y = 610.9 }
pts, len = Path.FindSync(0, TRADE_STREET, { x = -9068, y = 417 })
assert(pts and len < 350, len)
for i = 2, #pts - 1 do
	assert(pts[i].z > 85, "walks the canal bed")
end
-- The 50 to 61.6 degree band (#639) keeps the slide into the bed under it as a down-only step, so a point at the
-- bed's height starts on the bed until walks begin from the player's measured floor (#737). Ground a drop reaches is
-- kept with its way out, so the walk follows the bed west and leaves it only by the gate, never climbing back into
-- the streets; a street point still walks out by the gate.
local BED = { x = TRADE_STREET.x, y = TRADE_STREET.y, z = 74 }
local street = Path.FindSync(0, TRADE_STREET, GOLDSHIRE)
assert(passes(street, -8520, 960) > 100 and passes(Path.FindSync(0, BED, GOLDSHIRE), -8520, 960) > 100, "goes round")
pts = Path.FindSync(0, BED, { x = -9068, y = 417 })
for i = 2, #pts - 1 do
	assert(pts[i].z < 85 or pts[i].x < -9050, "climbs out of the bed into the streets")
end
-- A zeppelin dock stands at its transport's height: Grom'gol's tower platform, not the beach below it.
assert(loadfile("Data/Routes.lua"))("ShortestPathForever", ns)
local tower = ns.Docks[11]
pts = Path.FindSync(0, tower, GOLDSHIRE)
assert(tower.z and pts and pts[2].z > 25, "boards from the beach")

-- The string is pulled between node centres, but each walk is drawn from the endpoints themselves. Its first and last
-- segments must not cut across cells the walking map has no surface for (fitzforge, #144): count the yards each end
-- segment spends over such cells, past the bare run touching the endpoint, where the point itself may stand.
local Grid = ns.PathGrid
local function bare(map, x, y)
	local st = Grid.State(map)
	return Grid.bare(st, math.floor((x - st.x0) / st.cs), math.floor((y - st.y0) / st.cs))
end
local function bareEnds(map, points)
	local yards = 0
	for _, segment in ipairs({ { points[2], points[1] }, { points[#points - 1], points[#points] } }) do
		local a, b = segment[1], segment[2]
		local length = dist(a.x, a.y, b.x, b.y)
		local steps = math.max(1, math.floor(length / 0.5))
		local last = steps
		while last >= 0 and bare(map, a.x + (b.x - a.x) * last / steps, a.y + (b.y - a.y) * last / steps) do
			last = last - 1
		end
		for step = 0, last do
			if bare(map, a.x + (b.x - a.x) * step / steps, a.y + (b.y - a.y) * step / steps) then
				yards = yards + length / steps
			end
		end
	end
	return yards
end
-- A map click to Stonard's flight master, and out of Everlook, where the start's own cell is the snapped one: both
-- crossed 6 to 8 yards of rock or building on an end segment when drawn straight from the point.
for _, walk in ipairs({
	{ 0, { x = -10582.4, y = -3130.91 }, { x = -10456.97, y = -3279.25, z = 21.35 } },
	{ 1, { x = 6799.24, y = -4742.44, z = 701.5 }, { x = 7076.63, y = -4809.55 } },
}) do
	local drawn, cost = Path.FindSync(walk[1], walk[2], walk[3])
	assert(drawn and cost, "the end-segment walks are found")
	assert(drawn[1].x == walk[2].x and drawn[#drawn].y == walk[3].y, "the line still starts and ends at the points")
	assert(bareEnds(walk[1], drawn) == 0, "no end segment cuts across cells with no surface")
end

print("path_spec: ok")

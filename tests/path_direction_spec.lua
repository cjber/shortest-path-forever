-- Directed walking maps (#638, #639): steep ground is walked down only, a ledge drop is one way, a format 1 map still
-- decodes as it always did, and the local and abstract searches charge a drop the same cost.
local ns = {}
local fixture = assert(loadfile("tests/nav_fixture.lua"))()
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path, Grid = ns.Path, ns.PathGrid
local TILE = 1600 / 3
local CS = TILE / 67

-- A format 2 map in two clusters (three ADT tiles wide would be needed for more): ordinary ground, a steep step down,
-- a ledge drop inside a cluster and one across the boundary between them.
local function at(z, extra)
	local cell = { z = z }
	for key, value in pairs(extra or {}) do
		cell[key] = value
	end
	return cell
end
local UPHILL, DOWNHILL = 32, 20 -- a 12 yard face: too high for the endpoint rescue's 10 yard allowance
local FALL = 12 -- above the endpoint rescue's 10 yard allowance, below the 14.57 yards that hurt
local DROP = math.floor(0.5 + CS + 7 * math.sqrt(2 * FALL / 19.2911)) -- yards of walking plus the fall
local cells = {
	[20] = { [40] = at(20) },
	[21] = { [40] = at(20) },
	[30] = { [40] = at(UPHILL) },
	[31] = { [40] = at(DOWNHILL, { steep = true }) },
	[40] = { [40] = at(20 + FALL) },
	[41] = { [40] = at(20) },
	[66] = { [40] = at(20 + FALL, { flags = 1 }) },
	[67] = { [40] = at(20) },
}
-- The steep step is an ordinary signed bit: the decoder lets it downhill only, from the stored heights.
cells[40][40].flags = 1 -- the drop's high side: the grid step down is closed
-- The 66/67 pair is the only cross-cluster link, so both clusters need an entrance.
local map42 = fixture.format2({
	map = 42,
	nx = 2,
	ny = 1,
	cell = cells,
	link = {
		{ 40, 40, 1, 0, DROP }, -- a ledge drop
		{ 66, 40, 1, 0, DROP }, -- the same drop across a cluster boundary
	},
	node = {
		{ 66, 40, 1, out = { { 67, 40, DROP, DROP } } },
		{ 67, 40, 1 },
	},
})
fixture.install(42, map42)

local function point(gx, gy, z)
	return { x = (gx + 0.5) * CS, y = (gy + 0.5) * CS, z = z }
end

local function fails(map, ...)
	local points, why = Path.FindSync(map, ...)
	assert(points == nil, "the walk must not exist")
	return why
end

-- Ordinary ground stays two-way and is charged its horizontal step.
local forward, forwardCost = Path.FindSync(42, point(20, 40), point(21, 40))
local backward, backwardCost = Path.FindSync(42, point(21, 40), point(20, 40))
assert(forward and backward, "ordinary ground must walk both ways")
assert(math.abs(forwardCost - backwardCost) < 1e-9 and forwardCost > CS * 0.5, forwardCost)

-- Steep ground is walked down only, at the ordinary cost: slope never changes speed. The step itself is a symmetric
-- bit in the grid, so the decoder's stored-height check is what makes it one-way.
assert(Path.FindSync(42, point(30, 40, UPHILL), point(31, 40, DOWNHILL)))
assert(fails(42, point(31, 40, DOWNHILL), point(30, 40, UPHILL)) == "unreachable", "climbs the steep face")
local steepCost = select(2, Path.FindSync(42, point(30, 40, UPHILL), point(31, 40, DOWNHILL)))
assert(steepCost > CS * 0.5 and steepCost < CS * 1.5, steepCost)
local steepState = Grid.State(42)
local steepCell = 30 * 67 + 40
local steepMoves = steepState.moves[0][steepCell + 1] % 16
assert(steepMoves % 2 == 1, "the steep step is open in the grid's symmetric bits")
assert(steepState.links[0][steepCell + 1] == nil, "and needs no directed record")
assert(steepState.linksIn[0][steepCell + 1] == nil, "nor an inbound record")

-- A ledge drop is used going down and never up.
local drop, dropCost = Path.FindSync(42, point(40, 40, 20 + FALL), point(41, 40, 20))
assert(drop and dropCost, "the drop is the way down")
assert(math.abs(dropCost - DROP) < 1e-9, dropCost .. " against " .. DROP)
assert(fails(42, point(41, 40, 20), point(40, 40, 30)) == "unreachable", "climbs the drop")

-- The same drop across a cluster boundary: the abstract edge is one-way too.
local across, acrossCost = Path.FindSync(42, point(66, 40, 20 + FALL), point(67, 40, 20))
assert(across and math.abs(acrossCost - DROP) < 1e-9, tostring(acrossCost))
assert(fails(42, point(67, 40, 20), point(66, 40, 30)) == "unreachable", "climbs the cross-cluster drop")

-- Local and abstract searches charge a drop the same: the same fall costs the same either side of a boundary.
assert(math.abs(dropCost - acrossCost) < 1e-9, "local and abstract drop costs disagree")

-- Batches: no endpoint rescue, so a batch walks the drop's direction only. A reverse batch walks the edges that
-- reach `from`, which is what makes a one-way drop safe there.
local function many(from, to, reverse)
	local costs = Path.FindManySync(42, from, { to }, nil, reverse)
	return costs[1]
end
assert(many(point(40, 40, 20 + FALL), point(41, 40, 20)) == DROP, "forward batch crosses the drop")
assert(many(point(41, 40, 20), point(40, 40, 20 + FALL)) == false, "forward batch climbs the drop")
assert(many(point(67, 40, 20), point(66, 40, 20 + FALL), true) == DROP, "reverse batch crosses the drop the right way")
assert(many(point(66, 40, 20 + FALL), point(67, 40, 20), true) == false, "reverse batch climbs the drop")
-- A steep step lives in the grid's symmetric bits, so both batch directions must apply the stored-height rule.
assert(many(point(30, 40, UPHILL), point(31, 40, DOWNHILL)) ~= false, "forward batch walks the steep face down")
assert(many(point(31, 40, DOWNHILL), point(30, 40, UPHILL)) == false, "forward batch does not climb it")
assert(many(point(31, 40, DOWNHILL), point(30, 40, UPHILL), true) ~= false, "reverse batch walks it down into `from`")
assert(many(point(30, 40, UPHILL), point(31, 40, DOWNHILL), true) == false, "reverse batch does not climb it")

-- The decoded map is outbound only, and the reverse records exist for the local search's reverse direction.
local st = Grid.State(42)
assert(st.fmt == 2)
assert(Grid.grid(st, 0))
local ledge = 40 * 67 + 40
local links = st.links[0][ledge + 1]
assert(links and #links == 1, "the ledge leaves exactly one link")
local entry = links[1]
assert(entry % 16 - 8 == 1 and math.floor(entry / 16) % 16 - 8 == 0, "the link steps +x")
assert(math.floor(entry / 16384) == DROP, "the link keeps its cost override")
local landing = 41 * 67 + 40
local back = st.linksIn[0][landing + 1]
assert(back and #back == 1, "the landing has the reverse record")
assert(back[1] % 16 - 8 == -1 and math.floor(back[1] / 16) % 16 - 8 == 0, "the reverse record steps back")
assert(math.floor(back[1] / 16384) == DROP, "the reverse record keeps the cost")
assert(st.linksIn[0][ledge + 1] == nil, "the ledge is not entered from its landing")

-- Graph direction: the cross-cluster drop edge exists one way, and a reverse search reaches it from the source's
-- outbound record, which is all the file stores.
local nodes0, nodes1 = Grid.nodesOf(st, 0), Grid.nodesOf(st, 1)
assert(#nodes0 == 1 and #nodes1 == 1)
local a, b = nodes0[1], nodes1[1]
-- the format 2 node record is seven symbols, as format 1's: a wrong stride would read a neighbour's cell
local cellA, layerA, compA = Grid.metadata(st, a)
assert(cellA == 66 * 67 + 40 and layerA == 0 and compA == 1, "the entrance's own cell")
assert(Grid.entrance(st, a) == 66 * 67 + 40, "the entrance lands on its cell's base surface")
local cellB = Grid.metadata(st, b)
assert(cellB == 0 * 67 + 40, "the landing's own cell")
local out = Grid.adjacent(st, a)
assert(#out == 3 and out[1] == b and out[2] == DROP and out[3] == DROP, "the drop leaves its cluster")
assert(#Grid.adjacent(st, b) == 0, "the landing has no way back")
local into = Grid.preceding(st, b)
assert(#into == 3 and into[1] == a and into[2] == DROP, "the landing is entered by the drop")
assert(#Grid.preceding(st, a) == 0, "the ledge is entered by nothing")

-- Format 1 maps decode exactly as they did: symmetric step codes, a floor whose link is mirrored on the base cell.
local map43 = fixture.format1()
fixture.install(43, map43)
local old = Grid.State(43)
assert(old.fmt == 1)
assert(Grid.grid(old, 0))
local function cell(gx, gy)
	return gx * 67 + gy
end
local strip = cell(5, 10)
assert(old.z[0][strip + 1] == 20 and old.z[0][cell(5, 12) + 1] == 20, "heights")
local mi = old.moves[0][strip + 1] % 16
assert(mi % 2 == 0, "the close flag shut the +x step")
assert(mi % 4 >= 2, "the +y step stays open")
-- the floor above the middle cell, its +y step bit, and its explicit -y link to the base cell
local floor = 67 * 67
assert(old.z[0][floor + 1] == 23)
assert(old.at[0][-(cell(5, 11) + 1)] == floor)
local fl = old.links[0][floor + 1]
assert(fl and #fl == 2, "the floor has its step and its explicit link")
assert(fl[1] == 2 or fl[2] == 2, "the step bit decodes as +y")
assert(fl[1] == 11 or fl[2] == 11, "the explicit link decodes as +x onto the base surface")
-- the base cells the floor links to now have the mirrored links, which format 2 never synthesizes: the explicit
-- link was -y, so its mirror is +y onto layer 1, and the step bit was +y, so its mirror is -y
local function mirror(c, direction)
	for _, l in ipairs(old.links[0][c + 1] or {}) do
		if l % 8 == direction and math.floor(l / 8) - 1 == 1 then
			return true
		end
	end
	return false
end
assert(mirror(cell(5, 10), 2), "the explicit link is mirrored on the base cell below")
assert(mirror(cell(5, 12), 3), "the step bit is mirrored on the base cell above")
-- the symmetric graph decodes both ways with identical costs
local ids = Grid.nodesOf(old, 0)
assert(#ids == 2)
local e = Grid.adjacent(old, ids[1])
assert(#e == 3 and e[1] == ids[2] and e[2] == 16 and e[3] == 16)
local r = Grid.adjacent(old, ids[2])
assert(#r == 3 and r[1] == ids[1] and r[2] == 16 and r[3] == 16)

-- Endpoint rescue: format 1 keeps the 30-yard reach its bake shipped with; format 2 knows falling hurts past 14.57
-- yards. The start sits on an isolated ledge 20 yards above a connected strip, three cells away.
local cliff = {
	[5] = { [10] = at(20), [11] = at(20), [12] = at(20) },
	[8] = { [10] = at(40) },
}
fixture.install(44, fixture.format2({ map = 44, nx = 1, ny = 1, cell = cliff, node = { { 5, 10, 1 } } }))
fixture.install(45, fixture.format1_cells({ map = 45, nx = 1, ny = 1, cell = cliff, node = { { 5, 10, 1 } } }))
local high, low = point(8, 10, 40), point(5, 12, 20)
assert(Path.FindSync(45, high, low), "format 1 keeps the 30-yard endpoint rescue")
assert(fails(44, high, low) == "unreachable", "format 2 rejects a rescue past 14.57 yards")

-- Reverse batches follow the edges that reach a node, so their road ratios must be the predecessors' outbound ones.
-- B is entered by A but leaves nothing; reading its outbound ratio list would index nil.
local roadCells = { [20] = { [10] = at(20) }, [21] = { [10] = at(20) } }
fixture.install(
	46,
	fixture.format2({
		map = 46,
		nx = 1,
		ny = 1,
		cell = roadCells,
		node = {
			{ 20, 10, 1, out = { { 21, 10, 16, 16 } } },
			{ 21, 10, 1 },
		},
	})
)
local roadProfile = {
	roads = true,
	key = "roads",
	Point = function()
		return 1
	end,
	Near = function()
		return false
	end,
	Chord = function()
		return 0
	end,
	Charged = function()
		return false
	end,
}
local plainReverse = Path.FindManySync(46, point(21, 10, 20), { point(20, 10, 20) }, nil, true)[1]
local roadReverse = Path.FindManySync(46, point(21, 10, 20), { point(20, 10, 20) }, nil, true, roadProfile)[1]
assert(plainReverse and roadReverse, "the reverse batch must reach the target through the edge into its source")
assert(math.abs(plainReverse - roadReverse) < 1e-9, "a default road ratio leaves the real cost unchanged")
local roadState = Grid.State(46)
assert(Grid.grid(roadState, 0))
local bNode = Grid.nodesOf(roadState, 0)[2]
assert(#Grid.preceding(roadState, bNode) == 3 and #Grid.adjacent(roadState, bNode) == 0)
assert(#Grid.roadEdgesIn(roadState, bNode) == 4, "the predecessor edge has its own ratio")

-- A drop between two floors of one cell is a same-cell link: offset (0, 0), landing on the lower layer.
local sameCells = { [20] = { [10] = at(20) } }
fixture.install(
	47,
	fixture.format2({
		map = 47,
		nx = 1,
		ny = 1,
		cell = sameCells,
		floor = { { 20, 10, 10, 1 } },
		link = { { 20, 10, 0, 0, 7, 1 } },
		node = { { 20, 10, 1 } },
	})
)
local same = Grid.State(47)
assert(same.fmt == 2 and Grid.grid(same, 0))
local spot = 20 * 67 + 10
local floorNode = 67 * 67
assert(same.at[0][-(spot + 1)] == floorNode, "the cell's floor node")
assert(same.z[0][floorNode + 1] == 10, "the floor height")
local sameLink = same.links[0][spot + 1]
assert(sameLink and #sameLink == 1)
assert(sameLink[1] % 16 - 8 == 0 and math.floor(sameLink[1] / 16) % 16 - 8 == 0, "the same-cell offset")
assert(math.floor(sameLink[1] / 256) % 64 - 1 == 1, "the link lands on floor 1")
assert(math.floor(sameLink[1] / 16384) == 7, "the link keeps its cost")
local reverseSame = same.linksIn[0][floorNode + 1]
assert(reverseSame and #reverseSame == 1, "the floor has the reverse record")
assert(
	reverseSame[1] % 16 - 8 == 0 and math.floor(reverseSame[1] / 16) % 16 - 8 == 0,
	"the reverse record stays in the cell"
)
assert(math.floor(reverseSame[1] / 256) % 64 - 1 == 0, "the reverse record lands on the base surface")
local nk, nn = Grid.neighbour(same, 0, spot, 20, 10, 0, 0, false)
assert(nk == 0 and nn == floorNode, "the decoder walks a same-cell link")

-- A step both ways take is one bit on the floor, as format 1 writes it: the decoder resolves it by height and mirrors
-- it on the surface it lands on, so both ends walk to each other without a record.
local masked = { [20] = { [10] = at(20), [11] = at(20) } }
fixture.install(
	51,
	fixture.format2({
		map = 51,
		nx = 1,
		ny = 1,
		cell = masked,
		floor = { { 20, 10, 23, 1, 2 ^ 2 } }, -- +y, from the floor to the base surface of (20, 11)
		node = { { 20, 10, 1 } },
	})
)
local bit = Grid.State(51)
assert(bit.fmt == 2 and Grid.grid(bit, 0))
local over = 67 * 67
local beside = 20 * 67 + 11
assert(bit.z[0][over + 1] == 23)
local lifted = bit.links[0][over + 1]
assert(lifted and #lifted == 1, "the floor's step bit is its own link")
assert(lifted[1] % 16 - 8 == 0 and math.floor(lifted[1] / 16) % 16 - 8 == 1, "the floor steps +y")
assert(math.floor(lifted[1] / 256) % 64 - 1 == -1, "a step bit lands on the surface nearest its height")
local dropped = bit.links[0][beside + 1]
assert(dropped and #dropped == 1, "the surface it lands on has the same step the other way")
assert(dropped[1] % 16 - 8 == 0 and math.floor(dropped[1] / 16) % 16 - 8 == -1, "it steps back -y")
assert(math.floor(dropped[1] / 256) % 64 - 1 == 1, "and lands on floor 1")
assert(#bit.linksIn[0][over + 1] == 1 and #bit.linksIn[0][beside + 1] == 1, "both ends are entered")
local bk, bn = Grid.neighbour(bit, 0, over, 20, 10, 0, 1, false)
assert(bk == 0 and bn == beside, "the floor walks +y onto the base surface")

-- A format 3 bit names the layer it lands on, so it resolves the pair the bake linked even where a surface of the
-- target cell is nearer the floor's height: the base here is 3 yards off and a floor is half a yard off. The same
-- map in format 2 lands on the nearer floor instead, which is the approximation format 3 removes.
local named = { [20] = { [10] = at(20), [11] = at(20) } }
fixture.install(
	60,
	fixture.format3({
		map = 60,
		nx = 1,
		ny = 1,
		cell = named,
		floor = { { 20, 10, 23, 1, { [2] = 0 } }, { 20, 11, 23.5, 1 } }, -- +y onto the base surface of (20, 11)
		node = { { 20, 10, 1 } },
	})
)
fixture.install(
	61,
	fixture.format2({
		map = 61,
		nx = 1,
		ny = 1,
		cell = named,
		floor = { { 20, 10, 23, 1, 2 ^ 2 }, { 20, 11, 23.5, 1 } },
		node = { { 20, 10, 1 } },
	})
)
local namedState = Grid.State(60)
assert(namedState.fmt == 3 and Grid.grid(namedState, 0))
local namedLink = namedState.links[0][over + 1]
assert(namedLink and #namedLink == 1, "the floor's step bit is its own link")
assert(math.floor(namedLink[1] / 256) % 64 - 1 == 0, "the bit carries the base surface's layer")
local nk3, nn3 = Grid.neighbour(namedState, 0, over, 20, 10, 0, 1, false)
assert(nk3 == 0 and nn3 == beside, "the bit lands on the layer it names")
local mirrored = namedState.links[0][beside + 1]
assert(mirrored and #mirrored == 1 and math.floor(mirrored[1] / 256) % 64 - 1 == 1, "the base has the mirror")
local oldState = Grid.State(61)
assert(oldState.fmt == 2 and Grid.grid(oldState, 0))
local oldK, oldN = Grid.neighbour(oldState, 0, over, 20, 10, 0, 1, false)
local nearer = 67 * 67 + 1 -- the target cell's floor, half a yard from the source's height
assert(oldK == 0 and oldN == nearer, "format 2 still resolves a bit by height")

-- A goal is judged by the walks into it, not out of it. This pit is entered by a one-way drop from the ground above
-- and cannot be left forward, so only the reverse search sees that it is reachable; the higher ground beside it is
-- merely where the old forward rescue would have moved it, and nothing leaves there to the start either.
local pit = {
	[10] = {
		[9] = at(32, { flags = 2 }), -- the drop's high side: the grid step down is closed
		[10] = at(20, { flags = 15 }), -- the pit: only the inbound link
		[11] = at(28), -- within ZTOL above the pit, so a forward rescue prefers it
	},
}
fixture.install(
	48,
	fixture.format2({
		map = 48,
		nx = 1,
		ny = 1,
		cell = pit,
		link = { { 10, 9, 0, 1, DROP } },
		node = { { 10, 9, 1 } },
	})
)
local pitGoal = point(10, 10, 20)
local pitPath, pitCost = Path.FindSync(48, point(10, 9, 32), pitGoal)
assert(pitPath and math.abs(pitCost - DROP) < 1e-9, "the drop reaches the goal: " .. tostring(pitCost))
local pitNode = 10 * 67 + 10
local pitState = Grid.State(48)
local pitKey = "0:" .. pitNode .. ":" .. pitState.swim .. ":i"
assert(
	pitState.ends[pitKey] and pitState.ends[pitKey].node == pitNode,
	"a reachable goal keeps its own surface instead of moving to the ground beside it"
)

-- A goal nothing reaches still resolves to the nearest reachable surface below it, within the fall either format
-- allows; format 2 must pick the same surface and cost as format 1.
local below = {
	[10] = {
		[10] = at(32, { flags = 15 }), -- the unreachable goal, sealed from its neighbours
		[11] = at(24), -- the nearest reachable surface, 8 yards below
		[12] = at(24),
	},
}
fixture.install(49, fixture.format2({ map = 49, nx = 1, ny = 1, cell = below, node = { { 10, 12, 1 } } }))
fixture.install(50, fixture.format1_cells({ map = 50, nx = 1, ny = 1, cell = below, node = { { 10, 12, 1 } } }))
local belowCost2 = select(2, Path.FindSync(49, point(10, 12, 24), point(10, 10, 32)))
local belowCost1 = select(2, Path.FindSync(50, point(10, 12, 24), point(10, 10, 32)))
assert(belowCost2 and belowCost1, "both formats drop an unreached goal to the surface below")
assert(math.abs(belowCost2 - belowCost1) < 1e-9, "format 2 resolves a goal like format 1")
assert(math.abs(belowCost2 - CS) < 1e-9, "the goal moved to the nearest reached surface")

-- A walking step is charged for the cell it enters. A reverse tree walks a stored edge the other way, so it must
-- charge the node nearer its source: charging the predecessor instead made the same walk cost more from one end than
-- the other whenever the two ends differed in water. The goal is reached from its cluster's entrance at (10, 10),
-- which is water: the forward walk charges (10, 11) and (10, 12), so the walk into the goal must charge them too.
local wetWalk = {
	[10] = { [10] = at(20, { water = true }), [11] = at(20), [12] = at(20) },
	[67] = { [10] = at(20) },
}
fixture.install(
	52,
	fixture.format2({
		map = 52,
		nx = 2,
		ny = 1,
		cell = wetWalk,
		node = {
			{ 10, 10, 1, out = { { 67, 10, 16, 16 } } },
			{ 67, 10, 1, out = { { 10, 10, 16, 16 } } },
		},
	})
)
local wetLocal = select(2, Path.FindSync(52, point(10, 10, 20), point(10, 12, 20)))
local wetAcross = select(2, Path.FindSync(52, point(67, 10, 20), point(10, 12, 20)))
assert(wetLocal and wetAcross, "the wet walk exists both ways")
assert(
	math.abs(wetAcross - (16 + wetLocal)) < 1e-9,
	string.format(
		"the walk into the goal costs what the walk out of the entrance does: %s vs %s",
		wetAcross,
		16 + wetLocal
	)
)

-- A goal on a ledge whose drop is the only way in: the outbound rescue moves it to the higher ground beside it, and
-- a local walk must not stop there. Targeting that surface reported a walk to ground 8 yards above the goal, cheaper
-- than the drop that really reaches it.
local ledgeGoal = {
	[10] = { [10] = at(30, { flags = 2 }), [11] = at(20, { flags = 1 }) },
	[11] = { [10] = at(30), [11] = at(28) },
}
fixture.install(
	57,
	fixture.format2({
		map = 57,
		nx = 1,
		ny = 1,
		cell = ledgeGoal,
		link = { { 10, 10, 0, 1, 24 } },
		node = { { 10, 10, 1 } },
	})
)
local ledgeForward = select(2, Path.FindSync(57, point(10, 10, 30), point(10, 11, 20)))
assert(ledgeForward and math.abs(ledgeForward - 24) < 1e-9, "the goal costs the drop: " .. tostring(ledgeForward))
local ledgeReverse = Path.FindManySync(57, point(10, 11, 20), { point(10, 10, 30) }, nil, true)[1]
assert(
	ledgeReverse and math.abs(ledgeReverse - 24) < 1e-9,
	"a reverse batch ends on the start's own surface too: " .. tostring(ledgeReverse)
)

-- A steep leg cannot feed a diagonal detour: the direct diagonal is one symmetric bit, so opening it from a one-way
-- downhill leg let the walk climb the face diagonally. The two ordinary steps still go down.
local steepCorner = {
	[10] = { [9] = at(16, { steep = true }), [10] = at(32) },
	[11] = { [9] = at(16) },
}
fixture.install(54, fixture.format2({ map = 54, nx = 1, ny = 1, cell = steepCorner, node = { { 10, 10, 1 } } }))
local cornerState = Grid.State(54)
assert(cornerState.fmt == 2 and Grid.grid(cornerState, 0))
local cornerHigh = 10 * 67 + 10
assert(cornerState.moves[0][cornerHigh + 1] % 16 < 8, "the diagonal must not open through a steep leg")
assert(Grid.neighbour(cornerState, 0, cornerHigh, 10, 10, 1, -1, false) == nil, "nor be walked")
local climb, climbWhy = Path.FindSync(54, point(11, 9, 16), point(10, 10, 32))
assert(climb == nil and climbWhy == "unreachable", "the search must not climb the steep face diagonally")
local descend, descendCost = Path.FindSync(54, point(10, 10, 32), point(11, 9, 16))
assert(descend and math.abs(descendCost - 2 * CS) < 1e-9, "the two ordinary steps still go downhill")

-- A cross-cluster diagonal checks its corner: a detour that climbs steep ground is not a diagonal, however level its
-- two ends are. The same map keeps an ordinary cross-cluster diagonal open.
local steepAcross = {
	[66] = { [10] = at(20), [20] = at(20), [21] = at(20) },
	[67] = { [10] = at(32, { steep = true }), [11] = at(20), [21] = at(20) },
}
fixture.install(
	55,
	fixture.format2({
		map = 55,
		nx = 2,
		ny = 1,
		cell = steepAcross,
		node = { { 66, 10, 1 }, { 66, 20, 1 }, { 67, 11, 1 } },
	})
)
local acrossState = Grid.State(55)
assert(Grid.grid(acrossState, 0) and Grid.grid(acrossState, 1))
local acrossFrom = 66 * 67 + 10
assert(
	Grid.neighbour(acrossState, 0, acrossFrom, 66, 10, 1, 1, false) == nil,
	"the diagonal must not climb through its corner cell"
)
local levelFrom = 66 * 67 + 20
local lk, ln = Grid.neighbour(acrossState, 0, levelFrom, 66, 20, 1, 1, false)
assert(lk == 1 and ln == 21, "a level cross-cluster diagonal stays open")

-- A cross-cluster detour leg follows the same rule as one inside a cluster: a steep step that only goes downhill is
-- still not a detour, so the two ordinary steps are the way down. The corner's height alone used to open it, which
-- the bake never does, so the graph and the runtime disagreed about the crossing.
local steepDown = {
	[66] = { [10] = at(32) },
	[67] = { [10] = at(20, { steep = true }), [11] = at(20) },
}
fixture.install(
	59,
	fixture.format2({ map = 59, nx = 2, ny = 1, cell = steepDown, node = { { 66, 10, 1 }, { 67, 11, 1 } } })
)
local downState = Grid.State(59)
assert(Grid.grid(downState, 0) and Grid.grid(downState, 1))
local downFrom = 66 * 67 + 10
assert(
	Grid.neighbour(downState, 0, downFrom, 66, 10, 1, 1, false) == nil,
	"a steep downhill leg must not open the cross-cluster diagonal"
)
local dk, dn = Grid.neighbour(downState, 0, downFrom, 66, 10, 1, 0, false)
assert(dk == 1 and dn == 10, "the ordinary step across the border stays open")
local sk, sn = Grid.neighbour(downState, 1, 10, 67, 10, 0, 1, false)
assert(sk == 1 and sn == 11, "and the step down the face stays open")

-- A reverse batch's road ratios come from the edges that reach a node, wherever that node lives: the source's
-- cluster must not already have been visited for its outbound record to be readable.
local crossEdge = {
	[66] = { [10] = at(20) },
	[67] = { [10] = at(20) },
}
fixture.install(
	53,
	fixture.format2({
		map = 53,
		nx = 2,
		ny = 1,
		cell = crossEdge,
		node = {
			{ 66, 10, 1, out = { { 67, 10, 16, 16 } } },
			{ 67, 10, 1 },
		},
	})
)
local crossReverse = Path.FindManySync(53, point(67, 10, 20), { point(66, 10, 20) }, nil, true, roadProfile)[1]
assert(crossReverse and math.abs(crossReverse - 16) < 1e-9, "the reverse batch crosses the boundary")
local crossState = Grid.State(53)
assert(#Grid.roadEdgesIn(crossState, Grid.nodesOf(crossState, 1)[1]) == 4, "the entering edge has its ratio")

-- Format 1 has no steep encoding, so its state carries no steep check for the hot paths to call, and a floor that
-- claims value 3 (as only a format 2 bake writes) stays an ordinary floor: a rule the format does not carry must not
-- refuse a step.
assert(old.steep == nil, "format 1 has no steep check")
assert(type(Grid.State(42).steep) == "function", "a format 2 map carries the stored-height check")
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64(value, width)
	local digits = {}
	for i = width, 1, -1 do
		local d = math.floor(value / 64 ^ (i - 1)) % 64
		digits[#digits + 1] = alphabet:sub(d + 1, d + 1)
	end
	return table.concat(digits)
end
local flat = {
	[5] = { [10] = at(20), [11] = at(20) },
}
local format1Floor = fixture.format1_cells({ map = 58, nx = 1, ny = 1, cell = flat, node = { { 5, 11, 1 } } })
-- one floor on (5, 10) at 40 yards, value 3, its +y step bit, and no explicit links
format1Floor.floor =
	{ [1] = b64(1, 3) .. b64(5 * 67 + 10, 3) .. b64(1, 1) .. b64(3, 1) .. b64(40 + 2048, 2) .. b64(4, 2) .. b64(0, 3) }
fixture.install(58, format1Floor)
assert(Path.FindSync(58, point(5, 11, 20), point(5, 10, 40)), "a format 1 floor carries no steep rule")

print("path_direction_spec: ok")

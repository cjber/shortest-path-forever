-- A custom road preference must not run a local cluster search for a popped entrance that has no same-cluster
-- adjacency: a route across clusters connected only by their boundary edges does no interior work (#1355).
local F = assert(loadfile("tests/nav_fixture.lua"))()
local CS, MAP = (1600 / 3) / 67, 45002
local cells = {}
local function cell(x, y)
	cells[x] = cells[x] or {}
	cells[x][y] = { z = 20 }
end
-- Clusters 0 and 2 are a short strip to their boundary entrance.
for x = 50, 66 do
	cell(x, 30)
end
for x = 134, 144 do
	cell(x, 30)
end
-- Cluster 1 is full ground, so a local search from its popped entrance would expand most of its grid. Its other
-- entrances are never reached by the route: they only enlarge the targets such a search would sweep.
for x = 67, 133 do
	for y = 0, 66 do
		cell(x, y)
	end
end
local cross, straight = math.floor(CS), math.floor(67 * CS)
F.install(
	MAP,
	F.format2({
		nx = 3,
		ny = 1,
		cell = cells,
		node = {
			{ 66, 30, 1, out = { { 67, 30, cross, cross } } },
			{ 67, 30, 1, out = { { 66, 30, cross, cross }, { 134, 30, straight, straight } } },
			{ 134, 30, 1, out = { { 67, 30, straight, straight } } },
			{ 70, 5, 1 },
			{ 130, 5, 1 },
			{ 70, 65, 1 },
			{ 130, 65, 1 },
			{ 100, 35, 1 },
		},
	})
)
local ns = {}
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Path.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/PathJobs.lua"))("ShortestPathForever", ns)
local Path = ns.Path
local function point(x, y)
	return { x = (x + 0.5) * CS, y = (y + 0.5) * CS }
end
local from, to = point(50, 30), point(144, 30)
local function profile(factor)
	return {
		key = "synthetic-lazy-" .. factor,
		roads = true,
		roadFactor = factor,
		Point = function()
			return 1
		end,
		Chord = function()
			return 1
		end,
		Near = function()
			return false
		end,
		Charged = function()
			return false
		end,
	}
end
-- The 50% control pays no custom search, and no edge here has same-cluster adjacency, so a stronger preference
-- must still report the same real walk. The old eager call swept cluster 1's grid on every pop.
local controlCosts, _, controlExpansions = Path.FindManySync(MAP, from, { to }, false, false, profile(1.5))
local strongCosts, _, strongExpansions = Path.FindManySync(MAP, from, { to }, false, false, profile(3))
local control, strong = controlCosts[1], strongCosts[1]
assert(control and strong, "both preferences reach the goal")
assert(
	math.abs(strong - control) < 1e-8,
	("the lazy path must report the control's real cost: control %.17g strong %.17g"):format(control, strong)
)
assert(
	strongExpansions <= controlExpansions + 32,
	("an entrance with no same-cluster edge must not sweep its cluster: %d vs control %d"):format(
		strongExpansions,
		controlExpansions
	)
)

print("road_detour_lazy_spec: ok")

-- A custom road preference must reconsider the path inside an intermediate cluster.
local F = assert(loadfile("tests/nav_fixture.lua"))()
local C, CS, MAP = 67, (1600 / 3) / 67, 45001
local cells = {}
local function cell(x, y)
	cells[x] = cells[x] or {}
	cells[x][y] = { z = 20 }
end
for x = 60, 140 do
	cell(x, 30)
end
for y = 10, 30 do
	cell(67, y)
	cell(133, y)
end
for x = 67, 133 do
	cell(x, 10)
end
local cross, straight = math.floor(CS), math.floor(66 * CS)
F.install(
	MAP,
	F.format2({
		nx = 3,
		ny = 1,
		cell = cells,
		node = {
			{ 66, 30, 1, out = { { 67, 30, cross, cross } } },
			{ 67, 30, 1, out = { { 66, 30, cross, cross }, { 133, 30, straight, straight } } },
			{ 133, 30, 1, out = { { 67, 30, straight, straight }, { 134, 30, cross, cross } } },
			{ 134, 30, 1, out = { { 133, 30, cross, cross } } },
		},
	})
)
local ns = {}
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Path.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/PathJobs.lua"))("ShortestPathForever", ns)
local st, Path = ns.PathGrid.State(MAP), ns.Path
st.road[1] = {}
for y = 10, 30 do
	st.road[1][y] = 1
	st.road[1][66 * C + y] = 1
end
for x = 0, 66 do
	st.road[1][x * C + 10] = 1
end
local function point(x, y)
	return { x = (x + 0.5) * CS, y = (y + 0.5) * CS }
end
local from, to = point(60, 30), point(140, 30)
local function profile(factor)
	return {
		key = "synthetic-road-" .. factor,
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
local _, default = Path.FindSync(MAP, from, to, false, profile(1.5))
local _, strong = Path.FindSync(MAP, from, to, false, profile(3))
assert(default and strong)
-- The default's 66-cell shortcut crosses off-road ground. At 3x, the 106-cell
-- U-shaped road is cheaper despite being physically longer. Endpoints and
-- crossing edges are identical. Each inside corner cuts two axis steps to one
-- diagonal, so the selected interior is 102 + 2*sqrt(2) cells long. The
-- default shortcut retains its baked integer-yard cost.
assert(
	math.abs(strong - default - ((102 + 2 * math.sqrt(2)) * CS - straight)) < 1e-8,
	("custom preference retained baked shortcut: default %.17g strong %.17g"):format(default, strong)
)
for _, factor in ipairs({ 1.5, 3, 1.5, 3 }) do
	local hz = profile(factor)
	local expected = factor == 3 and strong or default
	local forward = Path.FindManySync(MAP, from, { to }, false, false, hz)[1]
	local inbound = Path.FindManySync(MAP, to, { from }, false, true, hz)[1]
	assert(math.abs(forward - expected) < 1e-8, "forward batch uses new shortcut")
	assert(math.abs(inbound - expected) < 1e-8, "inbound batch uses new shortcut")
end

-- The same U has only faint paint: at 10% it cannot justify the detour even at 3x.
for roadCell in pairs(st.road[1]) do
	st.road[1][roadCell] = 0.1
end
local faint = profile(3)
faint.key = "faint-road"
local _, faintCost = Path.FindSync(MAP, from, to, false, faint)
assert(
	math.abs(faintCost - default - (66 * CS - straight)) < 1e-8,
	"partial paint must not receive full-road preference"
)

print("road_shortcut_spec: ok")

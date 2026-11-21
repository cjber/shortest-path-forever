-- A pulled line is judged in the road-weighted time the search chose with (#891): a straight cut across the field
-- cannot beat the road bend the walk took just because its own raw time is shorter.
local fixture = assert(loadfile("tests/nav_fixture.lua"))()
local ns = {}
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
local Grid = ns.PathGrid
local C = 67
local CS = (1600 / 3) / C
local MAP = 45

local cells = {}
for x = 5, 40 do
	cells[x] = {}
	for y = 5, 40 do
		cells[x][y] = { z = 20 }
	end
end
fixture.install(MAP, fixture.format2({ map = MAP, nx = 1, ny = 1, cell = cells, node = { { 5, 5, 1 } } }))
local st = Grid.State(MAP)

-- An L-shaped road with one gap at its corner; the walk follows it rather than cutting the corner.
local road = {}
for x = 11, 30 do
	road[x * C + 10] = 1
end
for y = 11, 30 do
	road[10 * C + y] = 1
end
st.road[0] = road

local P =
	{ x = {}, y = {}, z = {}, w = {}, t = {}, k = {}, n = {}, r = {}, roads = true, roadFactor = 1.5, swim = st.swim }
local function add(x, y)
	local i = #P.x + 1
	P.x[i], P.y[i], P.k[i], P.n[i], P.w[i] = x, y, 0, x * C + y, 0
	P.z[i] = 20
	P.t[i] = (P.t[i - 1] or 0) + (i > 1 and CS or 0)
	P.r[i] = (P.r[i - 1] or 0) + (road[x * C + y] and 0 or 1)
end
for x = 30, 11, -1 do
	add(x, 10)
end
add(10, 10) -- the one off-road cell: the road's gap, and its corner
for y = 11, 30 do
	add(10, y)
end

local keep = Grid.smooth(st, P)
assert(#keep > 2, "the smoothed line must keep the road bend")
for i = 2, #keep do
	local a, b = keep[i - 1], keep[i]
	local ax, ay, bx, by = P.x[a], P.y[a], P.x[b], P.y[b]
	local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	local steps = math.max(1, math.ceil(length * 4))
	for step = 0, steps do
		local t = step / steps
		local x, y = math.floor(ax + (bx - ax) * t), math.floor(ay + (by - ay) * t)
		local cell = x * C + y
		assert(road[cell] or cell == 10 * C + 10, ("the drawn line leaves the road at %d, %d"):format(x, y))
	end
end
-- A low-alpha painted run has the same no-field-crossing rule as a fully painted one.
for cell in pairs(road) do
	road[cell] = 0.2
end
local faint = Grid.smooth(st, P)
assert(#faint > 2, "partial paint must keep the drawn road bend")
for i = 2, #faint do
	local a, b = faint[i - 1], faint[i]
	local dx, dy = P.x[b] - P.x[a], P.y[b] - P.y[a]
	local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) * 4))
	for step = 0, steps do
		local t = step / steps
		local x, y = math.floor(P.x[a] + dx * t), math.floor(P.y[a] + dy * t)
		local cell = x * C + y
		assert(road[cell] or cell == 10 * C + 10, "partial-paint drawn line leaves the road")
	end
end

-- A straight run across a raised platform must retain the ends of its ramps.
P.x, P.y, P.z, P.w, P.t, P.k, P.n, P.r = {}, {}, {}, {}, {}, {}, {}, {}
for x = 11, 17 do
	add(x, 10)
end
P.z = { 20, 20, 22, 22, 22, 20, 20 }
assert(table.concat(Grid.smooth(st, P), ",") == "1,2,3,5,6,7", "the drawn chord keeps the platform's grade changes")
-- Run the same profile through the real endpoint checks, with endpoints away from their cell centres.
local PLATFORM = 46
local platform = {}
for i, z in ipairs(P.z) do
	platform[i + 10] = { [10] = { z = z } }
end
fixture.install(PLATFORM, fixture.format2({ nx = 1, ny = 1, cell = platform, node = { { 11, 10, 1 } } }))
local state = Grid.State(PLATFORM)
local chord
local smooth = Grid.smooth
Grid.smooth = function(grid, path, ends)
	chord = ends.chord()
	return smooth(grid, path, ends)
end
for _, file in ipairs({ "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local function point(x, y)
	return { x = state.x0 + x * CS, y = state.y0 + y * CS, z = 20 }
end
local drawn = assert(ns.Path.FindSync(PLATFORM, point(11.25, 10.5), point(17.75, 10.5)))
assert(chord, "the production endpoint callback accepts the direct chord")
local heights = {}
for i, p in ipairs(drawn) do
	heights[i] = p.z
end
assert(table.concat(heights, ",") == "20,20,22,22,20,20", "the direct chord keeps the platform's grade changes")
local offset = assert(ns.Path.FindSync(PLATFORM, point(11.25, 10.25), point(17.75, 10.25)))
assert(chord and #offset == 2, "a clear chord offset from the cell centres must stay straight")
print("road_smoothing_spec: ok")

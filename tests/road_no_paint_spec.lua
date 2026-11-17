-- Missing painted-road data is plain off-road, not a free entrance connection.
local F = assert(loadfile("tests/nav_fixture.lua"))()
local ns = {}
for _, name in ipairs({ "PathGrid", "Path", "PathJobs" }) do
	assert(loadfile("Routing/" .. name .. ".lua"))("ShortestPathForever", ns)
end
local G = ns.PathGrid
-- A cluster with no RoadCells record still charges unpainted ground as off-road.
local EMPTY = 49895
F.install(
	EMPTY,
	F.format2({
		nx = 1,
		ny = 1,
		cell = {
			[10] = { [10] = { z = 20 } },
			[11] = { [10] = { z = 20 } },
			[12] = { [10] = { z = 20 } },
		},
		node = {
			{ 10, 10, 1, out = { { 12, 10, 16, 16 } } },
			{ 12, 10, 1, out = { { 10, 10, 16, 16 } } },
		},
	})
)
local empty = G.State(EMPTY)
local hz = {
	key = "no-paint",
	roads = true,
	roadFactor = 3,
	Point = function()
		return 1
	end,
	Near = function()
		return false
	end,
	Chord = function()
		return 1
	end,
	Charged = function()
		return false
	end,
}
local function point(x)
	return { x = (x + 0.5) * empty.cs, y = 10.5 * empty.cs, z = 20 }
end
assert(ns.Path.FindSync(EMPTY, point(10), point(12), false, hz))
local measured = false
for _, entry in pairs(empty.ends) do
	for id, real in pairs(entry.reals) do
		if real > 0 then
			assert(math.abs(entry.edges[id] - 3 * real) < 1e-8, "missing road data must charge plain off-road cost")
			measured = true
		end
	end
end
assert(measured, "search measured an unpainted entrance connection")
print("road_no_paint_spec: ok")

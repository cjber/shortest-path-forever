-- Compressed ceiling records index the base and each stacked floor separately.
local ns = {}
assert(loadfile("Routing/PathCeiling.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
local Grid = ns.PathGrid

local map = {
	format = 4,
	cells = 2,
	cx0 = 0,
	cy0 = 0,
	nx = 1,
	ny = 1,
	swim = 3,
	zstep = 2,
	graph = {},
	grid = { "BEAAy" },
	height = { "Xy" },
	floor = { "AAC" .. "DBgIAA" .. "ABgKAA" .. "AAAAAA" },
}
local older, packed = {}, {}
for key, value in pairs(map) do
	older[key], packed[key] = value, value
end
map.ceiling = { "BkrEgCg+DgEhIBhK" }
packed.ceiling = {}
packed.packed = { floor = {}, ceiling = { { "eJxzyi5yTXdO13ZJd83wdMrwBgAtDAU3" } } }
_G.ShortestPathForeverPathData = { [44] = map, [45] = older, [46] = packed }

local high = Grid.TILE * 0.75
local low = Grid.TILE * 0.25
assert(Grid.ceiling(44, low, low, 0) == nil, "a hover cannot force a grid decode")
assert(Grid.grid(assert(Grid.State(44)), 0))
local cases = {
	{ low, low, 0, 139.125, "terrain" }, -- Jasperlode Mine's reported terrain height
	{ low, high, 0, 126, "terrain" }, -- Deadmines tunnel's reported terrain height
	{ high, high, 0, 8, "structure" },
	{ high, high, 8, 10, "structure" },
}
for _, case in ipairs(cases) do
	local height, kind = Grid.ceiling(44, case[1], case[2], case[3])
	assert(height == case[4] and kind == case[5], "surface height or kind changed on decode")
end
assert(Grid.ceiling(44, high, low, 0) == nil, "an uncovered cell has no ceiling")
assert(Grid.ceiling(44, high, high, 10) == nil, "a top floor cannot inherit the lower floor's ceiling")
assert(Grid.grid(assert(Grid.State(45)), 0))
assert(Grid.ceiling(45, low, low, 0) == nil, "a bundle without ceiling metadata remains readable")

_G.C_EncodingUtil = assert(loadfile("tools/nav_encoding.lua"))()
_G.Enum = { CompressionMethod = { Zlib = 1 } }
assert(Grid.grid(assert(Grid.State(46)), 0))
assert(Grid.ceiling(46, high, high, 8) == 10, "packed ceiling data is available through the same lookup")

local height, kind = ns.PathCeilingAt(ns.DecodePathCeilings("Bf"), 0, 0)
assert(height == -1 and kind == "structure", "negative world heights are representable")
local terrain, terrainKind, structure = ns.PathCeilingAt(ns.DecodePathCeilings("BkrEAP"), 0, 0)
assert(terrain == 139.125 and terrainKind == "terrain" and structure == -0.5, "both sources survive on one floor")
-- Load the shipped bundle through its XML and compression path.
assert(loadfile("tools/load_nav.lua"))(0, ".", nil, true)
local eastern = assert(Grid.State(0))
local function cover(x, y, z)
	local cluster = assert(Grid.locate(eastern, x, y))
	assert(Grid.grid(eastern, cluster))
	return Grid.ceiling(0, x, y, z)
end

for _, cave in ipairs({
	{ -9086.57, -545.27, 62 }, -- Jasperlode Mine
	{ -11331.34, 1564.18, 28 }, -- Deadmines tunnel
}) do
	local above, source, ceiling = cover(cave[1], cave[2], cave[3])
	assert(
		above and source == "terrain" and ceiling and cave[3] < ceiling and ceiling < above,
		"a cave has both kinds of cover"
	)
end

local lower, lowerKind = cover(-8894, 611, 76)
local upper, upperKind = cover(-8894, 611, 96)
assert(
	lower and upper and lowerKind == "structure" and upperKind == "structure" and lower < upper,
	"stacked floors have distinct cover"
)
-- The actual Jasperlode and Deadmines walks carry the depth that the decoded cells supplied.
for _, file in ipairs({ "Path", "PathJobs" }) do
	assert(loadfile("Routing/" .. file .. ".lua"))("ShortestPathForever", ns)
end
for _, walk in ipairs({
	{ -9106.57, -9046.57, -545.27, 62, 60.03980235126 },
	{ -11351.34, -11331.34, 1564.18, 28, 20.000119944837 },
}) do
	local points, cost = ns.Path.FindSync(0, { x = walk[1], y = walk[3], z = walk[4] }, {
		x = walk[2],
		y = walk[3],
		z = walk[4],
	})
	assert(points and math.abs(cost - walk[5]) < 1e-6, "cave cover changes neither the chosen walk nor its cost")
	assert(not points[1].depth, "the approach starts above ground")
	local entrances = 0
	for i = 2, #points do
		if points[i].depth and not points[i - 1].depth then
			entrances = entrances + 1
			assert(points[i - 1].depthCut, "the baked mouth has a position on the drawn segment")
		end
	end
	assert(entrances == 1, "the approach has one terrain-cover entrance")
	if walk[1] == -9106.57 then
		assert(not points[#points].depth, "a walk across Jasperlode returns to uncovered ground")
	end
end
print("nav_ceiling_spec: ok")

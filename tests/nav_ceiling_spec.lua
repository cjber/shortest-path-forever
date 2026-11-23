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
print("nav_ceiling_spec: ok")

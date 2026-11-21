-- Indexed graphs keep metadata and both adjacency orders through the packed loader.
local fixture = assert(loadfile("tests/nav_fixture.lua"))()
fixture.install(46, {
	cx0 = 0,
	cy0 = 0,
	nx = 1,
	ny = 2,
	cells = 67,
	swim = 3,
	zstep = 2,
	format = 4,
	graphFormat = 1,
	graph = {},
	grid = {},
	height = {},
	floor = {},
	terrain = {},
	packed = {
		-- Interior and perimeter nodes, a 65-ordinal delta, and a road-only duplicate after the prefix.
		graph = {
			{
				"eJxzcnFycXJiYWdlc3JyOsPEQCFoZ6TYCAaGrYyUmsDCTKkJjBS7gYGFlYWliZGhibGR0YrhDQvXAw6O1yxMFIcPFVxGeRwBABu9CTg=",
			},
			{ "eJxjZGRkYoQDBlYGRgZmBpYABgYGAALrAG0=" },
		},
	},
})
local env = setmetatable({
	C_EncodingUtil = assert(loadfile("tools/nav_encoding.lua"))(),
	Enum = { CompressionMethod = { Zlib = 1 } },
}, { __index = _G })
local ns = {}
setfenv(assert(loadfile("Routing/PathGrid.lua")), env)("ShortestPathForever", ns)
local Grid = ns.PathGrid
local st = assert(Grid.State(46))
local cell, layer, component = Grid.metadata(st, 0)
assert(cell == 68 and layer == 2 and component == 180)
assert(#Grid.nodesOf(st, 0) == 66 and Grid.metadata(st, 65) == 134)
local function same(got, expected)
	assert(table.concat(got, ",") == expected, table.concat(got, ","))
end
same(Grid.adjacent(st, 0, true), "65,600,40,4096,12,8,65,11,321")
same(Grid.adjacent(st, 0, false), "65,600,40,4096,12,8")
same(Grid.preceding(st, 65, false), "0,600,40")
same(Grid.preceding(st, 65, true), "0,600,40,0,11,321")
same(Grid.preceding(st, 0, true), "65,17,16,4096,50,10")
same(Grid.preceding(st, 4096, false), "0,12,8")
print("nav_indexed_graph_spec: ok")

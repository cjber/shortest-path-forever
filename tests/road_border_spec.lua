-- Also exercise a longer road detour that plain/default-factor pruning considers redundant.
local deep = assert(io.popen("python3 tests/road_border_fixture.py --deep"))
local deepSpec = assert(loadstring(deep:read("*a")))()
assert(type(deepSpec) == "table", "maximum-factor fixture must finish successfully")
deep:close()
-- Exercise the graph producer and runtime together: road entrances exist, but plain-distance pruning can remove
-- the connection along the road and force refinement through an off-road entrance (#892).
local fixture = assert(loadfile("tests/nav_fixture.lua"))()
local pipe = assert(io.popen("python3 tests/road_border_fixture.py"))
local source = pipe:read("*a")
pipe:close()
local spec = assert(loadstring(source))()
spec.map, spec.nx, spec.ny = 42, 3, 2
fixture.install(42, fixture.format2(spec))
local ns = { RoadEdges = { [42] = {} } }
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
local Grid = ns.PathGrid
local st = assert(Grid.State(42))
for k, road in pairs(spec.road) do
	st.road[k] = road
end
Grid.smooth = function(_, P)
	local indices, links = {}, {}
	for i = 1, #P.x do
		indices[i], links[i] = i, 0
	end
	return indices, false, false, links
end
local plainReads, roadReads = 0, 0
for _, name in ipairs({ "adjacent", "preceding" }) do
	local read = Grid[name]
	Grid[name] = function(state, id, roads)
		if roads == false then
			plainReads = plainReads + 1
		elseif roads == true then
			roadReads = roadReads + 1
		end
		return read(state, id, roads)
	end
end
for _, file in ipairs({ "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path = ns.Path
for k, edges in pairs(Path.BakeRoadEdges(42)) do
	ns.RoadEdges[42][k + 1] = edges
end
local hz = {
	key = "roads",
	roads = true,
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
local function point(x)
	return { x = (x + 0.5) * st.cs, y = 66.5 * st.cs }
end
for _, ends in ipairs({ { 60, 140 }, { 140, 60 } }) do
	local from, to = point(ends[1]), point(ends[2])
	local points, cost = Path.FindSync(42, from, to, false, hz)
	assert(points, cost)
	for _, p in ipairs(points) do
		local k, cell = Grid.locate(st, p.x, p.y)
		assert(spec.road[k][cell], "road walk visits an off-road cell at a cluster border")
	end
	local plain, plainCost = Path.FindSync(42, from, to)
	assert(plain and plainCost < cost and cost < plainCost * 1.5, "road preference keeps physical travel costs")
	for _, reverse in ipairs({ false, true }) do
		local batch = Path.FindManySync(42, from, { to }, false, reverse, hz)
		assert(math.abs(batch[1] - cost) < 1e-9, "batch and drawn walk use the same retained road connection")
	end
end
assert(plainReads > 0 and roadReads > 0, "search must explicitly select base or road adjacency")
print("road_border_spec: ok")

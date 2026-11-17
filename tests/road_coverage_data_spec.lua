-- The faint SW Elwynn road is a single painted run, without filling the unpainted bridge farther north (#893).
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
assert(loadfile("Data/RoadCells.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
local G = ns.PathGrid
local st = G.State(0)
local points, count, low, high = {}, 0, math.huge, -math.huge
for x = math.floor((-10150 - st.x0) / st.cs), math.floor((-9950 - st.x0) / st.cs) do
	for y = math.floor((1100 - st.y0) / st.cs), math.floor((1300 - st.y0) / st.cs) do
		local wx, wy = st.x0 + (x + 0.5) * st.cs, st.y0 + (y + 0.5) * st.cs
		if wx > -10150 and wx < -9950 and wy > 1100 and wy < 1300 then
			local k, cell = G.locate(st, wx, wy)
			local road = k and G.roads(st, k)
			if road and road[cell] then
				points[x * st.GY + y] = { x, y }
				count = count + 1
				low, high = math.min(low, wy), math.max(high, wy)
			end
		end
	end
end
assert(count > 0 and high - low > 180, "painted run reaches both ends of the faint road")
local seed = next(points)
local stack, visited = { points[seed] }, 0
points[seed] = nil
while #stack > 0 do
	local p = table.remove(stack)
	visited = visited + 1
	for dx = -1, 1 do
		for dy = -1, 1 do
			local id = (p[1] + dx) * st.GY + p[2] + dy
			if points[id] then
				stack[#stack + 1] = points[id]
				points[id] = nil
			end
		end
	end
end
assert(visited == count, "partial-alpha SW Elwynn road must be one 8-connected run")
print("road_coverage_data_spec: " .. count .. " painted cells in one connected run")

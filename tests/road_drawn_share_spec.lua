local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({ "Routing/PathGrid.lua", "Data/RoadCells.lua", "Data/RoadEdges.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end

local Grid = ns.PathGrid
local st = Grid.State(0)
local from, to = { x = -9473, y = 60 }, { x = -8940, y = -130 }
local roads = {
	roads = true,
	key = "roads",
	Charged = function()
		return false
	end,
	Point = function()
		return 1
	end,
	Near = function()
		return false
	end,
	Chord = function()
		return 1
	end,
}

local raw
local smooth = Grid.smooth
Grid.smooth = function(state, path, ends)
	raw = { from }
	for i = 1, #path.x do
		raw[#raw + 1] = {
			x = state.x0 + (path.x[i] + 0.5) * state.cs,
			y = state.y0 + (path.y[i] + 0.5) * state.cs,
		}
	end
	raw[#raw + 1] = to
	return smooth(state, path, ends)
end
for _, file in ipairs({ "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local drawn = assert(ns.Path.FindSync(0, from, to, false, roads))

-- Split the drawn segments at each grid boundary and sum the painted portions.
local function roadShare(points)
	local painted, total = 0, 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local dx, dy = b.x - a.x, b.y - a.y
		local length = math.sqrt(dx * dx + dy * dy)
		local cuts = { 0, 1 }
		for _, axis in ipairs({ "x", "y" }) do
			local origin = st[axis .. "0"]
			local first, last = (a[axis] - origin) / st.cs, (b[axis] - origin) / st.cs
			for boundary = math.floor(math.min(first, last)) + 1, math.ceil(math.max(first, last)) - 1 do
				cuts[#cuts + 1] = (boundary - first) / (last - first)
			end
		end
		table.sort(cuts)
		for j = 2, #cuts do
			local mid = (cuts[j] + cuts[j - 1]) / 2
			local k, cell = Grid.locate(st, a.x + dx * mid, a.y + dy * mid)
			local coverage = k and Grid.roads(st, k)
			if coverage and coverage[cell] then
				painted = painted + length * (cuts[j] - cuts[j - 1])
			end
		end
		total = total + length
	end
	return painted / total
end

local routeShare, drawnShare = roadShare(raw), roadShare(drawn)
assert(routeShare < 1 and routeShare > 0, "the route crosses both painted and unpainted cells")
assert(drawnShare + 1e-9 >= routeShare, ("road share fell from %.4f to %.4f"):format(routeShare, drawnShare))
print("road_drawn_share_spec: ok")

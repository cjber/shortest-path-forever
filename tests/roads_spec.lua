-- Follow roads: RoadCells.lua's road cell sets and RoadEdges.lua's entrance edge ratios steer a walk onto the road,
-- while the cost it reports stays the real walk. With the option off nothing changes.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({
	"Data/RoadCells.lua",
	"Data/RoadEdges.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Grid, Path = ns.PathGrid, ns.Path
local st = Grid.State(0)

-- A cluster listed in RoadCells.lua decodes to a non-empty set; one not listed has none.
local listedKey = next(ns.RoadCells[0])
local listed = listedKey and listedKey - 1
assert(listed, "map 0 has roads")
local set = Grid.roads(st, listed)
assert(set and next(set) ~= nil, "a listed cluster has road cells")
local missing
for k = 0, 4095 do
	if not ns.RoadCells[0][k + 1] then
		missing = k
		break
	end
end
assert(missing and Grid.roads(st, missing) == nil, "a cluster with no road data has none")

-- An edge ratio array aligns with adjacent's triples, four values per edge, all between the road and off it.
local edgeKey = next(ns.RoadEdges[0])
local edgeCluster = edgeKey and edgeKey - 1
assert(edgeCluster, "map 0 has baked road edges")
local node = Grid.nodesOf(st, edgeCluster)[1]
assert(node, "the cluster has an entrance")
local adj = Grid.adjacent(st, node)
local ratios = Grid.roadEdges(st, node)
assert(#ratios == #adj / 3 * 4, #ratios .. " ratios for " .. #adj / 3 .. " edges")
for i = 1, #ratios do
	assert(ratios[i] >= 1 and ratios[i] <= Grid.OFFROAD, ratios[i])
end

-- The share of a drawn walk's length whose cells are road cells, sampled every 2 yards.
local function roadAt(x, y)
	local k, lc = Grid.locate(st, x, y)
	if not k then
		return false
	end
	local cells = Grid.roads(st, k)
	return cells and cells[lc] ~= nil or false
end
local function share(points)
	local total, on = 0, 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local dx, dy = b.x - a.x, b.y - a.y
		local length = math.sqrt(dx * dx + dy * dy)
		local steps = math.max(1, math.ceil(length / 2))
		for step = 1, steps do
			local t = (step - 0.5) / steps
			total = total + length / steps
			if roadAt(a.x + dx * t, a.y + dy * t) then
				on = on + length / steps
			end
		end
	end
	return on / total
end

local function profile(key, roads, roadFactor)
	return {
		key = key,
		roads = roads and true or nil,
		roadFactor = roadFactor,
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

-- Goldshire to Northshire Abbey in Elwynn Forest: the road runs along the zone's cobblestones.
local from, to = { x = -9460, y = 60 }, { x = -8920, y = -140 }
local plain, plainCost = Path.FindSync(0, from, to, false, profile("n"))
local road, roadCost = Path.FindSync(0, from, to, false, profile("r", true))
assert(plain and road and plainCost and roadCost)
local plainShare, roadShare = share(plain), share(road)
assert(roadShare > plainShare, ("road share %.3f is not above plain %.3f"):format(roadShare, plainShare))
assert(
	roadCost >= plainCost and roadCost <= plainCost * 1.5,
	("road cost %.1f, plain %.1f"):format(roadCost, plainCost)
)

-- With no profile at all the search is the same as the plain profile, cost and points.
local none, noneCost = Path.FindSync(0, from, to)
assert(none and math.abs(noneCost - plainCost) < 1e-9, "the option off keeps the plain cost")
assert(#none == #plain, "the option off keeps the plain walk")
for i = 1, #none do
	assert(none[i].x == plain[i].x and none[i].y == plain[i].y, "the option off keeps the plain points")
end

print(
	("roads: plain share %.3f cost %.1f, road share %.3f cost %.1f"):format(plainShare, plainCost, roadShare, roadCost)
)
print("roads_spec: ok")

-- The explicit default must preserve both the old physical cost and every drawn point, bit for bit.
local explicit, explicitCost = Path.FindSync(0, from, to, false, profile("default", true, 1.5))
assert(explicitCost == roadCost, "50% preserves the default road cost")
-- Omitting the preference uses OFFROAD in both search and drawing, just like an explicit default.
assert(#explicit == #road, "implicit and explicit default road preference draw the same line")
for i = 1, #road do
	assert(explicit[i].x == road[i].x and explicit[i].y == road[i].y, "default road drawing uses OFFROAD")
end
assert(share(explicit) >= roadShare, "the default walk's drawn line keeps its road share")
local shortest, shortestCost = Path.FindSync(0, from, to, false, profile("zero", true, 1))
assert(shortestCost == plainCost and #shortest == #plain, "0% removes all road preference")
for i, point in ipairs(plain) do
	assert(shortest[i].x == point.x and shortest[i].y == point.y, "0% preserves plain geometry")
end
-- A stronger preference still returns a physical walk. It may choose the same all-road route as the default.
local strong, strongCost = Path.FindSync(0, from, to, false, profile("strong", true, 3))
assert(strong and strongCost, "200% finds a walk")
assert(strongCost < roadCost * 3 / 1.5, "the reported cost is physical travel, not the preference weight")
-- Forward and inbound batches must use the same cost model as the rendered walk, including cached endpoints.
for _, case in ipairs({ { 1, plainCost }, { 1.5, roadCost }, { 3, strongCost } }) do
	local hz = profile("batch" .. case[1], true, case[1])
	local forward = Path.FindManySync(0, from, { to }, false, false, hz)[1]
	local inbound = Path.FindManySync(0, to, { from }, false, true, hz)[1]
	assert(
		math.abs(forward - case[2]) < 1e-9 and math.abs(inbound - case[2]) < 1e-9,
		"batches return the selected walk's real cost"
	)
end
-- Return to the default after changing it: neither the path nor endpoint cache may retain the stronger cost.
local restored, restoredCost = Path.FindSync(0, from, to, false, profile("default", true, 1.5))
assert(restoredCost == roadCost, "restoring 50% restores the cached default cost")
assert(share(restored) >= roadShare, "restoring 50% keeps the drawn line on the road")
print("road detour: default geometry, zero, stronger preference and both batch directions ok")

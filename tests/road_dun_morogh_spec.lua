-- Dun Morogh's roads are painted with the zone's cracked rock, not a texture named for a road (#1218): the walk from
-- Coldridge Pass (35.4, 62.3) to The Grizzled Den follows them with Follow roads on.
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
			local k, cell = Grid.locate(st, a.x + dx * t, a.y + dy * t)
			local set = k and Grid.roads(st, k)
			if set and set[cell] then
				on = on + length / steps
			end
		end
	end
	return on / total
end

local function profile(key, roads, factor)
	return {
		key = key,
		roads = roads and true or nil,
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

local from, to = { x = -5922, y = 58 }, { x = -6208, y = 339 }
local plain = assert(Path.FindSync(0, from, to, false, profile("plain")))
local road = assert(Path.FindSync(0, from, to, false, profile("road", true, 1.5)))
local plainShare, roadShare = share(plain), share(road)
assert(roadShare > 0.5, ("the Coldridge walk is %.2f road"):format(roadShare))
assert(roadShare > plainShare + 0.2, ("road share %.2f is not above plain %.2f"):format(roadShare, plainShare))
print(("road_dun_morogh_spec: plain %.2f, road %.2f"):format(plainShare, roadShare))

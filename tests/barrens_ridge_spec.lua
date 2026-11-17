-- A Gold Road -> Camp Taurajo walk climbed steep faces by borrowing a portal's height outside the two cells.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(1)
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end

local from = { x = -1771.144279, y = -1906.467662, z = 100 }
local to = { x = -1779.104478, y = -1898.507463, z = 110 }
local points, cost = ns.Path.FindSync(1, from, to)
assert(points, "the Barrens ridge has a walkable way around")
local direct = math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
assert(cost > direct + 0.01, "the walk must go around the steep face rather than climb the direct grid step")
assert(ns.Path.FindSync(1, to, from), "the reverse walk remains reachable")
assert(
	ns.Path.FindSync(1, { x = 1575, y = -2625 }, { x = -2380.67, y = -1882.67, z = 95.85 }),
	"Gold Road to Camp Taurajo remains reachable"
)
print("barrens_ridge_spec: ok")

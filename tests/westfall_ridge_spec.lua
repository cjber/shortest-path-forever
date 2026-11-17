-- The shipped map must not borrow a steep portal's remote end to climb a ridge. These steps were taken by
-- Ravenhill -> Sentinel Hill and Darkshire -> Ravenhill; the native terrain bake marks the intervening faces steep.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end

local crossings = {
	{
		{ x = -10670.646766, y = 648.756219, z = 28 },
		{ x = -10678.606965, y = 656.716418, z = 39 },
	},
	{
		{ x = -10766.169154, y = 187.064677, z = 34 },
		{ x = -10758.208955, y = 195.024876, z = 44 },
	},
}
for _, pair in ipairs(crossings) do
	local from, to = pair[1], pair[2]
	local points, cost = ns.Path.FindSync(0, from, to)
	assert(points, "the ridge has a walkable way around")
	local direct = math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
	assert(cost > direct + 0.01, "the walk must go around the face rather than climb the direct grid step")
	assert(ns.Path.FindSync(0, to, from), "the reverse walk remains reachable")
end

assert(
	ns.Path.FindSync(0, { x = -10750, y = 330 }, { x = -10628.89, y = 1036.68, z = 34.06 }),
	"Ravenhill to Sentinel Hill remains reachable"
)
print("westfall_ridge_spec: ok")

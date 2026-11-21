-- A few city and cave walks that a bake change broke before, each held to the raw navmesh's shortest walk
-- (tools/nav_reference.py): no shorter than the reference less the ends' slack, which a climb up a face would be,
-- and no longer than an octile grid walk of it. The full suite is caves_cities_spec (#1021); these run in seconds.
local ns = {}
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end

local OCTILE, SLACK = 1 / math.cos(math.pi / 8), 12

local walks = {
	[0] = {
		-- Searing Gorge: the steep floor of the Slave Worker cave is entered downhill (#1101).
		{ "Slave Worker cave, in", { -6727.8, -1108.6, 186.1 }, { -6423.8, -1300.7, 180.9 }, 377.3 },
		{ "Slave Worker cave, out", { -6423.8, -1300.7, 180.9 }, { -6727.8, -1108.6, 186.1 }, 372.6 },
	},
	[1] = {
		-- Thunder Bluff: the bridge and the ground below it are separate border crossings.
		{ "Innkeeper Pala to Taim Ragetotem", { -1300.3, 38.5, 129.3 }, { -1382.4, -77.8, 160.6 }, 157.3 },
		{ "Taim Ragetotem to Innkeeper Pala", { -1382.4, -77.8, 160.6 }, { -1300.3, 38.5, 129.3 }, 155.7 },
	},
}

for map, list in pairs(walks) do
	assert(loadfile("tools/load_nav.lua"))(map)
	for _, w in ipairs(list) do
		local name, a, b, reference = w[1], w[2], w[3], w[4]
		local from, to = { x = a[1], y = a[2], z = a[3] }, { x = b[1], y = b[2], z = b[3] }
		local points, cost = ns.Path.FindSync(map, from, to)
		assert(points and type(cost) == "number", name .. ": no walk")
		assert(
			cost >= reference - SLACK,
			("%s: %.1f yd is shorter than the navmesh allows (%.1f)"):format(name, cost, reference)
		)
		assert(
			cost <= reference * OCTILE + SLACK,
			("%s: %.1f yd against a navmesh walk of %.1f"):format(name, cost, reference)
		)
	end
end
print("caves_cities_guard_spec: ok")

local ns = {}
assert(loadfile("tools/load_nav.lua"))(1)
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua", "Routing/Planner.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
assert(loadfile(arg[1] or "Data/Routes.lua"))("ShortestPathForever", ns)

local from = { map = 1, x = 6341.38, y = 557.68, z = 16.29 }
local places = ns.Planner.Places({ docks = ns.Docks })
for _, id in ipairs({ 8, 10, 24 }) do
	local dock = ns.Docks[id]
	local place
	for _, candidate in ipairs(places) do
		if candidate.kind == "dock" and candidate.id == id then
			place = candidate
		end
	end
	assert(place, "missing dock")
	local points, why = ns.Path.FindSync(1, from, place, false)
	assert(points, why)
	assert(points.wet < 1, "Auberdine dock " .. id .. " requires swimming: " .. points.wet)
	assert(dock.walk and place.z == dock.walk.z and place.z > dock.z, "walk must target the pier deck")
	local last = points[#points]
	assert(last.x == dock.walk.x and last.y == dock.walk.y, "guidance ends off the boarding point")
	assert((dock.x - last.x) ^ 2 + (dock.y - last.y) ^ 2 < 30 ^ 2, "boarding point too far from boat")
end
print("dock_boarding_spec: Auberdine's three boarding routes stay on the pier")

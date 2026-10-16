-- Instance entrances (Data/Portals.lua ns.Entrances): a goal inside a dungeon or raid is planned to its door, which
-- must stand on a continent's walking map where a walk can reach it.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
assert(loadfile("tools/load_nav.lua"))(1)
for _, file in ipairs({ "Data/Portals.lua", "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local count = 0
for instance, door in pairs(ns.Entrances) do
	count = count + 1
	assert(instance > 2 and (door.map == 0 or door.map == 1), "each door stands on a continent")
	assert(type(door.name) == "string" and door.name ~= "", "each door is named")
	-- Every door is on the walking map: a walk from 40 yards off reaches it, or says why not other than no data.
	local near = { x = door.x + 40, y = door.y }
	local points, why = ns.Path.FindSync(door.map, near, door)
	assert(points or why == "unreachable", door.name .. " is on the walking map: " .. tostring(why))
end
assert(count >= 20, "the classic dungeons and raids have doors")
-- An AreaTrigger door keeps its height; a corpse-point door (most dungeons in this build) has none.
assert(ns.Entrances[409].name == "Molten Core" and ns.Entrances[409].z, "Molten Core's trigger has a height")
local deadmines = ns.Entrances[36]
assert(deadmines.name == "Deadmines" and deadmines.map == 0 and not deadmines.z)
assert(math.abs(deadmines.x + 11208) < 50 and math.abs(deadmines.y - 1675) < 50, "the Deadmines door is in Moonbrook")
print("entrances: " .. count .. " doors on the walking maps: ok")

-- Instance entrances (Data/Portals.lua ns.Entrances): a goal inside a dungeon or raid is planned to its door. Each
-- door must stand on its continent's walking map, where a walk reaches it, in the outdoor zone the instance is in.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
assert(loadfile("tools/load_nav.lua"))(1)
for _, file in ipairs({ "Data/Portals.lua", "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
-- The zone map each instance's door is in (UiMap IDs: Barrens 1413, Westfall 1436, Searing Gorge 1427, ...).
local ZONES = {
	[33] = 1421, -- Shadowfang Keep: Silverpine Forest
	[34] = 1453, -- Stormwind Stockade: Stormwind City
	[36] = 1436, -- Deadmines: Westfall
	[43] = 1413, -- Wailing Caverns: the Barrens
	[47] = 1413, -- Razorfen Kraul: the Barrens
	[48] = 1440, -- Blackfathom Deeps: Ashenvale
	[70] = 1418, -- Uldaman: Badlands
	[90] = 1426, -- Gnomeregan: Dun Morogh
	[109] = 1435, -- Sunken Temple: Swamp of Sorrows
	[129] = 1413, -- Razorfen Downs: the Barrens
	[189] = 1420, -- Scarlet Monastery: Tirisfal Glades
	[209] = 1446, -- Zul'Farrak: Tanaris
	[229] = 1427, -- Blackrock Spire: Searing Gorge's side of Blackrock Mountain
	[230] = 1427, -- Blackrock Depths
	[249] = 1445, -- Onyxia's Lair: Dustwallow Marsh
	[289] = 1422, -- Scholomance: Western Plaguelands
	[309] = 1434, -- Zul'Gurub: Stranglethorn Vale
	[329] = 1423, -- Stratholme: Eastern Plaguelands
	[349] = 1443, -- Maraudon: Desolace
	[389] = 1454, -- Ragefire Chasm: Orgrimmar
	[409] = 1427, -- Molten Core
	[429] = 1444, -- Dire Maul: Feralas
	[469] = 1428, -- Blackwing Lair: Burning Steppes' side
	[509] = 1451, -- Ruins of Ahn'Qiraj: Silithus
	[531] = 1451, -- Ahn'Qiraj Temple: Silithus
	[533] = 1423, -- Naxxramas: Eastern Plaguelands
}
local count = 0
for instance, door in pairs(ns.Entrances) do
	count = count + 1
	assert(ZONES[instance], door.name .. " is an instance this spec knows")
	assert(door.map == 0 or door.map == 1, door.name .. "'s door stands on a continent")
	local inZone = false
	for _, zone in ipairs(door.zones) do
		inZone = inZone or zone == ZONES[instance]
	end
	assert(inZone, door.name .. "'s door is in its zone")
	-- A walk from 40 yards off, on whichever side has ground, reaches the door.
	local reached
	for _, offset in ipairs({ { 40, 0 }, { -40, 0 }, { 0, 40 }, { 0, -40 } }) do
		reached = reached or ns.Path.FindSync(door.map, { x = door.x + offset[1], y = door.y + offset[2] }, door)
	end
	assert(reached, door.name .. "'s door is reached on the walking map")
end
assert(count == 26, "the classic dungeons and raids have doors")
-- A corpse-point door has no height; Naxxramas, with no corpse point, takes its AreaTrigger and its height.
assert(not ns.Entrances[36].z and ns.Entrances[533].z, "only a trigger door has a height")
print("entrances: " .. count .. " doors in their zones on the walking maps: ok")

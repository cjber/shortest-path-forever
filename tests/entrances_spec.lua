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

-- The door stop is built once, for a journey to a place inside the instance and for a Nearby services row alike.
ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
-- The file's registrations need the client's frames and menus; the door stop they do not.
ns.Init = function() end
local inside = 0
_G.GetInstanceInfo = function()
	return "", "none", 0, "", 0, 0, false, inside
end
_G.GetRealZoneText = function(instance)
	return instance == 36 and "The Deadmines" or ""
end
assert(loadfile("Journey/JourneyInput.lua"))("ShortestPathForever", ns)
local boss = {
	map = 36,
	x = 10,
	y = 10,
	label = "Boss",
	questID = 101,
	questIDs = { 101 },
	routeTitle = "Boss",
	details = { "Slay the boss" },
}
local door = assert(ns.EntranceStop(36, boss), "the door is built from the entrance data")
assert(
	door.map == ns.Entrances[36].map and door.x == ns.Entrances[36].x and door.y == ns.Entrances[36].y,
	"the door stands on its continent at the entrance's own point"
)
assert(
	door.label == "Boss" and door.entrance == 36 and door.stop == boss,
	"it keeps the stop it stands for, its label and the instance it enters"
)
local mapped = assert(ns.InstanceEntrance(boss), "a goal inside the instance plans to its door")
assert(
	mapped.label == door.label and mapped.entrance == door.entrance and mapped.stop == door.stop,
	"the map's instance journey and a Nearby services row start the same door stop"
)
local unnamed = assert(ns.EntranceStop(36, { map = 36 }), "a stop without a label still gets a door")
assert(unnamed.label == "Enter The Deadmines", "the door says what to enter, by the client's own name")
assert(unnamed.stop and unnamed.stop.map == 36, "and keeps the stop it stands for")
inside = 36
assert(ns.InstanceEntrance(boss) == boss, "inside the instance, the goal stays the goal")
inside = 0
assert(ns.EntranceStop(9999, boss) == nil, "no entrance, no door")
print("entrances: one door stop, for the map and the Nearby services list: ok")

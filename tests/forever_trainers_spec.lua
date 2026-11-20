-- Forever's own trainers (#1082): classic-db holds none of them, so Data/Services.lua types their roles in
-- tools/gen_services.py. Zephras Isle is its own world map, and without them its Nearby services listed no class or
-- profession trainer at all. One trainer per class and profession taught on the island, as QuestieDB places them.
local ns = {}
setfenv(assert(loadfile("Data/Services.lua")), { pairs = pairs })("ShortestPathForever", ns)

local CLASSES = {
	[251964] = 1, -- Blademaster Ren, warrior
	[251376] = 3, -- Tai'ree Farsight, hunter
	[251389] = 4, -- Akeri Duskblade, rogue
	[251374] = 7, -- Windshaper Boro, shaman
	[251379] = 8, -- Dorii Brightwhisper, mage
	[251373] = 11, -- Xyton Silverwind, druid
}
for npc, class in pairs(CLASSES) do
	assert(ns.ClassTrainers[npc] == class, ("Zephras class trainer %d trains class %d"):format(npc, class))
end

local PROFESSIONS = {
	[253004] = 171, -- Iaadaria Bitterwind, alchemy
	[251913] = 164, -- Aedi Thriceforged, blacksmithing
	[257004] = 333, -- Eaysaa Brightgust, enchanting
	[254345] = 182, -- Syriel Nightrain, herbalism
	[251993] = 165, -- Indari Sunseam, leatherworking
	[252388] = 186, -- Halavuul Cragwind, mining
	[257003] = 393, -- Ishlee Breezewhisper, skinning
	[251991] = 197, -- Taleen Shimmerthread, tailoring
	[257007] = 129, -- Melasa Fairmend, first aid
	[251905] = 185, -- Zerril Softbreeze, cooking
	[251992] = 356, -- Fenn Fairweather, fishing
}
for npc, skill in pairs(PROFESSIONS) do
	assert(ns.ProfessionTrainers[npc] == skill, ("Zephras profession trainer %d teaches skill %d"):format(npc, skill))
	assert(ns.ProfessionIcons[skill], ("skill %d has its profession icon"):format(skill))
end

print("forever_trainers_spec: ok")

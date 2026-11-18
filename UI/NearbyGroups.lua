---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- The groups the Nearby services list offers, by what a vendor sells and by the service an NPC's flags name. The
-- list and the map's town services read the same labels, so a bank is a bank in both places. The group shapes are in
-- types/Addon.lua (SPFVendorGroup and SPFServiceGroup).
--
-- `icon` is what the Nearby services row shows: the goods' own item for a vendor, the tracking atlas for a service.
-- `tracking` is the atlas the world map's service pin wears: the client's minimap tracking art, or the world map's own
-- marks where the tracking sheet has none, so a pin looks like the map's own and never a square item icon. Each kind
-- of service the map filter lists wears its own, so no pin borrows another service's mark (#978, #985); every name is
-- in the Forever client's UiTextureAtlasElement table, and tests/sim/town_services_scenario.lua asks the simulated
-- client for each. Two groups share one only where the filter treats them as one kind: arrows and bullets, food and
-- drink, bags and trade supplies, and the class trainer with the portal trainer, who is a mage trainer.
-- - Bags and trade supplies: the tracking sheet's crafting hammer (`Professions-Crafting-Orders-Icon`), since its
--   reagents pouch belongs to the reagent vendors.
-- - Books and recipes: the tracking sheet's recipe scroll (`poi-workorders`); the class book is the class trainer's.
-- - Weapons and armour: the minimap's steel armoury shield (`Warfronts-BaseMapIcons-Empty-Armory-Minimap`), not the
--   transmogrifier's purple banners, which belong to the transmogrifier.
-- - Weapon master: the tracking sheet's sword (`UpgradeItem-32x32`), apart from the class trainer's book.

-- Vendors grouped by what they sell: QuestieDB's item class and subclass, and the food and drink item IDs in
-- Data/Services.lua.
---@type SPFVendorGroup[]
local VENDOR_GROUPS = {
	{ key = "arrows", label = L["Arrows"], icon = 2512, tracking = "Ammunition" },
	{ key = "bullets", label = L["Bullets"], icon = 2516, tracking = "Ammunition" },
	{ key = "food", label = L["Food"], icon = 4540, tracking = "Food" },
	{ key = "drink", label = L["Drink"], icon = 159, tracking = "Food" },
	{ key = "bags", label = L["Bags"], icon = 4498, tracking = "Professions-Crafting-Orders-Icon" },
	{ key = "trade", label = L["Trade supplies"], icon = 2320, tracking = "Professions-Crafting-Orders-Icon" },
	{ key = "reagents", label = L["Reagents"], icon = 2928, tracking = "Reagents" },
	{ key = "books", label = L["Books and recipes"], icon = 2555, tracking = "poi-workorders" },
	{
		key = "gear",
		label = L["Weapons and armour"],
		icon = 851,
		tracking = "Warfronts-BaseMapIcons-Empty-Armory-Minimap",
	},
}

-- The other services keep their own keys and the client's tracking atlases; their tracking is the atlas itself.
---@type SPFServiceGroup[]
local SERVICES = {
	{ key = "innkeeper", flag = "INNKEEPER", label = L["Innkeeper"], icon = "innkeeper", tracking = "Innkeeper" },
	{
		key = "flight",
		flag = "FLIGHT_MASTER",
		label = L["Flight master"],
		icon = "flightmaster",
		tracking = "FlightMaster",
	},
	{
		key = "stable",
		flag = "STABLEMASTER",
		label = L["Stable master"],
		icon = "stablemaster",
		tracking = "StableMaster",
	},
	{ key = "repair", flag = "REPAIR", label = L["Repair"], icon = "repair", tracking = "Repair" },
	{ key = "bank", flag = "BANKER", label = L["Bank"], icon = "banker", tracking = "Banker" },
	{ key = "auction", flag = "AUCTIONEER", label = L["Auction house"], icon = "auctioneer", tracking = "Auctioneer" },
	{
		key = "transmog",
		flag = "TRANSMOGRIFIER",
		label = L["Transmogrifier"],
		icon = "poi-transmogrifier",
		tracking = "poi-transmogrifier",
	},
}

-- The trainers' map art, by group key: the class trainer's book, the weapon master's sword and the battlemaster's
-- banner from the tracking sheet. UI/NearbyRoles.lua builds those groups.
local ROLE_TRACKING = {
	class = "Class",
	portal = "Class",
	weapon = "UpgradeItem-32x32",
	battlemaster = "BattleMaster",
}

-- Each profession trainer's map art, by skill line: the world map's own profession mark for that profession (the
-- `worldquest-icon-*` art a profession's world quest wears), so a skinning trainer wears a hide and a tailor a spool,
-- not the square spell icon the Nearby services row shows. Lockpicking has no profession mark; its trainer wears the
-- minimap's locked chest (`vignetteloot-locked`). tests/nearby_professions_spec.lua fails a trainer skill missing here.
local PROFESSION_TRACKING = {
	[129] = "worldquest-icon-firstaid",
	[164] = "worldquest-icon-blacksmithing",
	[165] = "worldquest-icon-leatherworking",
	[171] = "worldquest-icon-alchemy",
	[182] = "worldquest-icon-herbalism",
	[185] = "worldquest-icon-cooking",
	[186] = "worldquest-icon-mining",
	[197] = "worldquest-icon-tailoring",
	[202] = "worldquest-icon-engineering",
	[333] = "worldquest-icon-enchanting",
	[356] = "worldquest-icon-fishing",
	[393] = "worldquest-icon-skinning",
	[633] = "vignetteloot-locked",
}

local SECTION_LABELS = {
	vendors = L["Vendors"],
	trainers = L["Trainers"],
	services = L["Services"],
	entrances = L["Dungeons and raids"],
}

ns.NearbyGroups = {
	vendors = VENDOR_GROUPS,
	services = SERVICES,
	roles = ROLE_TRACKING,
	professions = PROFESSION_TRACKING,
	sections = SECTION_LABELS,
}

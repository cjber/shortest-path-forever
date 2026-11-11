---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- The groups the Nearby services list offers, by what a vendor sells and by the service an NPC's flags name. The
-- list and the map's town services read the same labels and icons, so a bank looks like a bank in both places.
-- The group shapes are in types/Addon.lua (SPFVendorGroup and SPFServiceGroup).

-- Vendors grouped by what they sell: QuestieDB's item class and subclass, and the food and drink item IDs in
-- Data/Services.lua. The icon is the item the mock shows for the group.
---@type SPFVendorGroup[]
local VENDOR_GROUPS = {
	{ key = "arrows", label = L["Arrows"], icon = 2512 },
	{ key = "bullets", label = L["Bullets"], icon = 2516 },
	{ key = "food", label = L["Food"], icon = 4540 },
	{ key = "drink", label = L["Drink"], icon = 159 },
	{ key = "bags", label = L["Bags"], icon = 4498 },
	{ key = "trade", label = L["Trade supplies"], icon = 2320 },
	{ key = "reagents", label = L["Reagents"], icon = 2928 },
	{ key = "books", label = L["Books and recipes"], icon = 2555 },
	{ key = "gear", label = L["Weapons and armour"], icon = 851 },
}

-- The other services keep their own keys and the client's tracking atlases.
---@type SPFServiceGroup[]
local SERVICES = {
	{ key = "innkeeper", flag = "INNKEEPER", label = L["Innkeeper"], icon = "innkeeper" },
	{ key = "flight", flag = "FLIGHT_MASTER", label = L["Flight master"], icon = "flightmaster" },
	{ key = "stable", flag = "STABLEMASTER", label = L["Stable master"], icon = "stablemaster" },
	{ key = "repair", flag = "REPAIR", label = L["Repair"], icon = "repair" },
	{ key = "bank", flag = "BANKER", label = L["Bank"], icon = "banker" },
	{ key = "auction", flag = "AUCTIONEER", label = L["Auction house"], icon = "auctioneer" },
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
	sections = SECTION_LABELS,
}

-- UI/Nearby.lua's level tiers on arrows, shot, food and drink: which vendor a row goes to for your level, what it
-- names, and the better goods farther away it offers as a trip of its own, in the panel's rows and the tracking menu.
local timers, trackingMenus = {}, {}
local function node(text)
	local n = { text = text, children = {} }
	function n:CreateButton(childText, callback)
		local child = node(childText)
		child.callback = callback
		self.children[#self.children + 1] = child
		return child
	end
	function n:CreateTitle(title)
		self.children[#self.children + 1] = { text = title, title = true }
	end
	function n:SetEnabled(enabled)
		self.enabled = enabled
	end
	function n:SetScrollMode(extent)
		self.scrollExtent = extent
	end
	function n:SetTooltip(fn)
		self.tooltip = fn
	end
	return n
end
local env = setmetatable({
	Menu = {
		ModifyMenu = function(tag, callback)
			trackingMenus[tag] = callback
		end,
	},
	MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 },
	CreateFrame = function()
		return { RegisterEvent = function() end, SetScript = function() end }
	end,
	UnitFactionGroup = function()
		return "Horde"
	end,
	UnitClass = function()
		return "Hunter", "HUNTER", 3
	end,
	C_Map = {
		GetBestMapForUnit = function()
			return 100
		end,
		GetPlayerMapPosition = function()
			return {
				GetXY = function()
					return 0.1, 0.1
				end,
			}
		end,
	},
	C_Timer = {
		After = function(_, fn)
			timers[#timers + 1] = fn
		end,
	},
	debugprofilestop = function()
		return 0
	end,
	InCombatLockdown = function()
		return false
	end,
	geterrorhandler = function()
		return error
	end,
	SlashCmdList = {},
}, { __index = _G })
env._G = env

-- Nearby.lua over a fixture QuestieDB, read to the end. Its map points are the UI map's percent in thousandths.
local function load(questie)
	env.LibQuestieDB = questie
	local starts = {}
	local ns = {
		Init = function(fn)
			starts[#starts + 1] = fn
		end,
		WorldPoint = function(_, x, y)
			return { map = 1, x = x * 1000, y = y * 1000 }
		end,
		Path = {
			Busy = function()
				return false
			end,
		},
		db = {},
		GamepadUI = function()
			return false
		end,
		SafeCall = function(_, fn, ...)
			return true, fn(...)
		end,
	}
	setfenv(assert(loadfile("Locales/enUS.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("Data/Services.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/MenuModifier.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/Nearby.lua")), env)("ShortestPathForever", ns)
	for _, fn in ipairs(starts) do
		fn()
	end
	while #timers > 0 do
		table.remove(timers, 1)()
	end
	assert(ns.NearbyServices.State() == "ready", "the fixture reads")
	return ns
end

-- Goods in level tiers: Orgrimmar's nearest arrow seller sells Rough and Sharp only, the bow merchant a little
-- farther sells up to Jagged, and one vendor far off sells a level 51 arrow. The row goes to the best tier you can use
-- from around you, never to the far one, and names it.
do
	local tierNpcs = {
		[21] = { "Zendo'jian", { [10] = { { 11, 10 } } }, "H", 4, "Weapon Vendor", n = 5 },
		[22] = { "Jin'sora", { [10] = { { 30, 10 } } }, "H", 4, "Bow Merchant", n = 5 },
		[23] = { "Far quartermaster", { [10] = { { 90, 90 } } }, "H", 4, "Quartermaster", n = 5 },
	}
	local tierItems = {
		[2512] = { { 21, 22 }, 6, 2, "Rough Arrow", 1 },
		[2515] = { { 21, 22 }, 6, 2, "Sharp Arrow", 10 },
		[3030] = { { 22 }, 6, 2, "Razor Arrow", 25 },
		[11285] = { { 22 }, 6, 2, "Jagged Arrow", 40 },
		[19316] = { { 23 }, 6, 2, "Ice Threaded Arrow", 51 },
		[851] = { { 21 }, 2, 7, "Cutlass", 11 },
	}
	local tierIDs = {}
	for id in pairs(tierItems) do
		tierIDs[#tierIDs + 1] = id
	end
	table.sort(tierIDs)
	local tierLib = {
		RequireContract = function(v)
			return v == 2
		end,
		Enum = {
			byExpansion = {
				Classic = {
					npcFlags = {
						VENDOR = 4,
						TRAINER = 16,
						REPAIR = 16384,
						INNKEEPER = 128,
						BANKER = 256,
						AUCTIONEER = 4096,
						FLIGHT_MASTER = 8,
						STABLEMASTER = 8192,
					},
				},
			},
		},
		Support = {
			Get = function(name)
				assert(name == "ZoneDB")
				return { private = { areaIdToUiMapId = "return {[10]=100}", subZoneToParentZone = "return {}" } }
			end,
		},
		Npc = {
			GetAllIds = function()
				return { 21, 22, 23 }
			end,
			GetAll = function(id)
				return tierNpcs[id]
			end,
		},
		Item = {
			GetAllIds = function()
				return tierIDs
			end,
			GetAll = function(id, fields)
				assert(fields[5] == "requiredLevel", "the level each item needs is read with it")
				local row = tierItems[id]
				return row and { row[1], row[2], row[3], row[4], row[5], n = 5 }
			end,
		},
	}
	local level
	env.UnitLevel = function()
		return level
	end
	local tierNs = load(tierLib)
	local tiers = tierNs.NearbyServices
	local orgrimmar = { map = 1, x = 100, y = 100 }
	local function seller(query)
		return tiers.Shortlist("arrows", orgrimmar, 1, query)[1]
	end
	level = 5
	assert(seller().id == 21, "at 5 both sell the best you can use, Rough Arrow, and the nearest wins")
	assert(tiers.Detail("arrows", seller(), "") == "Zendo'jian · Rough Arrow", "the row names what you buy")
	level = 25
	assert(seller().id == 22, "at 25 the bow merchant's Razor Arrow beats the nearer Sharp Arrow")
	assert(tiers.Nearest("arrows", orgrimmar).id == 22, "the tracking menu's row goes there too")
	assert(seller("arrows").id == 22, "a search for the group itself still picks the tier")
	assert(tiers.Detail("arrows", seller(), "") == "Jin'sora · Razor Arrow", "and the row names it")
	local goods = tiers.Goods("arrows", seller(), "")
	assert(goods and #goods == 1 and goods[1] == 3030, "the goods a row names, for its icon and tooltip")
	assert(tiers.Goods("arrows", seller(), "Sharp")[1] == 2515, "while searching, the goods that matched")
	assert(tiers.Goods("gear", tiers.Nearest("gear", orgrimmar), "") == nil, "an untiered row names none")
	assert(seller("Sharp Arrow").id == 21, "a search for an item finds the nearest that sells it")
	assert(seller("Zendo").id == 21, "a search for an NPC finds that NPC")
	level = 60
	assert(seller().id == 22, "at 60 the far quartermaster's level 51 arrow is out of reach: Jagged Arrow it is")
	assert(tiers.Detail("arrows", seller(), "") == "Jin'sora · Jagged Arrow", "named at the tier it was chosen for")
	assert(seller("Ice Threaded").id == 23, "and found by name")
	assert(tiers.Nearest("gear", orgrimmar).id == 21, "gear has no tiers")
	-- Better goods farther away: at 60 the level 51 arrow is out of reach, so the panel offers it as a row of its own,
	-- and the tracking menu as a button under Arrows, to whoever carries a bow.
	local ranged, mana = 2, 0
	env.GetInventorySlotInfo = function(slot)
		assert(slot == "RANGEDSLOT")
		return 18
	end
	env.GetInventoryItemID = function(unit, slot)
		assert(unit == "player" and slot == 18)
		return ranged and 9000 or nil
	end
	env.UnitPowerMax = function(unit, power)
		assert(unit == "player" and power == 0)
		return mana
	end
	env.Enum = { PowerType = { Mana = 0 } }
	env.C_Item = {
		GetItemInfoInstant = function(id)
			assert(id == 9000)
			return id, "Weapon", "Bows", "INVTYPE_RANGED", 135490, 2, ranged
		end,
	}
	env.C_Map.GetMapInfo = function(map)
		return map == 100 and { name = "Durotar" } or nil
	end
	local lines = {}
	env.GameTooltip_SetTitle = function(_, text)
		lines[#lines + 1] = text
	end
	env.GameTooltip_AddNormalLine = function(_, text)
		lines[#lines + 1] = text
	end
	env.GameTooltip_AddColoredLine = function(_, text)
		lines[#lines + 1] = text
	end
	local function vendorRows()
		for _, section in ipairs(tiers.Sections(orgrimmar, "")) do
			if section.section == "vendors" then
				return section
			end
		end
	end
	local function rowById(id)
		for _, row in ipairs(vendorRows().rows) do
			if row.id == id then
				return row
			end
		end
	end
	level = 60
	local vendors = vendorRows()
	local better = vendors.rows[2]
	assert(
		vendors.rows[1].id == "arrows" and better.id == "better:arrows",
		"the better trip sits right under its group"
	)
	assert(better.npc.id == 23 and better.tier == 51, "it goes to the level 51 arrow, however far")
	assert(vendors.count == #vendors.rows - 1, "the section still counts its groups")
	assert(tiers.Shortlist("arrows", orgrimmar, 1, nil, 51)[1].id == 23, "a shortlist can be asked for a tier")
	assert(tiers.Detail("arrows", better.npc, "") == "Far quartermaster · Ice Threaded Arrow", "named at its tier")
	assert(tiers.Zone(better.npc) == "Durotar", "and the zone it stands in")
	assert(rowById("better:gear") == nil, "gear has no tiers")
	assert(rowById("better:drink") == nil and rowById("better:bullets") == nil, "nothing sold of the others here")
	assert(#tiers.Sections(orgrimmar, "Sharp Arrow")[1].rows == 1, "a search for an item names that, no trip")
	ranged = 3
	assert(rowById("better:arrows") == nil, "a gun has no use for arrows")
	ranged = nil
	assert(rowById("better:arrows") == nil, "nor does an empty ranged slot")
	ranged = 2
	level = 25
	assert(rowById("better:arrows") == nil, "at 25 the best is around you: no trip")
	level = 60
	-- Art.lua loads after Nearby.lua, so the menu reads the upgrade arrow's markup only when it is built.
	tierNs.Art = {
		Markup = function(atlas, height)
			return ("|A:%s:%d:11|a"):format(atlas, height)
		end,
	}
	local root = node()
	trackingMenus.MENU_WORLD_MAP_TRACKING(nil, root)
	local entries = root.children[1].children
	local trip
	for at, entry in ipairs(entries) do
		if entry.text == "Arrows" then
			trip = entries[at + 1]
		end
	end
	assert(trip and trip.text:find("Ice Threaded Arrow$"), "the menu offers the trip under Arrows")
	assert(trip.text:find("|A:bags-greenarrow:12:11|a", 1, true) == 1, "behind the client's upgrade arrow")
	trip.tooltip({})
	assert(lines[1] == "Ice Threaded Arrow", "its tooltip names the goods")
	assert(lines[2] == "Better for your level, farther away", "why they are offered")
	assert(lines[3] == "Far quartermaster, Durotar", "and who sells them where")
	level = nil
	assert(seller().id == 21, "with no level known the nearest wins, as before")
	assert(rowById("better:arrows") == nil, "and no trip is offered")
end
print("nearby_tiers: level tiers, the goods a row names, and better goods farther away: ok")

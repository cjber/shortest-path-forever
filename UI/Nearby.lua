---@type string, SPFNamespace
local _, ns = ...

if ns.broken then
	return
end
local L = ns.L
-- Vendors grouped by what they sell: QuestieDB's item class and subclass, and the food and drink item IDs in
-- Data/Services.lua. The icon is the item the mock shows for the group.
local VENDOR_GROUPS = {
	{ key = "arrows", label = L["Arrows"], icon = 2512 },
	{ key = "bullets", label = L["Bullets"], icon = 2516 },
	{ key = "food", label = L["Food"], icon = 4540 },
	{ key = "drink", label = L["Drink"], icon = 159 },
	{ key = "bags", label = L["Bags"], icon = 4498 },
	{ key = "trade", label = L["Trade supplies"], icon = 2320 },
	{ key = "reagents", label = L["Reagents"], icon = 2928 },
	{ key = "gear", label = L["Weapons and armour"], icon = 851 },
}
-- Groups whose goods come in level tiers (QuestieDB's requiredLevel): Rough to Jagged Arrow, Tough Hunk of Bread
-- to Homemade Cherry Pie, Spring Water to Morning Glory Dew. The nearest arrow seller in Orgrimmar sells Rough and
-- Sharp only, while the bow merchant beside him sells Razor and Jagged too.
local TIERED = { arrows = true, bullets = true, food = true, drink = true }
-- Yards farther than the nearest seller a vendor of a better tier for your level may stand and still be chosen:
-- about a minute's run, which crosses a capital. The best tiers of all (level 51 and up) are each sold by one vendor
-- on a continent, so a tier is only ever chosen from around you.
local TIER_REACH = 400
-- The ranged weapons each ammunition group feeds (item subclass: Bows, Guns, Crossbows), so a better arrow far off is
-- offered only to whoever carries a bow.
local AMMO = { [2] = "arrows", [3] = "bullets", [18] = "arrows" }
-- The client's own upgrade mark on an item (Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml:109, and Forever's
-- Camelot/EquipmentFlyout.xml:12), before a better trip's menu button; 12 high keeps its 20x22 shape (WFA-27).
local UPGRADE_ATLAS, UPGRADE_MARKUP = "bags-greenarrow", 12
-- The other services keep their own keys and the client's tracking atlases.
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
}
-- A vendor group's item IDs by NPC, which a search matches and a row says it sells.
local index, vendorItems, groups, groupByKey, state = {}, {}, {}, {}, "idle"
-- Every vendor item's name, so a search matches what a vendor sells and a row can name it.
local itemNames = {}
-- The level a tiered group's item needs, by item ID; 0 for none.
local itemLevels = {}
-- Each tiered group's best tier by NPC for one player level, since the level last asked.
local tierLevel, tierCache = nil, {}
-- Callers waiting for the index, so an open panel fills as soon as the read finishes, or says why it could not.
local waiting = {}

---@param fn fun()
local function WhenReady(fn)
	if state == "ready" then
		fn()
	else
		waiting[#waiting + 1] = fn
	end
end

-- Tells those callers the index is ready, or that it never will be.
local function Notify()
	local callers = waiting
	waiting = {}
	for _, fn in ipairs(callers) do
		fn()
	end
end

-- Case-folded matching for the panel's search box: plain substring, never a keyword list.
local Fold = ForeverCore.Text.Fold

local function Contains(folded, query)
	return query == "" or folded:find(query, 1, true) ~= nil
end
-- What the menu says in place of the services: QuestieDB is still being read, is not installed, or could not be read.
local STATUS = {
	building = L["Loading QuestieDB…"],
	missing = L["Nearby services need the QuestieDB addon."],
	failed = L["Nearby services could not read QuestieDB."],
}
-- A service's closest few by straight line: enough to include the one a boat or flight reaches sooner than the
-- closest walk, without planning every spawn on the continent.
local SHORTLIST = 5
-- A group list can run past the screen edge (a capital city sells dozens), and a menu never clamps to the screen,
-- so it scrolls past this many rows the way Blizzard's own long menus do (Blizzard_Menu SetScrollMode).
local MENU_ROW, MENU_ROWS = 20, 20

-- What put an NPC in a group (defined below, after the index is built), and the goods a row names.
local Items, Goods

-- Every NPC of a group on the player's continent that a folded query matches, or all of them with an empty query.
-- A group label, an NPC's name or title, or the name of an item that puts the NPC in the group each count.
local function Matching(key, world, query)
	if query == "" then
		return nil
	end
	local matching = {}
	local labelHit = query ~= "" and Contains(Fold((groupByKey[key] or {}).label), query)
	for _, place in ipairs(index[key] or {}) do
		if place.world.map == world.map then
			local hit = query == "" or labelHit or Contains(Fold(place.name), query)
			if not hit then
				hit = Contains(Fold(place.title), query)
			end
			if not hit then
				for _, itemID in ipairs(Items(key, place.id) or {}) do
					if Contains(Fold(itemNames[itemID]), query) then
						hit = true
						break
					end
				end
			end
			if hit then
				matching[place.id] = true
			end
		end
	end
	return matching
end

local function PlayerLevel()
	local level = UnitLevel and UnitLevel("player")
	return type(level) == "number" and level > 0 and level or nil
end

-- The level of the best goods of a tiered group an NPC sells that you can use: nil when it sells none you can, or
-- when your level or the group's tiers are unknown.
---@param key string
---@param npc integer
---@return integer?
local function Tier(key, npc)
	local level = PlayerLevel()
	if not (level and TIERED[key]) then
		return nil
	end
	if level ~= tierLevel then
		tierLevel, tierCache = level, {}
	end
	local byNpc = tierCache[key]
	if not byNpc then
		byNpc = {}
		tierCache[key] = byNpc
	end
	local tier = byNpc[npc]
	if tier == nil then
		tier = false
		local items = vendorItems[key] and vendorItems[key][npc]
		for _, itemID in ipairs(items or {}) do
			local needs = itemLevels[itemID] or 0
			if needs <= level and (not tier or needs > tier) then
				tier = needs
			end
		end
		byNpc[npc] = tier
	end
	return tier or nil
end

-- The tier to buy here: the best one you can use that a vendor sells within `reach` yards of the nearest seller
-- (TIER_REACH, or the whole continent). A search for an item or an NPC wants what it names, so only the group's own
-- label (or no query) picks a tier.
local function BestTier(key, world, folded, matching, reach)
	if not (TIERED[key] and PlayerLevel()) then
		return nil
	end
	if folded ~= "" and not Contains(Fold((groupByKey[key] or {}).label), folded) then
		return nil
	end
	local function Gap(place)
		if place.world.map == world.map and (not matching or matching[place.id]) then
			return math.sqrt((place.world.x - world.x) ^ 2 + (place.world.y - world.y) ^ 2)
		end
	end
	local nearest = math.huge
	for _, place in ipairs(index[key] or {}) do
		nearest = math.min(nearest, Gap(place) or math.huge)
	end
	local best
	for _, place in ipairs(index[key] or {}) do
		local gap = Gap(place)
		local tier = gap and gap <= nearest + reach and Tier(key, place.id)
		if tier and (not best or tier > best) then
			best = tier
		end
	end
	return best
end

---@param key string
---@param world SPFPoint
---@param limit integer
---@param query? string a raw search query, matched without case or accent
---@param tier? integer the tier to keep, in place of the best one around you
---@return SPFNearbyPlace[]
local function Shortlist(key, world, limit, query, tier)
	local list, gaps = {}, {}
	local folded = Fold(query)
	local matching = Matching(key, world, folded)
	tier = tier or BestTier(key, world, folded, matching, TIER_REACH)
	for _, place in ipairs(index[key] or {}) do
		if
			place.world.map == world.map
			and (not matching or matching[place.id])
			and (not tier or Tier(key, place.id) == tier)
		then
			local gap = (place.world.x - world.x) ^ 2 + (place.world.y - world.y) ^ 2
			local last = #list
			if last < limit or gap < gaps[last] or (gap == gaps[last] and place.id < list[last].id) then
				local at = last + 1
				while at > 1 and (gaps[at - 1] > gap or (gaps[at - 1] == gap and list[at - 1].id > place.id)) do
					at = at - 1
				end
				table.insert(list, at, place)
				table.insert(gaps, at, gap)
				if #list > limit then
					list[#list], gaps[#gaps] = nil, nil
				end
			end
		end
	end
	return list
end

local function Nearest(key, world)
	return Shortlist(key, world, 1)[1]
end

-- Whether this character would go out of its way for a group's goods: food always, drink with a mana bar, and
-- ammunition for the ranged weapon it carries.
local function Wanted(key)
	if key == "food" then
		return true
	elseif key == "drink" then
		return (UnitPowerMax("player", Enum.PowerType.Mana) or 0) > 0
	end
	local slot = GetInventorySlotInfo("RANGEDSLOT")
	local item = slot and GetInventoryItemID("player", slot)
	local subClass = item and select(7, C_Item.GetItemInfoInstant(item)) -- multi-value: the subclass is seventh
	return subClass ~= nil and AMMO[subClass] == key
end

-- The best tier you can use that any vendor on your continent sells, when it beats the one sold around you: the
-- panel and the menu offer it as a trip of its own, for whoever would walk farther for better goods. nil when the
-- best is around you already, while a search names an item or an NPC, or for goods this character has no use for.
---@param key string
---@param world SPFPoint
---@param query? string
---@return integer?
local function Better(key, world, query)
	if not TIERED[key] then
		return nil
	end
	local folded = Fold(query)
	local matching = Matching(key, world, folded)
	local here = BestTier(key, world, folded, matching, TIER_REACH)
	if not (here and Wanted(key)) then
		return nil
	end
	local best = BestTier(key, world, folded, matching, math.huge)
	return best and best > here and best or nil
end

-- The zone a place stands in, as the client names it.
---@param place SPFNearbyPlace
---@return string?
local function Zone(place)
	local info = C_Map.GetMapInfo(place.map)
	return info and info.name ~= "" and info.name or nil
end
-- The trainer groups are the class one and one per profession skill line.
local function Kind(key)
	if key == "class" or key:sub(1, 11) == "profession:" then
		return "trainer"
	end
	if key == "innkeeper" then
		return "innkeeper"
	end
	if key == "flight" then
		return "flightmaster"
	end
end
local function Navigate(key, place)
	if not place then
		return false
	end
	-- The stop carries the NPC id, so the nameplate arrows can point at the NPC the journey walks to.
	local stop = { map = place.map, x = place.x, y = place.y, title = place.name, kind = Kind(key), npc = place.id }
	return ShortestPathForever.API.NavigateRoute("Shortest Path Forever", { stop })
end
-- A service button's response: one that starts a journey closes every menu, one that cannot keeps the menu open.
-- The response is how a button closes its menu: the Forever client's MenuUtil has no CloseAllMenus (#161).
local function Pick(key, place)
	if Navigate(key, place) then
		return MenuResponse.CloseAll
	end
	return MenuResponse.Open
end
-- Food and drink are exact item IDs from the client's own spell effects (Data/Services.lua).
local function Set(list)
	local set = {}
	if type(list) == "table" then
		for _, id in ipairs(list) do
			set[id] = true
		end
	end
	return set
end
local FOOD, DRINK = Set(ns.Food), Set(ns.Drink)
-- The vendor groups an item belongs to, from QuestieDB's item class and subclass and its food and drink IDs.
local function VendorKeys(itemID, class, subClass)
	local keys = {}
	if class == 6 and subClass == 2 then
		keys[#keys + 1] = "arrows"
	elseif class == 6 and subClass == 3 then
		keys[#keys + 1] = "bullets"
	elseif class == 1 then
		keys[#keys + 1] = "bags"
	elseif class == 7 then
		keys[#keys + 1] = "trade"
	elseif class == 5 or (class == 15 and subClass == 1) then
		keys[#keys + 1] = "reagents"
	elseif (class == 2 and subClass ~= 14 and subClass ~= 20) or class == 4 then
		keys[#keys + 1] = "gear"
	end
	if FOOD[itemID] then
		keys[#keys + 1] = "food"
	end
	if DRINK[itemID] then
		keys[#keys + 1] = "drink"
	end
	return keys
end
-- An item one NPC sells, in each group the item puts them in.
local function AddVendorItem(key, npc, itemID)
	local byNpc = vendorItems[key]
	if not byNpc then
		byNpc = {}
		vendorItems[key] = byNpc
	end
	local items = byNpc[npc]
	if not items then
		items = {}
		byNpc[npc] = items
	end
	items[#items + 1] = itemID
end
-- The class trainer group: the companion addon's list, merged with the class trainers in Data/Services.lua for
-- the player's own class.
local function ClassTrainerIDs(tweaks)
	local ids = {}
	if
		tweaks
		and tweaks.API
		and type(tweaks.API.version) == "number"
		and tweaks.API.version >= 2
		and tweaks.API.Trainers
	then
		for _, trainer in ipairs(tweaks.API.Trainers()) do
			ids[trainer.npc] = true
		end
	end
	local classID = UnitClass and select(3, UnitClass("player"))
	if type(classID) == "number" then
		for npc, class in pairs(ns.ClassTrainers or {}) do
			if class == classID then
				ids[npc] = true
			end
		end
	end
	return ids
end
-- A profession group's label is the client's localised name for its skill line, as the Professions book shows it.
local function ProfessionName(skill)
	local name = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName(skill)
	return name ~= "" and name or nil
end
-- Every NPC that has a spawn in one group, once, in a stable order.
local function GroupNPCs(key)
	local seen, npcs = {}, {}
	for _, place in ipairs(index[key] or {}) do
		if not seen[place.id] then
			seen[place.id] = true
			npcs[#npcs + 1] = place.id
		end
	end
	table.sort(npcs)
	return npcs
end
local function BuildGroups()
	for _, byNpc in pairs(vendorItems) do
		for _, items in pairs(byNpc) do
			table.sort(items)
		end
	end
	local list = {}
	local byKey = {}
	local function Add(group)
		list[#list + 1] = group
		byKey[group.key] = group
	end
	for _, group in ipairs(VENDOR_GROUPS) do
		Add({
			section = "vendors",
			key = group.key,
			label = group.label,
			icon = group.icon,
			npcs = GroupNPCs(group.key),
		})
	end
	Add({
		section = "trainers",
		key = "class",
		label = L["Class trainer"],
		icon = "Class",
		npcs = GroupNPCs("class"),
	})
	local skills, seen = {}, {}
	for _, skill in pairs(ns.ProfessionTrainers or {}) do
		if not seen[skill] then
			seen[skill] = true
			skills[#skills + 1] = skill
		end
	end
	table.sort(skills)
	for _, skill in ipairs(skills) do
		local label = ProfessionName(skill)
		if label then
			Add({
				section = "trainers",
				key = "profession:" .. skill,
				label = label,
				icon = "Profession",
				npcs = GroupNPCs("profession:" .. skill),
			})
		end
	end
	for _, service in ipairs(SERVICES) do
		Add({
			section = "services",
			key = service.key,
			label = service.label,
			icon = service.icon,
			npcs = GroupNPCs(service.key),
		})
	end
	groupByKey = byKey
	return list
end
-- The NPC flag names whose rows the list needs: the services it groups on, and trainer for a class a companion addon
-- names as taught by an NPC this addon's own trainer list does not hold.
local KEEP_FLAGS = {}
for _, service in ipairs(SERVICES) do
	KEEP_FLAGS[#KEEP_FLAGS + 1] = service.flag
end
KEEP_FLAGS[#KEEP_FLAGS + 1] = "TRAINER"

-- The index, from QuestieDB's rows: the vendor groups, the level tiers, and every service NPC's spawns, a slice a
-- frame. The rows are read in UI/NearbyQuestie.lua, which checks what QuestieDB answers.
---@param read SPFNearbyQuestieRead
local function Assemble(read)
	itemNames, itemLevels, index, vendorItems, groups = {}, {}, {}, {}, {}
	tierLevel, tierCache = nil, {}
	state = "building"
	local co = coroutine.create(function()
		-- Every item QuestieDB says a vendor sells, with what this list groups it by.
		for itemID, item in pairs(read.items) do
			itemNames[itemID] = item.name
			local keys = VendorKeys(itemID, item.class, item.subClass)
			for _, npc in ipairs(item.vendors) do
				for _, key in ipairs(keys) do
					AddVendorItem(key, npc, itemID)
				end
			end
			for _, key in ipairs(keys) do
				if TIERED[key] then
					itemLevels[itemID] = item.level or 0
				end
			end
			coroutine.yield()
		end
		local classIds = ClassTrainerIDs(rawget(_G, "TweaksForever"))
		-- Every NPC the read kept, in each group its flags, its goods and its training put it in.
		for id, row in pairs(read.npcs) do
			local keys = {}
			for _, service in ipairs(SERVICES) do
				local flag = read.flags[service.flag]
				if type(flag) == "number" and bit.band(row.flags, flag) ~= 0 then
					keys[#keys + 1] = service.key
				end
			end
			for _, group in ipairs(VENDOR_GROUPS) do
				if vendorItems[group.key] and vendorItems[group.key][id] then
					keys[#keys + 1] = group.key
				end
			end
			if classIds[id] then
				keys[#keys + 1] = "class"
			end
			local skill = ns.ProfessionTrainers and ns.ProfessionTrainers[id]
			if skill then
				keys[#keys + 1] = "profession:" .. skill
			end
			if #keys > 0 then
				for _, spawn in ipairs(row.spawns) do
					local map, x, y = spawn[1], spawn[2], spawn[3]
					local world = ns.WorldPoint(map, x, y)
					if world then
						local place =
							{ id = id, name = row.name, title = row.title, map = map, x = x, y = y, world = world }
						for _, key in ipairs(keys) do
							index[key] = index[key] or {}
							index[key][#index[key] + 1] = place
						end
					end
					coroutine.yield()
				end
			end
			coroutine.yield()
		end
		groups = BuildGroups()
	end)
	local function Pump()
		if InCombatLockdown() or ns.Path.Busy() then
			C_Timer.After(0.1, Pump)
			return
		end
		local finish = debugprofilestop() + 1
		repeat
			local ok, err = coroutine.resume(co)
			if not ok then
				state = "failed"
				geterrorhandler()(err)
				Notify()
				return
			end
			if coroutine.status(co) == "dead" then
				state = "ready"
				Notify()
				return
			end
		until debugprofilestop() >= finish
		C_Timer.After(0, Pump)
	end
	C_Timer.After(0, Pump)
end

-- QuestieDB's answer: the index is assembled from the read, or the list says why there is none.
---@param read SPFNearbyQuestieRead?
---@param outcome string
local function Read(read, outcome)
	if read and ns.core.SafeCall("nearby services index", Assemble, read) then
		return
	end
	state = (read and "failed") or outcome
	Notify()
end

-- Starts the read, once: a saved read is assembled as it is, and a fresh one waits for Questie's own start.
local function Build()
	if state ~= "idle" then
		return
	end
	state = "building"
	ns.NearbyQuestie.Read(KEEP_FLAGS, Read)
end

-- The player's own map coordinates, which the public estimate takes.
local function PlayerUi()
	local map = C_Map.GetBestMapForUnit("player")
	local point = map and C_Map.GetPlayerMapPosition(map, "player")
	if map and point then
		local x, y = point:GetXY() -- multi-value: x and y
		return map, x, y
	end
end
local function PlayerWorld()
	local map, x, y = PlayerUi()
	if map then
		return ns.WorldPoint(map, x, y)
	end
end
-- One row's shortlist ranked by the planner's own journey cost, one Estimate per Step. The panel calls one Step a
-- frame; the tracking menu and /spfnear drain it at once on the click. The best starts as the straight-line nearest,
-- so a row always has an NPC, and stays so when no estimate can be made.
---@class SPFNearbyRank
---@field key? string
---@field candidates SPFNearbyPlace[]
---@field estimate SPFEstimate
---@field fromMap integer
---@field fromX number
---@field fromY number
---@field at integer
---@field best? SPFNearbyPlace
---@field seconds? number
local Rank = {}
Rank.__index = Rank

function Rank:Step()
	local place = self.candidates[self.at]
	if not place then
		return self.best or self.candidates[1], self.seconds, false
	end
	self.at = self.at + 1
	local seconds = self.estimate(self.fromMap, self.fromX, self.fromY, place.map, place.x, place.y)
	if seconds and (not self.seconds or seconds < self.seconds) then
		self.best, self.seconds = place, seconds
	end
	return self.best or self.candidates[1], self.seconds, self.at <= #self.candidates
end

local function NewRank(candidates, estimate, fromMap, fromX, fromY)
	return setmetatable({
		candidates = candidates,
		estimate = estimate,
		fromMap = fromMap,
		fromX = fromX,
		fromY = fromY,
		at = 1,
	}, Rank)
end

-- The chosen place: the closest few by straight line, then the cheapest of those by the planner's own journey cost.
-- A boat or flight can beat a shorter walk across the hills. Planned here, on the click, so opening or refreshing a
-- menu never starts a plan, and only the shortlist is planned.
local function TravelNearest(key, world, query, tier)
	local candidates = Shortlist(key, world, SHORTLIST, query, tier)
	local best = candidates[1]
	local api = ShortestPathForever and ShortestPathForever.API
	local map, x, y = PlayerUi()
	if #candidates < 2 or not (api and api.Estimate and map and x and y) then
		return best
	end
	local rank = NewRank(candidates, api.Estimate, map, x, y)
	local more = true
	while more do
		_, _, more = rank:Step()
	end
	return rank.best or best
end

-- The tooltip an upgrade's row and menu button share: the goods, why they are offered, and who sells them where.
---@param tooltip GameTooltip
---@param itemID integer
---@param place SPFNearbyPlace
local function BetterTooltip(tooltip, itemID, place)
	GameTooltip_SetTitle(tooltip, itemNames[itemID])
	GameTooltip_AddNormalLine(tooltip, L["Better for your level, farther away"])
	local zone = Zone(place)
	GameTooltip_AddColoredLine(
		tooltip,
		zone and L["%s, %s"]:format(place.name, zone) or place.name,
		HIGHLIGHT_FONT_COLOR
	)
end

-- A group's nearest from here, or a row that says it is not on this map. Under a tiered group, the better goods
-- farther away (Better), marked with the client's green upgrade arrow.
local function AddGroups(root, world)
	root:SetScrollMode(MENU_ROW * MENU_ROWS)
	local section
	for _, group in ipairs(groups) do
		if group.section ~= section then
			section = group.section
			root:CreateTitle(SECTION_LABELS[section])
		end
		local place = world and Nearest(group.key, world)
		local label = place and group.label or L["%s — unavailable here"]:format(group.label)
		local entry = root:CreateButton(label, function()
			return Pick(group.key, TravelNearest(group.key, world))
		end)
		entry:SetEnabled(place ~= nil)
		local tier = place and Better(group.key, world)
		local far = tier and Shortlist(group.key, world, 1, nil, tier)[1]
		local goods = far and Goods(group.key, far)
		if goods then
			---@cast far -?
			local arrow = ns.Art and ns.Art.Markup(UPGRADE_ATLAS, UPGRADE_MARKUP)
			local better = root:CreateButton((arrow and arrow .. " " or "") .. itemNames[goods[1]], function()
				return Pick(group.key, TravelNearest(group.key, world, nil, tier))
			end)
			better:SetTooltip(function(tooltip)
				BetterTooltip(tooltip, goods[1], far)
			end)
		end
	end
end

-- The panel itself lives in UI/ServicesPanel.lua; this is the way in both the tracking menu and /spfnear take.
local function OpenServices()
	Build()
	-- Under the gamepad interface a menu or panel this addon opens makes the client's gamepad focus tainted, so the
	-- addon opens neither (#158) and leaves the game's own menus alone as well (UI/MenuModifier.lua, #645): there is
	-- no way in to the services with a controller, and the player is told what they would need.
	if ns.GamepadUI() then
		ns.Print(L["This menu needs mouse and keyboard."])
		return
	end
	if ns.OpenWorldMap() then
		ForeverCore.QuestLogTabs.Select("services")
	end
end

-- The world map's tracking menu and the minimap's (Blizzard_Minimap/Mainline/Minimap.lua:645, Gethe/wow-ui-source
-- branch forever, tags it MENU_MINIMAP_TRACKING) both carry this submenu.
local function AddTrackingEntry(_, root)
	Build()
	local world = PlayerWorld()
	local submenu = root:CreateButton(L["Nearby services"])
	-- The way into the quest log's Nearby services tab, above the groups themselves.
	submenu:CreateButton(L["Open Nearby services"], function()
		OpenServices()
		return MenuResponse.CloseAll
	end)
	if not world then
		submenu:CreateTitle(L["Your position is unavailable"])
		return
	end
	if state ~= "ready" then
		submenu:CreateTitle(STATUS[state])
		return
	end
	AddGroups(submenu, world)
end

---@class SPFNearbyGroup
---@field section "vendors"|"trainers"|"services"
---@field key string
---@field label string
---@field icon number|string
---@field npcs number[]
---@class SPFNearbyRow
---@field id string the group's key, or "better:" and the key for its upgrade row
---@field group SPFNearbyGroup
---@field npc SPFNearbyPlace the nearest matching NPC by straight line
---@field tier? integer on an upgrade row, the better tier it goes to (Better)
---@class SPFNearbySection
---@field section "vendors"|"trainers"|"services"
---@field label string
---@field count integer
---@field collapsed boolean
---@field rows SPFNearbyRow[]
---@alias SPFEstimate fun(...: number): number?
---@alias SPFRank fun(places: SPFNearbyPlace[], estimate: SPFEstimate, map: number, x: number, y: number): SPFNearbyRank
---@class SPFNearbyServices
---@field Nearest fun(key: string, world: SPFPoint): SPFNearbyPlace?
---@field Index fun(): table<string, SPFNearbyPlace[]>
---@field Groups fun(): SPFNearbyGroup[]
---@field Items fun(key: string, npc: number): integer[]?
---@field State fun(): string
---@field OnReady fun(fn: fun())
---@field Sections fun(world: SPFPoint, query?: string, collapsed?: table<string, boolean>): SPFNearbySection[]
---@field Shortlist fun(key: string, world: SPFPoint, limit: integer, query?: string, tier?: integer): SPFNearbyPlace[]
---@field Rank SPFRank
---@field Detail fun(key: string, place: SPFNearbyPlace, query?: string): string
---@field Goods fun(key: string, place: SPFNearbyPlace, query?: string): integer[]?
---@field ItemName fun(itemID: integer): string?
---@field Zone fun(place: SPFNearbyPlace): string?
---@field BetterTooltip fun(tooltip: GameTooltip, itemID: integer, place: SPFNearbyPlace)
---@field Navigate fun(key: string, place: SPFNearbyPlace?): boolean
---@field PlayerUi fun(): integer?, number?, number?
---@field PlayerWorld fun(): SPFPoint?
---@field Open fun()
---@class SPFNearbyPlace
---@field id integer
---@field name string
---@field title? string
---@field map integer
---@field x number
---@field y number
---@field world SPFPoint

function Items(key, npcID)
	local byNpc = vendorItems[key]
	local items = byNpc and byNpc[npcID]
	if not items then
		return nil
	end
	local copy = {}
	for at, id in ipairs(items) do
		copy[at] = id
	end
	return copy
end

-- The panel's list: sections in their fixed order, each a header and the groups here that the query keeps. A group
-- with no NPC on the player's continent never reaches a section, and a section with no rows is left out.
local function Sections(world, query, collapsed)
	local folded = Fold(query)
	local list = {}
	for _, section in ipairs({ "vendors", "trainers", "services" }) do
		local rows, count = {}, 0
		for _, group in ipairs(groups) do
			if group.section == section then
				local place = Shortlist(group.key, world, 1, folded)[1]
				if place then
					count = count + 1
					rows[#rows + 1] = { id = group.key, group = group, npc = place }
					local tier = Better(group.key, world, folded)
					local far = tier and Shortlist(group.key, world, 1, folded, tier)[1]
					if far then
						rows[#rows + 1] = { id = "better:" .. group.key, group = group, npc = far, tier = tier }
					end
				end
			end
		end
		if #rows > 0 then
			local isCollapsed = type(collapsed) == "table" and collapsed[section] == true
			list[#list + 1] = {
				section = section,
				label = SECTION_LABELS[section],
				count = count,
				collapsed = isCollapsed,
				rows = isCollapsed and {} or rows,
			}
		end
	end
	return list
end

-- The goods a row names, sorted by name: while searching, the NPC's items that matched; otherwise, in a tiered group,
-- the NPC's goods of the best tier you can use. nil for none.
---@param key string
---@param place SPFNearbyPlace
---@param query? string
---@return integer[]?
function Goods(key, place, query)
	local folded = Fold(query)
	local tier = folded == "" and Tier(key, place.id)
	if folded == "" and not tier then
		return nil
	end
	local goods = {}
	for _, itemID in ipairs(Items(key, place.id) or {}) do
		local name = itemNames[itemID]
		if name and (tier and (itemLevels[itemID] or 0) == tier or not tier and Contains(Fold(name), folded)) then
			goods[#goods + 1] = itemID
		end
	end
	table.sort(goods, function(a, b)
		return itemNames[a] < itemNames[b]
	end)
	return #goods > 0 and goods or nil
end

-- A row's detail line: the NPC and its title, or the NPC and the goods the row names (Goods) in place of the title.
local function Detail(key, place, query)
	local goods = Goods(key, place, query)
	if goods then
		local names = {}
		for at, itemID in ipairs(goods) do
			names[at] = itemNames[itemID]
		end
		return L["%s · %s"]:format(place.name, table.concat(names, ", "))
	end
	if Fold(query) == "" and place.title then
		return L["%s · %s"]:format(place.name, place.title)
	end
	return place.name
end

ns.NearbyServices = {
	Nearest = Nearest,
	Index = function()
		return index
	end,
	Groups = function()
		return groups
	end,
	Items = Items,
	State = function()
		return state
	end,
	OnReady = WhenReady,
	Sections = Sections,
	Shortlist = Shortlist,
	Rank = NewRank,
	Detail = Detail,
	Goods = Goods,
	ItemName = function(itemID)
		return itemNames[itemID]
	end,
	Zone = Zone,
	BetterTooltip = BetterTooltip,
	Navigate = Navigate,
	PlayerUi = PlayerUi,
	PlayerWorld = PlayerWorld,
	Open = OpenServices,
}
ns.Init(function()
	-- Questie starts after every addon has loaded and applies its corrections then, so the first read begins at
	-- PLAYER_LOGIN: a saved read is assembled there at once, and a fresh one waits for Questie's ready callback.
	EventUtil.ContinueAfterAllEvents(Build, "PLAYER_LOGIN")
	ns.ModifyMenu("MENU_WORLD_MAP_TRACKING", "nearby", AddTrackingEntry)
	ns.ModifyMenu("MENU_MINIMAP_TRACKING", "nearby", AddTrackingEntry)
	SLASH_SPFNEAR1 = "/spfnear"
	SlashCmdList.SPFNEAR = function(message)
		local key = string.lower((message or ""):match("^%s*(.-)%s*$"))
		local world = PlayerWorld()
		if key ~= "" and state == "ready" and world then
			for _, group in ipairs(groups) do
				if group.key == key then
					Navigate(group.key, TravelNearest(group.key, world))
					return
				end
			end
		end
		OpenServices()
	end
end)

---@type string, SPFNamespace
local _, ns = ...
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
-- Callers waiting for the index, so an open panel fills as soon as the read finishes.
local waiting = {}

---@param fn fun()
local function WhenReady(fn)
	if state == "ready" then
		fn()
	else
		waiting[#waiting + 1] = fn
	end
end
-- Case-folded matching for the panel's search box: plain substring, never a keyword list.
local Fold = ns.Text and ns.Text.Fold or function(text)
	return tostring(text or ""):lower()
end

local function Contains(folded, query)
	return query == "" or folded:find(query, 1, true) ~= nil
end
-- What the menu says in place of the services: QuestieDB is still being read, is not installed, or could not be read.
local STATUS = {
	building = L["Loading QuestieDB…"],
	missing = L["Nearby services need the QuestieDB addon."],
	failed = L["Nearby services could not read QuestieDB."],
}
-- One of QuestieDB's zone tables, which it keeps as Lua source; nil when it does not read as a table.
---@param source any
---@return table?
local function Table(source)
	local chunk = type(source) == "string" and loadstring(source)
	if not chunk then
		return nil
	end
	setfenv(chunk, {})
	local ok, value = pcall(chunk)
	return ok and type(value) == "table" and value or nil
end
-- A service's closest few by straight line: enough to include the one a boat or flight reaches sooner than the
-- closest walk, without planning every spawn on the continent.
local SHORTLIST = 5
-- A group list can run past the screen edge (a capital city sells dozens), and a menu never clamps to the screen,
-- so it scrolls past this many rows the way Blizzard's own long menus do (Blizzard_Menu SetScrollMode).
local MENU_ROW, MENU_ROWS = 20, 20

-- What put an NPC in a group (defined below, after the index is built).
local Items

-- Every NPC of a group on the player's continent that a folded query matches, or all of them with an empty query.
-- A group label, an NPC's name or title, or the name of an item that puts the NPC in the group each count.
local function Matching(key, world, query)
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

---@param key string
---@param world SPFPoint
---@param limit integer
---@param query? string a raw search query, matched without case or accent
---@return SPFNearbyPlace[]
local function Shortlist(key, world, limit, query)
	local list, gaps = {}, {}
	local folded = Fold(query)
	local matching = folded ~= "" and Matching(key, world, folded) or nil
	for _, place in ipairs(index[key] or {}) do
		if place.world.map == world.map and (not matching or matching[place.id]) then
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
local function Build()
	if state == "building" or state == "ready" then
		return
	end
	local lib = rawget(_G, "LibQuestieDB")
	if not lib then
		state = "missing"
		return
	end
	local zones = lib.RequireContract and lib.RequireContract(2) and lib.Support.Get("ZoneDB")
	local expansion = lib.Enum and lib.Enum.byExpansion and lib.Enum.byExpansion.Classic
	local constants = expansion and expansion.npcFlags
	-- Without the two zone tables no spawn has a map, which would read as no service anywhere.
	local private = zones and zones.private
	local area = private and Table(private.areaIdToUiMapId)
	local parents = private and Table(private.subZoneToParentZone)
	if not (area and parents and constants and lib.Npc) then
		state = "failed"
		return
	end
	index, vendorItems, groups = {}, {}, {}
	state = "building"
	local co = coroutine.create(function()
		-- QuestieDB's own corrections to those two, which a flavour may leave out.
		local override = Table(private.areaIdToUiMapIdOverride) or {}
		local parentOverride = Table(private.subZoneToParentZoneOverride) or {}
		local faction = UnitFactionGroup("player") == "Alliance" and "A" or "H"
		local classIds = ClassTrainerIDs(rawget(_G, "TweaksForever"))
		-- Every item says who sells it and what it is; that is the whole vendor grouping.
		local item = lib.Item
		if item and item.GetAllIds and item.GetAll then
			local fields = { "vendors", "class", "subClass", "name" }
			for _, itemID in ipairs(item.GetAllIds()) do
				local values = item.GetAll(itemID, fields)
				if values then
					local vendors, class, subClass, name = unpack(values, 1, values.n)
					if type(name) == "string" then
						itemNames[itemID] = name
					end
					if type(class) == "number" and type(subClass) == "number" and type(vendors) == "table" then
						local keys = VendorKeys(itemID, class, subClass)
						for _, npc in ipairs(vendors) do
							for _, key in ipairs(keys) do
								AddVendorItem(key, npc, itemID)
							end
						end
					end
				end
				coroutine.yield()
			end
		end
		local fields = { "name", "spawns", "friendlyToFaction", "npcFlags", "subName" }
		for _, id in ipairs(lib.Npc.GetAllIds()) do
			local values = lib.Npc.GetAll(id, fields)
			if values then
				local name, spawns, friendly, flags, title = unpack(values, 1, values.n)
				if type(name) == "string" and (friendly == "AH" or friendly == faction) and type(flags) == "number" then
					local keys = {}
					for _, service in ipairs(SERVICES) do
						if bit.band(flags, constants[service.flag]) ~= 0 then
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
						for zone, points in pairs(spawns or {}) do
							local parent = parentOverride[zone] or parents[zone]
							local map = override[zone] or area[zone] or (parent and (override[parent] or area[parent]))
							for _, spot in ipairs(points) do
								local x, y = spot[1], spot[2]
								if
									map
									and type(x) == "number"
									and type(y) == "number"
									and x >= 0
									and x <= 100
									and y >= 0
									and y <= 100
								then
									local world = ns.WorldPoint(map, x / 100, y / 100)
									if world then
										local place = {
											id = id,
											name = name,
											title = type(title) == "string" and title ~= "" and title or nil,
											map = map,
											x = x / 100,
											y = y / 100,
											world = world,
										}
										for _, key in ipairs(keys) do
											index[key] = index[key] or {}
											index[key][#index[key] + 1] = place
										end
									end
								end
								coroutine.yield()
							end
						end
					end
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
				return
			end
			if coroutine.status(co) == "dead" then
				state = "ready"
				for _, fn in ipairs(waiting) do
					fn()
				end
				waiting = {}
				return
			end
		until debugprofilestop() >= finish
		C_Timer.After(0, Pump)
	end
	C_Timer.After(0, Pump)
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
local function TravelNearest(key, world, query)
	local candidates = Shortlist(key, world, SHORTLIST, query)
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

-- A group's nearest from here, or a row that says it is not on this map.
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
	end
end

-- The panel itself lives in UI/ServicesPanel.lua; this is the way in both the tracking menu and /spfnear take.
local function OpenServices()
	Build()
	-- Under the gamepad interface neither the map nor a menu the addon opens gets past the client (#158), so the
	-- map's own tracking menu, which the game opens, lists the services and the tab stays where the player finds it.
	if ns.GamepadUI() then
		ns.Print(L["Open the world map and choose Nearby services in its tracking menu."])
		return
	end
	if ns.OpenWorldMap() and ns.QuestLogTabs then
		ns.QuestLogTabs.Select("services")
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
---@field group SPFNearbyGroup
---@field npc SPFNearbyPlace the nearest matching NPC by straight line
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
---@field Shortlist fun(key: string, world: SPFPoint, limit: integer, query?: string): SPFNearbyPlace[]
---@field Rank SPFRank
---@field Detail fun(key: string, place: SPFNearbyPlace, query?: string): string
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
		local rows = {}
		for _, group in ipairs(groups) do
			if group.section == section then
				local place = Shortlist(group.key, world, 1, folded)[1]
				if place then
					rows[#rows + 1] = { group = group, npc = place }
				end
			end
		end
		if #rows > 0 then
			local isCollapsed = type(collapsed) == "table" and collapsed[section] == true
			list[#list + 1] = {
				section = section,
				label = SECTION_LABELS[section],
				count = #rows,
				collapsed = isCollapsed,
				rows = isCollapsed and {} or rows,
			}
		end
	end
	return list
end

-- A row's detail line: the NPC and its title, or while searching, the NPC and only the items that matched.
local function Detail(key, place, query)
	local folded = Fold(query)
	if folded ~= "" then
		local names = {}
		for _, itemID in ipairs(Items(key, place.id) or {}) do
			local name = itemNames[itemID]
			if name and Contains(Fold(name), folded) then
				names[#names + 1] = name
			end
		end
		if #names > 0 then
			table.sort(names)
			return L["%s · %s"]:format(place.name, table.concat(names, ", "))
		end
		return place.name
	end
	if place.title then
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
	Navigate = Navigate,
	PlayerUi = PlayerUi,
	PlayerWorld = PlayerWorld,
	Open = OpenServices,
}
ns.Init(function()
	Build()
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

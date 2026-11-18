-- UI/TownServices.lua on the world map: one client service icon per pin, a service's own icon when every member shows
-- that service, the addon's own market stall when a group stands for different services, the tooltip that names them
-- and the click that plans a journey, the four levels of detail, each service's own Map Filter checkbox with
-- repairers hidden by default, the battlemaster's own switch (#833), and the maps the pins belong on.
local dir = arg[0]:match("^(.*)/") or "tests"

local probe = "tools/.cache/blizzard-ui/Interface/AddOns/Blizzard_SharedXML/Spinner.lua"
do
	local handle = io.open(probe)
	if handle then
		handle:close()
	else
		local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
		assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture for tests/town_services_spec.lua")
	end
end

local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

assert(loadstring(source .. [==[
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end

-- A ready Nearby services index: two Orgrimmar services, a food seller and a trade supplier outside the city.
-- The capital comes from Data/Zones.lua's own Orgrimmar box,
-- not from a list here. The groups come in UI/Nearby.lua's own order, the vendors before the services, and each
-- carries the client's tracking atlas the map wears, the way UI/NearbyGroups.lua gives them.
local function group(section, key, label, tracking)
	return { section = section, key = key, label = label, icon = tracking, tracking = tracking, npcs = {} }
end
local groups = {
	group("vendors", "food", "Food", "Food"),
	group("vendors", "trade", "Trade supplies", "Reagents"),
	group("services", "bank", "Bank", "Banker"),
	group("services", "innkeeper", "Innkeeper", "Innkeeper"),
	group("services", "repair", "Repair", "Repair"),
}
local function place(id, name, x, y)
	return {
		id = id,
		name = name,
		map = 14,
		x = 0.5,
		y = 0.5,
		world = { map = 1, x = x, y = y },
	}
end
local index = {
	bank = { place(1, "Banker One", 1800, -4900) },
	innkeeper = { place(2, "Innkeeper Two", 2200, -4300) },
	-- Food Three also repairs, Repair Five repairs alone, and Repair Six shares Trade Four's spot, so hiding and
	-- showing repair covers an NPC that keeps a shown service, one that loses its only pin, and a cluster's choice.
	repair = {
		place(3, "Food Three", 0, 0),
		place(5, "Repair Five", 4000, 0),
		place(6, "Repair Six", 2000, 0),
	},
	food = { place(3, "Food Three", 0, 0) },
	trade = { place(4, "Trade Four", 2000, 0) },
}
local navigated
local catalogueState, catalogueReads = "idle", 0
-- The goods each NPC sells in each group, which the "Only my professions" rule judges a vendor by.
local vendorItems = {}
ns.NearbyServices = {
	Request = function()
		if catalogueState == "idle" then
			catalogueReads = catalogueReads + 1
			catalogueState = "building"
		end
	end,
	State = function()
		return catalogueState
	end,
	Index = function()
		return index
	end,
	Groups = function()
		return groups
	end,
	Items = function(key, npc)
		local byNpc = vendorItems[key]
		return byNpc and byNpc[npc] or nil
	end,
	OnReady = function() end,
	Navigate = function(key, spot)
		navigated = { key = key, spot = spot }
		return true
	end,
}
-- The world map's own map here is a zone; a check below turns it into a continent.
local mapTypes = { [1414] = Enum.UIMapType.Zone }
local info = C_Map.GetMapInfo
C_Map.GetMapInfo = function(id)
	local answer = info(id)
	answer.mapType = mapTypes[id] or answer.mapType
	return answer
end
ns.db.journey = true
ns.db.townServices = "all"
-- Repair and the vendors start hidden; the other services start shown, including for a saved table that predates the
-- switches (#978).
check(ns.db.townServiceRepair == false, "a repairer is hidden by default")
check(ns.db.townServiceFood == false and ns.db.townServiceBags == false, "and so are the vendors")
check(ns.db.townServiceBank == true and ns.db.townServiceClass == true, "the other services start shown")
-- The checks below are a player who shows food and trade supplies.
ns.db.townServiceFood, ns.db.townServiceBags = true, true
check(ns.Defaults.townServiceRepair == false, "the shipped defaults hide repair")
local saved = { townServices = "all" }
for key, value in pairs(ns.Defaults) do
	if saved[key] == nil then
		saved[key] = value
	end
end
check(saved.townServiceRepair == false, "an existing player's saved table gets repair hidden")
check(saved.townServiceBank == true and saved.townServiceProfessions == true, "and every other service switch")
saved.townServiceBank = false
check(ns.Defaults.townServiceBank == true, "a saved switch does not change the shipped defaults")
mapID, zoom = 1414, 0
setMapShown(false)
ns.RefreshTownServices()
check(catalogueReads == 0, "a closed map does not demand the catalogue")
ns.db.townServices = "off"
setMapShown(true)
ns.RefreshTownServices()
check(catalogueReads == 0, "disabled town services do not demand the catalogue")
ns.db.townServices = "all"
ns.RefreshTownServices()
check(catalogueReads == 1 and catalogueState == "building", "map-only demand starts before the ready gate")
ns.RefreshTownServices()
check(catalogueReads == 1, "a loading map consumer keeps the first request")
catalogueState = "ready"
ns.RefreshTownServices()
check(catalogueReads == 1, "a ready map consumer keeps the completed request")

local function pins()
	return ns.Canvas.Pools(WorldMapFrame).ShortestPathForeverServicePinTemplate.active
end
local function find(id)
	for _, pin in ipairs(pins()) do
		for _, point in ipairs(pin.cluster.services) do
			if point.entry.id == id then
				return pin
			end
		end
	end
end
local function count()
	return #pins()
end
-- The normal tooltip lines a pin writes, without running the client's own tooltip.
local function linesOf(pin)
	local lines = {}
	local old = GameTooltip_AddNormalLine
	GameTooltip_AddNormalLine = function(_, text)
		lines[#lines + 1] = text
	end
	pin.scripts.OnEnter(pin)
	GameTooltip_AddNormalLine = old
	return lines
end

-- Every service in one zone view: the two Orgrimmar services share one pin, the outlying sellers keep their own,.
check(count() == 3, "three pins on the zone: the city's services and the two outlying sellers")
local bank, inn = find(1), find(2)
check(bank == inn, "the two Orgrimmar services share one pin at this zoom")
check(#bank.cluster.services == 2, "the group pin carries both services")

-- No pin wears a town or city mark: a pin that stands for different services wears the addon's own market stall, and
-- a pin for one service its own client icon.
check(bank.Texture.atlas ~= "poi-majorcity" and bank.Texture.atlas ~= "poi-town", "a mixed pin wears no town mark")
check(
	bank.Texture.texture == "Interface\\AddOns\\ShortestPathForever\\media\\TownGroup" and bank.Texture.atlas == nil,
	"a mixed pin wears the addon's market stall, not one service's atlas"
)
check(
	bank.HighlightTexture.texture == bank.Texture.texture and bank.HighlightTexture.atlas == nil,
	"the mixed pin's highlight wears the stall too"
)
check(bank.Texture.width == 20 and bank.Texture.height == 20, "the stall fills the same 20 unit box as the atlases")
local groupCluster = bank.cluster
check(find(3).Texture.atlas == "Food", "an outlying food seller keeps the client's food icon")
check(find(3).Texture.texture == nil, "a pin for one NPC wears no file art")

-- Its tooltip names the town, lists every shown service of its NPCs once in the list's own order, and offers the
-- click that plans a journey.
local lines, hints = {}, {}
local oldLine, oldHint = GameTooltip_AddNormalLine, GameTooltip_AddInstructionLine
GameTooltip_AddNormalLine = function(_, text)
	lines[#lines + 1] = text
end
GameTooltip_AddInstructionLine = function(_, text)
	hints[#hints + 1] = text
end
bank.scripts.OnEnter(bank)
GameTooltip_AddNormalLine, GameTooltip_AddInstructionLine = oldLine, oldHint
check(GameTooltipTextLeft1.text == "Map1454", "the group pin is titled with the capital's own map name")
check(
	#lines == 2 and lines[1] == "Bank" and lines[2] == "Innkeeper",
	"the tooltip lists the group's services once each"
)
check(#hints == 1 and hints[1] == "Click to plan a journey here.", "the tooltip offers the journey click")
check(GameTooltip:IsOwned(bank), "hovering a group pin shows its tooltip")

-- A plain left click plans a journey through the Nearby services seam to the group's most useful service.
ns.Canvas.Click(bank, "RightButton")
check(navigated == nil, "the right button still zooms out instead of planning")
ns.Canvas.Click(bank, "LeftButton")
check(navigated and navigated.key == "bank", "a click plans to the group's most useful service")
check(navigated and navigated.spot.id == 1, "the journey goes to that service's NPC")
navigated = nil
ns.Canvas.Click(find(3), "LeftButton")
check(navigated and navigated.key == "food" and navigated.spot.id == 3, "a single service pin plans to its NPC")
navigated = nil

-- Zoomed in, the services separate into a pin each, wearing their own client art.
zoom = 1
canvasScaled()
bank, inn = find(1), find(2)
check(bank ~= inn, "the two Orgrimmar services separate when zoomed in")
check(bank.Texture.atlas == "Banker" and inn.Texture.atlas == "Innkeeper", "each service wears its own tracking atlas")
check(bank.Texture.texture == nil and inn.Texture.texture == nil, "and no file art is left over from the group")
check(bank:IsShown() and inn:IsShown(), "both service pins stay visible")

-- A pin the pool reuses paints cleanly both ways: handed a group it puts the stall over its own icon, and handed its
-- own NPC back it returns to the client atlas, at the same 20 unit box.
local foodPin = find(3)
local ownCluster = foodPin.cluster
foodPin:OnAcquired(groupCluster)
check(
	foodPin.Texture.texture == "Interface\\AddOns\\ShortestPathForever\\media\\TownGroup"
		and foodPin.Texture.atlas == nil,
	"a reused pin paints the stall when it is handed a group"
)
check(
	foodPin.HighlightTexture.texture == foodPin.Texture.texture,
	"and its highlight paints the same stall"
)
check(foodPin.Texture.width == 20 and foodPin.Texture.height == 20, "the stall is square in the pin's 20 unit box")
foodPin:OnAcquired(ownCluster)
check(
	foodPin.Texture.atlas == "Food" and foodPin.Texture.texture == nil,
	"the same pin returns to the atlas when it is handed one NPC again"
)
check(
	foodPin.Texture.height == 20 and foodPin.Texture.width <= 20,
	"and the atlas fits the box at its own shape again"
)

-- The four levels of detail: capitals only, capitals and important services, all towns, and off.
zoom = 0
canvasScaled()
ns.db.townServices = "capitals"
ns.RefreshTownServices()
check(count() == 1 and find(1) == find(2), "capitals only keeps the capital's services")
ns.db.townServices = "important"
ns.RefreshTownServices()
check(count() == 2 and find(1) == find(2) and find(4) and not find(3), "important adds the trade supplier, not food")
ns.db.townServices = "all"
ns.RefreshTownServices()
check(count() == 3 and find(3) and find(4), "all towns adds every service")
ns.db.townServices = "off"
ns.RefreshTownServices()
check(count() == 0, "off draws no town services")

-- No pins above a zone map: a continent only marks where the town is.
ns.db.townServices = "all"
mapTypes[1414] = Enum.UIMapType.Continent
ns.RefreshTownServices()
check(count() == 0, "a continent map draws no service pins")
mapTypes[1414] = Enum.UIMapType.Zone
ns.RefreshTownServices()
check(count() == 3, "the zone map draws them again")
-- The map's own type decides, never its zoom: zone and city maps draw pins, the maps above them none.
for _, case in ipairs({
	{ Enum.UIMapType.Cosmic, false, "the cosmic map" },
	{ Enum.UIMapType.World, false, "the world map" },
	{ Enum.UIMapType.Continent, false, "a continent" },
	{ Enum.UIMapType.Zone, true, "a zone" },
	{ Enum.UIMapType.Micro, true, "a city" },
}) do
	for _, level in ipairs({ 0, 1 }) do
		zoom = level
		mapTypes[1414] = case[1]
		canvasScaled()
		ns.RefreshTownServices()
		check((count() > 0) == case[2], case[3] .. (case[2] and " draws" or " hides") .. " service pins at zoom " .. level)
	end
end
zoom = 0
mapTypes[1414] = Enum.UIMapType.Zone
-- Off is the shipped level: a fresh profile draws no service pins on any map.
check(ns.Defaults.townServices == "off", "town services ship off")
ns.db.townServices = ns.Defaults.townServices
ns.RefreshTownServices()
check(count() == 0, "the shipped level draws nothing")
ns.db.townServices = "all"
ns.RefreshTownServices()

-- One map atlas per kind of service the map filter lists, and never an icon file: a pin looks like the map's own.
local kinds = {}
local function wear(kind, tracking)
	check(type(tracking) == "string" and not tracking:find("\\", 1, true), kind .. " wears an atlas name")
	check(not tracking:lower():find("interface", 1, true), kind .. " wears no Interface\\Icons texture")
	kinds[kind] = tracking
end
for _, group in ipairs(ns.NearbyGroups.vendors) do
	wear(ns.TownServiceKind and ns.TownServiceKind(group) or group.key, group.tracking)
end
for _, group in ipairs(ns.NearbyGroups.services) do
	wear(group.key, group.tracking)
end
for key, tracking in pairs(ns.NearbyGroups.roles) do
	wear(key, tracking)
end
for skill, tracking in pairs(ns.NearbyGroups.professions) do
	wear("profession:" .. skill, tracking)
end
-- Kinds the map filter treats as one share an atlas; every other pair differs.
local same = { arrows = "ammo", bullets = "ammo", food = "food", drink = "food", bags = "supplies", trade = "supplies" }
same.class, same.portal = "class", "class"
local owner = {}
for kind, tracking in pairs(kinds) do
	local family = same[kind] or kind
	check(owner[tracking] == nil or owner[tracking] == family, tracking .. " is worn by " .. kind .. " and another kind")
	owner[tracking] = family
end
check(kinds.gear ~= "poi-transmogrifier", "weapons and armour no longer wear the transmogrifier's banner")
check(kinds["profession:393"] == "worldquest-icon-skinning", "a skinning trainer wears the skinning mark")

-- A hidden service drops out of every pin: the food seller keeps its food icon and lists no repair, and the NPC
-- that only repairs draws nothing.
local food = find(3)
check(food and food.Texture.atlas == "Food", "a repairer hidden by default leaves the food seller's own icon")
check(#linesOf(food) == 0, "the hidden repair is not listed in the tooltip")
check(not find(5), "an NPC whose only service is hidden draws no pin")
check(find(4).Texture.atlas == "Reagents", "the trade supplier keeps its own icon while repair is hidden")

-- Showing repair at once brings its pins back, makes the shared NPC wear repair, and the mixed group keep its stall.
ns.SetOption("townServiceRepair", true)
ns.RefreshTownServices()
check(count() == 4 and find(5), "showing repair draws its alone pin")
check(find(3).Texture.atlas == "Repair", "the food seller keeps its own atlas for the shown repairer")
check(table.concat(linesOf(find(3)), " ") == "Food", "the tooltip lists the other shown service")
local shared = find(4)
check(
	#shared.cluster.services == 2
		and shared.Texture.texture == "Interface\\AddOns\\ShortestPathForever\\media\\TownGroup",
	"a mixed cluster wears the stall"
)
check(
	table.concat(linesOf(shared), ", ") == "Trade supplies, Repair",
	"the mixed tooltip lists every shown service in the list's own order, not a pinned service first"
)
ns.SetOption("townServiceRepair", false)
ns.RefreshTownServices()
check(count() == 3 and not find(5), "hiding repair drops its pin again")
check(
	find(3).Texture.atlas == "Food" and find(4).Texture.atlas == "Reagents",
	"the remaining services wear their own icons"
)

-- The Map Filter's Town services submenu has the four levels, then one checkbox per service the pins can wear.
local radios, checkboxes, scrollExtent = {}, {}, nil
local menuRoot = {
	CreateDivider = function() end,
	CreateButton = function(_, text)
		check(text == "Town services", "the submenu is still named Town services")
		return {
			SetScrollMode = function(_, extent) scrollExtent = extent end,
			CreateDivider = function() end,
			CreateRadio = function(_, label, get, click)
				radios[#radios + 1] = { label = label, get = get, click = click }
			end,
			CreateCheckbox = function(_, label, get, click)
				checkboxes[#checkboxes + 1] = { label = label, get = get, click = click }
			end,
		}
	end,
}
menus.MENU_WORLD_MAP_TRACKING(nil, menuRoot)
check(#radios == 4, "the submenu still has the four town levels")
check(scrollExtent == 400, "the per-kind catalogue scrolls after twenty rows")
check(#checkboxes == #groups, "one checkbox for every service in the catalogue")
for at, entry in ipairs(groups) do
	check(checkboxes[at].label == entry.label, "checkbox labels follow the authoritative catalogue order")
end
local box = {}
for _, row in ipairs(checkboxes) do
	box[row.label] = row
end
check(box["Repair"] and box["Repair"].get() == false, "repair starts unchecked")
check(box["Innkeeper"] and box["Innkeeper"].get() == true, "the other services start checked")
check(box["Food"] and box["Trade supplies"], "each vendor kind uses its own catalogue label")
check(not box["Dungeons and raids"], "a dungeon entrance gets no checkbox")
box["Repair"].click()
check(ns.db.townServiceKinds.repair == true and count() == 4, "checking repair shows its pins at once")
box["Repair"].click()
check(ns.db.townServiceKinds.repair == false and count() == 3, "unchecking it hides them again")

-- A saved choice survives the next load's defaults merge, and the shipped default stays hidden.
ns.db.townServiceKinds = nil
ns.SetOption("townServiceRepair", true)
ns.RefreshTownServices()
for key, value in pairs(ns.Defaults) do
	if ns.db[key] == nil then
		ns.db[key] = value
	end
end
check(ns.db.townServiceRepair == true, "a fresh defaults merge keeps the player's shown repairer")
check(ns.Defaults.townServiceRepair == false, "the shipped default is still hidden")
ns.SetOption("townServiceRepair", false)
ns.RefreshTownServices()

-- A setting that turns them back on redraws the map, through the same entry the settings page and filter menu call.
ns.db.townServices = "capitals"
ns.RefreshMap()
check(count() == 1, "the map's own refresh brings the pins back")
-- A battlemaster is a service of its own: hiding it drops its pin and leaves every other service where it was.
groups[#groups + 1] = group("services", "battlemaster", "Battlemaster", "BattleMaster")
index = {
	bank = index.bank,
	innkeeper = index.innkeeper,
	repair = index.repair,
	food = index.food,
	trade = index.trade,
	battlemaster = { place(7, "Battlemaster Seven", 4000, -3000) },
}
ns.db.townServices = "all"
ns.RefreshTownServices()
check(count() == 4, "all towns draws the battlemaster beside the other services")
check(find(7) and find(7).Texture.atlas == "BattleMaster", "the battlemaster pin wears the client's own mark")
check(find(7).Texture.texture == nil, "and no file art")
radios, checkboxes = {}, {}
menus.MENU_WORLD_MAP_TRACKING(nil, menuRoot)
for _, row in ipairs(checkboxes) do
	box[row.label] = row
end
check(box["Battlemaster"] and box["Battlemaster"].get(), "a newly available battlemaster has its own checkbox")
box["Battlemaster"].click()
check(ns.db.townServiceKinds.battlemaster == false, "unchecking the battlemaster writes its switch")
check(not find(7), "its pin goes")
check(count() == 3, "and no other service's pin goes with it")
check(find(1) == find(2) and find(3) and find(4), "the capital's services and both outlying sellers stay")
check(table.concat(linesOf(find(1)), ", ") == "Bank, Innkeeper", "a neighbour's tooltip keeps only its own services")
check(
	ns.db.townServiceBank == true
		and ns.db.townServiceInnkeeper == true
		and ns.db.townServiceFood == true
		and ns.db.townServiceRepair == false,
	"and no other service's switch moves"
)
box["Battlemaster"].click()
check(count() == 4 and find(7), "checking it brings the battlemaster's pin back")
-- A wandering NPC: QuestieDB lists every spawn along its route, but the town layer draws the NPC, not each of its
-- spawns. One pin per map at every zoom, on the spawn nearest the mean of its spawns there, which is still a real
-- spawn a journey can go to.
local function spawn(x, y)
	return {
		id = 20,
		name = "Fritz Fizzle",
		title = "Engineer",
		map = 14,
		x = x,
		y = y,
		-- The test client's zone-to-world mapping, the inverse of its C_Map.GetMapPosFromWorldPos
		-- (tests/ui_client.lua), so the projection puts each spawn back on these map fractions.
		world = { map = 1, x = (0.5 - y) * 25000, y = (0.5 - x) * 25000 },
	}
end
local wander = {
	spawn(0.3, 0.4),
	spawn(0.4, 0.42),
	spawn(0.35, 0.5),
	spawn(0.44, 0.48),
	spawn(0.55, 0.6),
}
index = { books = wander }
groups = { group("vendors", "books", "Books and recipes", "Books") }
ns.db.townServices = "all"
ns.db.townServiceBooks = true
zoom = 0
canvasScaled()
ns.RefreshTownServices()
check(count() == 1, "a wandering NPC draws one pin zoomed out")
zoom = 1
canvasScaled()
ns.RefreshTownServices()
check(count() == 1, "and still one at full zoom, not one pin per spawn")
local wanderer = find(20)
check(wanderer ~= nil, "the wandering NPC still shows")
local middleX, middleY = ns.MapPinPosition(wander[4].world, 1414)
check(
	wanderer.mapX == middleX and wanderer.mapY == middleY,
	"the pin stands on the spawn nearest the mean of its spawns"
)
ns.Canvas.Click(wanderer, "LeftButton")
check(
	navigated ~= nil
		and navigated.spot.id == 20
		and navigated.spot.x == wander[4].x
		and navigated.spot.y == wander[4].y
		and navigated.spot.world.x == wander[4].world.x
		and navigated.spot.world.y == wander[4].world.y,
	"a journey goes to that real spawn, not the mean"
)
navigated = nil

-- Only my professions (#914): a profession trainer and the supply rows whose goods serve a profession give way when
-- the character has not learned it, while a general supplier and every other service stay. What a vendor sells in the
-- row decides, never its title, so every supplier below is called Trade Supplies. A mixed NPC keeps its other service
-- and its tooltip stops naming the hidden one, and a food seller that also stocks a cooking reagent keeps its Food pin
-- while its Trade supplies row goes.
local realProfessions, realProfessionInfo = GetProfessions, GetProfessionInfo
local realItemProfessions = ns.ItemProfessions
GetProfessions = function()
	return 1
end
GetProfessionInfo = function()
	return "", 0, 1, 300, 0, 0, 197
end
ns.ItemProfessions = { [7001] = { 197 }, [7002] = { 164 }, [7003] = { 164, 185 }, [7004] = { 129, 185 } }
local trainer197 = group("trainers", "profession:197", "Tailoring", "Profession")
trainer197.skill = 197
local trainer164 = group("trainers", "profession:164", "Blacksmithing", "Profession")
trainer164.skill = 164
local tradeGroup = group("vendors", "trade", "Trade supplies", "Reagents")
local foodGroup = group("vendors", "food", "Food", "Food")
local innGroup = group("services", "innkeeper", "Innkeeper", "Innkeeper")
local tailor = place(30, "Tailor trainer", 2000, 0)
local smith = place(31, "Smith trainer", 2100, 0)
local tailorSupplies = place(32, "Thread and dye", 2200, 0)
tailorSupplies.title = "Trade Supplies"
local mixed = place(33, "Flux and hammers", 2300, 0)
mixed.title = "Trade Supplies"
local general = place(34, "General supplier", 2400, 0)
general.title = "Trade Supplies"
local twoProfessions = place(35, "Camping goods", 2500, 0)
twoProfessions.title = "Trade Supplies"
local breadSeller = place(36, "Bread and spices", 2600, 0)
breadSeller.title = "Trade Supplies"
vendorItems = {
	trade = {
		[32] = { 7001 },
		[33] = { 7002 },
		-- A good no profession's work consumes, so the general supplier always shows.
		[34] = { 7005 },
		[35] = { 7003 },
		[36] = { 7004 },
	},
	food = { [36] = { 7006 } },
}
groups = { foodGroup, tradeGroup, trainer197, trainer164, innGroup }
index = {
	["profession:197"] = { tailor },
	["profession:164"] = { smith },
	trade = { tailorSupplies, mixed, general, twoProfessions, breadSeller },
	food = { breadSeller },
	innkeeper = { mixed },
}
ns.db.townServiceKinds = nil
ns.db.onlyMyProfessions = true
ns.db.townServices = "all"
zoom = 1
canvasScaled()
ns.RefreshTownServices()
check(find(30) ~= nil and find(31) == nil, "only the learned profession's trainer draws a pin")
check(find(32) ~= nil and find(34) ~= nil, "the learned profession's and the general supplier's pins stay")
check(find(35) == nil, "a supplier for two unlearned professions goes")
check(find(33) ~= nil, "a vendor with another shown service stays")
check(#linesOf(find(33)) == 0, "its tooltip names no service for the unlearned profession")
check(find(36) ~= nil, "a food seller with nothing for a profession keeps its Food pin")
check(#linesOf(find(36)) == 0, "the cooking reagent it also sells hides its Trade supplies row")
GetProfessionInfo = function()
	return "", 0, 1, 300, 0, 0, 185
end
ns.RefreshTownServices()
check(find(35) ~= nil, "a supplier for two professions returns when either is learned")
check(
	table.concat(linesOf(find(36)), ", ") == "Trade supplies",
	"learning Cooking names its other row again"
)
ns.db.onlyMyProfessions = false
ns.RefreshTownServices()
check(find(31) ~= nil, "with the filter off, every trainer draws again")
check(table.concat(linesOf(find(33)), ", ") == "Trade supplies", "and the mixed NPC names the vendor service again")
ns.db.onlyMyProfessions = nil
ns.ItemProfessions = realItemProfessions
GetProfessions, GetProfessionInfo = realProfessions, realProfessionInfo

-- A newly classified service gets its own pin and saved visibility control.
local transmog = group("services", "transmog", "Transmogrifier", "poi-transmogrifier")
groups = {transmog}
index = {transmog = {place(270582, "Mon'ye", 1800, -4900)}}
ns.RefreshTownServices()
check(ns.Defaults.townServiceTransmog == true, "transmogrifiers show on old saves by default")
check(ns.TownServiceFilterable(transmog), "the shared transmog group has a map checkbox")
check(find(270582) ~= nil, "the shared index produces a transmogrifier town pin")
ns.SetTownServiceGroupShown(transmog, false)
check(find(270582) == nil, "the checkbox hides the transmogrifier pin")
ns.SetTownServiceGroupShown(transmog, true)
check(find(270582) ~= nil, "the checkbox restores the transmogrifier pin")

check(#errors == 0, table.concat(errors, "\n"))

print(
	(
		"town_services_spec: %d checks: icons, grouping, tooltip, journey, maps, levels, hidden services and professions ok"
	):format(checks)
)
]==]))()

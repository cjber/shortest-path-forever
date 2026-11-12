-- UI/TownServices.lua on the world map: one client service icon per pin, a service's own icon when every member shows
-- that service, the addon's own market stall when a group stands for different services, the tooltip that names them
-- and the click that plans a journey, the four levels of detail, each service's own Map Filter checkbox with
-- repairers hidden by default, and the maps the pins belong on.
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
ns.NearbyServices = {
	State = function()
		return "ready"
	end,
	Index = function()
		return index
	end,
	Groups = function()
		return groups
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
-- Repair starts hidden; the other services start shown, including for a saved table that predates the switches.
check(ns.db.townServiceRepair == false, "a repairer is hidden by default")
check(ns.db.townServiceBank == true and ns.db.townServiceFood == true, "the other services start shown")
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
setMapShown(true)
ns.RefreshTownServices()

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

-- A hidden service drops out of every pin: the food seller keeps its food icon and lists no repair, and the NPC
-- that only repairs draws nothing.
local food = find(3)
check(food and food.Texture.atlas == "Food", "a repairer hidden by default leaves the food seller's own icon")
check(#linesOf(food) == 0, "the hidden repair is not listed in the tooltip")
check(not find(5), "an NPC whose only service is hidden draws no pin")
check(find(4).Texture.atlas == "Reagents", "the trade supplier keeps its own icon while repair is hidden")

-- Showing repair at once brings its pins back, makes the shared NPC wear repair, and the mixed group keep its stall.
ns.SetTownServiceShown("townServiceRepair", true)
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
ns.SetTownServiceShown("townServiceRepair", false)
check(count() == 3 and not find(5), "hiding repair drops its pin again")
check(
	find(3).Texture.atlas == "Food" and find(4).Texture.atlas == "Reagents",
	"the remaining services wear their own icons"
)

-- The Map Filter's Town services submenu has the four levels, then one checkbox per service the pins can wear.
local radios, checkboxes = {}, {}
local menuRoot = {
	CreateDivider = function() end,
	CreateButton = function(_, text)
		check(text == "Town services", "the submenu is still named Town services")
		return {
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
check(#checkboxes == 13, "one checkbox for every service the pins show")
local box = {}
for _, row in ipairs(checkboxes) do
	box[row.label] = row
end
check(box["Repair"] and box["Repair"].get() == false, "repair starts unchecked")
check(box["Innkeeper"] and box["Innkeeper"].get() == true, "the other services start checked")
check(
	box["Profession trainers"] and box["Food and drink"] and box["Ammunition"] and box["Bags and trade supplies"],
	"the grouped services have one checkbox each"
)
check(not box["Dungeons and raids"], "a dungeon entrance gets no checkbox")
box["Repair"].click()
check(ns.db.townServiceRepair == true and count() == 4, "checking repair shows its pins at once")
box["Repair"].click()
check(ns.db.townServiceRepair == false and count() == 3, "unchecking it hides them again")

-- A saved choice survives the next load's defaults merge, and the shipped default stays hidden.
ns.SetTownServiceShown("townServiceRepair", true)
for key, value in pairs(ns.Defaults) do
	if ns.db[key] == nil then
		ns.db[key] = value
	end
end
check(ns.db.townServiceRepair == true, "a fresh defaults merge keeps the player's shown repairer")
check(ns.Defaults.townServiceRepair == false, "the shipped default is still hidden")
ns.SetTownServiceShown("townServiceRepair", false)

-- A setting that turns them back on redraws the map, through the same entry the settings page and filter menu call.
ns.db.townServices = "capitals"
ns.RefreshMap()
check(count() == 1, "the map's own refresh brings the pins back")
check(#errors == 0, table.concat(errors, "\n"))

print(
	(
		"town_services_spec: %d checks: service icons, grouping, tooltip, journey click, maps, levels and hidden services ok"
	):format(checks)
)
]==]))()

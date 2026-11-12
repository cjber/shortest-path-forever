-- UI/TownServices.lua on the world map: one client service icon per pin, the same icon on a group pin as its most
-- useful service, the tooltip that names a town's services and the click that plans a journey, the four levels
-- of detail and the maps the pins belong on.
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
-- not from a list here. Each group carries the client's tracking atlas the map wears, the way UI/NearbyGroups.lua
-- gives them.
local function group(section, key, label, tracking)
	return { section = section, key = key, label = label, icon = tracking, tracking = tracking, npcs = {} }
end
local groups = {
	group("services", "bank", "Bank", "Banker"),
	group("services", "innkeeper", "Innkeeper", "Innkeeper"),
	group("vendors", "food", "Food", "Food"),
	group("vendors", "trade", "Trade supplies", "Reagents"),
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

-- Every service in one zone view: the two Orgrimmar services share one pin, the outlying sellers keep their own,.
check(count() == 3, "three pins on the zone: the city's services and the two outlying sellers")
local bank, inn = find(1), find(2)
check(bank == inn, "the two Orgrimmar services share one pin at this zoom")
check(#bank.cluster.services == 2, "the group pin carries both services")

-- No pin wears a town or city mark: a group wears the most useful service's own client icon, a single NPC its own.
check(bank.Texture.atlas ~= "poi-majorcity" and bank.Texture.atlas ~= "poi-town", "a group pin wears no town mark")
check(bank.Texture.atlas == "Banker", "a group pin wears the icon of its most useful service")
check(find(3).Texture.atlas == "Food", "an outlying food seller wears the client's food icon, not an item's")
check(find(3).Texture.texture == nil, "no service pin wears an item icon")

-- Its tooltip names the town, leads with the service the pin wears, lists the rest once each, and offers the click
-- that plans a journey.
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
check(#lines == 2 and lines[1] == "Bank" and lines[2] == "Innkeeper", "the tooltip leads with the pin's service")
check(lines[1] == groups[1].label and bank.Texture.atlas == groups[1].tracking,
	"the group pin wears the icon of the service its tooltip leads with")
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
check(bank:IsShown() and inn:IsShown(), "both service pins stay visible")

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

-- A setting that turns them back on redraws the map, through the same entry the settings page and filter menu call.
ns.db.townServices = "capitals"
ns.RefreshMap()
check(count() == 1, "the map's own refresh brings the pins back")
check(#errors == 0, table.concat(errors, "\n"))

print(
	("town_services_spec: %d checks: service icons, grouping, tooltip, journey click, maps and levels ok"):format(
		checks
	)
)
]==]))()

-- UI/TownServices.lua on the world map: one icon per town while the services overlap, one per service when the map is
-- zoomed in, the four levels of detail, and the tooltip that names a town's services.
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

-- The client's item icons, which the map borrows for a vendor's goods.
C_Item.GetItemIconByID = function()
	return 12345
end

-- A ready Nearby services index: two Orgrimmar services, a food seller and a trade supplier outside the city. The
-- capital comes from Data/Zones.lua's own Orgrimmar box, not from a list here.
local function group(section, key, label, icon)
	return { section = section, key = key, label = label, icon = icon, npcs = {} }
end
local groups = {
	group("services", "bank", "Bank", "banker"),
	group("services", "innkeeper", "Innkeeper", "innkeeper"),
	group("vendors", "food", "Food", 4540),
	group("vendors", "trade", "Trade supplies", 2320),
}
local function place(id, name, x, y, map)
	return {
		id = id,
		name = name,
		map = map or 14,
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
}
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

-- Every service in one continent view: the two Orgrimmar services share one town pin, the outlying sellers keep
-- their own. A town pin wears the client's major city mark, not a service's item icon.
check(count() == 3, "three pins on the continent: the city and two outlying services")
local bank, inn = find(1), find(2)
check(bank == inn, "the two Orgrimmar services share one town pin at this zoom")
check(#bank.cluster.services == 2, "the town pin carries both services")
check(bank.Texture.atlas == "poi-majorcity", "a capital town pin wears the client's major city atlas")
check(find(3).Texture.texture == 12345, "an outlying food seller wears its goods' item icon")

-- Its tooltip names the town and lists the services, once each.
local lines = {}
local oldLine = GameTooltip_AddNormalLine
GameTooltip_AddNormalLine = function(_, text)
	lines[#lines + 1] = text
end
bank.scripts.OnEnter(bank)
GameTooltip_AddNormalLine = oldLine
check(GameTooltipTextLeft1.text == "Map1454", "the town pin is titled with the capital's own map name")
check(#lines == 2 and lines[1] == "Bank" and lines[2] == "Innkeeper", "the tooltip lists each service once")
check(GameTooltip:IsOwned(bank), "hovering a town pin shows its tooltip")

-- Zoomed in, the services separate into a pin each, wearing their own client art.
zoom = 1
canvasScaled()
bank, inn = find(1), find(2)
check(bank ~= inn, "the two Orgrimmar services separate when zoomed in")
check(bank.Texture.atlas == "banker" and inn.Texture.atlas == "innkeeper", "each service wears its own atlas")
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

-- A setting that turns them back on redraws the map, through the same entry the settings page and filter menu call.
ns.db.townServices = "capitals"
ns.RefreshMap()
check(count() == 1, "the map's own refresh brings the pins back")
check(#errors == 0, table.concat(errors, "\n"))

print(("town_services_spec: %d checks: town grouping, service pins, tooltip and levels ok"):format(checks))
]==]))()

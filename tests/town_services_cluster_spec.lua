-- UI/TownServices.lua's clustering: same-service pins merge at a wider distance than mixed pins, a same-service
-- group wears that service's own tracking icon while a mixed group wears the market stall, and full zoom splits every
-- NPC, spreading the ones that share a doorway so each keeps its own hover and click.
local dir = arg[0]:match("^(.*)/") or "tests"

local probe = "tools/.cache/blizzard-ui/Interface/AddOns/Blizzard_SharedXML/Spinner.lua"
do
	local handle = io.open(probe)
	if handle then
		handle:close()
	else
		local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
		assert(
			ok == true or ok == 0,
			"could not fetch the pinned Blizzard UI fixture for tests/town_services_cluster_spec.lua"
		)
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

local function group(section, key, label, tracking)
	return { section = section, key = key, label = label, icon = tracking, tracking = tracking, npcs = {} }
end
local groups = {
	group("services", "bank", "Bank", "Banker"),
	group("services", "innkeeper", "Innkeeper", "Innkeeper"),
	group("vendors", "food", "Food", "Food"),
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
-- Three groups far apart on the same map. Two bankers 1800 yards apart merge as one service before the mixed
-- distance would have merged them; an innkeeper beyond the mixed distance keeps its own pin. A banker and an
-- innkeeper 600 yards apart make a mixed group wearing the stall. Two food sellers one yard apart are the pair full
-- zoom must still split.
local index = {
	bank = {
		place(1, "Banker One", 0, 0),
		place(2, "Banker Two", 1800, 0),
		place(4, "Banker Four", 5000, 5000),
	},
	innkeeper = {
		place(3, "Innkeeper Three", 0, 1200),
		place(5, "Innkeeper Five", 5000, 5600),
	},
	food = {
		place(6, "Food Six", -5000, -5000),
		place(7, "Food Seven", -5000, -5001),
	},
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
local function namesOf(pin)
	local names = {}
	local old = GameTooltip_AddColoredLine
	GameTooltip_AddColoredLine = function(_, text)
		names[#names + 1] = text
	end
	pin.scripts.OnEnter(pin)
	GameTooltip_AddColoredLine = old
	return names
end

-- The two bankers merge as one Bank pin, though they are farther apart than the mixed distance: same services merge
-- first and at a wider reach. The innkeeper beyond that reach keeps its own pin, and the group is not a stall.
local two, one, three = find(2), find(1), find(3)
check(two == one, "two overlapping bankers share one pin")
check(three ~= one, "an innkeeper beyond the mixed distance keeps its own pin")
check(#one.cluster.services == 2, "the same-service pin carries both bankers")
check(one.Texture.atlas == "Banker" and one.Texture.texture == nil, "a same-service pin wears that service's icon")
check(one.Texture.atlas ~= "poi-majorcity" and one.Texture.atlas ~= "poi-town", "and never a town mark")
check(three.Texture.atlas == "Innkeeper" and three.Texture.texture == nil, "the separate innkeeper wears its own icon")
local bankers = namesOf(one)
check(GameTooltipTextLeft1.text == "Bank", "a same-service pin is titled with its service")
check(
	table.concat(bankers, ", ") == "Banker One, Banker Two",
	"its tooltip lists every member the pin stands for"
)

-- A mixed group within the plain pin size wears the addon's own market stall.
local four, five = find(4), find(5)
check(four == five, "a banker and an innkeeper whose pins overlap share one pin")
check(
	four.Texture.texture == "Interface\\AddOns\\ShortestPathForever\\media\\TownGroup" and four.Texture.atlas == nil,
	"a mixed group wears the market stall"
)
check(
	four.HighlightTexture.texture == four.Texture.texture and four.HighlightTexture.atlas == nil,
	"and its highlight wears the same stall"
)
check(count() == 4, "the map draws two same-service pins and one mixed pin at this zoom")

-- Full zoom splits every NPC, including two food sellers one yard apart, which spread around their shared centre.
zoom = 1
canvasScaled()
check(count() == 7, "full zoom gives every NPC its own pin")
for _, pin in ipairs(pins()) do
	check(#pin.cluster.services == 1, "no pin at full zoom stands for more than one NPC")
	check(pin.Texture.texture == nil, "no pin at full zoom wears the stall")
end
local fourFull, fiveFull = find(4), find(5)
check(fourFull ~= fiveFull, "two nearby NPCs of different services form two clusters at full zoom")
check(
	fourFull.Texture.atlas == "Banker" and fiveFull.Texture.atlas == "Innkeeper",
	"each of the split pins keeps its own service icon"
)
local six, seven = find(6), find(7)
check(six ~= seven, "two NPCs one yard apart split at full zoom")
check(six.Texture.atlas == "Food" and seven.Texture.atlas == "Food", "each wears its own service icon")
check(
	six.mapX ~= seven.mapX or six.mapY ~= seven.mapY,
	"the pair spreads around their shared centre instead of stacking on one spot"
)
ns.Canvas.Click(six, "LeftButton")
check(navigated and navigated.key == "food" and navigated.spot.id == 6, "the first spread pin can be clicked")
navigated = nil
ns.Canvas.Click(seven, "LeftButton")
check(navigated and navigated.key == "food" and navigated.spot.id == 7, "and so can the second")

check(#errors == 0, table.concat(errors, "\n"))
print(
	(
		"town_services_cluster_spec: %d checks: same-service first, mixed stall, full zoom split and spread ok"
	):format(checks)
)
]==]))()

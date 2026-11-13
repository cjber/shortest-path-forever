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

-- A flight master is the flight point's own NPC (QuestieDB's FLIGHT_MASTER flag puts it in the flight group), so the
-- town layer leaves it to the flight point pin: a flight master alone draws no town pin, and an NPC who is also a
-- vendor keeps one vendor pin with no second "Flight master" mark (#816).
local gearTracking
for _, vendor in ipairs(ns.NearbyGroups.vendors) do
	if vendor.key == "gear" then
		gearTracking = vendor.tracking
	end
end
groups[#groups + 1] = group("services", "flight", "Flight master", "FlightMaster")
groups[#groups + 1] = group("vendors", "gear", "Weapons and armour", gearTracking)
local rebuilt = {}
for key, list in pairs(index) do
	rebuilt[key] = list
end
rebuilt.flight = {
	place(8, "Gryphon Master", 9000, 9000),
	place(9, "Fruit Seller and Gryphon Master", 9100, 9100),
}
rebuilt.food = {}
for _, point in ipairs(index.food or {}) do
	rebuilt.food[#rebuilt.food + 1] = point
end
rebuilt.food[#rebuilt.food + 1] = place(9, "Fruit Seller and Gryphon Master", 9100, 9100)
-- Full zoom spreads these two around their shared centre; one zoom step out keeps them apart again, so both pins
-- must stand back on their own NPCs rather than stay where the spread put them (#816).
local spreadEleven = place(11, "Food Eleven", 7000, 7000)
local spreadTwelve = place(12, "Food Twelve", 7000, 7200)
rebuilt.food[#rebuilt.food + 1] = spreadEleven
rebuilt.food[#rebuilt.food + 1] = spreadTwelve
rebuilt.gear = { place(10, "Weapons Merchant", -9000, 9000) }
index = rebuilt
ns.RefreshTownServices()

check(find(8) == nil, "a flight master alone draws no town pin: the flight point pin stands for it")
local vendorAndFlight = find(9)
check(vendorAndFlight and vendorAndFlight.Texture.atlas == "Food", "an NPC who is also a vendor keeps its vendor pin")
for _, pin in ipairs(pins()) do
	check(pin.Texture.atlas ~= "FlightMaster", "no town pin wears the flight master's mark")
end
local flightLines = {}
local oldNormal = GameTooltip_AddNormalLine
GameTooltip_AddNormalLine = function(_, text)
	flightLines[#flightLines + 1] = text
end
vendorAndFlight.scripts.OnEnter(vendorAndFlight)
GameTooltip_AddNormalLine = oldNormal
check(not table.concat(flightLines, ", "):find("Flight master", 1, true), "and its tooltip lists no flight master")

-- The tracking set's `Gear` element is a treasure coin, not equipment: a weapons and armour pin must wear the
-- group's real mark, an atlas this client has, and never that plain gold dot (#816).
check(gearTracking ~= nil and gearTracking ~= "Gear", "weapons and armour do not wear the tracking set's coin")
check(ns.Art.Info(gearTracking) ~= nil, "and their mark is a client atlas")
check(find(10).Texture.atlas == gearTracking, "a weapons and armour pin wears it")

local eleven, twelve = find(11), find(12)
check(eleven and twelve and eleven ~= twelve, "the close pair has its own pins at full zoom")
local expectedX, expectedY = ns.MapPinPosition(spreadEleven.world, 1414)
check(eleven.mapX ~= expectedX or eleven.mapY ~= expectedY, "and full zoom spreads them off their own spot")
zoom = 0.999
canvasScaled()
ns.RefreshTownServices()
local elevenOut, twelveOut = find(11), find(12)
check(elevenOut and twelveOut, "the pair keeps both pins one zoom step out")
check(
	elevenOut.mapX == expectedX and elevenOut.mapY == expectedY,
	"a pin stands on its own NPC again once the zoom lets go of the spread"
)
local twelveX, twelveY = ns.MapPinPosition(spreadTwelve.world, 1414)
check(twelveOut.mapX == twelveX and twelveOut.mapY == twelveY, "and so does the other")
zoom = 1
canvasScaled()

check(#errors == 0, table.concat(errors, "\n"))
print(
	(
		"town_services_cluster_spec: %d checks: same-service first, mixed stall, full zoom split and spread ok"
	):format(checks)
)
]==]))()

-- #553: a journey from Stormwind to the Ironforge quest givers. The world map must draw the walk from the Deeprun Tram
-- to the giver on Ironforge, the walk to the tram on Stormwind, the minimap line and the arrow. The player's
-- UnitPosition is withheld from addons in the report, while the map APIs still know where the player stands; the
-- journey must fall back to them instead of waiting for a sample that never comes.
local dir = arg[0]:match("^(.*)/") or "tests"

-- The world map and its pins run against checksum-pinned Blizzard source, which tests/ui.sh fetches. A spec run on a
-- fresh checkout fetches it here too, as smoke_spec.lua does.
local probe = "tools/.cache/blizzard-ui/Interface/AddOns/Blizzard_SharedXML/Spinner.lua"
do
	local handle = io.open(probe)
	if handle then
		handle:close()
	else
		local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
		assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture for tests/tram_guidance_spec.lua")
	end
end
local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

assert(loadstring(source .. [==[
-- The client's own map regions (wago.tools UiMapAssignment, build 1.60.1.70862), world yards with x north and y west.
local MAPS = {}
local function map(id, name, kind, parent, cont, minX, minY, maxX, maxY)
	MAPS[id] = {
		name = name,
		type = kind,
		parent = parent,
		map = cont,
		minX = minX,
		minY = minY,
		maxX = maxX,
		maxY = maxY,
	}
end
map(1415, "Eastern Kingdoms", 2, 0, 0, -17000, -17000, 17000, 17000)
map(1429, "Elwynn Forest", 3, 1415, 0, -10254, -1935, -7940, 1535)
map(1453, "Stormwind City", 3, 1415, 0, -9154, -15, -7996, 1723)
map(1455, "Ironforge", 3, 1415, 0, -5097, -1504, -4569, -714)
local function project(row, x, y)
	return CreateVector2D((row.maxY - y) / (row.maxY - row.minY), (row.maxX - x) / (row.maxX - row.minX))
end
local function unproject(row, fx, fy)
	return CreateVector2D(row.maxX - fy * (row.maxX - row.minX), row.maxY - fx * (row.maxY - row.minY))
end
local baseWorld = C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos = function(id, v)
	local row = MAPS[id]
	if row then
		local fx, fy = v:GetXY()
		return row.map, unproject(row, fx, fy)
	end
	return baseWorld(id, v)
end
local basePosition = C_Map.GetMapPosFromWorldPos
C_Map.GetMapPosFromWorldPos = function(cont, v, override)
	if override and MAPS[override] then
		local row = MAPS[override]
		local x, y = v:GetXY()
		return row.map == cont and override or nil, row.map == cont and project(row, x, y) or nil
	end
	return basePosition(cont, v, override)
end
local baseInfo = C_Map.GetMapInfo
C_Map.GetMapInfo = function(id)
	local row = MAPS[id]
	if row then
		return { mapID = id, mapType = row.type, parentMapID = row.parent, name = row.name }
	end
	return baseInfo(id)
end
C_Map.GetMapInfoAtPosition = function(id)
	return C_Map.GetMapInfo(id)
end

-- UnitPosition is withheld from addons; the client's map APIs still answer with the player's place.
local SECRET = {}
local playerMap, playerMapX, playerMapY = 1453, 0.272, 0.383
UnitPosition = function()
	return SECRET, SECRET, SECRET, SECRET
end
canaccessvalue = function(value)
	return value ~= SECRET
end
C_Map.GetBestMapForUnit = function()
	return playerMap
end
C_Map.GetPlayerMapPosition = function()
	return CreateVector2D(playerMapX, playerMapY)
end

local API = ShortestPathForever.API
posX, posY, posZ, posMap, facing = -8439.5, 1250.3, 0, 0, 0
ns.db.pins, ns.db.transit, ns.db.portals, ns.db.mapFlightMasters, ns.db.mapRoutes, ns.db.otherFaction =
	true, true, false, false, false, true
setMapShown(true)
local function settleAll()
	for _ = 1, 200 do
		settle()
	end
end
local function show(id)
	mapID = id
	refreshMap()
end

assert(
	API.NavigateRoute("AdventureGuideForever", {
		{ map = 1455, x = 0.3323, y = 0.48, title = "Afadra", hold = true, kind = "pickup" },
	}),
	"the journey starts with the position read from the map"
)
settleAll()
local title, rows = ns.JourneyInfo()
assert(title and rows and #rows > 0, "the tracker has the journey's steps")
local pins = ns.MapCanvas.Pools(WorldMapFrame)
local line = pins.ShortestPathForeverRoutePinTemplate
local goals = pins.ShortestPathForeverGoalPinTemplate

show(1455)
local pin = line.active[1]
assert(pin and pin.used > 0, "the line is drawn on Ironforge")
assert(#goals.active > 0, "the goal is marked on Ironforge")
local walk
for _, path in ipairs(pin.paths) do
	if path.mode == "walk" and #path.points > 1 then
		local first, last = path.points[1], path.points[#path.points]
		if first.map == 0 and first.x == -4839.51 and last.map == 0 and last.x == -4822.44 then
			walk = path
		end
	end
end
assert(walk, "the walk from the tram to the giver is on the world map")
local firstX, firstY = ns.JourneyMapPosition(walk.points[1], 1455)
local lastX, lastY = ns.JourneyMapPosition(walk.points[#walk.points], 1455)
assert(firstX and firstY and lastX and lastY, "the walk's ends are placed on Ironforge")

show(1453)
pin = line.active[1]
assert(pin and pin.used > 0, "the line to the tram is drawn on Stormwind")
local target = select(1, ns.GuideTargets())
assert(target and target.map == 0 and target.x == -8346.46 and target.y == 514.031, "the arrow points at the tram")
assert(ShortestPathForeverMinimapRoute.used > 0, "the minimap draws the way to the tram")
print("tram guidance: journey steps, Ironforge and Stormwind lines, minimap and arrow ok")
]==]))()

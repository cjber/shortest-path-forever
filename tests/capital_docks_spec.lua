-- A capital's map is a sibling of the zone it stands in: UiMap gives each capital its continent as the parent, not
-- the zone around it. A world point in the capital's coarse region therefore resolves to the capital and never
-- reaches its zone. The Grom'gol zeppelin tower outside Orgrimmar's gate is one such point, and the Stormwind boat
-- dock the other: both belong on their zone's map, and on the capital only where the point is inside its region.
-- The map frame and pins are the real ones; only the client's UiMap tables are modelled here.
local dir = arg[0]:match("^(.*)/") or "tests"
local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

assert(loadstring(source .. [==[
-- The client's own regions for the maps involved (wago.tools UiMapAssignment, build 1.60.1.70790), in world yards
-- with x north and y west. type: 2 continent, 3 zone (the client has no separate city type).
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
map(1414, "Kalimdor", 2, 0, 1, -1717, -7250, 1808, -1962)
map(1411, "Durotar", 3, 1414, 1, -1717, -7250, 1808, -1962)
map(1454, "Orgrimmar", 3, 1414, 1, 1338, -5083, 2274, -3681)
map(1415, "Eastern Kingdoms", 2, 0, 0, -17000, -17000, 17000, 17000)
map(1429, "Elwynn Forest", 3, 1415, 0, -10254, -1935, -7940, 1535)
map(1453, "Stormwind City", 3, 1415, 0, -9154, -15, -7996, 1723)
local function project(row, x, y)
	return CreateVector2D((row.maxY - y) / (row.maxY - row.minY), (row.maxX - x) / (row.maxX - row.minX))
end
local function contains(row, x, y)
	return x >= row.minX and x <= row.maxX and y >= row.minY and y <= row.maxY
end
-- The client's best map: the smallest zone whose region holds the point, a capital included.
C_Map.GetMapPosFromWorldPos = function(cont, v, override)
	local x, y = v:GetXY()
	if override then
		local row = MAPS[override]
		return row and row.map == cont and override or nil, row and project(row, x, y) or nil
	end
	local best, area
	for id, row in pairs(MAPS) do
		if row.map == cont and row.type == 3 and contains(row, x, y) then
			local size = (row.maxX - row.minX) * (row.maxY - row.minY)
			if not area or size < area then
				best, area = id, size
			end
		end
	end
	return best and best or nil, best and project(MAPS[best], x, y) or nil
end
local function info(id)
	local row = MAPS[id]
	return {
		mapID = id,
		mapType = row and row.type or 3,
		parentMapID = row and row.parent or 0,
		name = row and row.name or ("Map" .. id),
	}
end
C_Map.GetMapInfo = info
C_Map.GetMapInfoAtPosition = function(id)
	return info(id)
end

-- One column of the map at a time, at a canvas large enough that the Orgrimmar towers do not merge.
canvas.width, canvas.height = 12000, 8400
ns.db.pins, ns.db.transit, ns.db.portals, ns.db.mapFlightMasters, ns.db.mapRoutes, ns.db.otherFaction =
	true, true, false, false, false, true
posX, posY, posMap, facing = 1360, -4631, 1, 0
setMapShown(true)

local pools = ns.MapCanvas.Pools(WorldMapFrame)
local dockPins = pools.ShortestPathForeverDockPinTemplate
local function pinFor(dockID)
	for _, pin in ipairs(dockPins.active) do
		for _, dock in ipairs(pin.cluster.docks) do
			if dock.id == dockID then
				return pin
			end
		end
	end
end
local function show(id)
	mapID = id
	ns.RefreshMap()
end

-- Durotar: the Grom'gol tower's pin is on the zone map at the tower, and the stop still reads as Orgrimmar.
show(1411)
local grom = pinFor(4)
assert(grom and grom:IsShown(), "the Grom'gol zeppelin has a pin on Durotar")
local gx, gy = ns.MapPinPosition(ns.DockPoint(4), 1411)
assert(grom.cluster.x == gx and grom.cluster.y == gy, "and it sits at the tower, not on the capital's edge")
assert(gy < 0.2, "near the top of the Durotar map, at the gate")
local tower = ns.DockLocation(4)
assert(tower.uiMap == 1411 and tower.capitalUiMap == 1454, "the tower is on Durotar, at Orgrimmar's gate")
assert(tower.zone == "Orgrimmar", "the stop is still named after the capital")
-- The generated capital zone link the fix reads, asserted after the pin check so a regression fails at the pin.
assert(ns.Zones[1454].zone == 1411, "Orgrimmar stands in Durotar")
assert(ns.Zones[1453].zone == 1429, "Stormwind City stands in Elwynn Forest")
-- The Undercity tower is already outside Orgrimmar's region and needs no redirect.
show(1454)
assert(ns.DockLocation(13).uiMap == 1411 and not ns.DockLocation(13).capitalUiMap, "the other tower is Durotar's")
local ox, oy = ns.MapPinPosition(ns.DockPoint(4), 1454)
assert(ox and oy, "the Grom'gol tower is inside Orgrimmar's coarse region")
assert(pinFor(4), "so it shows on Orgrimmar too")
assert(not ns.MapPinPosition(ns.DockPoint(13), 1454), "the Undercity tower is outside it")
assert(not pinFor(13), "so it does not show on Orgrimmar")
-- A capital the point is outside of never gets the pin.
show(1429)
assert(not pinFor(4), "no Orgrimmar pin on another continent")

-- The Stormwind boat dock, the same fault on the other continent.
posX, posY, posMap = -8654, 1344, 0
local boat = ns.DockLocation(25)
assert(boat.uiMap == 1429 and boat.capitalUiMap == 1453 and boat.zone == "Stormwind City", "the boat dock is in Elwynn")
show(1429)
assert(pinFor(25) and pinFor(25):IsShown(), "the boat dock has a pin on Elwynn Forest")
show(1453)
assert(pinFor(25), "and on Stormwind City, whose region holds it")

print("capital docks: the Grom'gol and Stormwind stops pin on their zone, with the capital only inside its region: ok")
]==]))()

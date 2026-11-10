-- Durotar's two Orgrimmar zeppelin towers: the icon they draw, and the hover that survives a zoom re-cluster.
-- The UI fixture's zone 14 is the map both towers stand on, as Durotar is in game.
local dir = arg[0]:match("^(.*)/") or "tests"
local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

assert(loadstring(source .. [[
local ZEPPELIN = "Interface\\AddOns\\ShortestPathForever\\media\\Zeppelin"
local FERRY = "flightmasterferry"

-- The fixture's scroll container is small next to a continent; this zoom range crosses the towers' merge point.
canvas.width, canvas.height = 12000, 8400
ns.db.pins, ns.db.transit, ns.db.portals, ns.db.mapFlightMasters, ns.db.mapRoutes, ns.db.otherFaction =
 true, true, false, true, true, true
posX, posY, posMap, facing = 0, 0, 1, 0
mapID, zoom = 14, 0
setMapShown(true)
ns.RefreshMap()

local pools = ns.Canvas.Pools(WorldMapFrame)
local dockPins = pools.ShortestPathForeverDockPinTemplate
local function ids(pin)
 local list = {}
 for _, dock in ipairs(pin.cluster.docks) do list[#list + 1] = dock.id end
 return table.concat(list, ",")
end
local function pinFor(dockID)
 for _, pin in ipairs(dockPins.active) do
  for _, dock in ipairs(pin.cluster.docks) do
   if dock.id == dockID then return pin end
  end
 end
end
local function carries(pin, dockID)
 for _, dock in ipairs(pin.cluster.docks) do
  if dock.id == dockID then return true end
 end
 return false
end

-- The icon: a boat keeps the stock ferry atlas, a zeppelin draws the addon's own file, and a stop follows both.
local boat = pinFor(1)
assert(boat and boat.Texture.atlas == FERRY and boat.Texture.texture == nil, "a boat still draws the ferry atlas")
local tower = pinFor(4)
assert(tower and tower.Texture.texture == ZEPPELIN and tower.Texture.atlas == nil, "a zeppelin draws its own file")
assert(pinFor(13) == tower, "the two Orgrimmar towers share one pin at this zoom")
local function texture()
 local t = {}
 function t:SetAtlas(atlas) self.atlas, self.texture = atlas, nil end
 function t:SetTexture(file) self.texture, self.atlas = file, nil end
 function t:SetTexCoord() self.whole = true end
 function t:SetSize(width, height) self.width, self.height = width, height end
 return t
end
local stop, boatStop = texture(), texture()
assert(ns.SetStopLook(stop, "zeppelin", 18) and stop.texture == ZEPPELIN, "a zeppelin stop draws the same file")
assert(ns.SetStopLook(boatStop, "boat", 18) and boatStop.atlas == FERRY, "a boat stop keeps the ferry atlas")

-- Hovering the merged towers highlights their routes; a re-cluster on this map must not lose the tower's hover.
local originalHover, hoveredRoutes = ns.HoverTransportRoutes, nil
ns.HoverTransportRoutes = function(owner, routes)
 hoveredRoutes = routes
 return originalHover(owner, routes)
end
tower.scripts.OnEnter(tower)
assert(GameTooltip:IsOwned(tower) and GameTooltip:IsShown(), "hovering the towers shows their tooltip")
assert(hoveredRoutes and hoveredRoutes[285] and hoveredRoutes[302], "both Orgrimmar crossings are drawn")

-- Zoom in: the towers split, and both docks remain addressable.
zoom = 1
canvasScaled()
local stv, undercity = pinFor(4), pinFor(13)
assert(stv and undercity and stv ~= undercity, "each tower has its own pin when zoomed in")
assert(stv:IsShown() and undercity:IsShown(), "both towers stay visible")
assert(carries(stv, 4) and carries(undercity, 13), "every Orgrimmar dock is still in its layer's pin map")
assert(GameTooltip:IsOwned(stv) and GameTooltip:IsShown(), "the hovered tower keeps its tooltip through the split")
assert(hoveredRoutes and hoveredRoutes[285], "and its Stranglethorn route stays drawn")
stv.scripts.OnEnter(stv)
assert(hoveredRoutes and hoveredRoutes[285], "hovering the Stranglethorn tower draws its route")
undercity.scripts.OnEnter(undercity)
assert(hoveredRoutes and hoveredRoutes[302], "hovering the Undercity tower draws its route")

-- Zoom back out: they merge again, and the tower under the pointer keeps its tooltip and route.
zoom = 0
canvasScaled()
local merged = pinFor(4)
assert(merged and merged == pinFor(13), "the towers share a pin again")
assert(merged:IsShown(), "the merged tower pin stays visible")
assert(GameTooltip:IsOwned(merged) and GameTooltip:IsShown(), "the hovered tower keeps its tooltip through the merge")
assert(hoveredRoutes and hoveredRoutes[302], "and its Undercity route stays drawn")
merged.scripts.OnEnter(merged)
assert(hoveredRoutes and hoveredRoutes[285] and hoveredRoutes[302], "the merged pin draws both crossings again")

-- The promise at Map.lua's early return: an unchanged pin set refreshes in place, keeping the same hovered pin.
local unchanged = pinFor(4)
canvasScaled()
assert(pinFor(4) == unchanged and GameTooltip:IsOwned(unchanged), "an unchanged pin set keeps its hover")
merged.scripts.OnLeave(merged)
ns.HoverTransportRoutes = originalHover
assert(not hoveredRoutes or hoveredRoutes[285] == nil, "leaving the pin clears its route highlight")
print("zeppelin_docks: own icon, every Orgrimmar tower addressable and hoverable across zoom re-clusters: ok")
]]))()

-- The real journey and its canvas pools, with OpenMap's waypoint handoff and projection as the client sees them.
local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture")

local source = {}
for _, part in ipairs({ "tests/ui_client.lua", "tests/ui_map.lua" }) do
	local file = assert(io.open(part))
	source[#source + 1] = file:read("*a")
	file:close()
end

assert(loadstring(table.concat(source) .. [[
local stitched = true
_G.OpenMapAPI = {
	major = 1,
	version = 2,
	IsStitched = function()
		return stitched
	end,
	CanvasFromWorldPos = function(continent, x, y)
		local _, position = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(x, y), mapID)
		return position:GetXY()
	end,
}
posX, posY, posMap = 0, 0, 1

-- The host stays on a Kalimdor zone as OpenMap pans over both continents.
local normalProjection = OpenMapAPI.CanvasFromWorldPos
local taxiNodes = ns.TaxiNodes
local hostMap = mapID
local flightMasters = ns.db.mapFlightMasters
local scan, suppresses = ns.CompanionMaps.Scan, ns.CompanionMaps.Suppresses
local queryTaxi = C_TaxiMap.GetTaxiNodesForMap
local queries, projections, companionVisible = 0, 0, false
function C_TaxiMap.GetTaxiNodesForMap(id)
	queries = queries + 1
	return queryTaxi(id)
end
function ns.CompanionMaps.Scan()
	return tostring(companionVisible)
end
function ns.CompanionMaps.Suppresses(kind, _, _, _, id)
	return companionVisible and kind == "flight" and id == 1
end
mapID = 14
ns.TaxiNodes = {
	[1] = { map = 1, x = 0, y = 0, name = "Kalimdor" },
	[2] = { map = 0, x = 0, y = 0, name = "Eastern Kingdoms" },
}
OpenMapAPI.CanvasFromWorldPos = function(continent)
	projections = projections + 1
	return continent == 1 and 0.5 or 1.5, 0.5
end
ns.db.mapFlightMasters = true
setMapShown(true)
local flights = ns.Canvas.Pools(WorldMapFrame).ShortestPathForeverFlightPinTemplate
viewRect = { left = -0.25, right = 2, top = 0, bottom = 1 }
mapTick()
assert(flights:GetNumActive() == 2, "The stitched view shows flights on both continents")
local easternPin = flights.active[1].poiInfo.nodeID == 2 and flights.active[1] or flights.active[2]
easternPin:SetPressed(true)
local initialQueries, initialProjections = queries, projections
local hostZoom = zoom
companionVisible = true
zoom = 0.5
mapTick()
assert(flights:GetNumActive() == 1 and flights.active[1] == easternPin and easternPin.pressed,
	"Showing a companion flight pin preserves the unaffected pressed pin")
companionVisible = false
zoom = hostZoom
mapTick()
assert(flights:GetNumActive() == 2 and easternPin.pressed, "Hiding the companion pin restores the SPF flight pin")
assert(queries == initialQueries and projections == initialProjections,
	"Companion changes reuse taxi queries and world projections")
viewRect = { left = 1, right = 2.25, top = 0, bottom = 1 }
mapTick()
assert(flights:GetNumActive() == 1, "Panning updates flight pins with the same host map")
local flight = flights.active[1]
local flightX, flightY = flight:GetPosition()
assert(flight == easternPin and easternPin.pressed, "Panning preserves a visible flight pin and its press")
assert(flight.poiInfo.nodeID == 2 and flightX == 1.5 and flightY == 0.5, "The pin uses OpenMap's canvas position")
local halfWidth = easternPin:GetWidth() * easternPin:GetScale() / (2 * canvas:GetWidth())
viewRect.left = flightX + halfWidth / 2
mapTick()
assert(flights:GetNumActive() == 1 and flights.active[1] == easternPin, "A partly visible flight icon stays drawn")
viewRect.left = flightX + halfWidth * 2
mapTick()
assert(flights:GetNumActive() == 0, "A flight icon fully outside the view is removed")
stitched = false
mapTick()
assert(flights:GetNumActive() == 1 and flights.active[1].poiInfo.nodeID == 1, "The regular map shows its zone's pin")

setMapShown(false)
ns.db.mapFlightMasters = flightMasters
ns.TaxiNodes = taxiNodes
mapID = hostMap
viewRect = { left = 0, right = 1, top = 0, bottom = 1 }
stitched = true
OpenMapAPI.CanvasFromWorldPos = normalProjection
ns.CompanionMaps.Scan, ns.CompanionMaps.Suppresses = scan, suppresses
C_TaxiMap.GetTaxiNodesForMap = queryTaxi
setMapShown(true)

local goals = ns.Canvas.Pools(WorldMapFrame).ShortestPathForeverGoalPinTemplate
local lines = ns.Canvas.Pools(WorldMapFrame).ShortestPathForeverRoutePinTemplate
local x, y, title = 0.55, 0.5, "Destination"
local function checkGoalPin(label)
	assert(goals:GetNumActive() == 1, label .. " has one SPF goal pin")
	local pin = goals.active[1]
	assert(pin:IsVisible() and not pin.Texture.hidden, label .. " shows the SPF goal marker")
	assert(pin.mouseEnabled, label .. " keeps SPF's goal hit area")
	local px, py = pin:GetPosition()
	assert(px == x and py == y, label .. " uses the same coordinates")
	return pin
end

assert(TomTom:AddWaypoint(mapID, x, y, { title = title, from = "TomTom/way" }))
settle()
local prior = checkGoalPin("A TomTom waypoint")
ns.SetOption("worldMapMarks", false)
assert(not prior:IsVisible(), "Turning off world map marks hides the active goal pin")
assert(not lines.active[1]:IsVisible(), "Turning off world map marks hides the route overlay")
assert(ns.HasJourney(), "Hiding world map marks keeps the journey active")
fireEvent("PLAYER_REGEN_DISABLED")
ns.SetOption("worldMapMarks", true)
assert(prior:IsVisible(), "Enabling world map marks in combat shows the route last drawn (#1302)")
fireEvent("PLAYER_REGEN_ENABLED")
checkGoalPin("World map marks enabled again")
prior = goals.active[1]


local openPin = assert(TomTom:AddWaypoint(mapID, x, y, { title = title, from = "OpenMap" }))
runPending()
assert(goals:GetNumActive() == 0, "A followed OpenMap pin has no duplicate SPF goal marker")
assert(not prior:IsVisible(), "The released SPF frame cannot take mouse input")
assert(ns.HasJourney() and lines:GetNumActive() > 0, "SPF still draws the route to the OpenMap pin")

stitched = false
mapTick()
checkGoalPin("An OpenMap waypoint on the regular map")
stitched = true
mapTick()
assert(goals:GetNumActive() == 0, "The duplicate stays gone when the stitched map returns")

assert(TomTom:RemoveWaypoint(openPin))
assert(not ns.HasJourney(), "Removing the OpenMap pin cancels its own route")

openPin = assert(TomTom:AddWaypoint(mapID, x, y, { title = title, from = "OpenMap" }))
settle()
assert(TomTom:AddWaypoint(mapID, x, y, { title = title, from = "TomTom/way" }))
runPending()
checkGoalPin("TomTom taking over at the same coordinates")
assert(not TomTom:RemoveWaypoint(openPin), "An old OpenMap handle cannot clear a TomTom waypoint")

assert(TomTom:AddWaypoint(mapID, x, y, { title = title, from = "OpenMap" }))
runPending()
assert(ShortestPathForever.API.Navigate("OpenMap", mapID, x, y))
runPending()
checkGoalPin("A map click forwarded by OpenMap")

assert(TomTom:AddWaypoint(mapID, x, y, { title = title, from = "OpenMap" }))
cursorX, cursorY = x, y
assert(clickHandlers[1](WorldMapFrame, "LeftButton"))
settle()
assert(waypoint and supertracked, "Guide places the native waypoint OpenMap mirrors")
local addonLoaded = C_AddOns.IsAddOnLoaded
function C_AddOns.IsAddOnLoaded(name)
	return name == "OpenMap" or addonLoaded(name)
end
-- OpenMap draws the followed waypoint in its tracked look on a child of the map's view.
function canvas:GetChildren()
	return unpack(self.children)
end
local mirror = CreateFrame("Button", nil, canvas)
mirror.u, mirror.v, mirror.look = x, y, { atlas = "Waypoint-MapPin-Tracked" }
local function scanMap()
	T = T + 0.25
	mapTick()
end
scanMap()
assert(goals:GetNumActive() == 0, "OpenMap's mirrored waypoint is the only marker at the guided stop")
stitched = false
mapTick()
checkGoalPin("An SPF map click on the regular map")
stitched = true
scanMap()
assert(goals:GetNumActive() == 0, "Returning to the stitched map removes the duplicate")
-- A hidden OpenMap saved pin can consume OpenMap's representation of the native waypoint.
-- The waypoint still projects onto the map, but OpenMap supplies no visible marker for it.
mirror:Hide()
scanMap()
checkGoalPin("A waypoint with no visible OpenMap marker")
mirror:Show()
scanMap()
assert(goals:GetNumActive() == 0, "Showing the mirror removes the duplicate")
local goal = ns.JourneyGoal()
local bend = { map = goal.map, x = goal.x - 50, y = goal.y }
ns.db.guideStops = false
ns.JourneyGuide.To(bend, { bend }, goal)
checkGoalPin("An OpenMap waypoint on a bend")
mirror:Hide()



assert(TomTom:AddWaypoint(mapID, x, y, { title = title, from = "OpenMap" }))
ns.db.tomtom = false
ns.RefreshTomTom()
assert(not ns.HasJourney(), "Disabling the shim cancels the OpenMap route it owns")

ns.db.tomtomFollow = true
_G.TomTom = assert(loadfile("tests/tomtom_fake.lua"))().New()
fireEvent("ADDON_LOADED", "TomTom")
local followed = assert(TomTom:AddWaypoint(mapID, x, y, { title = title, from = "OpenMap" }))
settle()
assert(ns.HasJourney() and goals:GetNumActive() == 0, "Following TomTom preserves an OpenMap pin's source")
TomTom:RemoveWaypoint(followed)
assert(not ns.HasJourney(), "Removal through installed TomTom cancels the OpenMap route")

assert(#errors == 0, table.concat(errors, "\n"))
print("openmap_pin_spec: ownership handoffs, goal visibility and mouse input passed")
]]))()

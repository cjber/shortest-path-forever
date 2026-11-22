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
assert(not prior:IsVisible(), "Enabling world map marks in combat leaves them hidden")
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
checkGoalPin("An SPF map click")

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

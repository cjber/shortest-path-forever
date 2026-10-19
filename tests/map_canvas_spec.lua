-- Run from the repository root: luajit tests/map_canvas_spec.lua
-- The addon's world map drawing (UI/MapCanvas.lua, #158) against the UI fixture: it writes nothing into the map, makes
-- no frame inside an open window, gives the gamepad's navigation no button to find, and keeps every pin's behaviour:
-- placing and scaling, hover and tooltip (with the mouse and with the gamepad's map cursor), clicks, Shift-click,
-- the right button passed through, combat, and the markers the other Forever addons read.
local dir = arg[0]:match("^(.*)/") or "tests"

local probe = "tools/.cache/blizzard-ui/Interface/AddOns/Blizzard_SharedXML/Spinner.lua"
do
	local handle = io.open(probe)
	if handle then
		handle:close()
	else
		local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
		assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture for tests/map_canvas_spec.lua")
	end
end

local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

-- Before the addon's Init runs: the world map takes no new field, the gamepad interface can be switched on, and every
-- frame the addon makes is recorded with the parent it was made under.
local guard = [==[
local made = {}
do
	local create = CreateFrame
	_G.CreateFrame = function(frameType, name, parent, template)
		local frame = create(frameType, name, parent, template)
		made[#made + 1] = { frame = frame, parent = parent, template = template }
		function frame:SetPassThroughButtons(...)
			self.passThrough = { ... }
		end
		function frame:SetHighlightLocked(value)
			self.highlightLocked = value
		end
		function frame:SetFrameLevel(level)
			self.frameLevel = level
		end
		function frame:GetFrameLevel()
			return self.frameLevel or 1
		end
		return frame
	end
end
local gamepad = false
-- JourneyInput.lua's Alt-click watches the same global mouse events.
_G.IsAltKeyDown = function()
	return false
end
Enum.InputDeviceInterfaceType = { KeyboardAndMouse = 0, Gamepad = 1 }
_G.C_InputInterfaceStyle = {
	GetCurrentStyle = function()
		return gamepad and 1 or 0
	end,
}
setmetatable(WorldMapFrame, {
	__index = getmetatable(WorldMapFrame).__index,
	__newindex = function(_, key)
		error("the addon wrote WorldMapFrame." .. tostring(key), 2)
	end,
})
]==]
local fixture = source:gsub('fireEvent%("ADDON_LOADED", "ShortestPathForever"%)', function()
	return guard .. '\nfireEvent("ADDON_LOADED", "ShortestPathForever")'
end, 1)

assert(loadstring(fixture .. [==[
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
local function noErrors(label)
	check(#errors == 0, label .. ": " .. table.concat(errors, "\n"))
end

-- Every value reachable from the map, two tables deep: what the map holds before and after must be the same.
local function snapshot(value, depth, seen)
	if type(value) ~= "table" or depth == 0 then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for key, inner in pairs(value) do
		copy[key] = snapshot(inner, depth - 1, seen)
	end
	return copy
end
local function same(a, b, path)
	if type(a) ~= "table" or type(b) ~= "table" then
		check(a == b, "the map's " .. path .. " changed")
		return
	end
	for key, inner in pairs(a) do
		same(inner, b[key], path .. "." .. tostring(key))
	end
	for key in pairs(b) do
		check(a[key] ~= nil, "the map took a new field " .. path .. "." .. tostring(key))
	end
end
local before = snapshot(WorldMapFrame, 3)
local providersBefore = #providers

-- Docks, portals and flight points to draw: the fixture's dock 1, a portal, and the flight points near it.
ns.db.pins, ns.db.transit, ns.db.portals, ns.db.mapFlightMasters, ns.db.mapRoutes = true, true, true, true, true
posX, posY, posMap, facing = 0, 0, 1, 0
shiftDown = false
mapID, zoom = 1414, 0
setMapShown(true)
ns.RefreshMap()
noErrors("open the map")
local pools = ns.MapCanvas.Pools(WorldMapFrame)
local docks = pools.ShortestPathForeverDockPinTemplate
local flights = pools.ShortestPathForeverFlightPinTemplate
check(docks:GetNumActive() > 0, "the map shows docks")
-- The fixture's flight points stand on zone 14, under continent 1414.
mapID = 14
mapTick()
check(flights:GetNumActive() > 0, "the zone map shows flight points")
mapID = 1414
mapTick()
check(flights:GetNumActive() == 0 and docks:GetNumActive() > 0, "the continent shows the docks again")

--[[ Nothing made inside the map, nothing the gamepad reads as a button ]]
local view = ns.MapCanvas.Watch(WorldMapFrame)
for _, record in ipairs(made) do
	check(record.parent ~= canvas, "a frame was made under the map's canvas")
	if record.frame.parent == view.layer or record.frame == view.host then
		check(record.parent == nil, "a map frame of the addon's was made with a parent")
	end
end
check(#canvas.children == 1 and canvas.children[1] == view.host, "one frame of the addon's on the canvas")
local pinCount = 0
for _, pool in pairs(pools) do
	for pin in pool:EnumerateActive() do
		pinCount = pinCount + 1
		check(pin.parent == view.layer, "a pin sits on the view's layer")
		for _, script in ipairs({ "OnClick", "OnMouseDown", "OnMouseUp", "OnDoubleClick" }) do
			check(pin.scripts[script] == nil, "a pin with a " .. script .. " script is a button to the gamepad")
		end
		for _, key in ipairs({ "owningMap", "pinTemplate", "dataProvider" }) do
			check(rawget(pin, key) == nil, "a pin carries the map's key " .. key)
		end
	end
end
check(pinCount > 0, "pins to look at")

--[[ OpenMap's stitched map: the pins are lifted over its art, and the layers redraw ]]
local heard = {}
view.listeners[#view.listeners + 1] = function(_, what)
	heard[#heard + 1] = what
end
check(view:Level("PIN_FRAME_LEVEL_DOCK", 1) < 9000, "under Blizzard's own pin levels before OpenMap")
_G.OpenMapAPI = {
	major = 1,
	version = 2,
	IsStitched = function()
		return true
	end,
	ArtTopLevel = function()
		return 9000
	end,
}
mapTick()
check(view.stitched == true and heard[#heard] == "map", "OpenMap's stitched map redraws the layers")
check(view:Level("PIN_FRAME_LEVEL_DOCK", 1) > 9000, "a pin over the stitched art is lifted above it")
local lifted = true
for _, pool in pairs(pools) do
	for pin in pool:EnumerateActive() do
		lifted = lifted and pin.frameLevel > 9000
	end
end
check(lifted, "pins already drawn are lifted too")
_G.OpenMapAPI = nil
mapTick()
check(view.stitched == false and view:Level("PIN_FRAME_LEVEL_DOCK", 1) < 9000, "and put back when it stops")

--[[ Placing and scaling, as MapCanvasPinMixin ]]
local function placed(pin)
	local scale = Lerp(pin.startScale, pin.endScale, zoom) / (0.5 + zoom * 1.5) * 1.4
	check(math.abs(pin.scale - scale) < 1e-9, "a pin's scale keeps its size on screen: " .. pin.scale .. " " .. scale)
	local anchor = pin.anchor
	check(anchor[1] == "CENTER" and anchor[2] == canvas and anchor[3] == "TOPLEFT", "placed on the canvas")
	check(math.abs(anchor[4] - 1000 * pin.mapX / pin.scale) < 1e-9, "at its map fraction across")
	check(math.abs(anchor[5] + 700 * pin.mapY / pin.scale) < 1e-9, "and down")
end
local dock = docks.active[1]
placed(dock)
zoom = 1
mapTick()
noErrors("zoom in")
placed(docks.active[1])
canvas.width = 1200
mapTick()
noErrors("resize")
check(math.abs(docks.active[1].anchor[4] - 1200 * docks.active[1].mapX / docks.active[1].scale) < 1e-9, "resized")
canvas.width = 1000
mapTick()
zoom = 0
mapTick()
dock = docks.active[1]

--[[ Hover with the mouse, and the right button passed through ]]
check(dock.passThrough and dock.passThrough[1] == "RightButton", "a dock passes the right button to the canvas")
dock.scripts.OnEnter(dock)
check(GameTooltip.owner == dock and GameTooltip.shown, "hovering a dock shows its tooltip")
dock.scripts.OnLeave(dock)
check(not GameTooltip.shown, "leaving it hides the tooltip")

--[[ A click is a press and release over the hovered pin ]]
local clicked
local action = dock.OnMouseClickAction
dock.OnMouseClickAction = function(_, button)
	clicked = button
end
function dock.IsMouseOver()
	return true
end
dock.scripts.OnEnter(dock)
local clicks
for _, frame in ipairs(frames) do
	if frame.events and frame.events.GLOBAL_MOUSE_UP and frame.events.GLOBAL_MOUSE_DOWN then
		clicks = frame
	end
end
check(clicks, "an open map listens for the mouse")
fireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
fireEvent("GLOBAL_MOUSE_UP", "LeftButton")
check(clicked == "LeftButton", "a left click reaches the dock")
clicked = nil
fireEvent("GLOBAL_MOUSE_DOWN", "RightButton")
fireEvent("GLOBAL_MOUSE_UP", "RightButton")
check(clicked == nil, "a right click goes through to the canvas, to zoom out")
fireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
dock.scripts.OnLeave(dock)
fireEvent("GLOBAL_MOUSE_UP", "LeftButton")
check(clicked == nil, "a press that leaves the pin is no click")
dock.scripts.OnLeave(dock)
fireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
fireEvent("GLOBAL_MOUSE_UP", "LeftButton")
check(clicked == nil, "a click over no pin of ours is the map's")
dock.OnMouseClickAction, dock.IsMouseOver = action, nil
noErrors("clicks")

--[[ Shift-click on the addon's own pins plans a journey there ]]
mapID = 14
mapTick()
local flight = flights.active[1]
local startJourney, planned = ns.StartJourney, nil
ns.StartJourney = function(point)
	planned = point
end
shiftDown = true
clickPin(flight, "LeftButton")
local node = ns.TaxiNodes[flight.poiInfo.nodeID]
check(planned and planned.x == node.x and planned.y == node.y, "Shift-clicking a flight point plans a journey to it")
check(planned.pinBadge and planned.label == flight.poiInfo.name, "named, with the clicked icon's corner tag")
planned = nil
clickPin(docks.active[1], "LeftButton")
check(planned and planned.pinBadge, "and a dock, where it stands")
shiftDown, ns.StartJourney = false, startJourney

--[[ A flight point super-tracks on a zone map; above one, its click goes through to zoom in ]]
check(flight.passThrough and #flight.passThrough == 0, "on a zone a flight point keeps both buttons")
clickPin(flight, "LeftButton")
local kind, id = C_SuperTrack.GetSuperTrackedMapPin()
check(kind == Enum.SuperTrackingMapPinType.TaxiNode and id == flight.poiInfo.nodeID, "a click super-tracks it")
check(not flight.SuperTrackGlow.hidden and not flight.SuperTrackMarker.hidden, "wearing the glow and marker")
clickPin(flight, "LeftButton")
check(C_SuperTrack.GetSuperTrackedMapPin() == nil and flight.SuperTrackGlow.hidden, "a second click lets it go")
mapID = 1414
mapTick()
local above = flights:Acquire({
	nodeID = flight.poiInfo.nodeID,
	name = "Above",
	position = CreateVector2D(0.5, 0.5),
	faction = Enum.FlightPathFaction.Neutral,
	atlasName = "taxinode_neutral",
})
check(above.passThrough[1] == "LeftButton" and #above.passThrough == 1, "on a continent its left click zooms in")
clickPin(above, "LeftButton")
check(C_SuperTrack.GetSuperTrackedMapPin() == nil, "no super-tracking from a continent")
context = {}
clickPin(above, "RightButton")
check(context["Flight path known"], "and its right click is still the menu's alone")
flights:Release(above)
noErrors("flight clicks")

--[[ The game's own flight points, where it draws them, are its own ]]
mapID = 14
mapTick()
local nodeID = flights.active[1].poiInfo.nodeID
C_TaxiMap.ShouldMapShowTaxiNodes = function()
	return true
end
C_TaxiMap.GetTaxiNodesForMap = function()
	return { { nodeID = nodeID, name = "Native", atlasName = "", textureKit = "" } }
end
ns.RefreshMap()
for pin in flights:EnumerateActive() do
	check(pin.poiInfo.nodeID ~= nodeID, "no second pin over the game's own flight point")
end
C_TaxiMap.ShouldMapShowTaxiNodes = function()
	return false
end
C_TaxiMap.GetTaxiNodesForMap = function()
	return {}
end
ns.RefreshMap()
check(flights:GetNumActive() > 0, "flight points are back")

--[[ The gamepad's map cursor hovers the nearest pin within reach ]]
gamepad, mapID = true, 1414
setMapShown(false)
setMapShown(true)
dock = docks.active[1]
local cursor = { x = 400, y = 300, shown = true }
_G.SoftCursor = {
	IsShown = function()
		return cursor.shown
	end,
	GetRect = function()
		return cursor.x - 8, cursor.y - 8, 16, 16
	end,
	GetEffectiveScale = function()
		return 1
	end,
}
function dock.GetCenter()
	return 405 / dock:GetEffectiveScale(), 296 / dock:GetEffectiveScale()
end
mapTick()
check(GameTooltip.owner == dock and dock.highlightLocked, "the map cursor over a dock shows its tooltip")
cursor.x = 600
mapTick()
check(not GameTooltip.shown and dock.highlightLocked == false, "moving the cursor away leaves it")
cursor.x = 400
mapTick()
check(GameTooltip.owner == dock, "back over it")
local other = docks.active[2]
check(other, "a second dock for the mouse")
cursor.shown = false
mapTick()
other.scripts.OnEnter(other)
mapTick()
check(GameTooltip.owner == other, "with the map cursor away, the mouse's hover stays")
other.scripts.OnLeave(other)
cursor.shown = true
setMapShown(false)
check(not GameTooltip.shown, "closing the map leaves the hovered pin")
dock.GetCenter, _G.SoftCursor, gamepad = nil, nil, false
setMapShown(true)
noErrors("gamepad")

--[[ The markers the other Forever addons read ]]
check(type(ForeverMapMarkers) == "table", "the shared list exists")
mapID = 14
mapTick()
local markers = ForeverMapMarkers.ShortestPathForever(WorldMapFrame)
local kinds = {}
for _, marker in ipairs(markers) do
	check(type(marker.x) == "number" and type(marker.y) == "number", "a marker is a map fraction")
	kinds[marker.kind] = true
end
check(kinds.flight, "flight points are listed")
mapID = 1414
mapTick()
kinds = {}
for _, marker in ipairs(ForeverMapMarkers.ShortestPathForever(WorldMapFrame)) do
	kinds[marker.kind] = true
end
check(kinds.dock and not kinds.flight, "on the continent, its docks")
check(#ForeverMapMarkers.ShortestPathForever({}) == 0, "a map the addon does not draw on lists nothing")

--[[ Combat hides every pin at once and draws nothing until it ends ]]
combat = true
fireEvent("PLAYER_REGEN_DISABLED")
check(not view.layer:IsShown(), "combat hides the addon's pins")
check(#ForeverMapMarkers.ShortestPathForever(WorldMapFrame) == 0, "and lists none")
zoom = 1
mapTick()
combat = false
fireEvent("PLAYER_REGEN_ENABLED")
check(view.layer:IsShown() and docks:GetNumActive() > 0, "back after combat")
zoom = 0
mapTick()
noErrors("combat")

--[[ A journey with stops, a crossing's far end pinged, and the map closed ]]
assert(ShortestPathForever.API.NavigateRoute("Test", {
	{ map = 1414, x = 0.51, y = 0.5, title = "First" },
	{ map = 1414, x = 0.55, y = 0.5, title = "Second" },
}))
settle()
check(pools.ShortestPathForeverGoalPinTemplate:GetNumActive() == 2, "the stops' buttons")
check(pools.ShortestPathForeverRoutePinTemplate:GetNumActive() == 1, "the line")
local stop = pools.ShortestPathForeverGoalPinTemplate.active[1]
check(stop.passThrough and #stop.passThrough == 0, "a stop keeps its right click, to clear")
for pin in pools.ShortestPathForeverGoalPinTemplate:EnumerateActive() do
	pin.scripts.OnEnter(pin)
	pin.scripts.OnLeave(pin)
end
clickPin(stop, "RightButton")
check(not ns.HasJourney(), "right-clicking a stop clears the journey")
for pin in docks:EnumerateActive() do
	pin.scripts.OnEnter(pin)
	context = {}
	clickPin(pin, "LeftButton")
	pin.scripts.OnLeave(pin)
end
noErrors("journey and docks")
setMapShown(false)
noErrors("close")

--[[ After all of it, the map holds what it held ]]
-- `shown` is the fixture's own switch for the map's IsShown, which the checks above turned.
before.shown = WorldMapFrame.shown
same(before, snapshot(WorldMapFrame, 3), "WorldMapFrame")
check(#providers == providersBefore, "no data provider was added")
for template in pairs(nativeActive) do
	check(not template:match("^ShortestPathForever"), "the map's pools hold a template of the addon's")
end
noErrors("end")
print(("map_canvas_spec: %d checks: no map writes, own frames, scaling, hover, clicks, gamepad, markers ok"):format(
	checks
))
]==]))()

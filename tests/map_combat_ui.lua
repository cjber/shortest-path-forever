-- Combat keeps the addon's world map pins and route as last drawn and redraws them once it ends (#1151, #1302). The
-- client is not yet in lockdown while it delivers PLAYER_REGEN_DISABLED, and no longer is at PLAYER_REGEN_ENABLED, so
-- the handler has to go by the event, not by InCombatLockdown().
local source = ""
for _, part in ipairs({ "tests/ui_client.lua", "tests/ui_map.lua" }) do
	local file = assert(io.open(part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [[
mapID = 1415
setMapShown(true)
local layer = ns.Canvas.Watch(WorldMapFrame).layer
assert(layer:IsShown(), "the pins show before combat")
local redraws = 0
local refreshFlightPins = ns.RefreshFlightPins
ns.RefreshFlightPins = function(...)
	redraws = redraws + 1
	return refreshFlightPins(...)
end
combat = false
fireEvent("PLAYER_REGEN_DISABLED")
assert(layer:IsShown(), "entering combat keeps the map pins")
combat = true
ns.RefreshMap()
ns.RefreshMap()
assert(redraws == 0, "nothing redraws in combat, got " .. redraws)
assert(layer:IsShown(), "a refresh in combat keeps the map pins")
-- Frozen pins take no hover, so no click reaches a waypoint, super-track or highlight call in lockdown.
local pin
for _, candidate in ipairs(ns.Canvas.Pools(WorldMapFrame).ShortestPathForeverDockPinTemplate.active) do
	pin = pin or candidate
end
assert(pin and pin.scripts.OnEnter, "the map has a pin to hover")
local entered = 0
local onMouseEnter = pin.OnMouseEnter
pin.OnMouseEnter = function(...)
	entered = entered + 1
	return onMouseEnter(...)
end
pin.scripts.OnEnter(pin)
assert(entered == 0, "a pin takes no hover in combat")
-- Another map would place the frozen pins wrongly: they hide there and come back on the map they were drawn for.
mapID = 1429
mapTick()
assert(not layer:IsShown(), "the frozen pins hide over another map")
mapID = 1415
mapTick()
assert(layer:IsShown(), "the frozen pins show again over their own map")
-- The map turns asked each layer to redraw; in combat each only queued.
redraws = 0
combat = false
fireEvent("PLAYER_REGEN_ENABLED")
assert(redraws == 1, "leaving combat redraws once, got " .. redraws)
assert(layer:IsShown(), "the pins show after combat")
pin = nil
for _, candidate in ipairs(ns.Canvas.Pools(WorldMapFrame).ShortestPathForeverDockPinTemplate.active) do
	pin = pin or candidate
end
local afterEnter = pin.OnMouseEnter
pin.OnMouseEnter = function(...)
	entered = entered + 1
	return afterEnter(...)
end
pin.scripts.OnEnter(pin)
assert(entered >= 1, "a pin hovers again after combat")
pin.scripts.OnLeave(pin)
fireEvent("PLAYER_REGEN_ENABLED")
assert(redraws == 1, "a second combat end with nothing queued redraws nothing, got " .. redraws)
assert(#errors == 0, table.concat(errors, "\n"))
print("map combat ok")
]], "map_combat_ui"))()

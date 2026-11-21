-- Combat hides the addon's world map pins and brings them back when it ends (#1151). The client is not yet in
-- lockdown while it delivers PLAYER_REGEN_DISABLED, and no longer is at PLAYER_REGEN_ENABLED, so the handler has to
-- go by the event, not by InCombatLockdown().
local source = ""
for _, part in ipairs({ "tests/ui_client.lua", "tests/ui_map.lua" }) do
	local file = assert(io.open(part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [[
mapID = 1429
setMapShown(true)
local layer = ns.Canvas.Watch(WorldMapFrame).layer
assert(layer:IsShown(), "the pins show before combat")
combat = false
fireEvent("PLAYER_REGEN_DISABLED")
assert(not layer:IsShown(), "entering combat hides the map pins")
combat = true
ns.RefreshMap()
combat = false
fireEvent("PLAYER_REGEN_ENABLED")
assert(layer:IsShown(), "leaving combat shows them again")
assert(#errors == 0, table.concat(errors, "\n"))
print("map combat ok")
]], "map_combat_ui"))()

-- Combat freezes the addon's world map pins and route line instead of hiding them (#1302). The client is not yet in
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
local view = ns.Canvas.Watch(WorldMapFrame)
local layer = view.layer
assert(layer:IsShown(), "the pins show before combat")

-- Count every visual change the map makes: the layer's own shown state, and each pin pool's acquire or release.
local draws = 0
local setShown = ns.Canvas.SetShown
ns.Canvas.SetShown = function(...)
 draws = draws + 1
 return setShown(...)
end
local pools = ns.Canvas.Pools(WorldMapFrame)
local originals = {}
for key, pool in pairs(pools) do
 local acquire, releaseAll = pool.Acquire, pool.ReleaseAll
 originals[key] = {acquire, releaseAll}
 pool.Acquire = function(self, ...) draws = draws + 1 return acquire(self, ...) end
 pool.ReleaseAll = function(self, ...) draws = draws + 1 return releaseAll(self, ...) end
end

-- A refresh outside combat reaches the drawing code.
ns.RefreshMap()
assert(draws > 0, "a refresh outside combat draws")
draws = 0

-- Entering combat leaves the last drawn layer exactly as it was.
fireEvent("PLAYER_REGEN_DISABLED")
assert(draws == 0 and layer:IsShown(), "entering combat neither hides nor redraws the map pins")
assert(ns.mapRefreshPending, "entering combat queues the refresh")
combat = true

-- Every request during combat queues, with no draw at all.
ns.RefreshMap()
ns.RefreshMap()
assert(draws == 0 and layer:IsShown(), "a refresh in combat draws nothing")
assert(ns.mapRefreshPending, "a refresh in combat stays queued")

-- One refresh reaches the drawing code when combat ends, and everything stays shown.
combat = false
fireEvent("PLAYER_REGEN_ENABLED")
assert(draws > 0 and layer:IsShown(), "combat end refreshes once and keeps the pins shown")
assert(not ns.mapRefreshPending, "combat end clears the queued refresh")

-- Restore the counters so later checks see the plain canvas.
ns.Canvas.SetShown = setShown
for key, pool in pairs(pools) do
 pool.Acquire, pool.ReleaseAll = originals[key][1], originals[key][2]
end
assert(#errors == 0, table.concat(errors, "\n"))
print("map combat ok")
]], "map_combat_ui"))()

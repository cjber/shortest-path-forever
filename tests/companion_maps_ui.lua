-- Ordinary companion layers step aside while active journey guidance remains visible.
local source = ""
for _, part in ipairs({ "tests/ui_client.lua", "tests/ui_map.lua" }) do
	local file = assert(io.open(part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [[
mapID = 14
setMapShown(true)
local dock = "ShortestPathForeverDockPinTemplate"
local flight = "ShortestPathForeverFlightPinTemplate"
local goal = "ShortestPathForeverGoalPinTemplate"
local function count(template) return #(active[template] or {}) end
ns.db.mapFlightMasters = true
ns.RefreshMap()
local docks, flights = count(dock), count(flight)
assert(docks > 0 and flights > 0, "fixture has ordinary docks and flight masters")
assert(ShortestPathForever.API.Navigate("CompanionTest", 14, 0.51, 0.5, "Destination"))
settle()
assert(count(goal) == 1)
C_AddOns.IsAddOnLoaded = function(name) return name == "Leatrix_Maps" end
local originalChildren = canvas.GetChildren
local px, py = active[flight][1]:GetPosition()
local nativePin = { isLeaMapsPin = true, data = { "FlightA" }, shown = true,
 IsVisible = function(self) return self.shown end,
 GetEffectiveScale = function() return canvas:GetEffectiveScale() end,
 GetCenter = function() return px * canvas:GetWidth(), 1000 - py * canvas:GetHeight() end,
}
canvas.GetLeft, canvas.GetTop = function() return 0 end, function() return 1000 end
canvas.GetChildren = function() return nativePin end
T = T + 1
mapTick()
assert(count(goal) == 1, "active journey destination remains visible")
assert(count(flight) < flights, "visible matching companion replaces flight pin")
assert(count(dock) == docks, "flight companion cannot hide transport docks")
nativePin.shown = false
T = T + 1
mapTick()
assert(count(flight) == flights and count(dock) == docks, "hidden companion restores original layers")
setMapShown(false)
setMapShown(true)
assert(count(goal) == 1, "reopening keeps journey guidance")
canvas.GetChildren = originalChildren
assert(#errors == 0, table.concat(errors, "\n"))
print("companion_maps_ui: suppression, restoration, reopen and active guidance passed")
]]))()

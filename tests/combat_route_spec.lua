-- A route settled with the map closed can be drawn when it opens in combat and reprojected onto another map.
if not os.getenv("SPF_BLIZZARD_UI") then
	local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
	assert(ok == true or ok == 0, "could not fetch the pinned Blizzard UI fixture")
end

local source = ""
for _, part in ipairs({ "tests/ui_client.lua", "tests/ui_map.lua" }) do
	local file = assert(io.open(part))
	source = source .. file:read("*a")
	file:close()
end

assert(loadstring(source .. [[
local lines = active.ShortestPathForeverRoutePinTemplate
local goals = active.ShortestPathForeverGoalPinTemplate
local function hasLine(id)
	local line = lines[1]
	return line and line:IsVisible() and line.drawMap == id and line.used > 0
end

posX, posY, posZ, posMap = 0, 0, 0, 1
zoom = 1
local function routeTo(x)
	local point = assert(ns.WorldPoint(1414, x, 0.5))
	ns.StartJourney(point)
	settle()
	assert(ns.JourneyPlan(), "the journey has finished planning")
end

routeTo(0.56)
local goalPool = ns.Canvas.Pools(WorldMapFrame).ShortestPathForeverGoalPinTemplate
local acquire = goalPool.Acquire
function goalPool:Acquire(...)
	assert(not combat, "combat does not acquire interactive pins")
	return acquire(self, ...)
end

-- The first opening can paint an already settled route without creating or reparenting any frames.
local frameCount = #frames
fireEvent("PLAYER_REGEN_DISABLED")
combat = true
setMapShown(true)
assert(hasLine(1414), "the map's first opening in combat paints the current route")
assert(#frames == frameCount and #goals == 0, "opening in combat reuses the painter and defers the goal pin")
-- Only a pin that takes the mouse reaches SetPassThroughButtons, which combat protects (UI/Canvas.lua).
assert(not lines[1].takesMouse, "the line painted in combat takes no mouse")
combat = false
fireEvent("PLAYER_REGEN_ENABLED")
assert(goals[1] and goals[1]:IsVisible(), "the queued goal pin appears after combat")

-- Then replace that route with the map closed. The new route must not inherit the old drawing.
setMapShown(false)
routeTo(0.60)
fireEvent("PLAYER_REGEN_DISABLED")
combat = true
setMapShown(true)
assert(hasLine(1414), "reopening in combat paints a route")
local points = lines[1].paths[1].points
assert(points[#points].y == ns.JourneyGoal().y, "reopening shows the latest route")
assert(not goals[1]:IsVisible(), "the old destination pin is hidden")

-- The zone and continent in the fixture both cover the route.
mapID = 14
mapTick()
assert(hasLine(14), "changing maps in combat reprojects the current route")
ns.db.worldMapMarks = false
ns.ShowMapPins()
assert(not hasLine(14), "the Show Shortest Path marks switch still hides the line")
ns.db.worldMapMarks = true
ns.ShowMapPins()
assert(hasLine(14), "turning the marks back on restores the projected line")
combat = false
fireEvent("PLAYER_REGEN_ENABLED")

assert(goals[1] and goals[1]:IsVisible(), "interactive stops redraw on the current map after combat")
assert(#errors == 0, table.concat(errors, "\n"))
print("combat_route_spec: current combat route is painted and reprojected")
]], "@combat_route_spec"))()

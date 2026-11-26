-- SuspendMapPins hides every pool's pins but the journey's, and the last owner's resume brings them back (#1375).
assert(os.execute("bash tools/fetch_blizzard_ui.sh") == 0, "could not fetch the pinned Blizzard UI fixture")
local source = ""
for _, part in ipairs({ "tests/ui_client.lua", "tests/ui_map.lua" }) do
	local file = assert(io.open(part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [[
mapID = 1415
setMapShown(true)
local API = ShortestPathForever.API
local function pool(key)
	return assert(ns.Canvas.Pools(WorldMapFrame)[key], key)
end
local dock = assert(pool("ShortestPathForeverDockPinTemplate").active[1], "the map has a dock pin")
local goals = pool("ShortestPathForeverGoalPinTemplate")
local function kinds()
	local found = {}
	for _, marker in ipairs(ForeverMapMarkers.ShortestPathForever(WorldMapFrame)) do
		found[marker.kind] = true
	end
	return found
end
assert(dock:IsVisible() and kinds().dock, "the dock pin shows before a hold")
assert(API.SuspendMapPins("one") == true and API.SuspendMapPins("two") == true, "two owners hold")
assert(not dock:IsVisible(), "a hold hides the marks")
assert(not kinds().dock, "a held pin is no marker for other addons")
assert(goals.parent:IsShown() and ns.Canvas.Watch(WorldMapFrame).layer:IsShown(), "the journey's pins stay")
mapID = 1429
mapTick()
mapID = 1415
mapTick()
local redrawn = assert(pool("ShortestPathForeverDockPinTemplate").active[1])
assert(not redrawn:IsVisible(), "a redraw under a hold stays hidden")
assert(API.ResumeMapPins("one") == true)
assert(not redrawn:IsVisible(), "one owner resuming leaves the other's hold")
assert(API.ResumeMapPins("two") == true)
assert(redrawn:IsVisible() and kinds().dock, "the last resume brings them back")
for _, owner in ipairs({ "  ", 7 }) do
	local ok, reason = API.SuspendMapPins(owner)
	assert(ok == nil and reason == "invalid", "an owner that is not a non-blank string is refused")
end
-- A pin without a level type, as a road or wall report mark, takes a point of interest's level, over the explored art.
ns.charDB.mapReportMarks = { { kind = "wall", map = 1415, x = 0.5, y = 0.5, world = { 0, 0, 0 } } }
mapID = 1429
mapTick()
mapID = 1415
mapTick()
local mark = assert(pool("mapReport").active[1], "the map has a report mark")
local interest = WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI", 1)
local given
function mark.SetFrameLevel(_, level)
	given = level
end
mark:ApplyFrameLevel()
assert(given == interest, "a report mark sits at the point of interest level")
assert(#errors == 0, table.concat(errors, "\n"))
print("api map pins ok")
]], "api_map_pins_spec"))()

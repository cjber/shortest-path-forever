-- Real map pins, route strokes and arrow text against the local offline client fixture.
local dir = arg[0]:match("^(.*)/") or "tests"
local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [[
setMapShown(true)
posX, posY, posMap, facing = 0, 0, 1, 0
mapID = 1414
-- Zoomed in, so the stops' rings stand apart; the overlap checks below zoom out.
zoom = 1
ns.Docks, ns.Routes, ns.TaxiNodes, ns.TaxiPaths, ns.Portals, ns.Landmasses = {}, {}, {}, {}, {}, {}
local api = ShortestPathForever.API
local lineTemplate, goalTemplate = "ShortestPathForeverRoutePinTemplate", "ShortestPathForeverGoalPinTemplate"
local stops = {
 {map=1414,x=0.51,y=0.5,title="First"},
 {map=1414,x=0.53,y=0.49,title="Second"},
 {map=1414,x=0.55,y=0.5,title="Third"},
 {map=1414,x=0.57,y=0.51,title="Last"},
}
local function tick()
 T = T + 0.1
 local driver = ShortestPathForeverJourneyDriver
 driver.scripts.OnUpdate(driver, 0.1)
 settle()
end
local function check(index, count)
 assert(api.CurrentStop("Test") == index)
 local pins = active[goalTemplate]
 assert(#pins == count-index+1)
 for i, pin in ipairs(pins) do
  -- Stops up to 25 wear the addon's gold numbered marker; later stops use the map's button and the font.
  local number = index + i - 1
  assert(pin.Texture.texture == ns.NumberFile(number) and pin.Texture.width == 24,
   "remaining pins retain their numbered markers")
  assert(pin.Button.hidden and pin.Disc.hidden and pin.Number.text == "")
  assert(pin.Texture.alpha == (i == 1 and 1 or ns.LaterAlpha), "only the stop being guided to is at full strength")
  assert(pin.alpha == nil and pin.Texture.atlas == nil, "the marker is the addon's own art")
  assert(pin.levelType == "PIN_FRAME_LEVEL_WAYPOINT_LOCATION", "stops draw above quest POIs")
  assert(pin.stopLabels[1] == stops[number].title and pin.stopNumbers[1] == number and pin.stopCount == count)
 end
 local line = active[lineTemplate][1]
 assert(line.used > 0 and line.used <= 4096)
 local preview = line.paths[#line.paths]
 assert(index == count or preview.preview and #preview.points == count-index+1)
 -- The leg being walked draws at full strength and every stroke of the later hops recedes.
 local current, later = 0, 0
 for i = 1, line.used do
  local alpha = line.lines[i].alpha
  assert(alpha == 1 or alpha == ns.LaterAlpha, "strokes are either current or later")
  if alpha == 1 then current = current + 1 else later = later + 1 end
 end
 assert(current > 0)
 assert(index == count and later == 0 or later > 0 and line.lines[line.used].alpha == ns.LaterAlpha)
 assert(line.lines[1].alpha == 1, "the current leg is drawn first, at full strength")
 assert(arrowFrame.Progress.text == string.format("Stop %d of %d: %s", index, count, stops[index].title))
 assert(ns.JourneyInfo() == arrowFrame.Progress.text)
 return line
end
assert(api.NavigateRoute("Test", stops))
settle()
local first = check(1, 4)
-- The journey's tracker block is its own switch. Off leaves the pin, the map line and the minimap route drawing, and
-- the journey still guided; the departures block answers its own switch.
local tracker = ShortestPathForeverObjectiveTracker
ns.RefreshTracker()
assert(#tracker.blocks > 0, "the journey starts with a tracker block")
ns.db.journeyTracker = false
ns.RefreshTracker()
assert(#tracker.blocks == 0, "off leaves no journey block in the objective tracker")
assert(tracker:GetContentsHeight() == 0, "an empty journey section takes no room")
assert(ns.HasJourney() and ns.IsJourneyGuided(), "the journey still plans and guides")
assert(#active[goalTemplate] == #stops and #active[lineTemplate] == 1, "its pins and map line stay")
assert(ShortestPathForeverMinimapRoute.Goal.texture == ns.PIN_FILE, "its minimap route stays")
ns.db.journeyTracker = true
ns.RefreshTracker()
assert(#tracker.blocks > 0, "on brings the journey block back")
-- The world map's own waypoint pin steps aside at an intermediate stop: it marks our waypoint, not the player's,
-- so the journey's own pins are the only ones on the map.
assert(waypointProvider.pin and not waypointProvider.pin:IsShown(), "the native waypoint pin hides at a later stop")
-- Map closure/reopening and canvas resizes keep the full itinerary, without reallocating pins.
local created = lineCreations
first:OnCanvasScaleChanged()
first:OnCanvasSizeChanged()
assert(lineCreations == created)
setMapShown(false)
setMapShown(true)
refreshMap()
check(1, 4)
for i, stop in ipairs(stops) do
 local point = ns.WorldPoint(stop.map, stop.x, stop.y)
 posX, posY = point.x, point.y
 tick()
 if i < #stops then check(i+1, 4) end
end
assert(api.CurrentStop("Test") == nil and not ns.HasJourney())
assert(#active[goalTemplate] == 0 and #active[lineTemplate] == 0)
assert(not ShortestPathForeverMinimapRoute.scripts.OnUpdate)
assert(not ShortestPathForeverJourneyDriver:IsShown() and not arrowFrame:IsShown())
-- Stops whose rings would overlap at this zoom share one ring, showing the first stop's number with its action badge
-- and naming each stop in order. A ring holding the stop being guided to sits on that stop at full strength; the rest
-- sit at their middle.
local close = {
 {map=1414,x=0.5,y=0.5,title="A"},
 {map=1414,x=0.512,y=0.5,title="B"},
 {map=1414,x=0.524,y=0.5,title="C"},
 {map=1414,x=0.536,y=0.5,title="D"},
 {map=1414,x=0.3,y=0.3,title="E"},
 {map=1414,x=0.7,y=0.7,title="F"},
 {map=1414,x=0.306,y=0.3,title="G"},
}
local function rings(expected)
 local pins = active[goalTemplate]
 assert(#pins == #expected, "one ring per group: " .. #pins)
 for i, want in ipairs(expected) do
  local pin = pins[i]
  assert(pin.Texture.alpha == (i == 1 and 1 or ns.LaterAlpha), "only the current stop's marker is at full strength")
  assert(pin.alpha == nil and pin.Disc.alpha == nil, "the marker hides the POI beneath")
  assert(#pin.stopLabels == #want.stops and pin.stopCount == 7)
  for j, n in ipairs(want.stops) do
   assert(pin.stopLabels[j] == close[n].title and pin.stopNumbers[j] == n, "the tooltip names each stop in order")
  end
  assert(pin.Texture.texture == ns.NumberFile(want.stops[1]) and pin.Number.text == "")
  assert(rawget(pin, "Count") == nil, "no text over the action badge")
  if #want.stops > 1 then
   local x = 0
   for _, n in ipairs(want.stops) do x = x + close[n].x end
   if i == 1 then
    local lead = want.stops[1]
    assert(pin.mapX == close[lead].x, "a ring holding the current stop sits on it")
   else
    assert(math.abs(pin.mapX - x / #want.stops) < 1e-9, "a shared ring sits at its stops' middle")
   end
  end
 end
 return pins
end
posX, posY = 0, 0
assert(api.NavigateRoute("Test", close))
settle()
zoom = 0
canvasScaled()
-- The current stop's ring takes the later stops overlapping it, rather than drawing over them.
local zoomedOut = rings({ {stops={1,2,3,4}}, {stops={5,7}}, {stops={6}} })
zoomedOut[1]:OnMouseEnter()
local atStop, yardsLeft = ns.JourneyLeft()
assert(atStop and tip[1] == "  Stop 1 of 7 | " .. atStop .. " · " .. yardsLeft, tip[1])
assert(tip[2] == "  A", tip[2])
assert(tip[3] == "  Stop 2 of 7" and tip[4] == "  B" and tip[7] == "  Stop 4 of 7" and tip[8] == "  D")
assert(tipColors[2] == HIGHLIGHT_FONT_COLOR and tipColors[4] == HIGHLIGHT_FONT_COLOR, "labels in white")
assert(tipColors[8] == HIGHLIGHT_FONT_COLOR, "the last shared stop's label in white")
assert(tip[#tip] == "  Right-click to clear" and tip[#tip - 1] == " " and tipColors[#tip] == NORMAL_FONT_COLOR)
zoomedOut[1]:OnMouseLeave()
-- A canvas refresh that keeps the grouping keeps the rings, hover and all.
local goalPool = ns.MapCanvas.Pools(WorldMapFrame)[goalTemplate]
local acquisitions, acquire = 0, goalPool.Acquire
goalPool.Acquire = function(self, ...) acquisitions = acquisitions + 1 return acquire(self, ...) end
canvasScaled()
assert(acquisitions == 0 and active[goalTemplate][1] == zoomedOut[1])
-- Zooming in splits the rings that no longer overlap, from the pool.
zoom = 1
canvasScaled()
goalPool.Acquire = nil
assert(acquisitions == 6 and #pools[goalTemplate] == 0, "the split reuses pooled buttons, plus three more")
rings({ {stops={1}}, {stops={2}}, {stops={3}}, {stops={4}}, {stops={5,7}}, {stops={6}} })
-- Arriving at a stop moves the full-strength ring on, still holding the later stops overlapping it.
zoom = 0
canvasScaled()
local arrive = ns.WorldPoint(close[1].map, close[1].x, close[1].y)
posX, posY = arrive.x, arrive.y
tick()
assert(api.CurrentStop("Test") == 2)
local pins = active[goalTemplate]
assert(#pins == 3 and pins[1].Texture.texture == ns.NumberFile(2))
assert(pins[1].Texture.alpha == 1 and #pins[1].stopLabels == 3)
assert(pins[1].mapX == close[2].x and pins[2].Texture.alpha == ns.LaterAlpha)
api.Cancel("Test")
zoom = 1
posX, posY = 0, 0

-- Pooled numbered pins must revert to the ordinary waypoint for a single destination.
assert(api.Navigate("Test", 1414, 0.51, 0.5, "Only"))
settle()
assert(#active[goalTemplate] == 1 and active[goalTemplate][1].Number.text == "")
assert(active[goalTemplate][1].Texture.texture == ns.PIN_FILE and active[goalTemplate][1].Texture.atlas == nil)
assert(active[goalTemplate][1].stopLabels == nil and arrowFrame.Progress.text == "")
-- Turning Guide off leaves the route and turns its goal bronze, as the game's own untracked waypoint does; turning
-- it back on returns gold, on the world map and the minimap.
ns.ToggleJourneyGuide()
settle()
assert(not ns.IsJourneyGuided() and ns.HasJourney(), "the route waits unguided")
assert(
	active[goalTemplate][1].Texture.texture == ns.PIN_INACTIVE_FILE
		and active[goalTemplate][1].Texture.atlas == nil,
	"an unguided goal wears the bronze pin"
)
assert(ShortestPathForeverMinimapRoute.Goal.texture == ns.PIN_INACTIVE_FILE, "the minimap follows it")
ns.ToggleJourneyGuide()
settle()
assert(ns.IsJourneyGuided(), "the journey guides again")
assert(active[goalTemplate][1].Texture.texture == ns.PIN_FILE, "and its goal is gold again")
assert(ShortestPathForeverMinimapRoute.Goal.texture == ns.PIN_FILE, "the minimap follows it back")

-- The destination's pin names the journey, with the time and distance left on its title line, and a one-leg trip
-- adds no step list of its own.
active[goalTemplate][1]:OnMouseEnter()
local _, rows, plan, planIndex = ns.JourneyInfo()
local left, far = ns.JourneyLeft()
assert(tip[1] == "  Journey to Only | " .. left .. " · " .. far, tip[1])
assert(#plan.legs - planIndex + 1 <= 1, "this journey is one leg")
assert(
	#rows > 0
		and #tip == 3
		and tip[2] == " "
		and tip[3] == "  Right-click to clear",
	"no step list, then a blank line and how to clear"
)
active[goalTemplate][1]:OnMouseLeave()
assert(api.Cancel("Test"))
-- A numbered stop that says what stands there keeps its numbered marker and wears that mark as a small badge over the
-- marker's lower right; a lone one wears the mark alone. The minimap only rings it. Pooled pins go back to plain.
posX, posY = 0, 0
-- The fixture's pin ring is a bare stub; record whether it is shown.
local stubIndex = mt.__index
mt.__index = function(t, k)
 if k == "SetShown" then return function(self, shown) self.hidden = not shown end end
 return stubIndex(t, k)
end
assert(api.NavigateRoute("Test", {{map=1414,x=0.51,y=0.5,title="Hand in",kind="turnin"}, stops[4]}))
settle()
local marked, plain = active[goalTemplate][1], active[goalTemplate][2]
assert(marked.Icon.atlas == "QuestTurnin" and not marked.Icon.hidden and math.abs(marked.Icon.height - 16) < 1e-9)
assert(marked.Icon.anchor[1] == "BOTTOMRIGHT" and marked.Icon.anchor[2] == 4 and marked.Icon.anchor[3] == -4)
assert(not marked.Texture.hidden and marked.Texture.texture == ns.NumberFile(1) and marked.Texture.width == 24)
assert(marked.Button.hidden and marked.Disc.hidden and marked.Number.text == "")
assert(plain.Icon.hidden and not plain.Texture.hidden and plain.Texture.texture == ns.NumberFile(2))
assert(plain.Button.hidden and plain.Disc.hidden and plain.Number.text == "")
-- The stop is off the minimap here, so its mark waits on the rim as the goal pin: a ring would circle nothing.
local miniRoute = ShortestPathForeverMinimapRoute
assert(miniRoute.goalEdge and miniRoute.Goal.texture == ns.PIN_FILE and miniRoute.Goal.atlas == nil)
-- Standing beside it, the minimap rings the game's own icon there again.
do
 local _, at = C_Map.GetWorldPosFromMapPos(1414, CreateVector2D(0.51, 0.5))
 posX, posY = at:GetXY()
 posX = posX - 20
 miniRoute.scripts.OnUpdate(miniRoute, 0.2)
 assert(not miniRoute.goalEdge and miniRoute.Goal.atlas == "adventureguide-ring")
 posX, posY = 0, 0
end
assert(api.Cancel("Test"))
assert(api.Navigate("Test", 1414, 0.51, 0.5, "Trainer", "trainer"))
settle()
-- The trainer's Class atlas fits the 22 by 22 look box at the stub atlas's 36 by 44 shape; a lone
-- stop has no number or button.
local lone = active[goalTemplate][1]
assert(
	not lone.Icon.hidden
		and lone.Icon.atlas == "Class"
		and math.abs(lone.Icon.width - 18) < 1e-9
		and lone.Icon.height == 22
		and lone.Icon.anchor[1] == "CENTER"
)
assert(lone.Texture.hidden and lone.Button.hidden and lone.Number.text == "")
mt.__index = stubIndex
assert(api.Cancel("Test"))
assert(api.Navigate("Test", 1414, 0.51, 0.5, "Only"))
settle()
assert(active[goalTemplate][1].Icon.hidden and active[goalTemplate][1].Texture.texture == ns.PIN_FILE)
assert(ShortestPathForeverMinimapRoute.Goal.texture == ns.PIN_FILE)
assert(api.Cancel("Test"))
posX, posY = 0, 0
assert(api.NavigateRoute("Test", stops))
settle()
assert(not api.Cancel("Other") and #active[goalTemplate] == 4)
-- The stop being travelled to lists the steps there under its own short count only when the trip has more than one
-- leg; a later stop names only itself.
active[goalTemplate][1]:OnMouseEnter()
local firstLeft, firstDistance = ns.JourneyLeft()
assert(tip[1] == "  Stop 1 of 4 | " .. firstLeft .. " · " .. firstDistance, tip[1])
assert(tip[2] == "  First" and tipColors[2] == HIGHLIGHT_FONT_COLOR, tip[2])
assert(tip[3] == " " and tip[4] == "  Right-click to clear" and #tip == 4, "one leg: no step list, then the hint")
active[goalTemplate][1]:OnMouseLeave()
active[goalTemplate][2]:OnMouseEnter()
assert(tip[1] == "# Stop 2 of 4" and tip[2] == "  Second" and tipColors[2] == HIGHLIGHT_FONT_COLOR)
assert(tip[3] == " " and tip[4] == "  Right-click to clear" and #tip == 4, "then a blank line and the hint")
active[goalTemplate][2]:OnMouseLeave()
active[goalTemplate][3]:OnMouseClickAction("RightButton")
assert(not api.CurrentStop("Test") and #active[goalTemplate] == 0)

-- Two stops at one place, one quest: each stop keeps its own count, action and details, a detail the earlier stop
-- already gave is not repeated, the time sits on the title line, and a one-leg trip adds no step list.
local lockboxDetails = "[17] Deep Ocean, Vast Sea\nChapter 2 of 2"
assert(api.NavigateRoute("Test", {
	{
		map = 1414,
		x = 0.51,
		y = 0.5,
		title = "Mist Veil's Lockbox",
		tooltip = lockboxDetails,
	},
	{
		map = 1414,
		x = 0.51,
		y = 0.5,
		title = "Silver Dawning's Lockbox",
		tooltip = lockboxDetails,
	},
}))
settle()
local sharedPin = active[goalTemplate][1]
assert(#active[goalTemplate] == 1 and #sharedPin.stopLabels == 2, "two stops at one place share one pin")
sharedPin:OnMouseEnter()
local sharedTime, sharedDistance = ns.JourneyLeft()
assert(tip[1] == "  Stop 1 of 2 | " .. sharedTime .. " · " .. sharedDistance, "the time is on the title line")
assert(tip[2] == "  Mist Veil's Lockbox" and tipColors[2] == HIGHLIGHT_FONT_COLOR, "the first action in white")
assert(tip[3] == "  [17] Deep Ocean, Vast Sea" and tip[4] == "  Chapter 2 of 2", "the first stop's details")
assert(tip[5] == "  Stop 2 of 2", "the second stop's count")
assert(tip[6] == "  Silver Dawning's Lockbox" and tipColors[6] == HIGHLIGHT_FONT_COLOR, "the second action in white")
assert(tip[7] == " " and tip[8] == "  Right-click to clear" and #tip == 8,
	"shared details shown once, then a blank line and the hint, with no step list for one leg")
sharedPin:OnMouseLeave()
assert(api.Cancel("Test"))

-- Previews can cross continents on an overview map when both endpoints project there.
assert(api.NavigateRoute("Test", {stops[1], {map=1415,x=0.52,y=0.5,title="Across the sea"}}))
settle()
local overview = active[lineTemplate][1]
local project = C_Map.GetMapPosFromWorldPos
C_Map.GetMapPosFromWorldPos = function(_, point, targetMap)
 return targetMap, CreateVector2D(0.5-point.y/25000, 0.5-point.x/25000)
end
overview.paths = {overview.paths[#overview.paths]}
overview:Draw()
assert(overview.used > 0, "cross-continent preview draws a dashed connection")
C_Map.GetMapPosFromWorldPos = project
api.Cancel("Test")

zoom = 0
local many = {}
for i=1,64 do
 many[i] = {map=1414,x=0.2+i/1000,y=i%2 == 0 and 0.3 or 0.7,title=tostring(i)}
end
local plan, planned, calls = ns.Planner.Plan, {}, 0
ns.Planner.Plan = function(options)
 if not planned[options.to] then planned[options.to], calls = true, calls+1 end
 return plan(options)
end
local started = os.clock()
assert(api.NavigateRoute("Test", many))
local startMS = (os.clock()-started)*1000
settle()
assert(calls == 1, "only the current stop is planned")
local line = active[lineTemplate][1]
-- They share two rings, one per row; the current stop's row sits on it.
local pins = active[goalTemplate]
assert(#pins == 2 and #line.paths[#line.paths].points == 64)
assert(pins[1].Texture.alpha == 1 and #pins[1].stopLabels == 32)
assert(pins[2].Texture.texture == ns.NumberFile(2) and #pins[2].stopLabels == 32)
local drawCPU, drawWorst = 0, 0
for _=1,30 do
 started = os.clock()
 line:Draw()
 local ms = (os.clock()-started)*1000
 drawCPU, drawWorst = drawCPU+ms, math.max(drawWorst, ms)
end
assert(line.used <= 4096)
api.Cancel("Test")

-- Hovering a later stop shows it at full: its icon and the leg leading to it lose the fade, and fade back on leave.
zoom = 1
posX, posY = 0, 0
assert(api.NavigateRoute("Test", {
 stops[1],
 { map = 1414, x = 0.53, y = 0.49, title = "Second", tooltip = "Quest detail" },
}))
settle()
local laterPin, laterLine = active[goalTemplate][2], active[lineTemplate][1]
assert(laterPin.Texture.alpha == ns.LaterAlpha and laterLine.lines[laterLine.used].alpha == ns.LaterAlpha)
laterPin:OnMouseEnter()
assert(laterPin.Texture.alpha == 1 and laterPin.Button.alpha == 1)
-- The tooltip: the count on its own title line, the label in white, details in the normal colour, then the hint.
assert(tip[1] == "# Stop 2 of 2" and tip[2] == "  Second" and tipColors[2] == HIGHLIGHT_FONT_COLOR)
assert(tip[3] == "  Quest detail" and tipColors[3] == NORMAL_FONT_COLOR)
assert(tip[4] == " " and tip[5] == "  Right-click to clear" and tipColors[5] == NORMAL_FONT_COLOR)
for i = 1, laterLine.used do
 assert(laterLine.lines[i].alpha == 1, "the hovered stop's leg at full strength")
end
laterPin:OnMouseLeave()
assert(laterPin.Texture.alpha == ns.LaterAlpha and laterPin.Button.alpha == ns.LaterAlpha)
assert(laterLine.lines[laterLine.used].alpha == ns.LaterAlpha, "and the leg fades again")
api.Cancel("Test")

-- Above 25 the numbered art runs out: stop 30 keeps the map's button and its font number, dimmer as a later stop.
local lots = {}
for i = 1, 30 do
 lots[i] = {map=1414,x=0.1+i*0.025,y=(i%2 == 0) and 0.35 or 0.65,title=tostring(i)}
end
zoom = 1
posX, posY = 0, 0
assert(api.NavigateRoute("Test", lots))
settle()
local thirtieth
for _, pin in ipairs(active[goalTemplate]) do
 if pin.stopLabels[1] == "30" and pin.stopNumbers[1] == 30 then thirtieth = pin end
end
assert(thirtieth, "the thirtieth stop has a pin")
assert(thirtieth.Texture.hidden and not thirtieth.Button.hidden and not thirtieth.Disc.hidden)
assert(thirtieth.Number.text == "30", "above 25 the map's button keeps the font number")
assert(thirtieth.Button.atlas == "UI-QuestPoi-QuestNumber" and thirtieth.Button.alpha == ns.LaterAlpha)
assert(thirtieth.Disc.alpha == nil)
api.Cancel("Test")
assert(#errors == 0, table.concat(errors, "\n"))
print(string.format("api_ui: numbered pins, preview lines, progress, pooling, completion/cancel: ok; "..
 "64 stops start %.3f ms / redraw %.3f mean %.3f worst ms", startMS, drawCPU/30, drawWorst))
]]))()

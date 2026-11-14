-- The route's painters against the client fixture: strokes land on pooled lines, a core over its outline, and stops
-- at one place share a button. The geometry itself is tests/strokes_spec.lua's.
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
mapID, zoom = 1414, 1
ns.db.mapRoutes = true
refreshMap()
ns.db.flightPinScale = 50
local flightPin = ns.Canvas.Pools(WorldMapFrame).ShortestPathForeverFlightPinTemplate:Acquire({
 nodeID = 32, name = "Stormwind", position = CreateVector2D(0.5, 0.5),
 faction = Enum.FlightPathFaction.Alliance, atlasName = "taxinode_alliance",
})
assert(flightPin.startScale == 0.5 and flightPin.endScale == 0.6, "flight icons use the selected scale")
clickPin(flightPin, "RightButton")
local knownToggle = assert(context["Flight path known"], "right-click opens the flight ownership menu")
local wasKnown = knownToggle.get() == true
knownToggle.click()
assert(ns.KnownTaxiNodes()[flightPin.poiInfo.nodeID] == (not wasKnown or nil),
 "the menu changes persisted flight ownership")
local api = ShortestPathForever.API
local lineTemplate, goalTemplate = "ShortestPathForeverRoutePinTemplate", "ShortestPathForeverGoalPinTemplate"
local DOT = "Interface\\AddOns\\ShortestPathForever\\media\\Dot"

local clicked = assert(ns.WorldPoint(1414, 0.52, 0.5))
clicked.label, clicked.pinBadge = "Flight master", true
ns.StartJourney(clicked)
settle()
local badgePin = active[goalTemplate][1]
assert(badgePin.Texture.anchor[3] == "BOTTOMRIGHT", "a clicked icon keeps its destination tag at the corner")
assert(badgePin.Texture.width <= 11 and badgePin.Texture.height <= 11 and not badgePin.Texture.hidden,
 "the corner tag stays small without stretching")
ns.ClearJourney()
ns.StartJourney(assert(ns.WorldPoint(1414, 0.53, 0.5)))
settle()
local reused = active[goalTemplate][1].Texture
assert(reused.anchor[1] == "BOTTOM" and reused.anchor[3] == "CENTER" and reused.width == 29 and reused.height == 29,
 "a reused pin restores full size, standing on its point at the goal")
ns.ClearJourney()

-- A stop above or below the terrain wears the map's floor arrow at the pin's upper right, and its tooltip says which.
-- A stop on the ground wears neither; a pin whose stops disagree wears no arrow.
do
 local ground = ns.PathGrid.ground
 ns.PathGrid.ground = function(_, _, _, z)
  if z == 60 then
   return "up"
  elseif z == -60 then
   return "down"
  end
 end
 assert(api.NavigateRoute("Test", { { map = 1414, x = 0.56, y = 0.5, title = "Tower", z = 60 } }))
 settle()
 local high = active[goalTemplate][1]
 assert(not high.Arrow.hidden and high.Arrow.atlas == "poi-door-arrow-up", "a stop above the ground wears the up arrow")
 assert(high.Arrow.anchor[1] == "TOPRIGHT" and high.Arrow.anchor[3] == "TOPRIGHT", "at the pin's upper right")
-- Outward from the corner, as the action badge is from the lower right, so the arrow never covers the stop number.
assert(high.Arrow.anchor[4] > 0 and high.Arrow.anchor[5] > 0, "the arrow stands outside the pin's upper right corner")
 high.scripts.OnEnter(high)
 assert(tip[2] == "  Above ground level" and tipColors[2] == HIGHLIGHT_FONT_COLOR,
  "the stop above the ground says so under its label")
 high.scripts.OnLeave(high)
 assert(api.NavigateRoute("Test", { { map = 1414, x = 0.56, y = 0.5, title = "City", z = -60 } }))
 settle()
 local low = active[goalTemplate][1]
 assert(
  not low.Arrow.hidden and low.Arrow.atlas == "poi-door-arrow-down",
  "a stop below the ground wears the down arrow"
 )
 low.scripts.OnEnter(low)
 assert(tip[2] == "  Below ground level" and tipColors[2] == HIGHLIGHT_FONT_COLOR,
  "the stop below the ground says so under its label")
 low.scripts.OnLeave(low)
 assert(api.NavigateRoute("Test", { { map = 1414, x = 0.56, y = 0.5, title = "Ground", z = -1 } }))
 settle()
 local flat = active[goalTemplate][1]
 assert(flat.Arrow.hidden, "a stop on the ground wears no arrow")
 flat.scripts.OnEnter(flat)
 assert(tip[2] ~= "  Above ground level" and tip[2] ~= "  Below ground level", "and says neither")
 flat.scripts.OnLeave(flat)
 assert(
  api.NavigateRoute("Test", {
   { map = 1414, x = 0.56, y = 0.5, title = "Tower", z = 60 },
   { map = 1414, x = 0.56, y = 0.5, title = "City", z = -60 },
  })
 )
 settle()
 local mixed = active[goalTemplate][1]
 assert(mixed.Arrow.hidden, "a pin whose stops disagree wears no arrow")
 ns.PathGrid.ground = ground
 ns.ClearJourney()
end

-- Stop 3 goes back to stop 1's place: one button, the first visit's number, both titles and the later detail.
assert(api.NavigateRoute("Test", {
 {map=1414,x=0.51,y=0.5,title="Quest giver"},
 {map=1414,x=0.55,y=0.5,title="Camp"},
 {map=1414,x=0.51,y=0.5,title="Quest giver",tooltip="Quest detail"},
}))
settle()
local rings = active[goalTemplate]
assert(#rings == 2, "the place visited twice shares one button")
assert(not rings[1].Texture.hidden and rings[1].Texture.texture == ns.NumberFile(1) and rings[1].Texture.width == 24,
 "the first stop's gold numbered marker")
assert(rings[1].Button.hidden and rings[1].Disc.hidden, "no quest button under a numbered marker")
assert(rawget(rings[1], "Count") == nil, "shared stop keeps its number without corner text")
assert(rings[1].stopLabels[1] == "Quest giver" and rings[1].stopLabels[2] == "Quest giver")
assert(rings[1].stopNumbers[1] == 1 and rings[1].stopNumbers[2] == 3 and rings[1].stopCount == 3)
assert(#rings[1].stopDetails[1] == 0 and rings[1].stopDetails[2][1] == "Quest detail",
 "shared stop keeps a later detail with its own stop when the lead has none")
assert(rings[2].Texture.alpha == ns.LaterAlpha and rings[2].Disc.alpha == nil, "a later stop's marker dims")

-- The world map draws the legs after the current stop, faded, until the player turns them off. The stop pins and
-- the leg being walked stay either way.
local function routeLegs()
 local _, index = ns.JourneyStops()
 local paths = active[lineTemplate][1] and active[lineTemplate][1].paths or {}
 local later, current = 0, 0
 for _, path in ipairs(paths) do
  if path.stop == index then
   current = current + 1
  else
   later = later + 1
  end
 end
 return later, current
end
local later, current = routeLegs()
assert(later > 0 and current > 0, "a journey of several stops draws the later legs after the current one by default")
local stopPins = #active[goalTemplate]
ns.db.laterLegs = false
ns.RefreshJourneyPreview()
local laterOff, currentOff = routeLegs()
assert(laterOff == 0 and currentOff == current, "with the later legs off, only the leg being walked is drawn")
assert(#active[goalTemplate] == stopPins, "the stop pins stay with the later legs off")
ns.db.laterLegs = true
ns.RefreshJourneyPreview()
assert(routeLegs() == later, "turning the later legs back on draws them again")

-- The line redraws every half second while you move; the button under the pointer stays, hovered, so its
-- right-click to clear is heard. A rebuilt button lost its hover and press, and the click with them.
local hoveredRing = rings[1]
hoveredRing.scripts.OnEnter(hoveredRing)
assert(hoveredRing.highlighted and GameTooltip.owner == hoveredRing, "the pointer is on the first stop")
ns.RefreshJourneyPreview()
assert(active[goalTemplate][1] == hoveredRing and hoveredRing.shown ~= false, "a redraw keeps the stop's button")
assert(hoveredRing.highlighted and GameTooltip.owner == hoveredRing, "and its hover, tooltip and all")
hoveredRing.scripts.OnLeave(hoveredRing)

-- Each stroke is a pooled pair on the pin's pulsing layer: the core over a darker, wider, half-strength outline.
local function painted(owner, label)
 local scale = owner:GetEffectiveScale()
 for i = 1, #owner.lines do
  local line, under = owner.lines[i], owner.underlines[i]
  assert(line.shown == (i <= owner.used) and under.shown == line.shown, label .. ": only the strokes in use show")
  if line.shown then
   assert(line.parent == owner.strokeLayer and under.parent == owner.strokeLayer)
   assert(line.layer == "ARTWORK" and line.sublevel == 0 and under.layer == "ARTWORK" and under.sublevel == -1)
   assert(math.abs(under.thickness - line.thickness - 2 / scale) < 1e-9, label .. ": a pixel of outline each side")
   assert(under.alpha == line.alpha * 0.5, label .. ": the outline at half the core's strength")
   assert(line.texture == DOT and under.texture == DOT, label .. ": a walk's breadcrumbs wear the dot texture")
   assert(line.color[1] == 1 and line.color[2] == 0.82 and under.color[1] == 0.04, label .. ": gold on dark")
  end
 end
end
local pin, mini = active[lineTemplate][1], ShortestPathForeverMinimapRoute
painted(pin, "world map")
painted(mini, "minimap")
assert(pin.used > 0 and mini.used > 0)
-- Each surface's walking line has its own switch. Off draws no dots there; the other surface keeps its own, and
-- the goal ring stays, so only the line goes.
local function linesOn(owner)
	local count = 0
	for i = 1, owner.used do
		if owner.lines[i].shown then
			count = count + 1
		end
	end
	return count
end
assert(ns.db.mapLine == true and ns.db.minimapLine == true, "both walking lines start on")
ns.db.mapLine = false
ns.RefreshRouteLines()
assert(#(active[lineTemplate] or {}) == 0, "the world map's switch off draws no route there")
assert(linesOn(mini) > 0, "the minimap keeps drawing its own")
assert(not mini.Goal.hidden, "the minimap's destination ring stays")
ns.db.mapLine, ns.db.minimapLine = true, false
ns.RefreshRouteLines()
pin = active[lineTemplate][1]
assert(linesOn(pin) > 0, "the world map keeps drawing its own")
assert(linesOn(mini) == 0, "the minimap's switch off draws no route there")
assert(not mini.Goal.hidden, "the minimap's destination ring stays with its line off")
ns.db.minimapLine = true
ns.RefreshRouteLines()
pin = active[lineTemplate][1]
assert(linesOn(pin) > 0 and linesOn(mini) > 0, "turning them back on draws both lines again")
-- The route is laid out only around the view and its margin: a long walk at a zoom where all of it would be hundreds
-- of dots keeps a viewful, in the places the whole walk has them. A drag inside the margin keeps them; past it redraws.
local savedZoom = zoom
zoom = 40
viewRect.left, viewRect.right, viewRect.top, viewRect.bottom = 0, 1, 0, 1
pin:Draw()
local whole = pin.used
viewRect.left, viewRect.right, viewRect.top, viewRect.bottom = 0.52, 0.525, 0.49, 0.51
pin:Draw()
local kept = pin.used
assert(whole > 200 and kept > 0 and kept < 200, "only the view's dots are laid out: " .. kept .. " of " .. whole)
for i = 1, kept do
 local x = pin.lines[i].start[1]
 assert(x >= 0.5175 * canvas:GetWidth() and x <= 0.5275 * canvas:GetWidth(), "every dot inside the view's margin")
end
-- A zoom asks on every frame it runs; the redraw waits for the next tenth of a second.
pin:OnCanvasScaleChanged()
assert(pin.scripts.OnUpdate and pin.used == kept, "a zoom waits")
pin.scripts.OnUpdate(pin, 0.05)
assert(pin.scripts.OnUpdate and pin.used == kept, "not before a tenth of a second")
pin.scripts.OnUpdate(pin, 0.06)
assert(not pin.scripts.OnUpdate, "one redraw, then it rests")
-- A drag inside the margin needs nothing; one past it redraws where the view went.
local drawn = pin.lines[1].start[1]
viewRect.left, viewRect.right = 0.522, 0.523
pin:OnViewMoved()
assert(pin.lines[1].start[1] == drawn, "a drag inside the margin keeps the drawing")
viewRect.left, viewRect.right, viewRect.top, viewRect.bottom = 0.54, 0.545, 0.49, 0.51
pin:OnViewMoved()
assert(pin.lines[1].start[1] > 0.535 * canvas:GetWidth(), "a drag past it redraws at the view")
-- Put the whole route back in the pool for the checks after this one.
viewRect.left, viewRect.right, viewRect.top, viewRect.bottom = 0, 1, 0, 1
pin:Draw()
zoom = savedZoom
-- A shorter route hides the pairs it no longer needs and creates none: on the map its few dots fall under the stop.
local longest, created = pin.used, lineCreations
assert(api.NavigateRoute("Test", {{map=1414,x=0.5,y=0.4976,title="Near"}}))
settle()
pin = active[lineTemplate][1]
assert(pin.used < longest and #pin.lines == longest and lineCreations == created, "pairs are pooled, not recreated")
painted(pin, "shorter route")
painted(mini, "shorter route on the minimap")
assert(mini.used > 0, "the minimap still leads to the stop")
-- Standing still, the minimap drops its every-frame redraw after a second; moving, turning or zooming wakes it.
for _ = 1, 12 do
 if mini.scripts.OnUpdate then mini.scripts.OnUpdate(mini, 0.1) end
end
assert(mini.scripts.OnUpdate == nil, "a still minimap rests")
mini.scripts.OnEvent(mini, "PLAYER_STARTED_MOVING")
assert(mini.scripts.OnUpdate, "moving wakes it")
for _ = 1, 8 do
 mini.scripts.OnUpdate(mini, 0.1)
end
assert(mini.scripts.OnUpdate, "not before a second has passed")
for _ = 1, 4 do
 if mini.scripts.OnUpdate then mini.scripts.OnUpdate(mini, 0.1) end
end
assert(mini.scripts.OnUpdate == nil and mini.ticker, "resting, with the poll running")
mini.ticker.fn()
assert(mini.scripts.OnUpdate == nil, "a poll that finds nothing new leaves it resting")
mini.lastX = nil -- as if a mouse turn or a boat had moved the minimap with no event
mini.ticker.fn()
assert(mini.scripts.OnUpdate, "a poll that finds a change wakes it")
-- The minimap marks the stop where the strokes' geometry puts it: 60 yards north of the player in a 200-yard view.
assert(not mini.Goal.hidden and mini.Goal.anchor[2] == mini and mini.Goal.anchor[4] == 0, "the stop, straight ahead")
assert(math.abs(mini.Goal.anchor[5] - 30) < 1e-9, "three tenths of the way to the rim")
assert(api.Cancel("Test"))

-- Boat and zeppelin routes are painted hidden and shown by route while a dock is hovered, outlines at half strength.
local transport = active.ShortestPathForeverTransportPinTemplate[1]
assert(transport.used > 0 and not transport.strokeLayer, "transport routes are drawn, without the journey's pulse")
local function showing()
 local count = 0
 for i = 1, transport.used do
  local alpha = transport.lines[i].alpha
  assert(transport.underlines[i].alpha == alpha * 0.5)
  count = count + (alpha > 0 and 1 or 0)
 end
 return count
end
assert(showing() == 0, "hidden until a dock is hovered")
ns.HoverTransportRoutes(transport, { [transport.paths[1].route] = true })
local hovered = showing()
assert(hovered > 0 and hovered < transport.used, "only the hovered dock's routes show")
-- Re-acquiring unchanged geometry keeps the strokes and their hover state without a redraw.
local before = lineCreations
refreshMap()
assert(showing() == hovered and lineCreations == before)
ns.HoverTransportRoutes(transport, nil)
assert(showing() == 0, "and hide again")

-- The walking line's colour is a preset: repainting reaches both painters without replanning the journey.
posX, posY, posMap = 0, 0, 1414
assert(api.NavigateRoute("Colour", { { map = 1414, x = 0.02, y = 0.02, title = "Colour" } }))
settle()
local cyan
for _, choice in ipairs(ns.RouteColors) do
 if choice.key == "cyan" then cyan = choice.color end
end
ns.SetRouteColor("cyan")
settle()
local red, green, blue = cyan:GetRGBA()
for _, owner in ipairs({ active[lineTemplate][1], mini }) do
 assert(owner.used > 0, "the route still has strokes")
 for i = 1, owner.used do
  local colour = owner.lines[i].color
  assert(colour[1] == red and colour[2] == green and colour[3] == blue, "the walking line wears the chosen colour")
 end
end
assert(api.Cancel("Colour"))
ns.SetRouteColor("gold")

-- Hovering a stop shows the quest's own area, as the game's "..." pin did before the stop replaced it (#859).
do
	local highlighted, clears = nil, 0
	WorldMapFrame.SetHighlightedQuestID = function(_, questID)
		highlighted = questID
	end
	WorldMapFrame.ClearHighlightedQuestID = function()
		highlighted, clears = nil, clears + 1
	end
	assert(api.NavigateRoute("Test", {
		{ map = 1414, x = 0.51, y = 0.5, title = "Quest giver", questID = 4242 },
		{ map = 1414, x = 0.55, y = 0.5, title = "Hand-in", handins = { 4243 } },
	}))
	settle()
	local questPin, handinPin = active[goalTemplate][1], active[goalTemplate][2]
	assert(questPin and handinPin, "both stops are drawn")
	assert(questPin.stopQuests[1] == 4242, "the pin carries the stop's first quest")
	questPin.scripts.OnEnter(questPin)
	assert(highlighted == 4242, "hovering a stop highlights its quest's area")
	questPin.scripts.OnLeave(questPin)
	assert(highlighted == nil and clears == 1, "leaving clears the area again")
	handinPin.scripts.OnEnter(handinPin)
	assert(highlighted == 4243, "a hand-in stop highlights the quest handed in there")
	-- The journey can end under the pointer, and its area goes with the pin.
	assert(api.Cancel("Test"))
	assert(highlighted == nil and clears == 2, "releasing the hovered pin clears the area")

	-- The gamepad interface takes no map Lua from the addon (#158).
	local gamepad = ns.GamepadUI
	assert(api.NavigateRoute("Test", { { map = 1414, x = 0.51, y = 0.5, title = "Quest giver", questID = 4242 } }))
	settle()
	local gamepadPin = active[goalTemplate][1]
	ns.GamepadUI = function()
		return true
	end
	gamepadPin.scripts.OnEnter(gamepadPin)
	assert(highlighted == nil and clears == 2, "under the gamepad interface nothing is highlighted")
	gamepadPin.scripts.OnLeave(gamepadPin)
	assert(highlighted == nil and clears == 2, "and nothing is cleared")
	ns.GamepadUI = gamepad
	assert(api.Cancel("Test"))

	-- A stop that names no quest has nothing to show.
	assert(api.NavigateRoute("Test", { { map = 1414, x = 0.51, y = 0.5, title = "Plain" } }))
	settle()
	local plainPin = active[goalTemplate][1]
	assert(plainPin.stopQuests == nil, "a stop with no quest carries none")
	plainPin.scripts.OnEnter(plainPin)
	plainPin.scripts.OnLeave(plainPin)
	assert(highlighted == nil and clears == 2, "hovering a stop with no quest highlights nothing")
	assert(api.Cancel("Test"))
	WorldMapFrame.SetHighlightedQuestID, WorldMapFrame.ClearHighlightedQuestID = nil, nil
end

assert(#errors == 0, table.concat(errors, "\n"))
print("route_ui: shared stop button, pooled stroke pairs, minimap stop mark and hovered transport routes ok")
]]))()

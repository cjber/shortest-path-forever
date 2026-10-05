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
visible, WorldMapFrame.shown = true, true
posX, posY, posMap, facing = 0, 0, 1, 0
mapID, zoom = 1414, 1
ns.db.mapRoutes = true
for _, provider in ipairs(providers) do provider:RefreshAllData() end
local api = ShortestPathForever.API
local lineTemplate, goalTemplate = "ShortestPathForeverRoutePinTemplate", "ShortestPathForeverGoalPinTemplate"
local DOT = "Interface\\AddOns\\ShortestPathForever\\media\\Dot"

local clicked = assert(ns.WorldPoint(1414, 0.52, 0.5))
clicked.label, clicked.pinBadge = "Flight master", true
ns.StartJourney(clicked)
settle()
local badgePin = active[goalTemplate][1]
assert(badgePin.Texture.anchor[3] == "BOTTOMRIGHT", "a clicked icon keeps its destination tag at the corner")
assert(badgePin.Texture.width <= 16 and badgePin.Texture.height <= 16 and not badgePin.Texture.hidden,
 "the corner tag stays small without stretching")
ns.ClearJourney()
ns.StartJourney(assert(ns.WorldPoint(1414, 0.53, 0.5)))
settle()
assert(active[goalTemplate][1].Texture.allPoints == active[goalTemplate][1], "reused pin restores full size")
ns.ClearJourney()

-- Stop 3 goes back to stop 1's place: one button, the first visit's number, both titles and the later detail.
assert(api.NavigateRoute("Test", {
 {map=1414,x=0.51,y=0.5,title="Quest giver"},
 {map=1414,x=0.55,y=0.5,title="Camp"},
 {map=1414,x=0.51,y=0.5,title="Quest giver",tooltip="Quest detail"},
}))
settle()
local rings = active[goalTemplate]
assert(#rings == 2, "the place visited twice shares one button")
assert(not rings[1].Button.hidden and not rings[1].Disc.hidden and rings[1].width == 20, "the map's quest button")
assert(rawget(rings[1], "Count") == nil, "shared stop keeps its number without corner text")
assert(rings[1].stopTitles[1] == "Stop 1 of 3: Quest giver" and rings[1].stopTitles[2] == "Stop 3 of 3: Quest giver")
assert(rings[1].stopDetails[1] == "Quest detail", "shared stop keeps a later detail when the lead has none")
assert(rings[2].Button.alpha == 0.9 and rings[2].Disc.alpha == nil, "a later stop fades over its opaque shadow")

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
-- A shorter route hides the pairs it no longer needs and creates none: on the map its few dots fall under the stop.
local longest, created = pin.used, lineCreations
assert(api.NavigateRoute("Test", {{map=1414,x=0.5,y=0.4976,title="Near"}}))
settle()
pin = active[lineTemplate][1]
assert(pin.used < longest and #pin.lines == longest and lineCreations == created, "pairs are pooled, not recreated")
painted(pin, "shorter route")
painted(mini, "shorter route on the minimap")
assert(mini.used > 0, "the minimap still leads to the stop")
-- The minimap marks the stop where the strokes' geometry puts it: 60 yards north of the player in a 200-yard view.
assert(not mini.Goal.hidden and mini.Goal.anchor[2] == mini and mini.Goal.anchor[4] == 0, "the stop, straight ahead")
assert(math.abs(mini.Goal.anchor[5] - 30) < 1e-9, "three tenths of the way to the rim")
assert(api.Cancel("Test"))

-- Standing in the held stop's objective area: no stop button, no line and no ring of ours. The world map keeps its
-- drawn outline, and the game's own minimap blob wears the bonus objective's gold in place of its quest blue
-- (Adventure Guide holds an objective stop while the player works there).
posX, posY, posMap, facing = 0, 0, 1, 0
assert(api.NavigateRoute("Test", {
 { map = 1414, x = 0.5, y = 0.5, title = "Area", kind = "objective", hold = true, radius = 10,
  shapes = { { map = 1414, x = 0.5, y = 0.5, radius = 60 } } },
}))
settle()
for _, provider in ipairs(providers) do provider:RefreshAllData() end
local areaPin = active[lineTemplate][1]
assert(areaPin and areaPin.area and #areaPin.area == 1, "the map pin carries the objective shape")
assert(#(active[goalTemplate] or {}) == 0, "no stop button inside the area")
assert(areaPin.used > 0, "the map draws the outline: " .. areaPin.used)
for i = 1, areaPin.used do
 local line = areaPin.lines[i]
 assert(line.textureColor, "an area stroke is a solid line, not a breadcrumb")
 assert(math.abs(line.color[1] - 1) < 1e-6, "the map's outline is the guide's yellow")
 assert(math.abs(line.color[2] - 0.82) < 1e-6, "the map's outline is the guide's yellow")
 assert(math.abs(line.color[3] - 0.25) < 1e-6, "the map's outline is the guide's yellow")
end
assert(mini.Goal.hidden, "the minimap's stop ring hides inside the area")
assert(mini.used == 0, "the minimap draws no outline of ours: the game draws the area")
assert(
 Minimap.questBlobInside == "Interface\\Minimap\\UI-BonusObjectiveBlob-Inside"
  and Minimap.questBlobOutside == "Interface\\Minimap\\UI-BonusObjectiveBlob-Outside"
  and Minimap.questBlobRing == "Interface\\Minimap\\UI-BonusObjectiveBlob-MinimapRing",
 "the game's own blob wears the bonus objective's gold inside the area"
)
-- Stepping out restores the stop button, the line and the stock blue blob.
posX = 100
for _, provider in ipairs(providers) do provider:RefreshAllData() end
assert(#(active[goalTemplate] or {}) == 1, "the stop button is back outside the area")
mini.scripts.OnUpdate(mini, 0.2)
assert(not mini.Goal.hidden, "and the minimap's stop ring is back")
assert(
 Minimap.questBlobOutside == "Interface\\Minimap\\UI-QuestBlobMinimap-Outside",
 "the stock quest blue comes back outside the area"
)
-- Clearing the journey while still inside hands the blue back too.
posX = 0
for _, provider in ipairs(providers) do provider:RefreshAllData() end
mini.scripts.OnUpdate(mini, 0.2)
assert(
 Minimap.questBlobOutside == "Interface\\Minimap\\UI-BonusObjectiveBlob-Outside",
 "back inside, the blob is gold again"
)
assert(api.Cancel("Test"))
assert(
 Minimap.questBlobOutside == "Interface\\Minimap\\UI-QuestBlobMinimap-Outside",
 "clearing the journey leaves the minimap's quest blue"
)

-- The client's own inside-area state is preferred when the stop names the one quest it stands for: it holds from
-- outside the guide's circle, and lets go from inside it.
insideQuestBlob[7] = true
posX, posY = 100, 0
assert(api.NavigateRoute("Test", {
 { map = 1414, x = 0.5, y = 0.5, title = "Area", kind = "objective", hold = true, questID = 7,
  shapes = { { map = 1414, x = 0.5, y = 0.5, radius = 60 } } },
}))
settle()
for _, provider in ipairs(providers) do provider:RefreshAllData() end
assert(#(active[goalTemplate] or {}) == 0, "the client's inside answer holds the route outside the circle")
insideQuestBlob[7] = false
posX, posY = 0, 0
for _, provider in ipairs(providers) do provider:RefreshAllData() end
assert(#(active[goalTemplate] or {}) == 1, "the client's outside answer releases it inside the circle")
insideQuestBlob[7] = nil
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
for _, provider in ipairs(providers) do provider:RefreshAllData() end
assert(showing() == hovered and lineCreations == before)
ns.HoverTransportRoutes(transport, nil)
assert(showing() == 0, "and hide again")
assert(#errors == 0, table.concat(errors, "\n"))
print("route_ui: shared stop button, pooled stroke pairs, minimap stop mark and hovered transport routes ok")
]]))()

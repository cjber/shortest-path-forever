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

-- Standing in the area of a quest the held stop names, on that quest's zone map: the game's own area for the quest
-- is drawn by the addon's blob pin in the minimap's gold set, the game's own minimap blob wears the same gold, and
-- the stop button, the line and the minimap's ring step aside (Adventure Guide holds an objective stop while the
-- player works there). Zone 14 is the zone under continent 1414.
local areaTemplate = "ShortestPathForeverAreaPinTemplate"
local GOLD, BLUE = "Interface\\Minimap\\UI-BonusObjectiveBlob-", "Interface\\Minimap\\UI-QuestBlobMinimap-"
local function refresh()
 for _, provider in ipairs(providers) do provider:RefreshAllData() end
 mini.scripts.OnUpdate(mini, 0.2)
end
local function count(template)
 return #(active[template] or {})
end
local function area(stop)
 stop.map, stop.x, stop.y, stop.title, stop.kind, stop.hold = 14, 0.5, 0.5, "Area", "objective", true
 assert(api.NavigateRoute("Test", { stop }))
 settle()
 refresh()
end
local circle = { { map = 14, x = 0.5, y = 0.5, radius = 60 } }
posX, posY, posMap, facing = 100, 0, 1, 0
mapID = 14
insideQuestBlob[7] = true
area({ questID = 7, shapes = circle })
local areaPin = active[areaTemplate][1]
assert(count(areaTemplate) == 1 and areaPin.blobMap == 14, "the area pin draws on the map being viewed")
assert(#areaPin.blobs == 1 and areaPin.blobs[1] == 7, "the named quest's own area, outside the guide's circle too")
assert(areaPin.fill == GOLD .. "Inside" and areaPin.border == GOLD .. "Outside", "in the minimap's gold set")
assert(areaPin.width == 1000 and areaPin.height == 700 and areaPin.x == 0.5, "the pin covers the canvas")
assert(areaPin.frameLevelType == "PIN_FRAME_LEVEL_QUEST_BLOB")
assert(count(goalTemplate) == 0, "no stop button inside the area")
assert(count(lineTemplate) == 0, "no line, and no ring of ours")
assert(mini.Goal.hidden and mini.used == 0, "the minimap's ring and line step aside")
assert(
 Minimap.questBlobInside == GOLD .. "Inside"
  and Minimap.questBlobOutside == GOLD .. "Outside"
  and Minimap.questBlobRing == GOLD .. "MinimapRing",
 "the game's own blob wears the bonus objective's gold inside the area"
)
-- A zoom redraws the blob once, after the frame, and leaves no script running.
areaPin.blobs = nil
areaPin:OnCanvasScaleChanged()
assert(areaPin.blobs == nil and areaPin.scripts.OnUpdate, "the redraw waits for the end of the frame")
areaPin.scripts.OnUpdate(areaPin, 0.01)
assert(#areaPin.blobs == 1 and areaPin.scripts.OnUpdate == nil, "one redraw, then idle")
-- The client's own state change is the trigger: stepping out restores the stop, the line and the stock blue.
insideQuestBlob[7] = false
fireEvent("PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED")
assert(count(areaTemplate) == 0 and #areaPin.blobs == 0, "leaving clears the area")
assert(count(goalTemplate) == 1 and count(lineTemplate) == 1, "the stop button and the line are back")
assert(not mini.Goal.hidden, "and the minimap's stop ring is back")
assert(Minimap.questBlobOutside == BLUE .. "Outside", "the stock quest blue comes back outside the area")
-- The client's outside answer wins inside the guide's circle.
posX = 0
refresh()
assert(count(areaTemplate) == 0 and count(goalTemplate) == 1, "the client's outside answer keeps the stop")
-- Back inside, a map that shows no quests (QuestBlobPinMixin's mapAllowsBlobs) keeps the stop; so does a player
-- who turned quest objectives off on the map.
insideQuestBlob[7] = true
mapID = 1414
fireEvent("PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED")
assert(count(areaTemplate) == 0 and count(goalTemplate) == 1, "a continent map draws no area")
mapID = 14
cvars.questPOI = "0"
refresh()
assert(count(areaTemplate) == 0 and count(goalTemplate) == 1, "no area with quest objectives hidden")
cvars.questPOI = "1"
refresh()
assert(count(areaTemplate) == 1 and count(goalTemplate) == 0, "the area is back on its zone")
assert(Minimap.questBlobOutside == GOLD .. "Outside", "back inside, the blob is gold again")
-- Clearing the journey while still inside clears the area and hands the blue back.
assert(api.Cancel("Test"))
assert(count(areaTemplate) == 0, "clearing the journey clears the area")
assert(Minimap.questBlobOutside == BLUE .. "Outside", "clearing the journey leaves the minimap's quest blue")
insideQuestBlob[7] = nil

-- A stop standing for several quests draws each one's area, inside any of them.
insideQuestBlob[9] = true
area({ questID = 8, questIDs = { 8, 9 } })
areaPin = active[areaTemplate][1]
assert(#areaPin.blobs == 2 and areaPin.blobs[1] == 8 and areaPin.blobs[2] == 9, "every named quest's area")
assert(count(goalTemplate) == 0 and mini.Goal.hidden, "inside any of them, the stop steps aside")
assert(Minimap.questBlobOutside == GOLD .. "Outside", "and the minimap's blob is gold")
insideQuestBlob[9] = nil
assert(api.Cancel("Test"))

-- A stop with circles and no quest has no area of the game's to show: inside it the map draws only the stop and
-- its breadcrumbs, and the minimap keeps its ring and the stock blue.
area({ radius = 10, shapes = circle })
assert(count(areaTemplate) == 0, "no blob for a stop that names no quest")
assert(count(goalTemplate) == 1 and not mini.Goal.hidden, "the stop keeps its button and its minimap ring")
for _, owner in ipairs({ active[lineTemplate][1], mini }) do
 for i = 1, owner.used do
  assert(owner.lines[i].texture == DOT, "only the walk's breadcrumbs: no ring geometry")
 end
end
assert(Minimap.questBlobOutside == BLUE .. "Outside", "the minimap's blob stays blue")
assert(api.Cancel("Test"))
mapID = 1414

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

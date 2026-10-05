# Reproducing the media

`tools/screenshots.py` uses Pillow 12+, LuaJIT and the shared
`wow-mock-screenshots` skill. Set `WOWMOCK` if the skill is not under
`~/.claude/skills/`. All downloaded art is pinned to Forever **1.60.1.70124**;
`~/.cache/wowmock/1.60.1.70124/` holds the assets. No game installation or
SavedVariables are read. Verified with Pillow 12.3.0 / FreeType 2.14.3.

```sh
python3 tools/screenshots.py --verify
python3 tools/screenshots.py --verify --refs /path/to/refs
```

`--verify` renders every output twice with fresh UI/font objects and requires
byte-identical encoded files. Independent complete runs were also compared with
SHA-256. Keep Pillow/FreeType versions fixed when comparing hashes. The optional
`--refs` writes enlarged side-by-side crops under `docs/verification/`; reference
pixels never enter product media.

## Scenes

| File in `screenshots/` | Content |
| --- | --- |
| `flight.png` | A smooth flight line leaving Stormwind on the Elwynn Forest map |
| `kalimdor.png` | Auberdine → Menethil → Theramore → Cenarion Hold, Silithus |
| `darkshore.png` | A measured walk south from Auberdine to the Grove of the Ancients |
| `docks.png` | Auberdine's clustered piers; arrivals/departures and destination glows |
| `stops.png` | A four-stop API route through Thelsamar (three places): the current stop lit like the tracked quest and the later ones plain, action badges on the map's numbered quest buttons |
| `area.png` | Elwynn Forest, standing in a held objective area: the world map outlines it in the route's own yellow, with no stop pin or line, cropped to the area |
| `tracker.png` | Capture 21's five Auberdine → Silithus steps, with the current totals header |
| `detached.png` | The Journey tracker detached from the quest tracker, under its draggable "Forever tracker" heading |
| `minimap.png` | Auberdine's piers as minimap pins, the last dotted stretch to the south pier, native Guide waypoint, the route button gold at the lower right |
| `compass.png` | The compass: the game's own ticks and gold letters fading out at each end, its waypoint pin and the yards under it, no panel (on by default) |
| `services.png` | The addon-owned nearby-services menu opened over the world map, with trainer and vendor specialty categories |
| `demo.gif` | Eight-second montage: route pulse/settle, tracker countdown and gliding compass; under 0.5 MB |

`tools/screenshots_services.py` draws the services scene and the route button,
`tools/screenshots_tracker.py` the detached tracker's heading, and `tools/screenshots_area.py`
the objective-area outline.

The static images render at two pixels per UI unit; the GIF renders at its final
760×555 size to retain the route's physical pixel widths. A shared palette reserves
text and route colours. Duplicate GIF frames combine their durations; total playback
remains 8,000 ms. The animation uses fixed time steps, never the wall clock.

## Source and corrections

- `Path.FindSync` loads the bundled Nav0/Nav1 maps through LuaJIT. `Planner.LegPoints`
  supplies boat geometry: route 295, docks 10 → 9, and route 292, docks 5 → 6.
  The final Silithus destination is Alliance taxi node 73 from `Data/Taxi.lua`.
  Timings in the tracker reproduce capture 21, not a new optimality measurement.
- `UI/Strokes.lua` and `UI/Route.lua` supply 2-pixel cores in 4-pixel outlines, 4-pixel walk dots in 6-pixel rims 9 apart, colours,
  overview curves, fading continent-edge curves and the 1.2-second settling pulse.
  Outlines render below all cores. The destination uses the native pin at 0.8 scale.
- `UI/StopPin.lua` gives the current stop the tracked quest's `UI-QuestPoi-QuestNumber-SuperTracked` button and the
  grid's dark numeral, and every later stop the plain `UI-QuestPoi-QuestNumber` button and its yellow numeral, at the
  0.9 alpha later lines share. Each button keeps the caller's action badge over its lower right.
- `area.png`'s centre is a real `QuestPOIBlob` on Elwynn Forest (`QuestPOIPoint` -8808, 328), projected through
  `UiMapAssignment`. The area's radius comes from the addon that named it, so 140 yards is a scene fixture; the
  addon draws the ellipse itself in `Strokes.lua`'s area colour, and the client's own minimap blob is not mocked.
- `UI/Map.lua` / `UI/Map.xml` supply 20-unit ferry pins, transitive dock clustering,
  18-unit glow outsets, hover highlighting and tooltip wording. Default map layers
  include zeppelins, lifts, trams, portals and undiscovered Alliance flight points.
  Loading `UI/Map.lua` with LuaJIT stubs confirms `DockPierName(8)` returns
  `Auberdine northeast pier`; the earlier mock hardcoded `north pier`. Hover
  labels use projected cluster coordinates, so dock 24 is `northwest pier` there
  while its world-coordinate tracker title is `west pier`.
- Pinned UiMap/UiMapAssignment and map-art tables supply the map tiles and reverse
  north-growing world x / west-growing y into map coordinates. Darkshore is explored.
- The initial minimap renderer selected the **seventh** WDT MAID FileDataID, a
  terrain normal texture. Direct inspection at Kalimdor tile (30,20) showed
  `MAID[6]=1290784` (green normal map) versus `MAID[7]=207875` (Auberdine terrain).
  Shared `minimap_art` now uses the eighth ID and stitches the actual minimap tiles.
- The initial compass border rotated its horizontal strips counter-clockwise,
  putting the top edge inside the frame. Blizzard `Backdrop.lua`'s `textureUVs`
  maps the strip's left edge to the top; clockwise rotation joins all four corners.
  Shared `tooltip_backdrop` implements that mapping. World-map frames also now
  apply Camelot's metal-corner offsets. The compass (`UI/Compass.lua`) draws no panel.
  `UI/RouteButton.lua`'s plate is the client's own `ui-hud-minimap-button` atlas (20 by 18).
- `UI/Tracker.lua`, `Journey/JourneyGuide.lua`, `UI/Arrow.lua`, `UI/Compass.lua` and `UI/RouteButton.lua`
  supply the text, Guide's 25-yard bend threshold, marker proportions, stock fonts,
  the ribbon's fade ramp and its gold active state, and heading easing.
  Blizzard's ObjectiveTracker templates, WorldMap frame, WaypointLocationDataProvider,
  Minimap XML, Camelot Skin/Diel and Backdrop sources supply the surrounding widgets.

## Visual review and limits

All supplied captures (11–16 and 18–21; no 17 supplied) were inspected. Enlarged
comparison sheets cover world map (14), Kalimdor (11), Darkshore (13), minimap (18/19),
tracker (21), compass (20), dock pins/glow and sampled animation frames.

The current source differs from these older captures: thinner physical route strokes,
curved overview crossings, a 360×60 compass ribbon with no panel whose ticks and gold
letters fade out at each end, and Journey totals in the section header. Selected starts,
facing, goals and schedules differ; the compass's 780-yard bearings are a separate
scene fixture. The animation is a montage, not one continuously recorded journey.

Remaining approximations: Pillow font baselines/rasterization differ by a few pixels;
engine pin nudging and native minimap marker sizing are approximated. The minimap
uses a selected 233⅓-yard radius and omits unrelated tracking POIs and the engine's
navigation beam. Backgrounds use the skill's neutral backdrop. Quest markers from
other tracked content in the captures are absent.

No supplied capture shows the dock tooltip or Boats countdown. Tooltip text/anchors
were checked against `UI/Map.lua`; the stock frame was compared with the skill's real
SkillUp tooltip capture, obtainable without changing either repository:

```sh
git -C ../skillup-forever show be11638:docs/screenshots/tooltip.png > /tmp/tooltip-ref.png
python3 tools/screenshots.py --refs /path/to/refs --tooltip-ref /tmp/tooltip-ref.png
```

Live timings, engine rendering and interaction remain unverified in game, by design.
The UI checks (`tests/ui.sh`) check route pixel sizing, overview/edge
curves, native waypoints, tracker totals/countdowns, compass bearings and the route
button's gold state.

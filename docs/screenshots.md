# Reproducing the media

`tools/screenshots.py` uses Pillow 12+, LuaJIT and the shared renderer in the sibling
`forever-core` checkout. Set `FOREVER_CORE` if it is not beside this repository. UI art and fonts use
`UI_ART_BUILD` in `tools/screenshots_art.py`; generated map and content data use `BUILD` from
`tools/gen_routes.py`, imported as `DATA_BUILD`. `~/.cache/wowmock/<build>/` holds the assets. No game installation or
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
| `docks.png` | Auberdine's clustered piers; arrivals/departures and hover highlighting |
| `stops.png` | A four-stop API route through Thelsamar (three places): the current stop at full strength and the later ones as faded as their lines, each on the addon's gold numbered marker with its action badge |
| `floors.png` | Westfall at Sentinel Hill: the current guide stop, Scout Riell at the top of the tower, wears the map's up arrow at its upper right, and its tooltip says "Above ground level" |
| `tracker.png` | Capture 21's five Auberdine → Silithus steps, with the current totals header |
| `detached.png` | The Journey tracker detached from the quest tracker, under its draggable "Forever tracker" heading |
| `minimap.png` | Auberdine's piers as minimap pins, the last dotted stretch to the south pier, the addon's own goal pin |
| `cast_prompt.png` | The current Hearthstone action, using the same icon, label and spacing as the screen prompt |
| `compass.png` | The compass: the game's own ticks and gold letters fading out at each end, turns 1 and 2 and the yards under the next, no panel (on by default) |
| `compass_behind.png` | The same compass facing about 140 degrees away: the markers and distance dim to 40 percent and only turn 1 shows |
| `arrival.png` | Standing in a quest's area: the arrow is the addon's gold goal pin with the stop's title and three objectives, and the compass ribbon is tinted green with no turns or distance |
| `services.png` | The Nearby services tab in the world map's quest log, its bags tab selected: Auberdine's vendors for a level 15 hunter, each with the nearest NPC and walking time, and the arrows, shot, food and drink for that level |
| `services_better.png` | The same tab for that hunter at level 25 with a bow: Dalmond still sells only Sharp Arrow, so a one-line row under Arrows offers Razor Arrow in Darnassus with its own time and the upgrade arrow on its icon; Auberdine already sells the best food and drink for 25 |
| `services_search.png` | The same tab while `water` is typed into its search box: the nearest food and drink vendors selling something that matches, each row naming only the item that matched |
| `services_roles.png` | The same tab's class, portal and battlemaster rows on their own: the class trainer and portal trainer in Darnassus, and the battlemaster there, each with the boat's time |
| `town_services.png` | Stormwind City zoomed out: its overlapping services collapse into group pins that wear the addon's own market stall (never a city castle, nor one service's icon), with the group's services and the click journey hint in the tooltip |
| `town_services_zoom.png` | The same city zoomed into the Trade District: one pin per NPC, each wearing its own tracking icon (the repairer's anvil, the auctioneer's coins, the baker's bread and milk), as the map separates overlapping services |
| `demo.gif` | Eight-second montage: route pulse/settle, tracker countdown and gliding compass; under 0.5 MB |

`tools/screenshots_services.py` draws the services scene,
`tools/screenshots_town.py` the two town services scenes, on `tools/screenshots_maps.py`'s shared map frame;
`tools/screenshots_tracker.py` the detached tracker's heading, and
`tools/screenshots_arrival.py` the arrival pin and its tinted compass.
`tools/screenshots_floors.py` draws the stop above the ground at Sentinel Hill.

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
  Outlines render below all cores. The destination uses the addon's own pin at 0.8 scale.
- `UI/StopPin.lua` gives every numbered stop up to 25 the addon's own gold numbered marker at 24 units, the current
  stop at full strength and later stops at the 0.4 alpha they share with the lines leading to them, and keeps above 25
  the tracked quest's `UI-QuestPoi-QuestNumber-SuperTracked` button and the font number. Each stop keeps the caller's
  action badge over its lower right.
- `UI/Map.lua` / `UI/Map.xml` supply 20-unit ferry pins, transitive dock clustering,
  hover highlighting and tooltip wording. Portals wear the map legend's teleport atlas,
  `TaxiNode_Continent_Neutral`, fitted at its own shape. Default map layers
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
- `UI/Tracker.lua`, `Journey/JourneyGuide.lua`, `UI/Arrow.lua` and `UI/Compass.lua`
  supply the text, Guide's 25-yard bend threshold, marker proportions, stock fonts,
  the ribbon's fade ramp and its gold active state, and heading easing.
  Blizzard's ObjectiveTracker templates, WorldMap frame, WaypointLocationDataProvider,
  Minimap XML, Camelot Skin/Diel and Backdrop sources supply the surrounding widgets.
- `arrival.png` reproduces `UI/Arrow.lua`'s `ShowArrival`: the addon's own gold goal pin,
  `media/Pin.tga`, at its native square 36 by 36, the stop's title in `GameFontNormal` 8 units
  below it and up to three objective lines in `GameFontHighlightSmall` 4 below the title, both
  centred in a 240-unit column. The ribbon keeps `Compass.lua`'s
  `ARRIVED_TICK_COLOR` and `ARRIVED_CENTER_COLOR` and its turns are absent because the guide
  holds no targets while it waits in the area. The stop is quest 878, *Tribes at War* in the
  Barrens, whose three objectives are the lines shown; the fixture names the kills rather than a
  recorded character's progress.
- The two town services scenes are Stormwind City's services from QuestieDB 1.0.13's Forever bake
  (`X-BUILD-COMMIT 0f7d8adc`), Npc spawns in area 1519 as map percent: the bank, inn, auction house, flight
  master, weapons merchant, baker and trade supplier around the Trade District, and the stable master, hunter
  trainer and engineering trainer in the Dwarven District. Clustering is `UI/Map.lua`'s transitive
  `OverlapGroups` against the client's 1002 by 668 map canvas, at the addon's pin size; a group wears its
  best-ranked service's atlas, `UI/NearbyGroups.lua`'s tracking icons. The fixture is an Alliance character
  (Horde-only NPCs are hidden, neutrals kept) and Stormwind is a zone map, so the pins belong there.

## Visual review and limits

All supplied captures (11–16 and 18–21; no 17 supplied) were inspected. Enlarged
comparison sheets cover world map (14), Kalimdor (11), Darkshore (13), minimap (18/19),
tracker (21), compass (20), dock pins and sampled animation frames.

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
curves, the addon's goal pins, tracker totals/countdowns, compass bearings and the route
button's gold state.

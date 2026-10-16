Shift-click the world map or minimap, or choose a quest, to plan a journey. Shortest Path Forever gives directions in the objective tracker and on both maps.

![A route settling, the departure countdown and compass](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/demo.gif)

The route settles, the next boat counts down and the compass turns with you.

## Features

- **Plan the trip.** Combine walking, known flights, boats, zeppelins, lifts, the tram, portals and teleports. Walking routes go around walls, hills and water, and replan as you move. A spot inside a dungeon or raid leads to its entrance.
- **Follow your guide.** RestedXP journeys are on by default, with no TomTom or bridge addon; without TomTom, other guides' waypoints work too. Adventure Guide takes over when its RestedXP display is on.
- **Choose what you see.** Hide Journey steps or the direction arrow while keeping the map route. Move and scale the arrow, which eases round to each bearing, and add the time left under the compass.
- **Complete a step.** Click the current journey step and choose *Complete this step*. Skipping a Hearthstone leaves it out for that journey; other steps return if you still need them.
- **Find services and departures.** Map tracking menus offer nearby trainers, repairs, vendors and other services using installed QuestieDB. Dock and flight master tooltips show destinations and times.
- **Travel prompts.** Hearthstone and teleport steps show what to cast. A sound and taskbar flash warn before a boat arrives, and an optional ping marks your arrival. A red corpse route guides ghosts back to their bodies.

![Journey steps with time and distance remaining](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/tracker.png)

The tracker shows the trip one step at a time.

![Route and waypoint on the minimap](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/minimap.png)

Walking breadcrumbs and the native waypoint lead to the next step.

![Dock destinations and departures](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/docks.png)

Hover a dock to see its services and destinations.

## Usage

- `/path` opens settings under **Options → AddOns → Shortest Path Forever**.
- Alt-click the world map to choose a destination directly over a Questie icon. Shift-click the map, minimap or a Shortest Path icon; for quests, choose **Plan journey** in the right-click menu.
- In **Map marks**, scale each kind of icon. Right-click a flight master icon to mark its path known or unknown.
- In **Interface**, choose what shows, metres, sizes and a compass background. While moving the arrow or compass, Shift-drag or use the arrow keys for fine placement.
- In **Guidance**, or by right-clicking the tracker's "Journey to …" line, turn off **Attach to quest tracker** to drag the shared column. **Resume guide** returns to RestedXP; **Keep journeys after a reload** restarts yours.
- `/way [zone] x y [title]` plans a journey, or `/path way` when another addon owns `/way`. **Follow TomTom's arrow** in Guidance follows TomTom.
- `/spfnear` opens nearby services. For a bug report, type `/path report` and paste what it shows.
- With the gamepad interface on, you open the world map; Shortest Path won't.

<!-- forever-family:start -->

## My other Forever addons

Each one works on its own, and they work together when you install more than one.

| Addon | What it does |
|---|---|
| [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) | Plans journeys on foot, by air, by sea and through portals, with directions in the tracker. |
| [Adventure Guide Forever](https://www.curseforge.com/wow/addons/adventure-guide-forever) | Suggests quests for your level and routes you from one to the next. |
| [SkillUp Forever](https://www.curseforge.com/wow/addons/skillup-forever) | Shows skill-up chances, recipe costs and levelling routes in the Professions window. |
| [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) | Shows your unfinished Legacy challenges on the world map and tracks the ones you choose. |
| [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) | Adds quest automation, rare alerts and merchant options to the game's settings. |

<!-- forever-family:end -->

Installed together, the others send Shortest Path their destinations. Pick an Adventure Guide journey or RestedXP step, or click a trainer or vendor in a SkillUp route to travel to the nearest one. Click a Legacy dungeon or raid pin, or a dungeon or raid entrance Tweaks adds to the map, to travel there.

Journey steps share one tracker column with the Adventure Guide, SkillUp and Legacy sections, above your quests.

Without Adventure Guide or Legacy, a grey hint suggests it where it would help. *Suggest my other Forever addons*, in settings, turns hints off.

Details and issues: [GitHub](https://github.com/cjber/shortest-path-forever). Licence: GPL-3.0-or-later.

Made by Cillian Berragan · [cillian.dev](https://cillian.dev/) · [GitHub](https://github.com/cjber) · [Twitter](https://twitter.com/cjberragan)

Built with AI assistance.

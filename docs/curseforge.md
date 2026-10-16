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

## With my other Forever addons

Each works alone; installed together, they send Shortest Path their destinations:

- [Adventure Guide Forever](https://www.curseforge.com/wow/addons/adventure-guide-forever) suggests quests for your level. Pick one and Shortest Path leads you to each stop, including RestedXP steps.
- [SkillUp Forever](https://www.curseforge.com/wow/addons/skillup-forever) plans profession levelling. Click a trainer or vendor in its route to travel to the nearest one.
- [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) puts unfinished Legacy challenges on the world map. Click a dungeon or raid pin to travel there.
- [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) adds dungeon and raid entrances to the map. Click one to travel there.

Journey steps share one tracker column with the Adventure Guide, SkillUp and Legacy sections, above your quests.

Details and issues: [GitHub](https://github.com/cjber/shortest-path-forever). Licence: GPL-3.0-or-later.

Made by Cillian Berragan · [cillian.dev](https://cillian.dev/) · [GitHub](https://github.com/cjber) · [Twitter](https://twitter.com/cjberragan)

Built with AI assistance.

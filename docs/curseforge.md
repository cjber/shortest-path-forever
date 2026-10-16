Shift-click the world map or minimap, or choose a quest, to plan a journey. Shortest Path Forever gives directions in the objective tracker and on both maps.

![A route settling, the departure countdown and compass](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/demo.gif)

The route settles, the next boat counts down and the compass turns with you.

## Features

- **Plan the trip.** Combine walking, known flights, boats, zeppelins, lifts, the tram, portals and teleports. Walking routes go around walls, hills and water. Routes replan as you move.
- **Follow your guide.** RestedXP journeys are on by default, without TomTom or a bridge addon. With TomTom absent, other guides can pass waypoints to Shortest Path. Adventure Guide takes over when its RestedXP display is on.
- **Choose what you see.** Hide Journey steps or the direction arrow while keeping the map route. Move and scale the arrow, which eases round to each bearing, and add the time left under the compass.
- **Complete a step.** Click the current journey step and choose *Complete this step*. Skipping a Hearthstone leaves it out for that journey; later plans follow your actual position.
- **Find services and departures.** Map tracking menus offer nearby trainers, repairs, vendors and other services using installed QuestieDB. Dock tooltips show destinations and times, and flight master tooltips list their flights. Ride times improve estimates.
- **Travel prompts.** Hearthstone and teleport steps show what to cast. Transport sounds and a taskbar flash warn before a boat arrives, and an optional ping marks your arrival. A red corpse route guides ghosts back to their bodies.
- **Keep your journey.** An option starts your own journey again after a `/reload`.

![Journey steps with time and distance remaining](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/tracker.png)

The tracker shows the trip one step at a time.

![Route and waypoint on the minimap](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/minimap.png)

Walking breadcrumbs and the native waypoint lead to the next step.

![Dock destinations and departures](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/docks.png)

Hover a dock to see its services and destinations.

## Usage

- `/path` opens settings under **Options → AddOns → Shortest Path Forever**.
- Alt-click the world map to choose a destination directly over a Questie icon. Shift-click the map, minimap or a Shortest Path icon; for quests, choose **Plan journey** in the right-click menu.
- In **Map marks**, scale each kind of icon from 25% to 200%. Right-click a flight master icon to correct whether its path is known.
- In **Interface**, choose what shows, metres, sizes and a compass background. While moving the arrow or compass, Shift-drag or use the arrow keys for fine placement.
- In **Guidance**, or by right-clicking the tracker's "Journey to …" line, turn off **Attach to quest tracker** to drag the shared column. **Resume guide** returns to RestedXP; **Keep journeys after a reload** restarts yours.
- `/way [zone] x y [title]` plans a journey there while TomTom and other addons leave `/way` free; `/path way` always works. With TomTom installed, **Follow TomTom's arrow** in Guidance follows its waypoints.
- `/spfnear` opens nearby services. For a bug report, type `/path report` and paste what it shows.

## With my other Forever addons

Each one works alone. Installed with Shortest Path Forever, they send it their destinations:

- [Adventure Guide Forever](https://www.curseforge.com/wow/addons/adventure-guide-forever) suggests quests and journeys for your level. Pick one and Shortest Path leads you to each stop, including RestedXP steps.
- [SkillUp Forever](https://www.curseforge.com/wow/addons/skillup-forever) plans profession levelling. Click a trainer or vendor in its route to travel to the nearest one by travel time.
- [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) puts unfinished Legacy challenges on the world map. Click a dungeon or raid pin to travel there.
- [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) adds dungeon and raid entrances to the map. Click one to travel there.

Journey steps share one tracker column with the Adventure Guide, SkillUp and Legacy sections, above your quests.

Details and issues: [GitHub](https://github.com/cjber/shortest-path-forever). Licence: GPL-3.0-or-later.

Made by Cillian Berragan · [cillian.dev](https://cillian.dev/) · [GitHub](https://github.com/cjber) · [Twitter](https://twitter.com/cjberragan)

Built with AI assistance.

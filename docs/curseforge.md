Shift-click the world map or minimap, or choose a quest, to plan a journey. Shortest Path Forever gives directions in the objective tracker and on both maps.

![A route settling, the departure countdown and compass](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/demo.gif)

The route settles, the next boat counts down and the compass turns with you.

## Features

- **Plan the trip.** Combine walking, known flights, boats, zeppelins, lifts, the tram, portals and teleports. Walking routes go around walls, hills and water. Routes replan as you move.
- **Follow your guide.** RestedXP journeys are enabled by default, without TomTom or a bridge addon. With TomTom absent, other guides can also pass waypoints to Shortest Path. Adventure Guide handles navigation when its RestedXP display is enabled.
- **Choose what you see.** Hide Journey steps or the direction arrow while keeping the map route. Use yards or metres, resize icons separately and optionally add a minimap settings button.
- **Complete a step.** Click the current journey step and choose *Complete this step*. Skipping a Hearthstone leaves it out for that journey; later plans follow your actual position.
- **Find services and departures.** Map tracking menus offer nearby trainers, repairs, vendors and other services using installed QuestieDB. Dock tooltips show destinations and times. Flight maps highlight the flight to take; ride times improve estimates.
- **Travel prompts.** Hearthstone and teleport steps show what to cast. Transport sounds and a taskbar flash warn before a boat arrives. A compass marks your turns; a red corpse route guides ghosts back to their bodies.

![Journey steps with time and distance remaining](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/tracker.png)

The tracker shows the trip one step at a time.

![Route and waypoint on the minimap](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/minimap.png)

Walking breadcrumbs and the native waypoint lead to the next step.

![Dock destinations and departures](https://raw.githubusercontent.com/cjber/shortest-path-forever/main/docs/screenshots/docks.png)

Hover a dock to see its services and destinations.

## Usage

- `/path` opens settings under **Options → AddOns → Shortest Path Forever**.
- Alt-click the world map to choose a destination directly over a Questie icon. Shift-click the map, minimap or a Shortest Path icon; for quests, choose **Plan journey** in the right-click menu.
- In **Map marks**, scale transport, flight master and minimap icons from 25% to 200%. Right-click a flight master icon to correct whether its path is known. Open a flight master's map to sync known paths.
- In **Interface**, choose tracker and arrow visibility, metres and the optional minimap button. Resize the tracker and compass separately.
- In **Guidance**, turn off **Attach to quest tracker** to drag the shared column. **Resume guide** returns to RestedXP; **Minimum Hearthstone saving** reserves it for larger savings.
- `/spfnear` opens nearby services. `/path perf` reports performance; `/path debug` enables a saved ride trace.

## With my other Forever addons

Each one is optional and works alone. Installed with Shortest Path Forever, they send it their destinations:

- [Adventure Guide Forever](https://www.curseforge.com/wow/addons/adventure-guide-forever) suggests quests and journeys for your level. Pick one and Shortest Path leads you to each stop, including RestedXP steps.
- [SkillUp Forever](https://www.curseforge.com/wow/addons/skillup-forever) plans profession levelling. Click a trainer or vendor in its route to travel there. It picks the nearest one by travel time.
- [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) puts unfinished Legacy challenges on the world map. Click a dungeon or raid pin to travel there.
- [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) adds dungeon and raid entrances to the map. Click one to travel there.

Journey steps share one tracker column with the Adventure Guide, SkillUp and Legacy sections, above your quests. Scale the column in **Interface**, or turn off **Attach to quest tracker** to drag it.

More details and issues: [GitHub](https://github.com/cjber/shortest-path-forever). Licence: GPL-3.0-or-later.

Made by Cillian Berragan · [cillian.dev](https://cillian.dev/) · [GitHub](https://github.com/cjber) · [Twitter](https://twitter.com/cjberragan)

Built with AI assistance.

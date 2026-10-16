# Features in depth

The detail behind each feature in the [README](../README.md).

## Guidance controls

Alt-click the world map to place a destination directly over a Questie icon. Shift-click remains available on the map, minimap and Shortest Path icons.

In **Map marks**, scale transport, flight master and minimap icons separately from 25% to 200%. Right-click a flight master icon to mark its path as known or unknown; opening a flight master's map also syncs paths reported by the client.

In **Interface**, turn **Show journey in tracker** and **Show direction arrow** off independently, leaving the map route visible. Choose yards or metres, resize the tracker and compass, give the compass a background, or enable the optional minimap settings button. Turn off **Attach to quest tracker** in Guidance, or in the right-click menu of the tracker's "Journey to …" line (out of combat), to drag the Forever column by its heading.

The direction arrow swings smoothly to each new bearing and rests while you stand still. **Move the arrow** and **Arrow scale** in Interface place and size it, together with the cast prompt that takes its place on a Hearthstone or teleport step. While moving the arrow or the compass, hold Shift as you drag to move it a quarter as far as the mouse, or rest the pointer on it and press the arrow keys to nudge it (ten times as far with Shift). The arrow keys walk as usual everywhere else and in combat. **Show the time left under the compass** (off by default) puts the journey's time left beside the distance to your next turn.

**Keep journeys after a reload** in Guidance (off by default) starts a journey you planned yourself (a map click, `/way`, a quest or Nearby services) again after a `/reload`, or when you log back in within 30 minutes. Guides and other addons start their own again, and one that does so first wins.

**Play a sound when you reach the goal** in Alerts (off by default) plays the map's ping when a journey you planned yourself arrives, even with the game in the background. Clearing a journey stays quiet.

`/path report` opens a window with a report already selected: addon and game versions, your character and position, the journey and its steps, your ride, the ride trace when `/path debug` is on, errors caught this session and your other addons. Press Ctrl+C and paste it into a bug report.

With the game's gamepad interface on, Shortest Path never opens the world map itself, nor takes the keyboard: *Show on map*, tracker dock lines and route ends turn a map you have open, or ask you to open one, and Nearby services points to the map's own tracking menu.

Click the current journey step and choose **Complete this step** to advance it. Skipping a Hearthstone leaves it out of plans for that journey. Other steps may return if your actual position still requires them.

With RestedXP installed, **Resume guide** in Guidance or the Journey header menu resumes its current target after another journey. Adventure Guide owns this action when its RestedXP display is enabled; update both addons to use the integrated resume control.

## Routes and map marks

- **Journey planner.** Shift-click anywhere on the world map or minimap for the fastest way there from where you
  stand: walking, the flight points you know, boats and zeppelins with their live waits, lifts, the tram and
  portals, including a flight master you haven't found yet if walking to it pays off. Walks go through
  tunnels and between a city's levels, such as Dun Algaz and the Undercity, and walks keep out of water, which is slow and risky, unless you have Water Walking or Levitate (the step asks you to cast it). The route is drawn
  on the map and minimap, walking legs dotted, and the steps sit in the objective tracker like a tracked
  quest. It replans as you move but only switches to a clearly faster way (at least 30 seconds and a tenth of the time left), and stays aboard if you are already riding. **Guide**, on from the start
  of every journey (click the tracker header to turn it off), moves the game's own waypoint marker to where each step ends, the next boat, lift or flight master (or, with *Mark only where steps end* off in `/path`, along the route turn by turn, round walls), and hands your tracked quest back when you finish. To head for a quest, pick **Plan journey** from its right-click menu in the objective
  tracker or quest log, or Shift-click its marker on the map; a finished quest routes to its turn-in.
  A goal inside a dungeon or raid, which has no walking map, is planned to the instance's entrance from outside
  (*Enter Deadmines*); going in completes it, and a guide's next stop inside starts from there.
  A journey can start with your Hearthstone, a mage's city teleport (with a Rune of Teleportation), a shaman's
  Astral Recall or a druid's Teleport: Moonglade, after its own icon and named in your game's language:
  *1. Use Hearthstone*. A cooldown counts as waiting, and a jump to another continent adds a few seconds for
  the loading screen. The client does not say where your bind point is, so it is where you stood when you last
  bound at an innkeeper with the addon on, or where your last Hearthstone or Astral Recall set you down. Until
  then, or after binding somewhere else with the addon off, the hearth is left out. The recorded bind position is saved per character and checked against
  the current bind name. Class teleports need no bind point. Turn this
  off with *Use hearth and teleports* in `/path`.
  ![Journey steps from Auberdine to Silithus with time and distance remaining](screenshots/tracker.png)

  The tracker shows each travel step, with time and distance remaining.

  ![Auberdine’s piers on the minimap, with the dotted route and Guide’s native waypoint](screenshots/minimap.png)

- **Journeys from your guides.** While TomTom is not installed, the addon answers its waypoint calls, so Questie,
  Zygor and other guides that set a waypoint plan a journey here instead, titled with the guide's own text. Every
  waypoint belongs to one owner, so a fresh one replaces the journey rather than queueing; *Let guides set TomTom
  waypoints* off in `/path` removes the shim and clears the journey it started. A held stop can name the quests
  whose area it stands for: standing in one, the client draws its own quest blob in the bonus objective's gold on
  the minimap and on the world map, and the stop's pin and line step aside until you leave. Inside is the client's
  own inside-area state for the quests the stop names. A stop that names circles and no quest uses the circles to
  tell when you have arrived, and keeps its pin and line.

- **Typed waypoints.** `/way [zone] x y [title]` plans a journey to that spot, read as TomTom reads it: x and y are
  percentages of the map, `#1429` names a map by its ID, a zone can be shortened to any part of its name
  (`/way elwynn 42 65 Goldshire`, `/way hinterlands 14 44`), and a decimal comma works. Without a zone the spot is on the map you stand on.
  `/way` is registered only when TomTom isn't loaded and no other addon has claimed it; `/path way` takes the same
  line and always works. With TomTom installed, *Follow TomTom's arrow* in Guidance (off by default) plans a journey
  to each waypoint its arrow takes, from `/way`, a guide or the waypoint you pick, including the one it points to
  after a `/reload`, and removing that waypoint in TomTom, one at a time or all at once, ends the journey. Its corpse
  arrow is left to the corpse run, so dying keeps the journey you were on.

- **The destination pin.** Hover the pin you are heading for on the world map to see the time and distance left and
  each step, worded as the tracker words them, with the current one lit. A later stop's pin names only that stop.
  With *Other Faction's Routes* off, it adds a line when the other faction's boats or zeppelins would get you there
  at least two minutes sooner, such as "Through Horde transport: about 4 min faster".

- **Finding the fastest way.** While a new journey is checked, the map shows only its destination pin and the
  tracker the Group Finder spinner; the route, steps and totals then appear together. A search that takes more than
  three seconds shows its best route so far, and changes it only for one at least 30 seconds and 10% faster, or if
  it stops working. The drawn route pulses gently on the world map and minimap while the spinner turns, then
  becomes steady as soon as the search finishes. Later checks run quietly without a spinner or pulsing.
  Nearby walks can settle immediately; longer searches stop as soon as no unchecked alternative can beat the chosen route. Only that route gets
  walking geometry, and drawn paths stay visible during refreshes, and clearing a journey releases its search caches. Walking
  maps load in small parts as the search reaches them, and a fixed walk on another continent keeps its measured cost
  and waits to draw its detailed line until you arrive there. Your position's costs refresh when you leave
  the path or once a minute. Repeating a destination reuses its costs; standing still or moving within the same
  walking-map cell by at most three yards also reuses your position's costs. Walk steps name the dock, pier, lift
  or flight master you are heading for.
  ![A walking route around the terrain south of Auberdine](screenshots/darkshore.png)

  Walking legs follow the terrain instead of a straight line to the destination.

  ![Eight-second demo of a route settling, the countdown and the compass](screenshots/demo.gif)

- **A compass that looks like the game.** A slim strip at the top of the screen follows your facing and marks
  Guide's next two turns, the next stop and your destination, in the map's own parchment ticks and gold letters,
  fading out at each end, with your destination drawn as the game's own waypoint pin. On by default; *Show the
  compass* in `/path` turns it off.
  ![The compass strip with the next turns and destination](screenshots/compass.png)

- **Find nearby services.** Open the minimap's tracking menu or the world map's and pick *Nearby services*, or use
  `/spfnear`. It lists class and profession trainers, repairs, reagents, vendors, innkeepers, banks, auction houses, flight
  masters and stable masters. Pick a trainer or vendor specialty to route to the nearest friendly location in your
  installed QuestieDB.

- **Back to your corpse.** Release as a ghost and a red-orange dotted path, the colour of your corpse's tombstone,
  walks you back to it on the world map and minimap, round walls like any walk. Guide leads the way and the tracker
  reads *Return to your corpse* with the time and distance left. Your journey, or one another addon asks for while
  you are a ghost, waits and plans again from wherever you come back to life: at your corpse, at the spirit healer
  or from another player's resurrection. A corpse in another world map, such as a dungeon, gets no path. *Show the
  way to your corpse* in `/path` turns it off.

- **Docks on the world map.** Each pier gets the stock ferry icon and each zeppelin tower a matching
  zeppelin, on its zone and continent map. Hover one to see where each boat goes next, when it arrives and
  when it leaves; the docks it sails to light up. Docks too close to tell apart at the current zoom share
  one icon, and its tooltip names each pier by where it lies, and draws its routes on the map.
  Crossings between continents curve from dock to dock on the Azeroth map; closer maps show the sailing path.
- **On the minimap as well.** Docks, lifts, tram stations and portals appear on the minimap with the same icons
  and tooltips, and vanish at its rim like the game's own tracking icons. The goal you are heading for is the
  exception: beyond the rim, its mark waits on the rim in its direction, a little faded. *Transport* in the minimap's tracking
  menu (or `/path`) turns them off.
  ![Hovering Auberdine’s piers shows departures and lights destination docks](screenshots/docks.png)

- **Lifts, the Deeprun Tram and portals.** The Great Lift, Freewind Post, Thunder Bluff and Undercity
  lifts, and both tram trains, count down like the boats (each landing or station is its own stop). The
  tram shows at its Stormwind and Ironforge entrances. Portals are marked with where they go.
- **Flight masters on the world map**, known and undiscovered, with the game's own flight point icons. Hover one
  for the flights from it and how long each takes: your own timed flights first, then the shipped times. Flight
  points you haven't found are grey, and so is every flight from one you haven't found.
- **In the map's filter menu.** *Flight Masters*, *Boat and Zeppelin Routes*, *Boats & Zeppelins*, *Lifts &
  Tram* and *Portals* turn each layer off; *Other Faction's Routes* shows the
  boats and zeppelins run by the other faction (anyone can ride them, but they are hidden by default).
- **The next departures in the objective tracker.** Walk up to a dock, lift or tram station and a section
  appears beside your quests, counting down to the next arrival and departure of everything that calls there.
  On board, it shows where the boat calls next and when it arrives.
- **A heads-up when your boat is due.** A raid-warning banner, a sound and a flashing taskbar icon, half a
  minute before a timed boat reaches your dock and just before your own boat docks, for anyone waiting AFK.
- **Times from real rides.** Each route's loop time comes from the game's own path data, so one ride tells
  the addon where that boat is for hours. Ride a boat, lift or tram once and its schedule syncs. Until then
  its dock says *no sighting yet*, and a journey counts half a loop as its wait, shown as *leaves in about 2:45*.
  A flight is timed from take-off to landing, and that time is preferred over the shipped estimate from then on. A
  flight's remaining time counts down from how far along the drawn route you are, so it holds steady on a slow or
  fast ride.
- **Shared between players.** Sightings are passed on quietly over guild, party and yell at the docks, so
  someone else's ride can time your boat. No chat messages are shown; turn it off in the settings.

## With my other Forever addons

- **Adventure Guide's suggestions.** With Adventure Guide Forever on (a version whose API offers suggestions) and
  *Shift-click to plan journeys* on, right-click a quest in the tracker or the quest log: under *Plan journey*,
  *Adventure Guide suggests* lists up to three of its suggestions as `[level] title`, in its own order. Choosing one
  starts it as Adventure Guide's own Start does. If its route has moved on since the menu opened, one chat line says
  so.
- **The Forever addons page.** *Forever addons*, the last page of the settings, lists my five WoW: Forever addons
  with a line on each and whether you have it: on, installed but turned off, or not installed. *Copy link* opens a
  small window with the addon's CurseForge address selected, to copy into your browser. It never opens in combat.
- **Quiet hints.** Only for an addon that isn't installed at all, and only while *Suggest my other Forever addons*
  on that page is ticked (it is by default):
  - with Adventure Guide missing, a grey *Suggest quests for my level: Adventure Guide Forever* under *Plan journey*;
  - with Adventure Guide missing, once a session, a grey "What next?" line under a journey you planned yourself
    that arrives with nothing more planned, for two minutes or until another journey starts;
  - with Legacy missing, a grey line on the tooltip of the pin you're heading for when it's a dungeon or raid door.
    Shortest Path can't tell which instances Legacy covers, so it shows on every door.

  Clicking the menu entry or the tracker line opens the link window with *Don't suggest this again*.

## Languages

The addon follows the game's language. Which languages it ships in, how they were translated and how to correct a
line are in [Locales/README.md](../Locales/README.md).

Outside the Chinese clients the game shows yards as metres, so distances do too. *Distances in metres* in Interface
switches to real metres and kilometres.

# Changelog

What changed in each release, in the terms someone finding their way would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists.

Each version's entry is also its release notes on GitHub, CurseForge and Wago. Older entries are kept
verbatim rather than rewritten as the addon moves.

## [Unreleased]

- **A journey you cannot walk to says why.** When you stand somewhere the walking map cannot place, and no flight, boat or spell gets you there either, the tracker now reads no walking path instead of No way there from here.
- **A minimap click that goes nowhere tells you.** Shift-clicking a spot on the minimap that cannot be turned into a place, such as the corner of a square minimap, now prints that no journey can be planned to that spot, as the same click on the world map does.

## [1.8.0] - 2026-10-02

- **Long walks take the boat.** A journey that would be one walk of ten minutes or more now takes boats, trams or flights when they arrive nearly as soon, such as the Stormwind and Menethil boats from Ironforge to Tirisfal Glades.
- **Opening the map no longer breaks it in a fight.** After Show on map, a dock or portal pin, or the nearby services menu had opened the world map, every later look at the map in combat raised a blocked-action warning and lost its quest markers until a reload. The map now opens cleanly and keeps its markers in combat.
- **The Hearthstone slider shows its value.** Minimum Hearthstone saving now reads out the time it is set to, and its name is no longer cut short.
- **The guides stay put in a fight.** In combat the game stretches its quest tracker and nudges it back on screen, which shoved the Forever sections sideways across the screen until the fight ended. They now stay stacked above the quest list.
- **Move the compass.** Settings → Interface → Move the compass lets you drag it anywhere on screen; right-click it to put it back. The journey tracker already moves: turn off Attach to quest tracker and drag it.
- **Setting names fit the panel.** The settings are renamed with shorter names, so none is cut off in the settings panel. Each tooltip carries the detail the name leaves out.

## [1.7.0] - 2026-10-01

- **Follow your movement speed.** Mounted speeds, boosts and slows affect route choices and arrival times, including while standing still. A speed change updates the active journey promptly.

- **Keep guides clear of quests in combat.** Companion sections stay clear when the quest list grows during a fight. Detaching restores the quest tracker’s original Edit Mode position.

- **Remove the Powderfuse Port flight path.** It no longer appears as a flight master or a route stop; its client data lacks the ordinary flight-map flags.

- **Set a minimum Hearthstone saving.** Journeys still consider the Hearthstone by default, or you can require a chosen number of seconds saved over the fastest route without it; class teleports remain eligible.

## [1.6.1] - 2026-09-30

- **Move the shared tracker.** Turn off Attach to quest tracker in Settings to drag all Forever sections together. The position survives `/reload`.

- **Organise the source.** Group runtime modules into Core, Routing, Journey, Transport and UI folders. Update the manifest, developer tools and tests while preserving client load order and runtime behaviour.

## [1.6.0] - 2026-09-30

- **Avoid hostile transport landings by default.** New installs leave opposing-faction boat and zeppelin routes off. Journey planning and travel estimates respect that choice; players who opted in keep their setting.

- **Development disclosure.** This release was developed with AI assistance. Changes were reviewed and checked with automated tests, linting and type checks; live verification remains ongoing.

- **Find nearby services.** Middle-click the route button or use `/spfnear` to open the nearby-services submenu in the world-map tracking dropdown. Route to a friendly class trainer, profession trainer, repairer, reagent vendor, innkeeper, bank, auctioneer, flight master or stable master. Trainers and vendors can be selected by specialty. Locations come from installed QuestieDB; class trainers use Tweaks Forever’s current-class list.
- **Hide walking directions inside quest areas.** Adventure Guide can hold an objective stop while its arrow and Journey lines step aside. Directions return if you leave the area.
- **Keep the tracker legible in combat.** Companion sections stay in one column without moving protected quest-tracker frames.

## [1.5.0] - 2026-09-30

- **A route button on the minimap.** A round button in the game's own minimap button art starts and stops the
  route in one click, and turns gold while a route is on. Right-click opens `/path`; *Show a route button on the
  minimap* turns it off.
- **The compass looks like the game and starts on for new installs.** The dark box and its border are gone: the ribbon is
  the game's own parchment ticks and gold letters, fading out at each end, with the destination drawn as the
  game's own waypoint pin. Existing compass preferences are kept. *Show a compass while Guide is on* in `/path` still turns it off.
- **Settings, grouped.** `/path` opens a short index of Map marks, Transport, Guidance, Alerts and Interface
  instead of one long list, with each group on its own page. Every option is where it was.
- **A dock pin's tooltip survives a filter change.** A pin whose cluster still held a pier the filter had just
  hidden no longer reads an empty departure list and raises a Lua error.

## [1.4.7] - 2026-09-29

- **Keep quest destinations visible.** Adventure Guide can hold a stop until the quest interaction changes, without the normal arrival radius clearing its guidance.
- **Keep one tracker column.** Addon sections stack above the quest tracker regardless of which companion addon loads first.
- **Stop the arrow cleanly.** Cancelling or replacing guidance no longer lets a queued arrow update read a cleared path or revive the previous destination.

## [1.4.6] - 2026-09-28

- **Keep map pins safe and responsive in combat.** World-map and minimap pin refreshes now wait until combat ends,
  while static portal, flight and transport layers reuse unchanged results and recover cleanly if the map releases
  their pooled pins.

## [1.4.5] - 2026-09-28

- **Keep route stops legible.** Numbered stops use warm gold rings instead of dim blue, and later stops retain stronger contrast. Pickup and turn-in badges remain visible on shared stops.

## [1.4.4] - 2026-09-28

- **Separate addon tracking from Blizzard’s layout.** Addon sections now use their own frame pools and sit beside the quest tracker, avoiding the shared tracker registration implicated in Edit Mode aura errors.
- **Check the client integration in CI.** Regression checks run against pinned Forever tracker source and reject native tracker registration.

## [1.4.3] - 2026-09-27

- **Native UI methods stay untouched.** Tracker registration waits for the game to finish loading, and route waypoint pins refresh through map and tracking events.

- **Clearer route pins.** Route circles have a muted blue tint. Grouped stops keep their action icon instead of a `+N` count; the tooltip lists every stop.

- **Smoother flight lines.** Flight routes curve gently on the world map and minimap, retaining their endpoints and loading boundaries.

## [1.4.2] - 2026-09-27

- **The compass draws transport icons as the map does.** Lift and tram arrows sit smaller beside the ferry, as they
  do on the world map and minimap, and the boat icon in the minimap's tracking menu keeps its own shape.
- **The departure dot can be translated.** The "·" between a dock's status and its departure time is now part of a
  phrase a translation can change.

## [1.4.1] - 2026-09-27

- **The corpse run says why it has no path.** When the walk back to your body can't be found, the tracker now gives
  the same reason a journey would: no walking map for the zone, the search failing, or no walking path at all.
  Before, it always said there was no walking path.

## [1.4.0] - 2026-09-25

- **Ready for translation.** Every line the addon writes, from the settings to the tracker and the map's tooltips,
  now comes from one list of phrases, so the addon can be translated. Translations are welcome on GitHub; anything
  not yet translated stays in English, as before.
- **A line on what changed after an update.** The first time you log in on a new version, one line in chat says
  which version you are on and the main thing it changed. It stays quiet on a fresh install, and *Tell me what's new
  after an update* in `/path` turns it off.

## [1.3.0] - 2026-09-25

- **The flight map shows which flight to take.** At the flight master, your journey's route uses the game's own
  lines and lights up the final destination, including flights through several stops. Hover other flight points
  as usual; your route comes back when you move away. *Show the flight to take on the flight map* in `/path` turns it off.
- **Route stops look like the map's own quest buttons.** Each numbered stop on the world map is now the brown disc
  with the gold ring the game uses for quests, with the game's own yellow number in it and the same glow on hover,
  rather than a thinner ring of its own.
- **A route stop that says what stands there keeps its number.** When another addon marks a stop as a flight master,
  a quest giver, a boat and so on, the map shows the numbered step circle with that icon as a small badge on its
  lower right, rather than the icon with a loose number beside it. A single destination still shows the icon alone.
- **The dotted path stops short of each stop.** The dots end a little before every numbered circle, on the map at any
  zoom and on the minimap, instead of running under it.
- **A place you go back to shows one circle.** Stops at the same place, or close enough to overlap on the map, share
  one circle with the first stop's number and a small *+1*, *+2* on its lower right. Hovering it names each stop.
- **Portal and flight point tooltips close with the map.** Closing the world map while hovering one used to leave
  its tooltip on screen; the dock and stop pins already cleared theirs.
- **A route sent while you are a ghost no longer errors.** Another addon's route queued behind the way back to your
  corpse, before any journey that session (after a `/reload` while dead, say), raised a Lua error in the tracker.
  It now waits quietly until you are alive again.

## [1.2.0] - 2026-09-25

- **The way back to your corpse.** Release your spirit and a dotted path leads from the graveyard back to your body,
  in the red-orange of the corpse's own tombstone, on the world map and the minimap. It follows the walking paths
  round walls and hills, Guide steers along it, and the tracker reads *Return to your corpse* with the time and
  distance left. The journey you were on steps aside and comes back when you are alive again, whether at your
  corpse, at the spirit healer or raised by another player; a route another addon asks for while you are a ghost
  waits the same way. *Show the way back to your corpse* in `/path` turns it off.
- **A stop shows what is there.** When another addon says what stands at a stop, such as a quest to hand in, a
  quest giver, a trainer or a flight master, its map pin shows the game's own mark for it, the “?” or “!”, inside
  the stop's gold ring, rather than a pin that hides it. On the minimap the stop is circled, so the game's own icon
  there stays in sight.
- **Guide marks only where each step ends, from the start.** The game's waypoint marker now goes straight to the
  next boat, lift, flight master or your destination rather than to each turn of the walk. Turn off *Guide marks
  only where each step ends* in `/path` to have it lead you round every turn again.
- **Journeys can start with your hearthstone.** The Hearthstone, a mage's city teleports (with a Rune of
  Teleportation in your bags), a shaman's Astral Recall and a druid's Teleport: Moonglade are the first step when
  they save time: *1. Use Hearthstone*, after its own icon and named in your game's language. A cooldown counts as
  waiting time, so a hearth due in two minutes can still win. Your bind point is learned when you next set it at
  an innkeeper, and forgotten if you bind somewhere else without the addon, or on a `/reload` or relog while the
  client does not load addons' saved settings. Other addons' estimates from where you stand count them too.
  *Use your hearthstone and teleports* in `/path` turns this off.
- **Walking legs are round breadcrumb dots.** They are evenly spaced around every bend, instead of dashes, on the
  map and the minimap alike, and a little smaller on continent and world maps. Boats, zeppelins and flights keep
  their solid coloured lines.
- **Arrival alerts sound like the transport.** A boat rings the ship's bell it rings at the dock, a zeppelin
  sounds its horn and the tram plays its own arrival, instead of the raid-warning sound, which reads as a boss
  mechanic rather than your boat.
- **Other addons can offer Shortest Path guidance.** The version 1 public API estimates travel time and starts
  journeys through one or several stops in order. Numbered map pins, drawn as the Adventure Guide's gold-numbered
  rings that glow when you hover them, mark the remaining stops, and the way on to each is drawn as you will
  travel it: walks follow the paths round hills like the current leg, and boats, zeppelins and flights show in
  their colours, never a line across the sea. A dotted straight line stands in only until that stretch is worked
  out, a moment after the current leg's. Stops whose pins would overlap at the map's zoom share one, numbered like
  *4-7* or *2, 5*, and hovering it names each stop in order. The stop you are heading for keeps its pin at full
  strength, and later stops overlapping it join that pin rather than stack on it. Guidance advances on arrival
  and shows your progress. An addon can check the current stop and cancel only its own whole route, preserving a
  journey you start yourself. It can also show how a trip goes, such as the boat, the flight and a new flight
  path to pick up on the way, say why no time is shown (in combat, or no way there yet), and warn you before
  replacing a journey you are already on.
- **Transport shows on the minimap.** Docks, lifts, tram stations and portals appear there with the world map's
  icons, and hovering one gives the same departures tooltip. They vanish at the minimap's rim like the game's own
  tracking icons, and cost nothing away from them. *Transport* in the minimap's tracking menu, or the new setting
  in `/path`, turns them off.
- **An untimed crossing gives the average wait.** A journey step on a boat, lift or tram that nobody has timed yet
  no longer says “no sighting yet” beside a wait it cannot know. It reads *leaves in about 2:45* instead: half the
  loop. Timed crossings read *leaves in 2:28*, a teleport on cooldown *ready in 4:12*, and a flight step no longer
  shows a wait, since taxis leave the moment you pick where to go.
- **Tram journeys name where you are walking.** Journeys through the Deeprun Tram no longer tell you to walk to
  “Unknown”. A step towards a passage or portal names it, such as *Walk to Passage to Stormwind*, and a tram
  passage's map pin says where it leads.
- **Guide tidies up its map pin.** It keeps the pin hidden and removes it when a journey ends, tracking changes or
  you reload, while preserving your own pins and tracking choices.
- **Clicking a dock, station or portal opens the other end.** The world map moves to the far side of the crossing
  and pings where it comes in. A dock with boats or zeppelins to several places asks which one with a small menu.
  The tooltip says when a click will take you somewhere.
- **A search shows the Group Finder spinner.** New journeys show a destination pin and the familiar spinner while
  finding the fastest way, then reveal the route and steps together. Longer searches show their best route after
  three seconds and keep it unless another is at least 30 seconds and 10% faster, or the route no longer works.
  While the spinner turns, the route pulses gently on the world map and minimap, becoming steady when the search
  finishes. Later checks happen quietly without pulsing routes or changing “finding” messages. Journey searches
  retain less memory, clearing a journey frees its caches, and `/path perf` now collects unused memory before
  reporting what remains.
- **The Journey header's time is the sum of the steps below it.** It used to count down to the planned arrival, so
  standing still it slipped a few seconds below the steps and jumped back every five seconds.
- **Walks in Stormwind no longer loop round the city through the canals.** The game never reports your height,
  and the walk started from the lowest floor under you, often the canal bed below a street. A walk from somewhere
  with several levels, or to a map click or stop there, now starts from whichever one is quickest. Zeppelin walks
  end on the tower's platform, not the ground below it, at Grom'gol, Tirisfal and the tower to Zephras. A walk no
  longer runs out and back along the same street, as one from Stormwind's flight master to the Mage Quarter did
  past the Trade District.
- **The rotating minimap and the compass no longer raise Lua errors** when the game briefly hides your facing.

## [1.1.0] - 2026-09-23

- **Open the settings from the addon compartment** on the minimap, as with `/path`.
- **The Journey and Boats section keeps its place in the objective tracker** beside SkillUp Forever's shopping list: the two shared one slot, so their order could change; each now has its own, above your quests.
- **A new icon**, drawn to match the other WoW: Forever addons, now also on the three walking maps in the addon list.

## [1.0.0] - 2026-09-23

- **A route finder for WoW: Forever.** Pick a spot on the map or a quest and it plans the fastest way there and
  walks you to it.
- **Every boat and zeppelin has its dock marked on the world map**, including the new Forever crossings to
  Southshore, Riverglades and Zephras Isle: a ferry for boats and a zeppelin drawn to match it for zeppelins.
  Hovering a dock lists where each boat goes next, counts down to its arrival and departure, and lights up the
  docks it sails to. Docks that would overlap on a zoomed-out map share one icon, with each pier named in the
  tooltip. The map's filter menu can hide the icons, or just the other faction's routes. Near a dock, a Boats
  section above your quests shows the same countdowns.
- **One ride fixes a boat's schedule for hours.** Each route's loop time comes from the game's own path data.
  Ride once and it syncs, and the sighting is shared quietly with your guild, party and anyone at the dock, so
  other players' rides time your boats too. Sharing can be turned off in the settings (`/path`).
- **Lifts, the tram and portals are timed and marked too.** The lifts at the Great Lift, Freewind Post, Thunder
  Bluff and Undercity, and both Deeprun Tram trains, are timed the same way: countdowns on the map and in the
  tracker, synced from a ride and shared. The tram is marked at its city entrances, and portals are marked with
  where they lead.
- **Shift-click the world map or minimap to plan the fastest way to that spot.** It combines walking, the flight
  points you know, boats and zeppelins with their live waits, the lifts, the tram and portals, and a flight master
  you haven't found yet when walking to it pays off. **Plan journey** in a quest's right-click menu, or
  Shift-clicking its marker on the map, does the same for its objective, or its turn-in once it is complete.
- **The route is drawn on the world map and minimap** as a slim outlined line that reads on any map, walking legs
  dotted and the destination marked with the waypoint pin, and its steps sit in the objective tracker like a
  tracked quest. Flight masters are marked on the world map, known and undiscovered, and hovering a dock draws its
  boat and zeppelin routes. On the Azeroth map, crossings curve from dock to dock across the sea; closer maps keep
  the real sailing path to the map edge.
- **Guide moves the game's own waypoint marker along the route.** It is on from the start of every journey and
  toggled from the tracker header, goes turn by turn (or only to where each step ends, a setting), and gives your
  tracked quest back when you finish.
- **Walking legs follow the ground** round walls, cliffs and water on Eastern Kingdoms, Kalimdor and Zephras Isle,
  from walking maps that come in the same download. They take tunnels such as Dun Algaz and the Undercity's lower
  levels, ride a lift when the way round on foot is longer, and take the boat rather than a long swim. Walks keep
  out of water, unless you have Water Walking or Levitate, when the step asks you to cast it and the route
  crosses. Walks between docks, flight masters and portals are measured ahead of time and ship with the addon, so
  plans spend less time checking walks. Replanning on board keeps you on the boat.
- **Searches settle quickly and stay light.** While a journey's walks are being checked, the tracker says it is
  finding the fastest way and the route pulses softly on the map and minimap. Easy routes settle quickly, and
  longer searches stop once unchecked alternatives cannot beat the chosen route, without searching the whole
  continent. Drawn paths stay visible during refreshes. Route finding uses less memory and shares its work across
  frames to reduce hitches; the first walking-map load starts after the click. Repeated journeys to the same
  destination reuse their walking costs. Your position is checked again when you leave the path or once a minute;
  standing still or moving a few yards within the same walking-map cell reuses its costs. Once settled, the
  arrival countdown returns. Walk steps name the dock, pier, lift or flight master you are heading for.
- **An optional compass strip follows your facing.** It marks Guide's next two turns, the next stop and your
  destination, with yards to the next turn. It is off by default and can be turned on in `/path`. Its heading
  glides smoothly as you turn, with stock UI fonts, a soft frame and correctly proportioned markers. Marks for the
  same place or bearing combine into one, keeping the destination or transport icon and the distance to your next
  turn.
- **Guide and the route keep going when your coordinates drop out.** They survive temporarily unavailable player
  coordinates, and the drawn walking leg trims as you move without waiting for the next route search. On the
  minimap, the final 30 yards fade into the destination and the whole line fades as you approach within 40 yards.
  Guide's final marker uses a fading arrow nearby so its native waypoint does not cover the goal; the world-map
  route keeps its contrast.
- **On board, the tracker shows where the boat calls next** and when it gets there, once the ride has synced.
  Half a minute before a timed boat reaches the dock you are waiting at, and shortly before your own boat docks,
  a raid-warning banner, a sound and a flashing taskbar icon let you know, even with the game in the background.
  A `/reload` or logout mid-ride keeps the ride so far. Every map layer, the tracker, the alerts and their sound,
  the planner and sharing can each be switched off in the settings.
- **The Journey section in the objective tracker shows the time and yards remaining** across every leg,
  following measured walking paths and transport routes. The destination stays on its own line, and the totals
  update as you travel without rebuilding the tracker layout.
- **Background polling sleeps when you are standing still** away from travel activity. Docks and passive boat or
  lift rides still wake the countdowns and observation; unchanged tracker content is reused, and shared sightings
  don't rebuild unrelated map layers. Walking searches and tracker updates wait through combat. Less terrain
  bookkeeping is built at login, and `/path perf` shows the client's measured CPU cost and addon memory for
  checking performance in game.

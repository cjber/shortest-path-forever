# Addon API

Addons can use `ShortestPathForever.API` (`version = 1`) with uiMapIDs and normalized 0–1 coordinates.

- `Estimate(fromMap, fromX, fromY, toMap, toX, toY)` returns travel seconds, or `nil` and why (`"combat"`,
  `"invalid"` or `"unreachable"`), without changing guidance. It omits endpoint terrain searches and caches
  estimates for five seconds, rounding origins to 0.0001. An estimate from where the player stands counts their
  hearthstone and class teleports, with cooldowns, unless the setting *Use hearth and teleports* is off;
  from anywhere else it leaves them out.
- `EstimateDetail` takes the same arguments and cache and returns `{seconds, legs}`, each leg a fresh
  `{mode, to, seconds, wait?, newFlightPath?}`.
- `NavigateRoute(owner, stops)` guides through 1 to 64 `{map, x, y, title, tooltip}` stops in order, advancing on arrival
  and ending after the last. Remaining stops have numbered map pins, and the way between them is drawn as
  planned, walks along the walking map, once worked out behind the current leg; the tracker and arrow show
  “Stop 2 of 4: …”.
- `Navigate(owner, map, x, y, title, kind)` is the one-stop form.

  Both return a boolean; invalid input, combat or disabled Journeys return `false` without replacing guidance.
  Titles are optional, as is `tooltip`, a destination detail shown on the stop pin's tooltip and never used as
  the arrow label. A stop with `hold = true` waits for its owner to replace or cancel the route rather
  than advancing on arrival. For held objective areas, optional `radius` (yards, finite and non-negative)
  hides walking directions inside the area while preserving ownership and the current stop. Directions
  resume outside it.
- `CurrentStop(owner)` returns the current 1-based stop or `nil`.
- `Cancel(owner)` returns `true` only when it clears that owner's whole route.
- `Active()` says whether any journey is guiding, yours or another addon's.
- `Ended(owner)` says why that owner's last journey ended: `"arrived"` after its last stop, `"cleared"` by the
  player (or by turning Journeys off), `"replaced"` by another addon's or the player's journey, or `"cancelled"`
  by the owner's own `Cancel`; its second return is the `GetTime()` it ended. It is `nil` while the journey runs,
  before the owner's first, and after a reload. Poll it: Shortest Path fires no event of its own when a journey
  ends.

Use your addon's name as `owner`; starting another journey replaces ownership.

## Stop kinds

A stop's optional `kind` says what stands there: `"pickup"`, `"turnin"`, `"objective"`, `"trainer"`,
`"innkeeper"`, `"flightmaster"`, `"battlemaster"`, `"dungeon"`, `"boat"`, `"zeppelin"`, `"lift"`, `"tram"` or
`"portal"`. Its numbered map pin then wears the game's own mark for it (a quest's “!” or “?”, a flight master, a
boat) as a small badge on its lower right; a lone stop shows the mark alone. The minimap circles the spot
rather than covering the game's icon there. Any other kind is ignored, as is a kind whose art the client lacks: the
stop keeps the plain pin.

![Three stops through Thelsamar: the flight master, a quest giver and a hand-in, each badged on its numbered quest button](screenshots/stops.png)

## TomTom waypoints

While TomTom is not installed and *Let guides set TomTom waypoints* is on, Shortest Path provides the global
`TomTom` table guides know, so Questie, Zygor and others route here instead. The global is never defined when
TomTom is installed or loads later.

- `TomTom:AddWaypoint(map, x, y, opts)` starts a journey to that uiMapID and 0-1 point and returns the waypoint
  table: `[1]` the map, `[2]` and `[3]` the point, `title` and `from` from `opts`. The other `opts` fields
  (`persistent`, `minimap`, `world`, `silent`, `crazy`, `callbacks` and the distances) are copied onto it.
- `TomTom:AddMFWaypoint(map, floor, x, y, opts)` takes the same map and point; this client has no map floors, so
  `floor` is only checked.
- `TomTom:AddZWaypoint(continent, zone, x, y, desc, ...)` takes 0-100 coordinates. The old continent and zone
  indices have no client mapping on this build, so the zone is used when it names a uiMapID and the continent
  otherwise.
- `TomTom:RemoveWaypoint(waypoint)` cancels the journey only when that waypoint is the one this shim set.

Every waypoint belongs to one owner, so a newer one replaces the journey rather than queueing. Turning the
setting off removes the global and clears any journey it started.

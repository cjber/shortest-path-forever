# Addon API

Addons can use `ShortestPathForever.API` (`version = 1`) with uiMapIDs and normalized 0–1 coordinates. Additions
keep `version` at 1 and raise `minor` (1 from `Subscribe`, absent before); check that a function exists before
calling it. The full types are in [`types/API.lua`](../types/API.lua).

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
  resume outside it. Optional `questID` names the quest a held area stands for, and optional `questIDs` every
  quest it stands for when there are several: an array of 1 or more quest IDs, given with or without `questID`.
  While the player stands in the area of any named quest, by the client's own inside-area state, the game's own
  area takes the place of the stop pin and its line: the world map draws each named quest's area with the
  client's own blob, the minimap's own quest blob is recoloured, and both wear the stock bonus objective gold.
  Leaving the area, the stop changing and the journey ending all restore the stock map and minimap. Optional
  `shapes` names the area as 1 or more `{map, x, y, radius}` circles, each on the map it names with its `radius`
  in yards. Circles are never drawn. They decide inside only for a stop that names no quest, or while the client
  has no answer for any quest it names, and such a stop keeps its pin and line.
- `CurrentStop(owner)` returns the current 1-based stop or `nil`.
- `Cancel(owner)` returns `true` only when it clears that owner's whole route.
- `Active()` says whether any journey is guiding, yours or another addon's.
- `Ended(owner)` says why that owner's last journey ended: `"arrived"` after its last stop, `"cleared"` by the
  player (or by turning Journeys off), `"replaced"` by another addon's or the player's journey, or `"cancelled"`
  by the owner's own `Cancel`; its second return is the `GetTime()` it ended. It is `nil` while the journey runs,
  before the owner's first, and after a reload. `Subscribe` says when to read it again.
- `Subscribe(callback)` calls `callback(changes)` on the frame after guidance changes, at most once per burst of
  changes, whoever made them. `changes` is a new table each call with any of these set to `true`: `started` (a
  journey began where none was under way), `changed` (the journey under way now heads somewhere else, replaced or
  on to its next stop; sending the same destination again is no change), `ended` (it ended with nothing after it),
  `stop` (what `CurrentStop` answers changed: an addon's route started, moved on or ended) and `active` (what
  `Active` answers changed, including the player turning guidance off or a corpse run guiding after a journey
  ends). Several can be set together, so read `CurrentStop`, `Ended` and `Active` again rather than replaying
  them. A callback is not told about a burst already under way when it subscribed. It returns a function that
  unsubscribes, safe to call twice. An error in one callback goes to the game's error handler without stopping
  the others. A non-function callback is an error.

Use your addon's name as `owner`; starting another journey replaces ownership.

## World map markers

Shortest Path draws its world map pins on frames of its own, so `WorldMapFrame:EnumeratePinsByTemplate` doesn't find
them. The Forever addons share one global table instead: the first to load creates `ForeverMapMarkers`, and each sets a
function under its folder name. `ForeverMapMarkers.ShortestPathForever(map)` takes the map frame (`WorldMapFrame`) and
returns a new array of `{x, y, kind}`. These are the pins shown on `map:GetMapID()`, as 0–1 fractions. `kind` is `"dock"`,
`"portal"`, `"flight"` or `"stop"`. The array is empty while the map is closed, in combat, and for a map Shortest
Path doesn't draw on. Another addon adds its own markers the same way:

```lua
ForeverMapMarkers = ForeverMapMarkers or {}
ForeverMapMarkers.MyAddon = function(map) return {} end
for _, markers in pairs(ForeverMapMarkers) do
	for _, marker in ipairs(markers(WorldMapFrame)) do
		-- marker.x, marker.y, marker.kind
	end
end
```

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
TomTom is enabled or loads later; a TomTom switched off in the AddOns list leaves the shim in place.

- `TomTom:AddWaypoint(map, x, y, opts)` starts a journey to that uiMapID and 0-1 point and returns the waypoint
  table: `[1]` the map, `[2]` and `[3]` the point, `title` and `from` from `opts`. The other `opts` fields
  (`persistent`, `minimap`, `world`, `silent`, `crazy`, `callbacks` and the distances) are copied onto it.
- `TomTom:AddMFWaypoint(map, floor, x, y, opts)` takes the same map and point; this client has no map floors, so
  `floor` is only checked.
- `TomTom:AddZWaypoint(continent, zone, x, y, desc, ...)` takes 0-100 coordinates. The old continent and zone
  indices have no client mapping on this build, so the zone is used when it names a uiMapID and the continent
  otherwise.
- `TomTom:RemoveWaypoint(waypoint)` cancels the journey only when that waypoint is the one this shim set.
  `TomTom:ClearWaypoint(waypoint)` does the same, and `TomTom:ClearAllWaypoints()` removes the shim's waypoint.
- `TomTom:AddWaypointToCurrentZone(x, y, desc)` takes 0-100 coordinates on the map you are on.
- `TomTom:IsValidWaypoint(waypoint)` and `TomTom:WaypointExists(map, x, y, desc)` say whether that waypoint is the
  one set. `TomTom:GetClosestWaypoint()` and `TomTom:SetClosestWaypoint()` return it, as the only one there is.
  `TomTom:GetDistanceToWaypoint(waypoint)` gives its yards from you, on your continent, or `nil`.
- `TomTom:SetCrazyArrow(waypoint, arrival, title)` on a waypoint table that isn't the current one starts a journey
  to it.

Every waypoint belongs to one owner, so a newer one replaces the journey rather than queueing. Turning the
setting off removes the global and clears any journey it started.

With TomTom installed, *Follow TomTom's arrow* (off by default) works the other way round: Shortest Path hooks
TomTom's own `SetCrazyArrow`, `RemoveWaypoint` and `ClearWaypoint` with `hooksecurefunc` on TomTom's table and plans a
journey, owned by `"TomTom"`, to each waypoint the arrow takes. At login, once the world is up, it follows the
waypoint TomTom's arrow was restored to, unless a journey is already under way. Removing that waypoint, including
through TomTom's *Remove all waypoints* or `/way reset all`, cancels the journey. TomTom's corpse arrow is not
followed: the corpse run does that job and keeps the journey you were on.

## Alongside Polestar

Polestar has a TomTom stand-in, a `/way` and a *Follow TomTom's arrow* of its own, and can hand its target to
Shortest Path through this API (its *Hand guiding to Shortest Path Forever*). With both installed, in either load
order, neither blocks the other's and no waypoint is planned twice:

- The stand-in takes the `TomTom` global as Shortest Path loads, and Polestar takes it at login only while it's free,
  so it stays out. If *Let guides set TomTom waypoints* was off at login and Polestar's stand-in
  (`Polestar.Nav.tomtomShim`) took the global, Shortest Path doesn't count it as TomTom: turning the setting on takes
  the global over, and turning it off again gives Polestar's back while Polestar still answers waypoints
  (`Polestar.Get("nav.answerTomTom")`) and isn't handing its target here (`Polestar.Nav.HandedOff()`).
- `/way` is claimed as Shortest Path loads, while TomTom isn't installed and no addon has it, and Polestar claims it
  at login only while it's free. At login, TomTom or an addon that took `/way` without looking keeps it, and Shortest
  Path lets it go.
- *Follow TomTom's arrow* hooks only the real TomTom, never Polestar's stand-in. When Polestar follows TomTom's arrow
  too and hands its target here (`nav.followTomTom` and `nav.spfHandoff`), that target arrives as Polestar's journey,
  so Shortest Path doesn't follow the waypoint as well. With Polestar guiding by itself, Shortest Path follows, and
  Polestar steps aside while that journey runs. The copy of its own target Polestar puts in TomTom
  (`from = "Polestar"`) is never followed, and the stand-in refuses it (`AddWaypoint` returns `nil`): whether
  Polestar's target goes to Shortest Path is Polestar's hand-off setting.
- Polestar's *Follow TomTom's arrow* is meant for the real TomTom. While this stand-in answers in its place, leave it
  off: a guide's waypoint is already a journey here.

Polestar's hand-off reads the meanings above as they are written: `NavigateRoute` with one stop and its `kind`,
`hold`, `radius`, `shapes`, `questID` and `questIDs`; `CurrentStop` still naming a stop while `Active()` is false
when there is no way there; `Active()` true while anyone's journey guides; each reason `Ended` gives; `Cancel`
clearing only the owner's own journey; and `Subscribe`'s news on the next frame. `tests/api_contract_spec.lua` pins
each of them, so a change to one fails the specs and would need `version` 2.

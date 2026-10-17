# Tests

Every spec is a plain LuaJIT script run from the repository root (`luajit tests/<name>_spec.lua`). CI runs them all
with a glob, so a new `*_spec.lua` is picked up without being listed anywhere. None of them needs the game: the
client is stubbed, and agents never launch it. Checks that need the real client go in a PR's in-game list.

## Layers

| Layer | How it loads the addon | Use it for | Examples |
|---|---|---|---|
| Planner | `Transport/Model.lua` and `Routing/Planner.lua` on hand-made docks, routes and flight paths | which way a plan goes, waits, teleports and hearth rules, with no frames | `planner_spec`, `teleports_spec`, `planner_pruning_spec` |
| Walking maps | `Routing/PathGrid.lua`, `Path.lua` and `PathJobs.lua` on the shipped `Nav/` maps | walking search, costs, slices and loading | `path_spec`, `path_many_spec`, `nav_loading_spec` |
| Journey | `journey_driver.lua`: the journey, search, guide and steps over a stubbed client, with `path_fake.lua` answering walks, plus whatever files the spec loads on top | journeys, arrivals, replans, the public API, TomTom and anything hooked on them | `journey_spec`, `api_spec`, `tomtom_spec`, `journey_optimal_spec` |
| Single module | the module's own file, with only the client calls it makes stubbed in the spec | settings rows, the compass, the timetable, flight times | `settings_spec`, `compass_spec`, `timetable_spec`, `taxitimes_spec` |
| Whole client | `ui_client.lua` then `ui_map.lua`: the addon in TOC order against Blizzard's own map, tracker and menu code, which `tools/fetch_blizzard_ui.sh` fetches pinned into `tools/.cache/blizzard-ui` | pins, route strokes, the tracker host, menus and waypoints | `smoke_spec` (fetches it itself), and the `*_ui.lua` checks `tests/ui.sh` runs: `api_ui`, `route_ui`, `tracker_ui`, `waypoint_ui` |

## The journey driver

`journey_driver.lua` returns `driver`, with the addon's namespace as `driver.ns` and its globals as `driver.env`:

- `driver.load(file)` runs one more addon file in the same namespace and globals, as the TOC would.
- `driver.begin(from, to)` stands you at `from` and Shift-clicks the world map at `to` (world points), then settles
  the walking search. `driver.click(to)` clicks without settling, and `driver.minimap()` Shift-clicks the minimap.
- `driver.move(point)` moves you. `driver.update(seconds)` is one frame of that length: the clock moves on, the
  deferred events fire once, each shown frame's `OnUpdate` runs once, and the walking search settles.
- `driver.fire(event)` sends a client event to every frame; `driver.shown()` is the route drawn on the map and
  `driver.waypoint()` the user waypoint and whether it is tracked.
- `driver.path` is the fake walking search. While `auto` is on (the default), settling answers every search with the
  straight line. Set `auto = false` and nothing is answered, `begin` included, until the spec calls `finish` or
  `costs`.
- `driver.secret` stands in for a value the client keeps secret; using it as a number errors.

`tomtom_fake.lua` stands in for TomTom 4.3.12 for `tomtom_follow_spec` and `polestar_compat_spec`, which also has a
small Polestar of its own, written from Polestar's documented behaviour. `api_contract_spec` pins the API meanings
other addons build on.

## Benches

Not specs: run them with `luajit -joff`.

- `journey_bench.lua` prints every search and the worst frame of a real journey on the shipped maps. AGENTS.md keeps
  that frame under 3 ms; `journey_performance.md` has the search's own 2 ms budget and how it is shared.
- `hearth_savings_bench.lua` checks the Hearthstone comparison's plan; `SPF_BENCH_STRICT=1` adds its 3 ms budget.
- `planner_speed_bench.lua` checks that a run-speed change reuses the planner's graph.
- `memory_bench.lua`, `runtime_bench.lua` and `activity_bench.lua` drive the whole client, so they need
  `tools/fetch_blizzard_ui.sh` run first (`tests/ui.sh` or `smoke_spec` does it). `search_performance.md` records the
  memory figures, and `journey_performance.md` the runtime ones.

## Tools that live here

- `walk_sim.lua` follows a real journey's geometry at walking speed.
- `nav_compare.lua` compares the shipped walking maps with another source snapshot.
- `test_typecheck.py` is the Python regression test for the multi-value lint behind `tools/typecheck.sh`.

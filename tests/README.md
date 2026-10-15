# Tests

Every spec is a plain LuaJIT script run from the repository root (`luajit tests/<name>_spec.lua`). CI runs them all
with a glob, so a new `*_spec.lua` is picked up without being listed anywhere. None of them needs the game: the
client is stubbed, and agents never launch it. Checks that need the real client go in a PR's in-game list.

## Layers

| Layer | How it loads the addon | Use it for | Examples |
|---|---|---|---|
| Planner | `Transport/Model.lua` and `Routing/Planner.lua` on hand-made docks, routes and flight paths | which way a plan goes, waits, teleports and hearth rules, with no frames | `planner_spec`, `teleports_spec`, `planner_pruning_spec` |
| Walking maps | `Routing/PathGrid.lua`, `Path.lua` and `PathJobs.lua` on the shipped `Nav/` maps | walking search, costs, slices and loading | `path_spec`, `path_many_spec`, `nav_loading_spec` |
| Journey | `journey_driver.lua`: the journey, search, guide and steps over a stubbed client, with `path_fake.lua` answering walks | journeys, arrivals, replans, the public API and anything hooked on them | `journey_spec`, `api_spec`, `tomtom_spec`, `journey_optimal_spec` |
| Single module | the module's own file with only the client calls it makes stubbed in the spec | settings rows, the compass, the timetable, teleports, TomTom | `settings_spec`, `compass_spec`, `timetable_spec`, `taxitimes_spec` |
| UI checks | `tests/ui.sh`: `ui_client.lua` and `ui_map.lua` load the addon in TOC order against Blizzard's own map, tracker and menu code, fetched pinned by `tools/fetch_blizzard_ui.sh` | pins, route strokes, the tracker host, menus and waypoints | `api_ui`, `route_ui`, `tracker_ui`, `waypoint_ui` |

## The journey driver

`journey_driver.lua` returns `driver`, with the addon's namespace as `driver.ns` and its globals as `driver.env`:

- `driver.load(file)` runs one more addon file in the same namespace and globals, as the TOC would.
- `driver.begin(from, to)` stands you at `from` and Shift-clicks the world map at `to` (world points); the walking
  search answers at once.
- `driver.move(point)` and `driver.update(seconds)` move you and run that long of frames, events and searches.
- `driver.path` is the fake walking search: set `auto = false` to answer searches yourself with `finish` and `costs`.
- `driver.secret` stands in for a value the client keeps secret; using it as a number errors.

`tomtom_fake.lua` stands in for TomTom 4.3.12 for the TomTom specs.

## Benches

Not specs: run them with `luajit -joff`. `journey_bench.lua` times every frame of a real journey on the shipped maps
(frames stay under 3 ms; see `journey_performance.md`), and `hearth_savings_bench.lua` checks the Hearthstone
comparison (`SPF_BENCH_STRICT=1` adds its 3 ms budget). `planner_speed_bench.lua`, `memory_bench.lua`,
`runtime_bench.lua` and `activity_bench.lua` measure the planner, memory, idle cost and event cost;
`search_performance.md` records their numbers.

## Tools that live here

- `walk_sim.lua` follows a real journey's geometry at walking speed.
- `nav_compare.lua` compares the shipped walking maps with another source snapshot.
- `test_typecheck.py` is the Python regression test for the multi-value lint behind `tools/typecheck.sh`.

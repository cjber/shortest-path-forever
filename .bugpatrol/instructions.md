# About the app

Shortest Path Forever is a World of Warcraft: Forever addon written in Lua 5.1. It cannot run outside
the game client, and you must never start the game. What runs here is its headless test harness: each
`tests/<name>_spec.lua` stubs the client API, loads the addon files the TOC lists, and checks one
feature. Run a spec with `luajit tests/<name>_spec.lua`; a failing spec exits non-zero and prints the
failed assertion. `luacheck <file>` lints a file.

Two benches are part of the suite and run outside the game:

- `luajit -joff tests/journey_bench.lua` times the planner and asserts a frame budget.
- `SPF_BENCH_STRICT=1 luajit -joff tests/hearth_savings_bench.lua` times the hearthstone comparison.
  Its 3 ms budget is a local machine budget, so a failure here is a timing signal, not a bug report,
  unless the code path it exercises changed.

The world map has its own invariant: `tests/map_canvas_spec.lua` runs the map files against a canvas
that fails on any write. Drawing goes through `UI/MapCanvas.lua` with the addon's own frames, never
`AddDataProvider`, `AcquirePin`, `AddOverlayFrame` or a `MapCanvasPinMixin`.

Use the specs and `luajit -e` one-liners that load the harness to check what a change claims. Report a
spec that fails, an error that a spec prints, or a behaviour a spec shows that the change does not
intend.

## Sign in

No sign-in.

## Important flows

- Planning a journey between two places: the planner picks walking, flight, boat, zeppelin, tram,
  portal and teleport legs by travel time, and the guide line follows the chosen route.
- The guide: next turn, next stop, destination, and the warning when a flight master is undiscovered.
- Docks: live boat and zeppelin times, the dock warning, and the dock markers on the map.
- The travel journal, when it is turned on: distance walked, journeys, transports, flights, portals.
- The tracker section and the compass/settings pages.

## Never do these things

- Never launch the game, Battle.net, Lutris or Wine.
- Never edit, move or delete files.
- Never use the network.
- Never treat a bench timing as a functional failure without saying so.

# Verify navigation in the game client

Use a packaged build containing the merged navigation helpers and the performance-accounting fix.
The AddOns directory must contain `ShortestPathForever`, the three base navigation addons and all 39 helper
addons. Leave unrelated addons enabled for the integration run. Capture the client build and addon version
with the results in [issue #103](https://github.com/cjber/shortest-path-forever/issues/103).

## Cold cross-continent journey

1. Start in Auberdine on a character that can use the Menethil boat; turn off competing travel shortcuts if they bypass that crossing.
2. `/reload`, open the world map and Shift-left-click a reachable location near Menethil Harbor in the Wetlands.
3. Confirm the journey appears without a visible freeze and the distant walk keeps a plausible time and distance while its line is still simple.
4. Run `/path perf` and record the CPU peak, ticks over 5 ms and memory total; CPU profiling unavailable is a missing measurement, not a pass.
5. Take the planned crossing without cancelling the journey and confirm the Wetlands walking line gains terrain detail after landing.
6. Confirm the journey stays selected, continues guiding and has no unexpected straight-line reset or Lua error.

## Cancellation and combat

1. `/reload`, start the same cold journey, then left-click the route button while its search is still pending.
2. Confirm the tracker and route disappear and do not return when the pending work completes.
3. Start a journey, open and close the map out of combat, then enter ordinary combat and open the map again.
4. Confirm there is no blocked-action message, no protected pin creation and no repeated search work during combat.
5. End combat and confirm one resumed search settles and guidance remains usable.

## Evidence

Record the observed route, character travel options, client build, addon version and other loaded addons.
Save `/path perf` output before and after landing. Its CPU figures describe the main addon; memory includes
loaded navigation helpers. Helper addon loading may need separate client profiling for total frame attribution.
Capture errors or blocked-action messages verbatim. If a result fails, include the shortest reproducible sequence.

These checks are pending. Headless tests cover retained-route arrival, cancellation, missing helper parts,
combat suspension and performance-memory accounting, but do not establish live loading or secure UI behaviour.
Repository instructions prohibit agents from driving the client, so completion requires a human client run.

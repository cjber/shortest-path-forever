# Journey performance

Terrain is compressed inside the main addon. The client parses the compressed strings at login and uses
`C_EncodingUtil` to decode only the fields a search needs. A compressed block expands to at most 16 KB.
No terrain helper addons or `LoadAddOn` calls are needed during a route search.

Searches and plans share a 2 ms frame budget, with periodic checkpoints. The budget is cooperative: one native
call or garbage collection can exceed it. Combat pauses queued searches until combat ends. No event, tooltip,
click or callback plans in its own frame: it starts a path job and shows the answer when it lands
(`tests/frame_budget_spec.lua`). A cluster's graph decodes in slices of 512 nodes; a reuse asked in a frame
answers only from a decoded cluster.

Decoded grids and graph nodes have separate memory ceilings. Completed grids release their raw strings;
compressed blocks stay available for cache eviction and revisits. Cancellation stops queued work and discards
partial decoded fields. A walking job holds its endpoint and refined corridor grids through smoothing and
point construction, temporarily exceeding the grid ceiling when the corridor needs it. Each refined point keeps
its surface height so drawing does not decode terrain again. Completion, errors and cancellation release only
that job's holds; idle cleanup still preserves only Floor's pinned clusters. It runs once no search has run for
`Path.linger` (30 s) rather than whenever the queue drains: a journey searches its walks again every few seconds,
and reuses the clusters the last search decoded (`tests/linger_spec.lua`). Offline tools use system zlib to implement the client's encoding API.

The journey search uses lower bounds to decide which endpoint walks still need exact costs. A feasible plan
uses a single earliest label per arrival state to find a valid incumbent quickly. The final optimiser keeps
visited-set alternatives to prove the optimum. The incumbent arrival allows the planner to discard labels that
cannot beat it. The route's current walking leg gets its geometry first. Later legs with known costs wait until they become the next walk to follow.
A plan given its path job pauses at the budget. The public `Estimate` and `EstimateDetail` still plan whole in
their caller's frame: another addon may ask from inside a C call (a secure hook), where Lua 5.1 cannot yield (#717).

A feasible route can be followed while the search continues to prove the final route. The first walking leg
must be measured before that route is offered. Cancellation, destination changes and water-mode changes
invalidate outstanding work. The completed initial search must match an unrestricted exact-cost plan.

## Verification

```sh
luajit tests/nav_loading_spec.lua
luajit tests/path_many_spec.lua
luajit tests/linger_spec.lua
luajit tests/journey_progressive_spec.lua
luajit tests/journey_optimal_spec.lua
luajit tests/frame_budget_spec.lua
luajit -joff tests/journey_bench.lua
luajit -joff tests/runtime_bench.lua cold gc
SPF_BENCH_STRICT=1 luajit -joff tests/hearth_savings_bench.lua
luajit tests/walk_sim.lua
python3 tools/check_generated.py --offline
```

The runtime benchmark reports first usable guidance separately from completed proof, and includes compressed
terrain startup and memory. Figures are headless LuaJIT with JIT disabled, not in-game profiling. The offline
base64 implementation is Lua; the client uses native encoding APIs.

Check in game with a fresh login, a local walk, a journey with transport, and a cross-continent journey. Cancel
and change destinations while searching, and let a later walking leg become active. `/path perf` reports the
main addon's collected memory, including bundled terrain.

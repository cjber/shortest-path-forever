# Navigation and tooling measurements

The baseline is `150e7039b4231699b5a155cf84edd5a2b6322637`. Measurements use an AMD Ryzen 7 9700X,
30 GiB RAM, Linux and Python 3.14.7. Other desktop workloads were present, so these are comparative measurements,
not a promise about every frame in the game. The existing tiles come from the historical 1.60.1.69913 bake logs;
they predate the extractor's complete-inventory manifest. They prove equivalence for the inputs supplied.

## Python baker

Map 0 has 736 populated tile files. Two populated crops cover ground, water and overlapping floors. The original
single-worker runs of rows 30-32, columns 30-32 took 19.09 and 16.94 seconds; six workers took 14.25 and 14.57 seconds.
The identical output SHA256 is `292984c5f0f51b9a7e65ca77409d4460e935b30811a4c5252d929f3ae6e5db6a`.

| Sample | Original graph phase | Reused adjacency | Result |
|---|---:|---:|---|
| Rows 30-32, columns 30-32 | 8.51 s | 3.30 s | Byte-identical Lua |
| Rows 47-49, columns 29-31 | 6.37 s | 3.71 s | Byte-identical Lua |
| Full map 0 | Graph phase not timed separately | 593.85 s | Byte-identical Lua to the original full bake |

The original full bake completed in 1,264.6 seconds wall time and 1,663 seconds CPU time. Its
getrusage largest-process peak was reported as 1,086 MB, not aggregate concurrent memory. The optimized
full run did not capture total wall time, so these totals cannot establish an end-to-end speedup.
Both full Lua files are byte-identical.

The full map has 29,813 graph nodes and 168,860 edges. Its component phase took 19.54 seconds, floor assembly
3.56 seconds and emission 8.54 seconds. Parent-only cProfile misses the rasterizer workers; separate worker
profiling shows connectivity and portal geometry checks dominate a dense tile.

A bounded 12-tile worker cache experiment on the first crop changed raster time from 9.35 to 9.31 seconds while
largest-worker RSS rose from about 104 to 160 MiB. The workload was not isolated, so this establishes no useful
speed gain. The cache is not adopted. Reusing legal directed adjacency is retained: it removes repeated work
without changing water costs, floor connectivity or graph pruning.

`gen_nav.py --metrics report.json --build <input-build>` records input and code hashes, crop bounds, worker count,
phase wall time, CPU and Linux getrusage peaks. The largest worker's RSS is not concurrent aggregate memory.
`bake.sh` additionally requires the extractor's build, recipe and expected-tile manifest, and verifies every tile
status and file. Use a fresh output directory for unproven old tiles or changed extraction inputs.

The pinned Mappster upstream currently returns Repository not found, preventing a fresh extractor/Recast timing
and full extractor build. The new provenance module compiles and passes its standalone .NET 10 regression test.
Restore the pinned source before claiming a complete extraction benchmark; historical extractor logs are not a
substitute for one.

## In-game Lua paths, measured headlessly

These timings use `luajit -joff tests/runtime_bench.lua cold`. The harness executes real addon planning and
navigation code with client API stubs. Atomic loading of the original continent required roughly 20-26 ms in one
frame; splitting files in that same addon did not add a scheduling boundary.

The packaged data now loads in whole-cluster helper addons with at most 512 KiB of Lua each. Repeated cold-route
runs measured 2.43 and 2.54 ms worst active frames, with approximately 5 MiB resident memory including the harness,
compared with approximately 18.4 MiB before. One run under concurrent workloads reached 3.03 ms. The 2 ms search
allowance reserves scheduler headroom; it is not a hard total-frame deadline.

The journey benchmark covers four representative journeys and keeps exact route costs, with no straight-line
resets. Deferred remote-continent geometry preserves baked walking costs and resumes when the retained journey
reaches that continent. The arrival test exercises JourneySearch's same-journey branch and fails without the
resume fix. Loading tests cover cancellation, missing parts, bounded loading and synchronous-cost equivalence.

The existing idle eviction and scratch lifecycle remain in place. These measurements justify reducing eager
loads, not retaining more trees or adding pools. Python remains suitable for generation; a Rust rewrite adds
build and distribution work before establishing an additional benefit. Lua remains the client runtime.

Before merging, verify a cold cross-continent journey and its landing in game, including cancelling during
loading and continuing after combat. Headless tests do not reproduce the client's loading cost or secure UI.

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
| Full map 0 | Graph phase not timed separately | 811.44 s in the measured full repeat | Byte-identical Lua to the original full bake |

The original full bake completed in 1,264.6 seconds wall time and 1,663 seconds CPU time. Its
getrusage largest-process peak was reported as 1,086 MB, not aggregate concurrent memory. A fresh merged
full bake records 955.21 seconds internally, 822.28 seconds parent CPU and 529.20 seconds worker CPU
(1,351.48 seconds combined). Its parent peak is 1,083.0 MiB and largest-worker peak 162.2 MiB.
Both Lua outputs have SHA256 `a53a3d3fea642dbec294e4516e794a0e7dfbdd65653fe2c7af8a8c4003bf53e0`.

The full map has 29,813 graph nodes and 168,860 edges. The merged repeat's component phase takes 21.17 seconds,
rasterisation 106.63 seconds, floor assembly 4.58 seconds, graph construction 811.44 seconds and emission
11.38 seconds. An earlier untimed-total merged run recorded a 593.85-second graph phase. The full observations
are single runs under different background loads; the merged internal total also excludes argument parsing and
process startup included in the original external timer. They suggest improvement but do not establish a
controlled full-bake speedup. Use the common external runner and repeated runs for that claim.
Parent-only cProfile misses rasterizer workers; separate worker profiling shows connectivity and portal
geometry checks dominate a dense tile.

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

## Classified crop comparison

[Raw measurements](benchmarks/issue103.json) contain all 48 runs, tile and output hashes, source commits,
phase times for the merged baker and resource accounting. The baseline is the original source above; the
merged source is `ccaffdd3f3bb75f78bfe7c4af1ee2b80d56309aa`. Each crop is four adjacent tiles, with three
fresh-process repeats per version and per worker count. Version order alternates between repeats.
All twelve runs for each crop produce identical Lua. Input hashes remain identical across those runs.

| Crop, rows / columns | Ground cells | Water cells | Extra floors | Graph nodes |
|---|---:|---:|---:|---:|
| Stormwind City and Elwynn edge, 48-49 / 30-31 | 10,372 | 946 | 3,796 | 111 |
| Ironforge and Dun Morogh overlapping floors, 40-41 / 34-35 | 10,333 | 0 | 4,570 | 97 |
| Westfall ground near Sentinel Hill, 51-52 / 30-31 | 16,065 | 1,309 | 1,810 | 106 |
| Wetlands and Menethil shore, 38-39 / 33-34 | 6,939 | 6,646 | 1,304 | 100 |

Locations use the baker's world-coordinate bounds and the bundled taxi coordinates. Stormwind includes its
Elwynn edge, Westfall includes settlement features, and Ironforge includes Dun Morogh ground. The labels identify
representative terrain rather than pure synthetic controls. The Wetlands crop is 49% water among walkable base
cells; Ironforge has 4,570 extra floor surfaces on 3,515 cells. Single-tile probes are excluded because they have
no inter-cluster graph nodes.

Wall figures below are median seconds, with minimum and maximum in parentheses. CPU is median user plus system
seconds including waited descendants. RSS is median largest-process peak in MiB; it cannot measure aggregate
concurrent memory.

| Crop | Workers | Original wall | Merged wall | Original / merged CPU | Original / merged RSS |
|---|---:|---:|---:|---:|---:|
| Stormwind City | 1 | 7.24 (7.15-7.58) | 6.36 (6.35-6.82) | 7.01 / 6.21 | 65.0 / 67.5 |
| Stormwind City | 6 | 6.13 (5.35-6.15) | 4.92 (4.88-5.09) | 7.26 / 6.12 | 65.0 / 67.1 |
| Ironforge | 1 | 6.55 (6.06-6.86) | 5.16 (5.13-5.38) | 6.43 / 5.06 | 55.7 / 65.7 |
| Ironforge | 6 | 4.95 (4.90-5.34) | 3.60 (3.56-3.86) | 6.52 / 5.15 | 55.7 / 65.9 |
| Westfall ground near Sentinel Hill | 1 | 8.85 (8.73-8.92) | 5.97 (5.94-6.04) | 8.68 / 5.87 | 58.9 / 60.2 |
| Westfall ground near Sentinel Hill | 6 | 7.84 (7.60-7.89) | 4.91 (4.90-5.01) | 8.87 / 6.01 | 59.1 / 60.1 |
| Wetlands | 1 | 5.97 (5.96-6.08) | 4.40 (4.25-4.78) | 5.70 / 4.12 | 51.7 / 53.2 |
| Wetlands | 6 | 4.67 (4.45-4.71) | 3.11 (2.83-3.17) | 5.53 / 4.04 | 51.4 / 53.5 |

Observed wall medians fall by 12-37% across these crops. The recorded original and merged ranges do not overlap
within each comparison, but three repeats on a busy machine do not establish unloaded performance. A load-average
snapshot was 21.34 / 18.97 / 16.96 on 16 logical CPUs. The corpus and benchmark runs stayed separate; desktop,
game and other agent workloads were present. Four tiles with pool chunks of two can occupy at most two workers,
so the six-worker runs measure the default pool's behaviour on small crops, not six-way scaling.

These results support retaining directed adjacency reuse and Python. No evidence here supports adding worker
caches or replacing the baker with Rust. The full-map repeat measures the larger workload; it is not extrapolated from these crops.

To repeat a crop, export the baseline source with `git show <baseline>:tools/baker/gen_nav.py`, then run that
file and the merged `tools/baker/gen_nav.py` in fresh processes with identical `NAV_MM`, `--map 0`, `--rows`,
`--cols` and `--jobs`. Wrap both with [the measured resource runner](benchmarks/resource-run.py):

```sh
python3 docs/benchmarks/resource-run.py resources.json python3 tools/baker/gen_nav.py output.lua \
  --map 0 --rows 48 49 --cols 30 31 --jobs 6 --metrics phases.json --build 1.60.1.69913
```

Use distinct output paths, three repeats and alternating version order. Add metrics only to the merged baker;
the historical source predates that option. Keep all output and resource files outside the game installation.

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

[Live verification](live-navigation-verification.md) remains pending for a cold cross-continent journey, landing,
cancellation and combat recovery. Headless tests do not reproduce the client's loading cost or secure UI.
The `/path perf` memory regression now tests that loaded helpers are included once and unloaded helpers are excluded.

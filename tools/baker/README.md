# Shortest Path Forever baker

Bakes the walkable ground of a WoW map from a local client install. `tools/pack_nav.py` compresses it into
`Nav/` inside the main addon. `PathGrid.lua` uses the client's native zlib decoder on demand, in blocks of at most 16 KB.

## Extraction source availability

Fresh extraction requires Mappster revision `d93fd3b347d8c63663cff536955e3cae97fa28a6`.
Its pinned upstream returns 404, and no matching public repository, revision archive or local source copy has
been recovered. The two public repositories named Mappster are unrelated applications. Keep this pin until an
identical licensed source tree is recovered and `mappster.patch` applies cleanly; a similarly named repository
cannot establish compatible client formats or output.

Python generation and packing still work with existing terrain inputs. Historical inputs without `source.json`
remain suitable for comparing generator output, but cannot prove extraction completeness. See
[the benchmark report](../../docs/tooling-benchmarks.md) and [issue #103](https://github.com/cjber/shortest-path-forever/issues/103).

## Usage

```sh
WOW="$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft" MAPS="0 1 2991" ./bake.sh
```

Requires git, curl, cmake, a C++ compiler, python3 (3.10+, standard library only) and about 10 GB of free RAM at
`THREADS=8`. The .NET 10 SDK is installed under `$OUT` if `$DOTNET_ROOT` holds none. Everything is written under
`$OUT` (default `./work`): nothing is written inside the game install and nothing is fetched from Blizzard's CDN. A
file that local storage cannot supply fails the bake.

| Variable | Default | Meaning |
|---|---|---|
| `WOW` | the Lutris/Wine path above | install root holding `.build.info` |
| `PRODUCT` | `wow_classic_beta` | product in `.build.info` (WoW Forever) |
| `MAPS` | `0 1 2991` | Map IDs to bake. Other maps need `MAP_NAME`. |
| `THREADS` | `8` | tiles baked in parallel |
| `JOBS` | `6` | gen_nav rasterizer processes |
| `OUT` | `./work` | scratch and output |

Steps, each reusable on its own:

1. `NavBaker --maps <install> <product>` lists every map with its tile count.
2. `NavBaker --continent <install> <product> <map> <outDir> [threads]` streams the map a row of ADTs at a time. It is
   resumable within one client build, extractor recipe and tile inventory: every tile gets `status/<map>_<x>_<y>` (`ok`, `empty` or `FAILED`) and a line in `tiles.log`. A tile
   whose Recast bake throws is retried with the LAYERS partitioner, then MONOTONE, then with coarser detail sampling (2x, then 4x). The
   retry is recorded. A tile that runs out of memory is baked again alone with the same settings, so the output does
   not depend on memory pressure. `ROWS="a b"` limits the rows.
3. `NavBaker --region <install> <product> <map> <outDir> <row0> <row1> <col0> <col1> [threads]` bakes a rectangle.
4. `NAV_MM=<outDir> python3 gen_nav.py <out.lua> --map <map> --name <name> [--jobs n]` turns TrinityCore-layout `.mmtile`
   files into the addon's HPA* graph and 8-yard grids. The output is deterministic. Each cell keeps one base surface
   and its height (2-yard steps); where walkable surfaces overlap (a tunnel under a pass, a city under a city), the
   others are kept as floors, each linked to the neighbouring surfaces it actually joins. Floors under water in the
   same cell (lake and sea beds) are dropped. Every graph edge carries two costs: one where a swum yard counts as
   `SWIM` (3) running yards, so walks keep out of water, and one for a player walking on water, where it counts as 1.

The baker emits raw base64 cluster fields. `python3 tools/pack_nav.py` compresses them with zlib into blocks
that expand to at most 16 KiB and bundles them under `Nav/`, with each Lua file at most 512 KiB. The main
addon's XML loads the compressed strings; `PathGrid.lua` uses the client's native encoding API to decode
fields on demand, with asynchronous checkpoints between blocks. Older shipped tables can be converted
without rebaking or reading a client install. Offline tools load the same bundle through `tools/load_nav.lua`.
Running the packer again leaves the data unchanged.

For repeatable timing, add `--metrics report.json --build <input-client-build>` to `gen_nav.py`. The report records
input tile SHA256 hashes, crop bounds, jobs, phase wall times, parent and worker CPU, output SHA256 and Linux
getrusage peak RSS. The worker RSS is the largest individual worker, not the total concurrent process memory.
Use a separate output file, the same tiles and build, and repeat both single-worker and parallel runs on an idle
machine. A crop's global component pruning differs from a full continent, so compare identical crops and use a
full-map run to check scale. `bake.sh` requires `source.json` from the extractor and checks every expected tile's `ok` or `empty` status
against its file before publishing. Cached tiles without provenance, changed builds or changed extractor recipes
require a fresh output directory. `--require-complete` enables this check for a direct `gen_nav.py` invocation;
metrics from old caches without it describe the files supplied and do not prove extraction completeness.

The graph builder reuses each cluster's legal adjacency for entrance searches and both water modes. It preserves
directed costs: entering water changes the destination step's cost. It needs no native extension or extra runtime.

`NAV_DBD` points NavBaker at a directory holding `Map.dbd` and `LiquidType.dbd`. bake.sh fetches them from a pinned
WoWDBDefs commit and checks their sha256.

## Files

- `bake.sh`: the pipeline above, with every upstream pinned to a commit.
- `mappster.patch`: applied to Mappster. It puts the extractor behind an `IFileSource` interface, lets the
  model caches be cleared, and makes the Recast partitioner a setting.
- `src/`: `NavBaker.csproj`, which compiles Mappster's `Extractor/` and `Nav/` but not its GUI or its CASC library;
  `Program.cs` for the headless commands; and `ZezulaCasc.cs`, the P/Invoke `IFileSource` over Zezula's CascLib.
- `gen_nav.py`.

## Walks between fixed places

After rebaking a walking map, or when docks, flight masters or portals change, rebake the walking costs between
them from the repo root (`tests/planner_spec.lua` fails on a stale key):

```sh
luajit tools/bake_walks.lua > Data/Walks.lua
```

The walk baker uses `Path.FindManySync` once per source and water mode. Its costs match the abstract graph
and local endpoint costs returned by `Path.Find`; smoothing the displayed line does not change them.
Pairs with different local forward/reverse costs store both directions.

## Licences

| Component | Licence | How it is used |
|---|---|---|
| Shortest Path Forever baker (these files) | GPL-3.0-or-later | committed |
| [Mappster](https://github.com/F0RSV1NNA/Mappster) `d93fd3b` | MIT | cloned and patched at build time, not committed |
| [CascLib](https://github.com/ladislav-zezula/CascLib) (Ladislav Zezula) `2a280f5` | MIT | cloned and built at build time |
| [DotRecast](https://github.com/ikpil/DotRecast) 2026.3.1 | zlib | NuGet |
| [DBCD, DBCD.IO, DBDefsLib](https://github.com/wowdev/DBCD) 2.3.0 | MIT | NuGet |
| [WoWDBDefs](https://github.com/wowdev/WoWDBDefs) `7539907` (Map.dbd, LiquidType.dbd) | CC BY-SA 4.0 | fetched at build time, never committed |
| .NET 10 SDK/runtime | MIT | installed at build time |
| Generated `Nav<map>.lua` | shipped under the addon's GPL-3.0-or-later | derived geometry (walkable cells), not client files, but Blizzard's EULA applies to the source data |

Mappster's `ThirdParty/CascLib` submodule (WoW-Tools CascLib, which has no licence) is never fetched or compiled.

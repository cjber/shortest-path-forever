# Shortest Path Forever baker

Bakes walking maps from a local WoW: Forever client. `tools/pack_nav.py` compresses them into `Nav/` inside the
main addon, where `PathGrid.lua` decodes them on demand with the client's native zlib decoder, in blocks of at
most 16 KiB. The extractor is TrinityCore, pinned to
`e3916b2adcf2f8a70ae33817fc57b6c0266e2fb0`, with three patches: `trinitycore-client.patch` for Forever tables and local CASC reads,
`trinitycore.patch` for bounded terrain and model extraction, and `trinitycore-nav.patch` for navigation
completeness and liquid hazards.

## Usage

```sh
WOW="$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft" MAPS="0 1 2991" tools/baker/bake.sh
```

Requires Linux, git, CMake, Ninja, a C++ compiler, Python 3.10+, and TrinityCore's development dependencies:
Boost, OpenSSL, zlib, bzip2 and readline. On Debian/Ubuntu install `build-essential cmake ninja-build git
libboost-all-dev libssl-dev zlib1g-dev libbz2-dev libreadline-dev`. The tools build without the server,
scripts, database or jemalloc. Python uses only the standard library.

The client install is read only. CASC reads use local storage and built-in keys. Missing required geometry, files or liquid-table keys
fail extraction. Inaccessible Map table sections are skipped and logged; the selected map and its parent
metadata must still exist. Build sources come from GitHub, but client files and encryption keys are never downloaded.
All sources, builds, logs and output stay under `OUT`, which must be outside the game install.

| Variable | Default | Meaning |
|---|---|---|
| `WOW` | the Wine path above | install root holding `.build.info` |
| `PRODUCT` | `wow_classic_beta` | active product in `.build.info` |
| `MAPS` | `0 1 2991` | space-separated map IDs |
| `MAP_NAME` | known map title | name of an additional map |
| `THREADS` | `8` | native extraction and navigation workers |
| `JOBS` | `6` | build and Python rasterizer workers |
| `OUT` | `tools/baker/work` | sources, builds, extraction scratch and output |
| `ROWS`, `COLS` | whole map | inclusive tile bounds, each written as `"lo hi"` |
| `BUILD_ONLY` | `0` | `1` builds tools without requiring a client, as CI does |

A small crop, with neighbouring tiles extracted for collision at its edges:

```sh
OUT=/tmp/spf-terrain MAPS=0 ROWS="48 49" COLS="30 31" THREADS=2 JOBS=2 tools/baker/bake.sh
```

The stages are `mapextractor`, `vmap4extractor`, `vmap4assembler`, `mmaps_generator`, `gen_nav.py` and
`pack_nav.py`. Each extraction gets a fresh `extract<map>-*` scratch directory. Navigation tiles live in
`trinity<map>/mmaps`; the bundle lives in `addons/ShortestPathForever/Nav/`, laid out as the main addon's
`Nav/` directory. Scratch directories are retained for inspection and can be removed after a successful bake. The script never copies output into the game or the repository.

## Completeness and repeatability

The map extractor inventories selected tiles from the WDT before converting their ADTs. `trinity.py` records
the active client version, product, pinned source, patch and binary hashes, commands, crop and expected tiles
in `source.json` before navigation generation. Every expected tile needs a terminal `ok` or `empty` status;
missing and failed statuses block Python generation. The tile files must exactly match the `ok` statuses.
The portable recipe hashes source, patches, build and commands. Exact binary hashes remain in provenance,
so rebuilt executables still require a fresh `OUT`. Worker counts can change when resuming.
A different build, recipe or crop requires a fresh `OUT`. Files without provenance cannot be resumed.

A rerun extracts inputs afresh and resumes navigation tiles with terminal statuses. It verifies completeness
before generating or packing a map. The generator writes raw Lua into the scratch directory, and the packer
builds a complete bundle there: the baked map plus every other map `Nav.xml` in `OUT` lists, each one
validated. Only that complete bundle replaces the files under `addons/`, as one batch that is rolled back if a
replace fails; files it leaves out are removed afterwards, and an unrecognised file in the output stops the
publish. Native stages record fresh-process wall time, CPU and Linux largest-process
peak RSS in `trinity<map>.metrics.json`; `nav<map>.metrics.json` adds Python phase timings and input/output hashes.
Peak RSS does not measure aggregate concurrent memory. `bake<map>.log` retains commands and stage output.

To generate from existing terrain independently:

```sh
NAV_MM=/path/to/mmaps python3 tools/baker/gen_nav.py /tmp/Nav0.lua --map 0 --name "Eastern Kingdoms" \
  --require-complete --metrics /tmp/nav0.json
```

An existing source manifest is always validated and supplies the source label, including for direct generator runs.
Historical Mappster tiles use the same pinned Detour layout. They remain usable without `--require-complete`,
but lack an authoritative tile inventory and cannot prove extraction completeness. The generator keeps their
original source label by default; new TrinityCore bakes supply their own source and recipe label.
A bake never regenerates the walking maps shipped in the repository.

## Walking maps

The Python generator builds HPA* graphs and 8-yard grids from Detour polygons. It keeps overlapping walkable
floors, drops underwater floors, and stores directed costs for ordinary swimming and walking on water.
Small disconnected components such as rooftops are removed over the supplied crop or map. A crop therefore
has different global pruning from a continent; compare identical bounds when measuring.

The generator emits raw base64 cluster fields. `pack_nav.py --root <addon root> NavN.lua...` compresses them
with zlib into blocks that expand to at most 16 KiB and bundles them under `Nav/`, each Lua file at most
512 KiB, with a `Nav.xml` that lists every file. Maps already in the bundle and not named on the command line
are kept. The main addon's TOC loads `Nav/Nav.xml`; `PathGrid.lua` decodes fields on demand, with asynchronous
checkpoints between blocks. Packing a bundle again leaves it unchanged. Offline Lua tools load the same
bundle through `tools/load_nav.lua`.

Boat and zeppelin walking endpoints are generated from nearby dry boarding surfaces in the bundled map. Transport coordinates remain the boat or airship position for timetable calculations.

After intentionally replacing shipped terrain, regenerate boarding endpoints and fixed-place walking costs from the repository root:

```sh
python3 tools/gen_routes.py --offline
luajit tools/bake_walks.lua > Data/Walks.lua
```

TrinityCore replaces terrain extraction only. Route timings, lifts, portals and teleport destinations still
use the separately pinned CMaNGOS sources documented in `AGENTS.md`.

## Licences

| Component | Licence | Use |
|---|---|---|
| This baker | GPL-3.0-or-later | committed tools, excluded from the addon zip |
| [TrinityCore](https://github.com/TrinityCore/TrinityCore/tree/e3916b2adcf2f8a70ae33817fc57b6c0266e2fb0) | GPL-2.0-or-later | fetched and patched at build time, not shipped |
| CascLib | MIT | TrinityCore's pinned vendored dependency |
| Recast/Detour | zlib | TrinityCore's pinned vendored dependency |
| [WoWDBDefs](https://github.com/wowdev/WoWDBDefs/tree/7539907c14f9ac88c6db20f5fa699425ad35ac84) | CC BY-SA 4.0 | reference for supported Forever table layouts |
| Generated navigation Lua | GPL-3.0-or-later | derived walkable cells; Blizzard's EULA applies to client source data |

See [the benchmark report](../../docs/tooling-benchmarks.md) for measurements and
[live verification](../../docs/live-navigation-verification.md) for checks requiring the client.

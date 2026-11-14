# Shortest Path Forever baker

Bakes walking maps from a local WoW: Forever client. `tools/pack_nav.py` compresses them into `Nav/` inside the
main addon, where `PathGrid.lua` decodes them on demand with the client's native zlib decoder, in blocks of at
most 16 KiB. The extractor is TrinityCore at the commit in `trinitycore.rev`, with three patches: `trinitycore-client.patch` for Forever tables and local CASC reads,
`trinitycore.patch` for bounded terrain and model extraction, and `trinitycore-nav.patch` for navigation
completeness, the player's own slope and step limits, liquid hazards and ledge drops.

## Usage

```sh
WOW="$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft" MAPS="0 1 2991" tools/baker/bake.sh
```

`bake.sh` needs Ninja (`ninja-build`); CMake's Makefile generator is not used, so the build recipe does not depend on
the generator a machine happens to prefer.

Requires Linux, git, CMake, Ninja, a C++ compiler, Python 3.10+, LuaJIT, and TrinityCore's development dependencies:
Boost, OpenSSL, zlib, bzip2 and readline. On Debian/Ubuntu install `build-essential cmake ninja-build git
libboost-all-dev libssl-dev zlib1g-dev libbz2-dev libreadline-dev`. The tools build without the server,
scripts, database or jemalloc. Python uses only the standard library.

The client install is read only. CASC reads use local storage and built-in keys. Missing required geometry, files or liquid-table keys
fail extraction, except a model, WMO or WMO group the build does not ship (CascLib `ERROR_FILE_NOT_FOUND`): the game has no
collision for it either, so it is skipped, logged once as `SPF-MODEL-NOT-IN-BUILD` and recorded in the map's metrics and
provenance, while every other failure stays fatal. Inaccessible Map table sections are skipped and logged; the selected map and its parent
metadata must still exist. Build sources come from GitHub, but client files and encryption keys are never downloaded.
All sources, builds, logs and output stay under `OUT`, which must be outside the game install.

| Variable | Default | Meaning |
|---|---|---|
| `WOW` | the Wine path above | install root holding `.build.info` |
| `PRODUCT` | `wowf` | active product in `.build.info` |
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
in `source.json` before navigation generation. It also records the skipped Map table sections and the models the build
does not ship, which extraction skips and logs as `SPF-MODEL-NOT-IN-BUILD`. Every expected tile needs a terminal `ok` or `empty` status;
missing and failed statuses block Python generation. The tile files must exactly match the `ok` statuses.
The portable recipe hashes source, patches, build and commands. Exact binary hashes remain in provenance,
so rebuilt executables still require a fresh `OUT`. Worker counts can change when resuming.
A different build, recipe or crop requires a fresh `OUT`. Files without provenance cannot be resumed.

Each map's header names its build, TrinityCore commit and recipe, and a `Generator` digest over `gen_nav.py` and
the baker modules it imports. CI runs `tools/check_nav.py`, which recomputes both from the checkout and fails when a
change to the pin, a patch, an extractor command or the generator code leaves a map stale: rebake the maps in the
same PR. The daily data refresh runs it with `--build` against the newest Forever build and keeps the issue "Walking
maps are behind the client" open until the maps are rebaked from that build.

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
Ground a player cannot reach is removed over the supplied crop or map: every disconnected component that holds
none of the map's fixed places with a height (flight masters, docks and lift ends, portal ends and teleport landings,
read from `Data/` by `places.lua`), such as the sealed terrain under Stormwind, and small components such as
rooftops. A crop holding no such place is refused, and a crop has different global pruning from a continent;
compare identical bounds when measuring.

The bake uses the player's own collision limits, not a server creature's:

| Limit | Setting | Player (source) |
|---|---|---|
| Walkable slope | `walkableSlopeAngleNotSteep` 50 | a face is walkable while its normal's z is above cos 50 (benilla-re `systems/collision/walking.md`, cos 50 `0x3f248dbb`; the Forever client's float pool holds the same constant) |
| Steep ground, walked down only | `walkableSlopeAngle` 61.6 | the settle sweep reaches `t * tan 61.6 + 1/36` below the move (tan 61.6 `1.8493990`, also in the Forever client's pool); ground from 50 to 61.6 degrees is `NAV_AREA_GROUND_STEEP`, area 10 |
| Step height | `walkableClimb` 4 x `ch` 0.5 = 2.0 yd | H = 2.0 yd (`0x617430` in the 1.12.1 client; the same value in Forever's build) |
| Agent clearance | `walkableHeight` 3 x 0.5 = 1.5 yd | close to the 1.6 yd the older 0.533 yd voxel reached; a player is not a tall creature |
| Falling | `NAV_DROP_REACH` 14.57 yd | fall damage starts here (TrinityCore `Player::HandleFall` at the pinned commit) |

The horizontal cell stays 0.5333 yd so terrain is sampled as before; the vertical cell is 0.5 yd because 2.0 yards is
not a whole number of 0.5333 ones. The nav patch also corrects Recast's span merge in
`dep/recastnavigation`: a merged span keeps the area of the surface on top, so a low unwalkable face rasterized under a
stair tread no longer turns the tread unwalkable and cuts the stair (the Undercity stairs were cut this way). Ground
below the top liquid surface of its own voxel column is a bed nobody stands on: the patched `TileBuilder` gives it
`NAV_AREA_UNDER_LIQUID` (area 7) and flag `0x40`, so Recast splits it into polygons of its own and the generator never
joins sealed terrain to the world through a canal floor (Stormwind's under-city ground was reached this way). Slope
never changes speed, so no slope cost is charged. Ground from 50 to 61.6 degrees is `NAV_AREA_GROUND_STEEP` (area 10),
which the generator keeps as a distinct layer and turns into downhill-only steps: its search between cells never
climbs through it, so a route goes around a face the player would slide back down. A
landing between 2.0 and 14.57 yards below a ledge is baked as a one-way Detour
off-mesh connection (`DT_OFFMESH_CON_BIDIR` never set) by the patched `TileBuilder`, which looks outwards from every
walkable span with no walkable neighbour, rejects a landing whose fall column or path crosses a wall or a shelf, and
emits one connection per ledge run. A connection belongs to the tile its start is in, as Detour requires, so its
landing may lie in the next tile; the heightfield border bounds how far out it can be. The connection carries the two
floor surfaces, and the generator charges the walk plus free fall's time at the client's gravity (19.2911 yd/s²) run
at 7 yd/s. `tools/baker/check_drops.py` compiles and exercises that helper alongside `check_hazards.py`.

Maps are written in format 3. A step both ways take is one bit in a floor's step mask, and the node stores the layer
each set direction lands on, so the decoder resolves the pair the bake linked rather than a surface merely near its
height. A step one way takes because one end is steep rides the same bit: the decoder's stored-height test refuses the
climb, so a ledge is dropped off but never climbed and steep ground is never walked up. Only a step one way takes for
a reason the decoder cannot decide for itself (a wall, ground it cannot pass) or one with a cost of its own is a
record. The file stores each single link once, from the node that leaves it: a step's [node, direction, layer], or a
drop's [node, x, y, layer, cost in whole yards]. Floors, record nodes and cells are written as deltas, so a cluster's
list of surfaces and its records cost a fraction of the absolute indices they used to. An offset of (0, 0) is a link
within one cell, so a drop from a ledge to a distinct floor of the same cell is stored too, and the generator maps a
drop to the surfaces its endpoints lie on (the poly's own height, not the nearest cell anchor), linking the ledge to
the landing's floor or, when that floor is rasterized in a neighbouring cell, to that cell's matching layer. The tile
graph keeps one record per edge from the node that leaves it as well, and the decoder builds every node's
predecessors from those records. `Routing/PathGrid.lua` still decodes format 2, whose floor step bits it resolves by
height, and format 1, which every map shipped before format 2 uses and which keeps its symmetric links and
height-matched floor steps.

The generator emits raw base64 cluster fields. `pack_nav.py --root <addon root> NavN.lua...` compresses them
with zlib into blocks that expand to at most 16 KiB and bundles them under `Nav/`, each Lua file at most
512 KiB, with a `Nav.xml` that lists every file. Maps already in the bundle and not named on the command line
are kept. The main addon's TOC loads `Nav/Nav.xml`; `PathGrid.lua` decodes fields on demand, with asynchronous
checkpoints between blocks. Packing a bundle again leaves it unchanged. Offline Lua tools load the same
bundle through `tools/load_nav.lua`.

Each cluster also carries a terrain field: the cells whose ground is one of their floors, sampled from the
extractor's `maps/` directory (`NAV_MAPS`) at the centre of every walking-map cell with the same layout as the
walking grid and quantized to the grid's 2-yard step. A cell with no floor is left out: it has one place to stand,
and the route walks the player onto it. A cell with floors takes the layer nearest the terrain at its centre (ties
to the base) and stores an exception only when that ground layer is not the base; a cell with floors over an ADT
hole or with no extracted tile stores the no-ground marker. `PathGrid.ground` snaps a stop to its cell's nearest
surface, takes the stored ground layer (or the base when the cell is left out), and says "up" above it and "down"
below it; a floorless cell and a no-ground cell say nothing. A cluster's exceptions are decoded on the first hover
rather than with its walking fields, so a tower top reads "up" and a city floor under the ruins reads "down"
without route decoding paying for the field. `gen_nav.py` emits it for a fresh bake; an existing bundle's walking
fields can gain it without being re-baked:

```sh
python3 tools/baker/terrain_field.py --root . --maps-dir /path/to/extract/maps --maps 0 1 2991
```

This rewrites only the `terrain` field, leaving graph, grid, height and floor byte-identical. `tools/baker/terrain.py`
reads the pinned extractor's format (flat, float, uint16 and uint8 heights, and holes).

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

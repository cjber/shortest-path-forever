#!/usr/bin/env python3
"""Generate Data/TownAreas.lua: the ground each flight master's town covers, as the client's own terrain marks it.

The client names the area the player stands in from its terrain: every ADT map chunk carries an AreaTable id, and the
minimap says "Southshore" while you stand on the chunks carrying Southshore's. A town's ground is the set of those
33-yard chunks around its flight master, when that flight master stands in a sub-area of its zone (AreaTable
ParentAreaID: a town or a camp, not the zone itself and not a capital). A flight master standing in no sub-area keeps
the radius Journey/Hazards.lua falls back on.

Tiles come from wago.tools' CASC mirror for the pinned build, found through each map's WDT (Map.WdtFileDataID), and
are cached in tools/.cache/casc-<build>/.
"""

import argparse
import struct
import subprocess
import sys
from pathlib import Path

try:
    from tools.forever_tools.fsio import atomic_write
    from tools.gen_roads import B64, casc, chunks
    from tools.gen_routes import BUILD, db2

except ModuleNotFoundError:
    from forever_tools.fsio import atomic_write
    from gen_roads import B64, casc, chunks
    from gen_routes import BUILD, db2

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Data" / "TownAreas.lua"
# A tile is 16 x 16 chunks of 100/3 yards, in the same layout as the walking maps' clusters (Routing/PathGrid.lua).
TILE = 1600 / 3
CHUNK = TILE / 16
SIDE = 64  # the WDT lists a 64 x 64 grid of tiles


def lua(script):
    """LuaJIT's answer to a script run in this checkout."""
    result = subprocess.run(["luajit", "-"], cwd=ROOT, input=script, capture_output=True, text=True, check=True)
    return result.stdout


def taxi_nodes():
    """(id, map, x, y) of every flight master Data/Taxi.lua ships, exactly as the addon reads them."""
    nodes = []
    for line in lua("""
local ns = {}
assert(loadfile("Data/Taxi.lua"))("ShortestPathForever", ns)
for id, node in pairs(ns.TaxiNodes) do
\tprint(string.format("%d\\t%d\\t%.2f\\t%.2f", id, node.map, node.x, node.y))
end
""").splitlines():
        node, map_id, x, y = line.split("\t")
        nodes.append((int(node), int(map_id), float(x), float(y)))
    return sorted(nodes)


def areas(offline):
    """AreaTable's ParentAreaID and name per area: a zone or a capital has no parent, its towns and camps name one."""
    return {
        int(row["ID"]): (int(row["ParentAreaID"]), row["AreaName_lang"]) for row in db2("AreaTable", offline=offline)
    }


def tile_of(x, y):
    """The ADT tile and chunk a world point falls in, as the walking maps count them."""
    row, col = int(32 - x / TILE), int(32 - y / TILE)
    chunk = (int(((32 - col) * TILE - y) / CHUNK), int(((32 - row) * TILE - x) / CHUNK))
    return row, col, chunk


def wdt_tiles(data):
    """{(row, col): the tile's root ADT file ID} from a WDT's MAID: the map chunks' own headers live in it."""
    for tag, start, size in chunks(data):
        if tag == "MAID":
            ids = struct.unpack_from(f"<{size // 4}I", data, start)
            width = len(ids) // (SIDE * SIDE)
            return {divmod(at, SIDE): ids[at * width] for at in range(SIDE * SIDE) if ids[at * width]}
    raise ValueError("WDT has no MAID chunk")


def tile_areas(data):
    """One tile's chunk area ids by MCNK (chunk y, chunk x); a chunk's header carries the AreaTable id at 0x34."""
    found = {}
    for tag, start, _size in chunks(data):
        if tag == "MCNK":
            x, y = struct.unpack_from("<II", data, start + 4)
            found[(x, y)] = struct.unpack_from("<I", data, start + 0x34)[0]
    return found


def reader(wdt, offline):
    """Each tile's chunk area ids, read once; None where the WDT has no tile."""
    tiles = {}

    def read(row, col):
        if not (0 <= row < SIDE and 0 <= col < SIDE):
            return None
        if (row, col) not in tiles:
            file_id = wdt.get((row, col))
            tiles[(row, col)] = tile_areas(casc(file_id, offline)) if file_id else None
        return tiles[(row, col)]

    return read


def ground(read, area, x, y):
    """Every chunk carrying `area` in the point's tile and the tiles joined to it through tiles that carry it too, as
    global (chunk x, chunk y) indices."""
    row, col, _ = tile_of(x, y)
    cells, seen, queue = set(), {(row, col)}, [(row, col)]
    while queue:
        r, c = queue.pop()
        found = read(r, c) or {}
        mine = [(cx, cy) for (cx, cy), found_area in found.items() if found_area == area]
        if not mine:
            continue
        for cx, cy in mine:
            cells.add((16 * (32 - r) - cy - 1, 16 * (32 - c) - cx - 1))
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                if (r + dr, c + dc) not in seen:
                    seen.add((r + dr, c + dc))
                    queue.append((r + dr, c + dc))
    return cells


def encode(cells):
    """i0, j0, w, h and the cells as an x-major bitmask, six bits a base64 symbol, padded with zeros at the end."""
    i0, j0 = min(i for i, _ in cells), min(j for _, j in cells)
    w, h = max(i for i, _ in cells) - i0 + 1, max(j for _, j in cells) - j0 + 1
    bits = [1 if (i, j) in cells else 0 for i in range(i0, i0 + w) for j in range(j0, j0 + h)]
    symbols = []
    for at in range(0, len(bits), 6):
        group = bits[at : at + 6]
        value = 0
        for bit in group:
            value = value * 2 + bit
        symbols.append(B64[value * 2 ** (6 - len(group))])
    return i0, j0, w, h, "".join(symbols)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="require existing tools/.cache inputs")
    args = parser.parse_args()
    nodes = taxi_nodes()
    wdts = {int(row["ID"]): int(row["WdtFileDataID"]) for row in db2("Map", offline=args.offline)}
    maps = {map_id: wdt_tiles(casc(wdts[map_id], args.offline)) for _, map_id, _, _ in nodes if map_id in wdts}
    readers = {map_id: reader(wdt, args.offline) for map_id, wdt in maps.items()}
    area_info = areas(args.offline)
    entries, towns = [], 0
    for node, map_id, x, y in nodes:
        if map_id not in readers:
            continue
        row, col, chunk = tile_of(x, y)
        found = readers[map_id](row, col) or {}
        area = found.get(chunk)
        if area not in area_info or area_info[area][0] == 0:
            continue
        cells = ground(readers[map_id], area, x, y)
        if not cells:
            continue
        i0, j0, w, h, mask = encode(cells)
        towns += 1
        entries.append(
            f"\t[{node}] = {{ area = {area}, map = {map_id}, i0 = {i0}, j0 = {j0}, w = {w}, h = {h}, "
            f'cells = "{mask}" }}, -- {area_info[area][1]} ({len(cells)} chunks)'
        )
        print(f"town {node} {area_info[area][1]}: {len(cells)} chunks", file=sys.stderr)
    lines = [
        "-- Generated by tools/gen_towns.py - do not edit.",
        f"-- Source: wago.tools CASC, wow_classic_beta {BUILD}: each map tile's MCNK terrain area ids (AreaTable),",
        "-- through the Map table's WDT.",
        "-- TownAreas[flight master] = { area, map, i0, j0, w, h, cells }: the client's own area around that flight",
        f"-- master. Chunk (i, j) covers x in [i, i + 1) and y in [j, j + 1) times the chunk size ({CHUNK:.2f} yards).",
        "-- cells is an x-major bitmask of the w x h chunks from (i0, j0), six bits a base64 symbol (A-Za-z0-9+/)",
        "-- with the last symbol padded with zeros. A flight master whose chunk is its zone's own area, or a capital,",
        "-- has no entry: Journey/Hazards.lua keeps a radius around those.",
        "local ns = select(2, ...)",
        "",
        "-- stylua: ignore",
        "ns.TownAreas = {",
        *entries,
        "}",
    ]
    atomic_write(OUTPUT, "\n".join(lines) + "\n")
    print(f"towns: {towns}", file=sys.stderr)


if __name__ == "__main__":
    main()

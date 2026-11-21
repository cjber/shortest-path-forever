"""Generate Data/RoadCells.lua from painted terrain and tools/RoadTrails.lua from recorded city trails.

The client has no road table. Roads are painted onto the terrain: each ADT tile's texture file (`_tex0.adt`) lists
its textures (MDID) and, per map chunk, up to four layers (MCLY) blended by alpha maps (MCAL). A road is wherever one
of ROAD_TEXTURES shows. The tiles come from wago.tools' CASC mirror for the pinned build, found through each map's
WDT (Map.WdtFileDataID), and are cached in tools/.cache/casc-<build>/.

Each walking-map cell keeps its painted coverage, quantised to 63 levels. Every positive coverage survives
quantisation; unpainted ground stays zero. Search interpolates between road and off-road cost with this weight.

Run after rebaking a walking map or changing ROAD_TEXTURES, then run tools/bake_roads.lua.
"""

import argparse
import hashlib
import re
import struct
import sys
from pathlib import Path

try:
    from tools.forever_tools import wago
    from tools.forever_tools.fsio import atomic_write
except ModuleNotFoundError:
    from forever_tools import wago
    from forever_tools.fsio import atomic_write

ROOT = Path(__file__).resolve().parent.parent
# The checked-in painted roads were generated at this build. Pin their source so they reproduce offline
# when the travel-table BUILD in gen_routes.py changes.
ROAD_BUILD = "1.60.1.70938"
CACHE = ROOT / "tools" / ".cache"
POLESTAR_REV = "6f27c95cba66f8be6b6687b3a62afc3dbfa17cae"
POLESTAR_FILE = "addon/Polestar_Nav/Trails/Trails.lua"
POLESTAR_SHA256 = "bfc24e7e513574e37f4aecd21bde60aa3ee1d99950882cb9248ed6a42d4ec4ec"
TRAIL_CELLS = 128
TRAIL_HEIGHT_BIAS = 32768
OUTPUT = ROOT / "Data" / "RoadCells.lua"
TRAIL_OUTPUT = ROOT / "tools" / "RoadTrails.lua"
MAPS = (0, 1, 2991)
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

# The tileset textures that paint roads and paved streets, by file ID. Each was checked by drawing where it shows over
# the client's own minimap of the tile it covers most: kept when it traces the roads seen there. Left out on that check:
# general dirt and gravel that also paint fields and slopes (Westfall's and Durotar's dirt, Duskwood and Loch Modan
# gravel), footprint and scrape overlays (Desolace, Winterspring, Dun Morogh), and textures that only paint plazas,
# docks' dirt or temple rings (Swamp of Sorrows stone road, Burning Steppes brick, Badlands pillar tiles). Roads painted
# with a zone's general dirt are therefore not roads here.
ROAD_TEXTURES = {
    186766: "aerie peaks/aeriepeaksrockroadbase",
    186802: "alteracmtns/alteracrockroadbase",
    186813: "araithihighlands/arathihighlandscityfloor",
    186839: "ashenvale/ashenvaleroad",
    186883: "ashzara/ashzararoad",
    186918: "barrens/barrensroad01",
    186962: "burningstepps/burningsteppsspireroad01",
    186975: "darkshore/darkshoreroad",
    187035: "durotar/durotarroad",
    187066: "duskwallow marsh/duskwallowstoneroad",
    187073: "duskwood/duskwoodcobblestone2",
    187074: "duskwood/duskwoodcobblestone",
    187100: "elwynn/elwynncobblestonebase",
    187104: "elwynn/elwynncobblestonedock",
    188478: "felwood/felwoodroad",
    188508: "feralas/feralasroad",
    188542: "hyjal/alphahyjalroad",
    188566: "ironforge/ironforgerock06road2",
    188584: "kalidar/kalidardarnroad",
    188598: "kalidar/kalidarroad",
    188610: "loch modan/lochmodanbrickroadbase",
    188665: "mullgore/mullgoreroad01",
    188727: "plaguelandseast/eastplaguedroadbase",
    188763: "redridge/redridgerockroadbase",
    188796: "silverpine/silverpineroad",
    188818: "stranglethorn/stranglethorncobblestoneroad",
    188859: "tanaris/tanarisdirtfootprint",
    188911: "the blasted lands/blastedlandsroad",
    188964: "tirisfall/tirisfallstoneroad01",
    188982: "westwood/westfallcobblestonebase",
    189026: "wetlands/wetlandsroad01",
    189071: "zulgurub/zulgurubroad01",
    304640: "expansion03/gilneas/gn_cobblestonef",
}
TEXELS = 1024  # alpha texels across an ADT tile: 16 chunks of 64
COMPRESSED = 0x200  # MCLY: the layer's alpha map is run-length encoded


def casc(file_id, offline):
    def validate(data):
        if len(data) < 8:
            raise ValueError(f"file {file_id} is truncated")

    return wago.fetch(
        f"https://wago.tools/api/casc/{file_id}?version={ROAD_BUILD}",
        CACHE / f"casc-{ROAD_BUILD}" / str(file_id),
        user_agent="ShortestPathForever/1.0",
        offline=offline,
        timeout=60,
        validate=validate,
    )


def polestar(offline):
    def validate(data):
        if hashlib.sha256(data).hexdigest() != POLESTAR_SHA256:
            raise ValueError("Polestar Trails.lua does not match the pinned SHA-256")

    data = wago.fetch(
        f"https://raw.githubusercontent.com/fitzforge/polestar/{POLESTAR_REV}/{POLESTAR_FILE}",
        CACHE / f"polestar-{POLESTAR_REV}-Trails.lua",
        user_agent="ShortestPathForever/1.0",
        offline=offline,
        validate=validate,
    )
    maps = {}
    for line in data.splitlines():
        map_line = re.fullmatch(rb"\t\[(0|1)\] = \{", line)
        if map_line:
            tiles = maps.setdefault(int(map_line[1]), {})
        tile_line = re.fullmatch(rb'\t\t\["(\d+)_(\d+)"\] = "(.*)",', line)
        if tile_line:
            col, row = int(tile_line[1]), int(tile_line[2])
            tiles[row, col] = list(decode_trail_tile(tile_line[3]))
    return maps


def varint(data, pos):
    value, shift = 0, 0
    while True:
        byte = data[pos]
        pos += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, pos
        shift += 7


def decode_trail_tile(literal):
    """Polestar's Lua decimal escapes, then cell/weight and zigzag quarter-yard height deltas."""
    data = re.sub(rb"\\([0-9]{3})", lambda m: bytes([int(m[1])]), literal)
    pos = cell = height = 0
    while pos < len(data):
        packed, pos = varint(data, pos)
        delta, pos = varint(data, pos)
        cell += packed // 4
        height += (delta >> 1) ^ -(delta & 1)
        yield cell, height, packed % 4


def encode_trails(trails, cells):
    """Assign each Polestar cell's centre to its containing Nav cell; keep its level for floor matching."""
    records = set()
    for cell, height, weight in trails:
        row, col = divmod(cell, TRAIL_CELLS)
        x = (2 * (TRAIL_CELLS - row) - 1) * cells // (2 * TRAIL_CELLS)
        y = (2 * (TRAIL_CELLS - col) - 1) * cells // (2 * TRAIL_CELLS)
        records.add((x * cells + y, (height + TRAIL_HEIGHT_BIAS) * 4 + weight))
    return "".join(
        B64[value >> 12] + B64[value >> 6 & 63] + B64[value & 63] for record in sorted(records) for value in record
    )


def chunks(data, start=0, end=None):
    end = len(data) if end is None else end
    while start + 8 <= end:
        tag = data[start : start + 4][::-1].decode("latin-1")
        size = struct.unpack_from("<I", data, start + 4)[0]
        yield tag, start + 8, size
        start += 8 + size


def wdt_tiles(data):
    """{(row, col): tex0 file ID} from a WDT's MAID; row is the ADT name's second number, as Nav's mmtile rows."""
    for tag, start, size in chunks(data):
        if tag == "MAID":
            ids = struct.unpack_from(f"<{size // 4}I", data, start)
            width = len(ids) // 4096
            return {divmod(i, 64): ids[i * width + 3] for i in range(4096) if ids[i * width] and ids[i * width + 3]}
    raise ValueError("WDT has no MAID chunk")


def alpha(data, start, flags):
    if not flags & COMPRESSED:
        return data[start : start + 4096]
    out, i = bytearray(), start
    while len(out) < 4096:
        head = data[i]
        count = head & 0x7F
        if head & 0x80:
            out += bytes([data[i + 1]]) * count
            i += 2
        else:
            out += data[i + 1 : i + 1 + count]
            i += 1 + count
    return bytes(out[:4096])


def road_weights(data):
    """A tile's road weight per texel (0-255, row-major from its north-east corner), or None without roads.

    Each layer above the first is blended over what lies beneath by its alpha, as the terrain is drawn."""
    textures, weights, index = (), None, 0
    for tag, start, size in chunks(data):
        if tag == "MDID":
            textures = struct.unpack_from(f"<{size // 4}I", data, start)
        elif tag == "MCNK":
            layers, mcal = (), 0
            for sub, at, length in chunks(data, start, start + size):
                if sub == "MCLY":
                    layers = [struct.unpack_from("<IIIi", data, at + 16 * i) for i in range(length // 16)]
                elif sub == "MCAL":
                    mcal = at
            roads = [textures[layer[0]] in ROAD_TEXTURES for layer in layers]
            if any(roads):
                weights = weights or bytearray(TEXELS * TEXELS)
                road = [255.0 if roads[0] else 0.0] * 4096
                for layer, is_road in zip(layers[1:], roads[1:], strict=True):
                    a = alpha(data, mcal + layer[2], layer[1])
                    if is_road:
                        road = [w + (255.0 - w) * v / 255 for w, v in zip(road, a, strict=True)]
                    else:
                        road = [w * (255 - v) / 255 for w, v in zip(road, a, strict=True)]
                row0, col0 = divmod(index, 16)
                for y in range(64):
                    at = (row0 * 64 + y) * TEXELS + col0 * 64
                    weights[at : at + 64] = bytes(round(w) for w in road[y * 64 : (y + 1) * 64])
            index += 1
    return weights


def nav_layout(map_id):
    """cx0, cy0, ny and cells of a bundled walking map, from its Nav files."""
    found = {}
    for path in sorted((ROOT / "Nav").glob(f"Nav{map_id}[_.]*lua")):
        for key, value in re.findall(r"^\t(cx0|cy0|nx|ny|cells) = (-?\d+),$", path.read_text(), re.M):
            found[key] = int(value)
    return found


def cells_of(weights, cells):
    """Positive coverage levels (1 to 63), x-major from the tile's south (x) and east (y) edges."""
    road = {}
    edges = [round(TEXELS * (1 - n / cells)) for n in range(cells + 1)]
    for i in range(cells):
        rows = range(edges[i + 1], edges[i])
        for j in range(cells):
            c0, c1 = edges[j + 1], edges[j]
            total = sum(sum(weights[r * TEXELS + c0 : r * TEXELS + c1]) for r in rows)
            if total > 0:
                coverage = total / (255 * len(rows) * (c1 - c0))
                road[i * cells + j] = max(1, round(coverage * 63))
    return road


def encode(road, count):
    """Runs of equal coverage: two base64 length symbols and one coverage symbol (0 to 63)."""
    out, value, run = [], 0, 0

    def emit(length, level):
        while length > 4095:
            out.append(B64[63] * 2 + B64[level])
            length -= 4095
        out.append(B64[length // 64] + B64[length % 64] + B64[level])

    for cell in range(count):
        level = road.get(cell, 0)
        if level != value:
            if run:
                emit(run, value)
            value, run = level, 0
        run += 1
    if value:
        emit(run, value)
    return "".join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="require existing tools/.cache inputs")
    args = parser.parse_args()
    trails = polestar(args.offline)
    maps = wago.db2_rows(
        "Map",
        ROAD_BUILD,
        CACHE,
        user_agent="ShortestPathForever/1.0",
        offline=args.offline,
        required=("ID", "WdtFileDataID"),
    )
    wdts = {int(row["ID"]): int(row["WdtFileDataID"]) for row in maps}
    lines = [
        "-- Generated by tools/gen_roads.py; do not edit.",
        f"-- Source: wago.tools CASC, wow_classic_beta {ROAD_BUILD}: ADT terrain texture layers (MDID, MCLY, MCAL) of",
        f"-- {len(ROAD_TEXTURES)} road textures. Positive coverage uses levels 1 to 63; unpainted cells stay zero.",
        "-- roads[map][k + 1]: Nav cluster k's cells, x-major, as runs of equal coverage:",
        "-- two base64 length symbols followed by one coverage symbol (A-Za-z0-9+/); trailing zero cells omitted.",
        "local ns = select(2, ...)",
        "",
        "-- stylua: ignore",
        "ns.RoadCells = {",
    ]
    for map_id in MAPS:
        layout = nav_layout(map_id)
        cells, ny = layout["cells"], layout["ny"]
        tiles = wdt_tiles(casc(wdts[map_id], args.offline))
        lines.append(f"\t[{map_id}] = {{")
        roads = 0
        for k in range(layout["nx"] * ny):
            row, col = 31 - (layout["cx0"] + k // ny), 31 - (layout["cy0"] + k % ny)
            if (row, col) not in tiles:
                continue
            weights = road_weights(casc(tiles[(row, col)], args.offline))
            road = cells_of(weights, cells) if weights else {}
            if road:
                roads += len(road)
                lines.append(f'\t\t[{k + 1}] = "{encode(road, cells * cells)}",')
        lines.append("\t},")
        print(f"map {map_id}: {roads} road cells", file=sys.stderr)
    lines.append("}")
    atomic_write(OUTPUT, "\n".join(lines) + "\n")
    lines = [
        "-- Generated by tools/gen_roads.py for tools/bake_roads.lua; do not edit.",
        f"-- Source: fitzforge/polestar {POLESTAR_REV}, {POLESTAR_FILE}.",
        "-- Each trail record is local cell (3 symbols), then (quarter-yard height + 32768) * 4 + weight (3).",
        "-- Weight 1, 2 or 3 corresponds to recordings by 3-9, 10-49 or 50+ distinct players, respectively.",
        "-- stylua: ignore",
        "return {",
    ]
    for map_id, tiles in sorted(trails.items()):
        layout = nav_layout(map_id)
        lines.append(f"\t[{map_id}] = {{")
        clusters = {}
        for (row, col), trail in tiles.items():
            x, y = 31 - row - layout["cx0"], 31 - col - layout["cy0"]
            if 0 <= x < layout["nx"] and 0 <= y < layout["ny"]:
                clusters[x * layout["ny"] + y + 1] = encode_trails(trail, layout["cells"])
        for cluster, records in sorted(clusters.items()):
            lines.append(f'\t\t[{cluster}] = "{records}",')
        lines.append("\t},")
    lines.append("}")
    atomic_write(TRAIL_OUTPUT, "\n".join(lines) + "\n")


if __name__ == "__main__":
    main()

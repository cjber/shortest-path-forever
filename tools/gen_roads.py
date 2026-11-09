"""Generate Data/RoadCells.lua: which walking-map cells are road, from the client's painted terrain.

The client has no road table. Roads are painted onto the terrain: each ADT tile's texture file (`_tex0.adt`) lists
its textures (MDID) and, per map chunk, up to four layers (MCLY) blended by alpha maps (MCAL). A road is wherever one
of ROAD_TEXTURES shows. The tiles come from wago.tools' CASC mirror for the pinned build, found through each map's
WDT (Map.WdtFileDataID), and are cached in tools/.cache/casc-<build>/.

A cell of the walking map (Nav/, 8 yd, 67 to an ADT tile) is road when road textures cover at least half of it.

Run after rebaking a walking map or changing ROAD_TEXTURES; tools/bake_roads.lua then reads the output.
"""

import argparse
import re
import struct
import sys
from pathlib import Path

try:
    from tools.forever_tools import wago
    from tools.forever_tools.fsio import atomic_write
    from tools.gen_routes import BUILD, db2
except ModuleNotFoundError:
    from forever_tools import wago
    from forever_tools.fsio import atomic_write
    from gen_routes import BUILD, db2

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache" / f"casc-{BUILD}"
OUTPUT = ROOT / "Data" / "RoadCells.lua"
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
        f"https://wago.tools/api/casc/{file_id}?version={BUILD}",
        CACHE / str(file_id),
        user_agent="ShortestPathForever/1.0",
        offline=offline,
        timeout=60,
        validate=validate,
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
    """The tile's road cells, x-major: cell (i, j) runs from the tile's south (x) and east (y) edges."""
    road = set()
    edges = [round(TEXELS * (1 - n / cells)) for n in range(cells + 1)]
    for i in range(cells):
        rows = range(edges[i + 1], edges[i])
        for j in range(cells):
            c0, c1 = edges[j + 1], edges[j]
            total = sum(sum(weights[r * TEXELS + c0 : r * TEXELS + c1]) for r in rows)
            if total * 2 >= 255 * len(rows) * (c1 - c0):
                road.add(i * cells + j)
    return road


def encode(road, count):
    """Alternating run lengths, off first, two base64 symbols each; a run over 4095 continues after an empty one."""
    out, value, run = [], False, 0

    def emit(length):
        while length > 4095:
            out.append(B64[63] * 2 + "AA")
            length -= 4095
        out.append(B64[length // 64] + B64[length % 64])

    for cell in range(count):
        if (cell in road) != value:
            emit(run)
            value, run = not value, 0
        run += 1
    if value:
        emit(run)
    return "".join(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="require existing tools/.cache inputs")
    args = parser.parse_args()
    wdts = {int(row["ID"]): int(row["WdtFileDataID"]) for row in db2("Map", offline=args.offline)}
    lines = [
        "-- Generated by tools/gen_roads.py; do not edit.",
        f"-- Source: wago.tools CASC, wow_classic_beta {BUILD}: ADT terrain texture layers (MDID, MCLY, MCAL) of",
        f"-- {len(ROAD_TEXTURES)} road textures. A walking-map cell is road when they cover at least half of it.",
        "-- roads[map][k + 1]: Nav cluster k's cells, x-major, as alternating run lengths starting with non-road",
        "-- ones, two base64 symbols (A-Za-z0-9+/) each.",
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
            road = cells_of(weights, cells) if weights else set()
            if road:
                roads += len(road)
                lines.append(f'\t\t[{k + 1}] = "{encode(road, cells * cells)}",')
        lines.append("\t},")
        print(f"map {map_id}: {roads} road cells", file=sys.stderr)
    lines.append("}")
    atomic_write(OUTPUT, "\n".join(lines) + "\n")


if __name__ == "__main__":
    main()

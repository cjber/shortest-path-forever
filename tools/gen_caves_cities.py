"""Generate tests/fixtures/caves_cities.lua: the caves and cities suite's places and reference walks (#1015).

Spawns are classic-db's stationary creatures on the two continents that live on the ground (InhabitType's ground bit)
and are not spawned only by a game event: each must stand on the walking map. City walks join every service
(trainer, banker, auctioneer, innkeeper, flight master, battlemaster, stable master) in each capital Data/Zones.lua
bounds to and from each of the capital's hubs: its flight masters, bankers, auctioneers, innkeepers and the lift
landings Data/Transports.lua lists inside it. Cave walks go into and out of every cave an underground spawn lies
in (cave_walks), and CASES adds walks #1011 measured. Each walk carries its reference: the shortest walk on the raw
navmesh the walking map is baked from (tools/nav_reference.py), in horizontal yards. Areas load a few tiles at a time,
so a run stays under 1 GB.

    python3 tools/gen_caves_cities.py --mmaps '<bake>/trinity{map}/mmaps' --terrain '<bake>/extract{map}-*/maps'
"""

import argparse
import csv
import gc
import glob
import gzip
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "baker"))

import gen_nav  # noqa: E402
from gen_transit import CACHE, DB_REV, classicdb  # noqa: E402

OUTPUT = ROOT / "tests" / "fixtures" / "caves_cities.lua"
MAPS = (0, 1)
TUPLES = re.compile(r"\(((?:'(?:\\.|[^'\\])*'|[^()'])*)\)")
INHABIT_GROUND = 1  # creature_template.InhabitType bit (cmangos InhabitTypeValues)
# creature_template.NpcFlags bits (cmangos NPCFlags) that make a creature a city service, and the hubs among them.
SERVICES = {8: "flight", 16: "trainer", 128: "inn", 256: "bank", 2048: "battlemaster", 4096: "auction", 8192: "stable"}
HUBS = {"flight", "bank", "auction", "inn", "lift"}
INTERACTION = 5.0  # yards a player talks to a creature from (INTERACTION_DISTANCE, TrinityCore ObjectDefines.h)


def rows(line):
    for m in TUPLES.finditer(line):
        yield next(csv.reader([m[1]], quotechar="'", escapechar="\\"))


def creatures(path):
    """(entry, name, subname, npc flags, map, x, y, z) of each ground creature that stands still and is always there."""
    templates, spawns, event = {}, [], set()
    with gzip.open(path, "rt", encoding="utf-8") as stream:
        for line in stream:
            if line.startswith("INSERT INTO `creature_template` VALUES "):
                for r in rows(line):
                    templates[int(r[0])] = (r[1], "" if r[2] == "NULL" else r[2], int(r[13]), int(r[16]))
            elif line.startswith("INSERT INTO `creature` VALUES "):
                for r in rows(line):
                    if int(r[2]) in MAPS and r[11] == "0":
                        spawns.append((int(r[0]), int(r[1]), int(r[2]), float(r[4]), float(r[5]), float(r[6])))
            elif line.startswith("INSERT INTO `game_event_creature` VALUES "):
                for r in rows(line):
                    if int(r[1]) > 0:
                        event.add(int(r[0]))
    out = []
    for guid, entry, m, x, y, z in spawns:
        t = templates.get(entry)
        if t and guid not in event and t[2] & INHABIT_GROUND:
            out.append((entry, t[0], t[1], t[3], m, x, y, z))
    return out


def lua_json(script):
    run = subprocess.run(["luajit", "-e", script], cwd=ROOT, check=True, capture_output=True, text=True)
    return json.loads(run.stdout)


JSON = """local function enc(v)
  if type(v) == "table" then
    local o = {}
    for k, x in pairs(v) do o[#o + 1] = string.format("%q:%s", tostring(k), enc(x)) end
    return "{" .. table.concat(o, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end
"""


def capitals():
    """{zone id: (name, map, minX, minY, maxX, maxY)} of the capitals Data/Zones.lua bounds."""
    zones = lua_json(
        JSON + 'local ns = {} assert(loadfile("Data/Zones.lua"))("x", ns) local o = {} '
        "for id, z in pairs(ns.Zones) do if z.city then o[id] = z end end print(enc(o))"
    )
    return {int(k): (v.get("name", k), v["map"], v["minX"], v["minY"], v["maxX"], v["maxY"]) for k, v in zones.items()}


def lifts():
    """(map, x, y, z, site, name) of every lift landing Data/Transports.lua lists."""
    docks = lua_json(
        JSON + 'local ns = { Docks = {}, Routes = {} } assert(loadfile("Data/Transports.lua"))("x", ns) '
        "local o = {} for id, d in pairs(ns.Docks) do if d.site then o[id] = d end end print(enc(o))"
    )
    return [(d["map"], d["x"], d["y"], d["z"], d["site"], d["name"]) for d in docks.values()]


def closest(graph, key, p):
    """(distance, point): a poly's nearest point to p in 3D."""
    from baker.geometry import point_in_convex

    poly = graph.polys[key]
    x, y, z = p
    if point_in_convex(x, y, poly["xy"]):
        h = graph.height(key, x, y)
        return abs(z - h), (x, y, h)
    best = (math.inf, None)
    pts = poly["pts"]
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        d = [b[k] - a[k] for k in range(3)]
        n = sum(v * v for v in d)
        t = 0.0 if n == 0 else max(0.0, min(1.0, sum((p[k] - a[k]) * d[k] for k in range(3)) / n))
        q = tuple(a[k] + t * d[k] for k in range(3))
        best = min(best, (math.dist(p, q), q))
    return best


class Graph:
    """nav_reference over one area's tiles, with a bounding-box index so locating many points stays quick."""

    def __init__(self, ref, map_id, tiles):
        self.g = ref.load(map_id, tiles)
        self.index = {}
        for key, p in self.g.polys.items():
            xs, ys = [q[0] for q in p["pts"]], [q[1] for q in p["pts"]]
            for i in range(math.floor(min(xs) / 8), math.floor(max(xs) / 8) + 1):
                for j in range(math.floor(min(ys) / 8), math.floor(max(ys) / 8) + 1):
                    self.index.setdefault((i, j), []).append(key)
        polys = self.g.polys

        def locate(point, tile=None):
            x, y, z = point
            from baker.geometry import point_in_convex, poly_distance

            best = None
            for di in (0, -1, 1):
                for dj in (0, -1, 1):
                    for key in self.index.get((math.floor(x / 8) + di, math.floor(y / 8) + dj), ()):
                        p = polys[key]
                        if point_in_convex(x, y, p["xy"]):
                            d = abs(self.g.height(key, x, y) - z)
                        else:
                            d = poly_distance(point, p["pts"]) + 50
                        if best is None or d < best[0]:
                            best = (d, key)
            return best and best[1]

        self.g.locate = locate
        # Weakly connected parts (a drop joins its ledge and landing): a walk between two parts has no reference,
        # known without searching the whole area.
        self.part = {}
        for start in polys:
            if start in self.part:
                continue
            self.part[start], todo = start, [start]
            while todo:
                u = todo.pop()
                for w in (*self.g.adj.get(u, ()), *(d[0] for d in self.g.drops.get(u, ()))):
                    if w in polys and w not in self.part:
                        self.part[w] = start
                        todo.append(w)

    def reach(self, p):
        """{part: (distance, point)}: the nearest point of each part a player can talk to a creature at p from."""
        x, y, _ = p
        out, cells = {}, math.ceil(INTERACTION / 8)
        for di in range(-cells, cells + 1):
            for dj in range(-cells, cells + 1):
                for key in self.index.get((math.floor(x / 8) + di, math.floor(y / 8) + dj), ()):
                    d, q = closest(self.g, key, p)
                    part = self.part[key]
                    if d <= INTERACTION and d < out.get(part, (math.inf,))[0]:
                        out[part] = (d, q)
        return out

    def length(self, a, b):
        """(reference length, reach): the shortest walk between the points the two creatures are talked to from, on
        the part of the navmesh nearest both, and how far those points lie from the creatures; None when no part has
        both within reach."""
        ra, rb = self.reach(a), self.reach(b)
        shared = [(ra[k][0] + rb[k][0], k) for k in ra if k in rb]
        if not shared:
            return None
        part = min(shared)[1]
        w = self.g.walk(ra[part][1], rb[part][1])
        return w and (round(w.length, 1), round(ra[part][0] + rb[part][0], 1))


def tiles(x0, y0, x1, y1, pad=1):
    r = sorted(int(32 - x / gen_nav.T) for x in (x0, x1))
    c = sorted(int(32 - y / gen_nav.T) for y in (y0, y1))
    return [(i, j) for i in range(r[0] - pad, r[1] + pad + 1) for j in range(c[0] - pad, c[1] + pad + 1)]


def city_walks(ref, spawns, mmaps):
    walks = []
    landings = lifts()
    for zone, (_, m, x0, y0, x1, y1) in sorted(capitals().items()):
        places, seen = [], set()
        for entry, who, sub, flags, sm, x, y, z in spawns:
            kind = next((v for k, v in SERVICES.items() if flags & k), None)
            if kind and sm == m and x0 <= x <= x1 and y0 <= y <= y1 and entry not in seen:
                seen.add(entry)
                places.append((kind, f"{who} <{sub}>" if sub else who, x, y, z))
        for lm, x, y, z, site, end in landings:
            if lm == m and x0 <= x <= x1 and y0 <= y <= y1:
                places.append(("lift", f"{site} {end}", x, y, z))
        os.environ["NAV_MM"] = mmaps.format(map=m)
        graph = None  # one capital's graph in memory at a time
        gc.collect()
        graph = Graph(ref, m, tiles(x0, y0, x1, y1))
        for a in places:
            for b in places:
                if a is not b and (a[0] in HUBS or b[0] in HUBS):
                    walks.append(
                        (f"{zone} {a[1]} -> {b[1]}", m, a[2:], b[2:], graph.length(a[2:], b[2:]) or (None, None))
                    )
        hubs = sum(p[0] in HUBS for p in places)
        print(f"{zone}: {len(places)} places, {hubs} hubs", file=sys.stderr)
    return walks


def terrain_heights(directory, map_id):
    """height(x, y) over a map's extracted terrain; None over a hole or off the map. Callers go tile by tile, so only
    the last few tiles read are kept."""
    from functools import lru_cache

    from terrain import TILE, Tile

    @lru_cache(maxsize=16)
    def tile_at(row, col):
        path = Path(directory) / f"{map_id:04d}_{row:02d}_{col:02d}.map"
        return Tile(path.read_bytes(), path.name) if path.is_file() else None

    def height(x, y):
        row, col = int(32 - x / TILE), int(32 - y / TILE)
        tile = tile_at(row, col)
        return tile and tile.height((32 - row) - x / TILE, (32 - col) - y / TILE)

    return height


def cave_walks(ref, spawns, mmaps, terrain):
    """Into and out of every cave: a spawn more than gen_nav.CLIMB below the terrain over it is underground. Each
    underground spawn's tile is loaded with its eight neighbours, one window at a time to keep memory to nine tiles.
    Every underground poly is joined to its nearest open poly (one not under the terrain) by one search out from all
    the open ones; the open poly reached is the cave's mouth. Each mouth's cave is walked to and from the spawn
    farthest inside it."""
    import heapq

    walks = []
    for m in MAPS:
        height = terrain_heights(terrain[m], m)
        os.environ["NAV_MM"] = mmaps.format(map=m)
        by_tile = {}
        tile_of = lambda s: (int(32 - s[5] / gen_nav.T), int(32 - s[6] / gen_nav.T))  # noqa: E731
        for s in sorted(spawns, key=tile_of):
            if s[4] == m and (h := height(s[5], s[6])) is not None and s[7] < h - gen_nav.CLIMB:
                by_tile.setdefault(tile_of(s), []).append(s)
        caves = {}  # mouth poly -> (depth, spawn, mouth centre)
        for (r, cl), under in sorted(by_tile.items()):
            gc.collect()
            graph = Graph(ref, m, [(r + dr, cl + dc) for dr in (-1, 0, 1) for dc in (-1, 0, 1)])
            g = graph.g

            def centre(key, g=g):
                pts = g.polys[key]["pts"]
                return tuple(sum(p[a] for p in pts) / len(pts) for a in range(3))

            dist, mouth, heap = {}, {}, []
            for key in g.polys:
                c = centre(key)
                h = height(c[0], c[1])
                if h is None or c[2] >= h - gen_nav.CLIMB:
                    dist[key], mouth[key] = 0.0, key
                    heap.append((0.0, key))
            heapq.heapify(heap)
            while heap:
                d, u = heapq.heappop(heap)
                if d > dist[u]:
                    continue
                cu = centre(u)
                for w in g.adj.get(u, ()):
                    if w in g.polys:
                        nd = d + math.dist(cu, centre(w))
                        if nd < dist.get(w, math.inf):
                            dist[w], mouth[w] = nd, mouth[u]
                            heapq.heappush(heap, (nd, w))
            for s in under:
                reach = graph.reach(s[5:8])
                if not reach:
                    continue  # the spawn stands on nothing: the coverage check reports it
                key = g.locate(min(reach.values())[1])
                if key in mouth and dist[key] > 0 and (mouth[key] not in caves or dist[key] > caves[mouth[key]][0]):
                    a = centre(mouth[key])
                    walks_ab = (graph.length(a, s[5:8]), graph.length(s[5:8], a))
                    caves[mouth[key]] = (dist[key], s, a, walks_ab)
            del graph, g, dist, mouth
        for _, s, a, (into, out) in sorted(caves.values(), key=lambda v: v[2]):
            name = f"cave {m} {a[0]:.0f},{a[1]:.0f} {s[1]}"
            walks.append((name + " in", m, a, s[5:8], into or (None, None)))
            walks.append((name + " out", m, s[5:8], a, out or (None, None)))
        print(f"map {m}: {len(by_tile)} tiles with underground spawns, {len(caves)} caves", file=sys.stderr)
    return walks


# Walks other issues settled (#1011): the Dun Algaz pass both ways, the Wetlands to Thelsamar through the tunnel, and an
# Ironforge ramp past 50 degrees.
CASES = [
    ("Dun Algaz pass up", 0, (-4350.2, -2463.7, 216), (-4668.7, -2694.5, 323)),
    ("Dun Algaz pass down", 0, (-4668.7, -2694.5, 323), (-4350.2, -2463.7, 216)),
    ("Wetlands to Thelsamar", 0, (-3900, -2500, 108), (-5378, -2973, 324)),
    ("Ironforge ramp up", 0, (-4971.1, -991.0, 718), (-4963.2, -991.0, 728)),
    ("Ironforge ramp down", 0, (-4963.2, -991.0, 728), (-4971.1, -991.0, 718)),
]


def case_walks(ref, mmaps):
    walks = []
    for name, m, a, b in CASES:
        os.environ["NAV_MM"] = mmaps.format(map=m)
        graph = Graph(ref, m, tiles(a[0], a[1], b[0], b[1], pad=0))  # pad 0 gives the lengths #1011 measured with pad 2
        walks.append((name, m, a, b, graph.length(a, b) or (None, None)))
    return walks


def lua(v):
    if v is None:
        return "nil"
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    return f"{v:.1f}".rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def only(found):
    if len(found) != 1:
        raise SystemExit(f"--terrain matches {len(found)} directories: {found}")
    return found[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--mmaps", required=True, help="the raw navmesh tiles per map, a format string with {map}")
    ap.add_argument("--terrain", required=True, help="the extracted terrain maps per map, a glob with {map}")
    ap.add_argument("--offline", action="store_true")
    args = ap.parse_args()
    import nav_reference as ref

    classicdb(offline=args.offline)  # fetches the pinned dump once
    spawns = creatures(CACHE / f"classicdb-{DB_REV[:8]}.sql.gz")
    walks = case_walks(ref, args.mmaps) + city_walks(ref, spawns, args.mmaps)
    walks += cave_walks(ref, spawns, args.mmaps, {m: only(glob.glob(args.terrain.format(map=m))) for m in MAPS})
    source = json.loads((Path(args.mmaps.format(map=0)) / "source.json").read_text())
    out = [
        "-- Generated by tools/gen_caves_cities.py - do not edit.",
        "-- rule-ignore: file-size-no-growth - generated data, one row per walk",
        f"-- Spawns: https://github.com/cmangos/classic-db/tree/{DB_REV}",
        f"-- References: tools/nav_reference.py over the raw navmesh tiles of build {source.get('build')}.",
        "-- spawns[map] = { x, y, z, ... }; walks = { { name, map, x1, y1, z1, x2, y2, z2, reference, reach }, ... }",
        "-- stylua: ignore",
        "return {",
        "\tspawns = {",
    ]
    for m in MAPS:
        pts = sorted({(round(x, 1), round(y, 1), round(z, 1)) for _, _, _, _, sm, x, y, z in spawns if sm == m})
        out.append(f"\t\t[{m}] = {{")
        out += ["\t\t\t" + ", ".join(lua(c) for p in pts[i : i + 6] for c in p) + "," for i in range(0, len(pts), 6)]
        out.append("\t\t},")
    out += ["\t},", "\twalks = {"]
    for name, m, a, b, (length, reach) in walks:
        out.append("\t\t{ " + ", ".join(lua(v) for v in (name, m, *a, *b, length, reach)) + " },")
    out += ["\t},", "}", ""]
    OUTPUT.write_text("\n".join(out))
    print(f"{OUTPUT.relative_to(ROOT)}: {len(spawns)} spawns, {len(walks)} walks", file=sys.stderr)


if __name__ == "__main__":
    main()

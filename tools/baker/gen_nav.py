# rule-ignore: file-size-no-growth - one map bake shares one set of globals
"""Build a map's walking-route data (HPA* graph + per-cluster 8 yd grids) as an addon Lua file.

usage: gen_nav.py [<out.lua>] --map <id> [--name "<title>"] [--rows r0 r1 --cols c0 c1] [--jobs n]

Reads our own bake of the local client (TrinityCore mmtile layout <mm>/MMMM_RR_CC.mmtile, one Detour tile
per ADT) from NAV_MM. The tile bounding box comes from the .mmtile files present (optionally cut to --rows/--cols).
Every tile with walkable data becomes a cluster. Poly components a player cannot reach are dropped over the whole
map: those holding none of the map's fixed places (tools/baker/places.lua: flight masters, docks and lift ends, portal
ends, teleport landings), such as the sealed terrain under Stormwind, and those under MIN_COMPONENT polys (rooftops,
treetops, props).

Streamed so a continent fits in memory: pass 1 finds the poly components over the whole map with a compact
union-find; pass 2 rasterizes each tile from the 3x3 tiles around it (in parallel); pass 3 builds the HPA graph over
the assembled grid. All iteration is in a canonical (tile, poly) order, so the output is deterministic and a tile's
cells do not depend on which window computed them.

Detour stores vertices as (worldY, worldZ, worldX). Output is in UnitPosition's frame: x grows north (world X),
y grows west (world Y).
"""

import base64
import glob
import heapq
import json
import math
import multiprocessing
import os
import re
import subprocess
import sys
import time
from array import array
from collections import Counter, defaultdict
from pathlib import Path
from textwrap import wrap
from typing import cast

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from baker.geometry import (
    centroid,
    clip_convex,
    clip_segment,
    height,
    plane,
    point_in_convex,
    poly_distance,
    poly_distance2,
    seg_in_box,
)  # noqa: E402
from baker.inputs import arguments, generator_digest, source_label  # noqa: E402
from baker.measure import record, tile_hashes  # noqa: E402
from baker.terrain import encode_sparse as encode_terrain  # noqa: E402
from baker.terrain import sample_cluster  # noqa: E402
from baker.tiles import load_tile  # noqa: E402
from forever_tools.fsio import atomic_write  # noqa: E402

MM = os.environ.get("NAV_MM", "mm")
MAPS = os.environ.get("NAV_MAPS", "")  # the extractor's maps/ directory; absent for historical bakes without terrain
ROOT = Path(__file__).resolve().parents[2]
T = 1600 / 3
CELLS = 67
CS = T / CELLS
# A swum yard counts as three running ones: beyond the slower pace (4.7 against 7 yd/s), swimming means climbing
# out at a bank that may be a cliff, aggro from things that cannot be outrun, and fatigue far from shore.
SWIM = 3.0
WATER_WALK = 1.0  # walking on water is running
WEIGHTS = (SWIM, WATER_WALK)  # every edge carries one cost per weight, in this order
ENTRANCE_RUN = 20  # longest border run (cells) served by one entrance
# The runtime clamp and settings slider share this limit; do not maintain a separate baker range.
ROAD_FACTOR_MAX = (
    1 + int(re.search(r"^local ROAD_DETOUR_MAX = (\d+)$", (ROOT / "Journey/Hazards.lua").read_text(), re.M)[1]) / 100
)
PRUNE = 1.02  # drop an intra edge when a two-hop path is within 2%
MIN_COMPONENT = 500
DIRS = {(1, 0): 0, (-1, 0): 1, (0, 1): 2, (0, -1): 3, (1, 1): 4, (1, -1): 5, (-1, 1): 6, (-1, -1): 7}
MARGIN = 1.0  # a step between cells may use navmesh this far outside the two cells (yd)
CLIMB = 3.0  # two surfaces at one point are the same layer within this height (yd)
ZQ = 2  # base heights are stored to this step (yd)
AREA_GROUND, AREA_GROUND_STEEP, AREA_WATER, AREA_OCEAN = 11, 10, 9, 6
# The player's own limits (benilla-re systems/collision/walking.md, the Forever client's float pool, TrinityCore
# Player::HandleFall): ground from 50 to 61.6 degrees is steep and walked only downhill, a step reaches 2.0 yards, and
# falling hurts past 14.57 yards. A drop's fall costs the time free fall takes, and a slope costs nothing.
GRAVITY = 19.2911  # yards per second squared
RUN = 7.0  # the player's run speed, yards per second
FALL_LIMIT = 14.57  # the longest fall that does not hurt, yards
DROP_COLUMNS = 4  # how far (8-yard cells) from a ledge a baked connection may land
LAYER_MARGIN = DROP_COLUMNS
FLAG_UNDER_HAZARD = 0x80  # Mappster: ground under magma or slime
FLAG_UNDER_LIQUID = 0x40  # Mappster: ground under liquid
SOURCE = source_label(None)
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

# Set by configure(): the map, its tiles and the global grid.
MAP = 0
TILES = {}  # (rr, cc) -> path
ROWS = COLS = range(0)
CX0 = CY0 = NX = NY = GW = GH = 0
X0 = Y0 = 0.0
ORD = {}  # (rr, cc) -> canonical tile ordinal (rows outer, cols inner)
# Set by components(): each tile's first poly id and each poly's component size.
BASE = {}  # (rr, cc) -> first dense poly id of the tile
SIZE = array("i")  # dense poly id -> poly count of its navmesh component; kept when >= MIN_COMPONENT
# Nodes are cells (the base surface, ids below GW * GH) and floors (GW * GH + floor index), filled by assemble_floors().
FLOOR_CELL, FLOOR_VAL, FLOOR_Z, FLOOR_LAYER = array("i"), bytearray(), array("f"), bytearray()  # layer: 1 = lowest
BASE_Z = array("f")  # cell -> height of its base surface
LINKS = defaultdict(dict)  # node -> {node it steps to besides the base grid's own: cost in yards, or None for the step}
# (node, node) steps whose direction the navmesh walk decided where the stored heights would not: the runtime takes them
# as written, with no steep test (#1101). A rasterize_tile link marks one with the cost FREE_STEP.
FREE = set()
FREE_STEP = "free"
NARROW_STEP = "narrow"
WET_STEP = "wet"
WET_STEPS = defaultdict(set)  # cluster -> steps without straight dry clearance
NARROW_STEPS = defaultdict(set)  # cluster -> steps with only centre-line dry clearance
FLOORS_OF = defaultdict(list)  # cluster -> its floor nodes, by (cell, height)
LINKED_OF = defaultdict(list)  # cluster -> its nodes with LINKS, sorted
FLOORS_AT = {}  # cell -> its floor nodes, lowest first
TERRAIN = {}  # cluster -> its terrain field (tools/baker/terrain.py)
KINDS = defaultdict(int)  # how the encoded links came out: step bits, one-way records, drops
ROAD_CELLS = {}  # global cell -> road coverage (0 to 1) from Data/RoadCells.lua, as the runtime charges it


def configure(map_id, rows=None, cols=None):
    global MAP, TILES, ROWS, COLS, CX0, CY0, NX, NY, GW, GH, X0, Y0, ORD
    KINDS.clear()
    WET_STEPS.clear()
    NARROW_STEPS.clear()
    MAP = map_id
    TILES = {}
    for path in glob.glob(os.path.join(MM, f"{map_id:04d}_??_??.mmtile")):
        rr, cc = map(int, re.findall(r"_(\d\d)_(\d\d)\.mmtile$", path)[0])
        if (rows is None or rows[0] <= rr <= rows[1]) and (cols is None or cols[0] <= cc <= cols[1]):
            TILES[(rr, cc)] = path
    if not TILES:
        sys.exit(f"no {map_id:04d}_RR_CC.mmtile files in {MM}")
    ROWS = range(min(r for r, _ in TILES), max(r for r, _ in TILES) + 1)
    COLS = range(min(c for _, c in TILES), max(c for _, c in TILES) + 1)
    CX0, CY0 = 31 - max(ROWS), 31 - max(COLS)
    NX, NY = len(ROWS), len(COLS)
    X0, Y0 = CX0 * T, CY0 * T
    GW, GH = NX * CELLS, NY * CELLS
    ORD = {rc: i for i, rc in enumerate(sorted(TILES))}
    global ROAD_CELLS
    ROAD_CELLS = read_roads(map_id)


def enc(v, width):
    assert 0 <= v < 64**width, (v, width)
    return "".join(B64[(v >> (6 * (width - 1 - i))) & 63] for i in range(width))


def cluster_of_tile(rr, cc):
    return ((31 - rr) - CX0) * NY + ((31 - cc) - CY0)


def places(map_id):
    """The map's fixed places with a height, as (x, y, z): players arrive there, so their ground is reached."""
    run = subprocess.run(
        ["luajit", "tools/baker/places.lua", str(map_id)], cwd=ROOT, check=True, capture_output=True, text=True
    )
    return [tuple(p) for p in json.loads(run.stdout)]


def decode_road_runs(s):
    """Positive-painted cells and their coverage (symbol / 63, as Routing/PathGrid.lua reads it): two base64 length
    symbols, then one coverage symbol per run."""
    cells, at = {}, 0
    for pos in range(0, len(s), 3):
        run = B64.index(s[pos]) * 64 + B64.index(s[pos + 1])
        coverage = B64.index(s[pos + 2]) / 63
        if coverage > 0:
            cells.update(dict.fromkeys(range(at, at + run), coverage))
        at += run
    return cells


def off_road(cell, base):
    """The part of a step's cost the road factor scales: Routing/Path.lua charges 1 + (OFFROAD - 1) * (1 - coverage),
    so faint paint is nearly off road and only full coverage is free."""
    return base * (1 - ROAD_CELLS.get(cell, 0.0))


def read_roads(map_id):
    """Data/RoadCells.lua's road cells for a map, as global cell id -> coverage; empty before a road bake."""
    path = ROOT / "Data" / "RoadCells.lua"
    if not path.exists():
        return {}
    found, inside = {}, False
    for line in path.read_text().splitlines():
        if line.strip() == f"[{map_id}] = {{":
            inside = True
            continue
        if inside:
            if line.strip() == "},":
                break
            m = re.match(r'\s*\[(\d+)\] = "([^"]+)"', line)
            if m:
                found[int(m.group(1)) - 1] = decode_road_runs(m.group(2))
    roads = {}
    for k, locals_ in found.items():
        for cell, coverage in locals_.items():
            roads[(k // NY * CELLS + cell // CELLS) * GH + (k % NY * CELLS + cell % CELLS)] = coverage
    return roads


def drop_cost(horizontal, fall):
    """A drop's cost in running yards: the horizontal step plus the time free fall takes at the client's gravity,
    run at the player's speed. Slope never changes how fast ground is crossed, so a fall is the only extra."""
    return horizontal + RUN * math.sqrt(2 * fall / GRAVITY)


def walkable(pts, flags, area, typ):
    # Ground under liquid is a hidden floor, such as the bare terrain about 35 yards under Stormwind. The player's
    # height is unknown when a walk starts, so a route could pick it. The TrinityCore patch bakes it as area 7 with
    # flag 0x40, the flag Mappster gave it, and both are refused here. Steep ground is kept and its steps become
    # downhill-only links.
    return (
        typ == 0
        and area in (AREA_GROUND, AREA_GROUND_STEEP, AREA_WATER, AREA_OCEAN)
        and not flags & (FLAG_UNDER_HAZARD | FLAG_UNDER_LIQUID)
        and pts
    )


def read_tile(rc):
    """One tile's walkable polys as (local index, pts (X, Y, Z), water, steep), its intra-tile links, border edges
    and the one-way drops the local bake emitted as off-mesh connections, as ((start X, Y, Z), (end X, Y, Z))."""
    verts, tile_polys, connections = load_tile(TILES[rc])
    pts_of = [[(verts[v * 3 + 2], verts[v * 3], verts[v * 3 + 1]) for v in pv] for pv, *_ in tile_polys]  # (X, Y, Z)
    ok = [bool(walkable(pts_of[i], flags, area, typ)) for i, (_, _, flags, area, typ) in enumerate(tile_polys)]
    # Detour holds (west, up, north); a connection's ends are in the same frame as the vertices
    drops = [((pos[2], pos[0], pos[1]), (pos[5], pos[3], pos[4])) for pos, _, _, _ in connections]
    polys, links, border = [], [], []
    for i, (_pv, pn, _flags, area, _typ) in enumerate(tile_polys):
        if not ok[i]:
            continue
        pts = pts_of[i]
        polys.append((i, pts, area in (AREA_WATER, AREA_OCEAN), area == AREA_GROUND_STEEP))
        n = len(pts)
        for e, nb in enumerate(pn):
            if nb == 0:
                continue
            p1, p2 = pts[e], pts[(e + 1) % n]
            if nb & 0x8000:  # tile-border edge; detour side 0/4 is an x (= world Y) border
                side = nb & 0xFF
                if side in (0, 4):
                    key, lo, hi = ("y", round(p1[1], 1)), *sorted((p1[0], p2[0]))
                else:
                    key, lo, hi = ("x", round(p1[0], 1)), *sorted((p1[1], p2[1]))
                border.append((key, i, lo, hi, (p1[2] + p2[2]) / 2))
            elif ok[nb - 1]:
                links.append((i, nb - 1, p1[:2], p2[:2]))
    return polys, links, border, drops


def match_borders(border):
    """Cross-tile links from border edges keyed by line: [(a, b, ends)] for overlapping edges of different tiles."""
    out = []
    for key, es in border.items():
        es.sort(key=lambda t: (t[1], t[0]))
        for i in range(len(es)):
            for j in range(i + 1, len(es)):
                if es[j][1] >= es[i][2] - 0.01:
                    break
                a, b = es[i][0], es[j][0]
                if a >> 16 == b >> 16:
                    continue
                lo, hi = max(es[i][1], es[j][1]), min(es[i][2], es[j][2])
                if hi - lo > 0.05 and abs(es[i][3] - es[j][3]) < 4:
                    axis, at = key
                    out.append((a, b, ((lo, at), (hi, at)) if axis == "y" else ((at, lo), (at, hi))))
    return out


def gid(rc, i):
    return ORD[rc] << 16 | i


def components(spots):
    """Pass 1: union-find over every walkable poly of the map; SIZE records each poly's component size, or 0 for a
    component no fixed place in spots stands on. A place stands on its nearest walkable poly in its own or a
    neighbouring tile, whatever that poly's component."""
    global SIZE
    parent = array("i")
    border = defaultdict(list)
    dense = {}  # gid -> dense id, only while matching borders
    near = defaultdict(list)  # tile -> the places in it or a neighbouring tile
    for n, (x, y, _) in enumerate(spots):
        rr, cc = int(32 - x / T), int(32 - y / T)
        if (rr, cc) in TILES:
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    near[(rr + dr, cc + dc)].append(n)
    stand = [(math.inf, -1)] * len(spots)  # place -> (distance, dense id of the poly it stands on)

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for rc in sorted(TILES):
        polys, links, edges, _ = read_tile(rc)
        BASE[rc] = base = len(parent)
        loc = {i: base + n for n, (i, _, _, _) in enumerate(polys)}
        parent.extend(range(base, base + len(polys)))
        for i, j, _, _ in links:
            parent[find(loc[i])] = find(loc[j])
        for n in near.get(rc, ()):
            for i, pts, _, _ in polys:
                # the gap to the poly's bounding box never exceeds the distance to the poly
                gap = max(
                    max(min(p[a] for p in pts) - spots[n][a], spots[n][a] - max(p[a] for p in pts)) for a in (0, 1, 2)
                )
                if gap < stand[n][0]:
                    d = poly_distance(spots[n], pts)
                    if d < stand[n][0]:
                        stand[n] = (d, loc[i])
        for key, i, lo, hi, z in edges:
            g = gid(rc, i)
            dense[g] = loc[i]
            border[key].append((g, lo, hi, z))
    for a, b, _ in match_borders(border):
        parent[find(dense[a])] = find(dense[b])
    size = defaultdict(int)
    for x in range(len(parent)):
        size[find(x)] += 1
    reached = {find(x) for _, x in stand if x >= 0}
    if not reached:
        sys.exit(f"no fixed place of map {MAP} stands on the selected tiles, so none of their ground is reachable")
    SIZE = array("i", (size[r] if r in reached else 0 for r in map(find, range(len(parent)))))
    big = sorted((size[r] for r in reached if size[r] >= MIN_COMPONENT), reverse=True)
    print(
        f"tiles {len(TILES)}, polys {len(parent)}, components {len(size)}, reached {len(reached)}, kept {len(big)} "
        f"({sum(big)} polys): {big[:12]}{' ...' if len(big) > 12 else ''}",
        flush=True,
    )


def load_window(tiles):
    """Kept polys of some tiles keyed by gid, with their adjacency and portals (world coordinates)."""
    polys, adj, portal, border = {}, defaultdict(set), {}, defaultdict(list)
    for rc in sorted(tiles, key=ORD.__getitem__):
        tp, links, edges, _ = read_tile(rc)
        base = BASE[rc]
        kept = set()
        for n, (i, pts, water, steep) in enumerate(tp):
            if SIZE[base + n] < MIN_COMPONENT:
                continue
            kept.add(i)
            nv = len(pts)
            c = tuple(sum(p[a] for p in pts) / nv for a in range(3))
            polys[gid(rc, i)] = dict(
                c=c,
                water=water,
                steep=steep,
                size=SIZE[base + n],
                pts=[(p[0], p[1]) for p in pts],
                plane=plane(pts, c),
                zs=(min(q[2] for q in pts), max(q[2] for q in pts)),
            )
        for i, j, p1, p2 in links:
            if i in kept and j in kept:
                adj[gid(rc, i)].add(gid(rc, j))
                portal[(gid(rc, i), gid(rc, j))] = (p1, p2)
        for key, i, lo, hi, z in edges:
            if i in kept:
                border[key].append((gid(rc, i), lo, hi, z))
    for a, b, ends in match_borders(border):
        adj[a].add(b)
        adj[b].add(a)
        portal[(a, b)] = portal[(b, a)] = ends
    return polys, adj, portal


def rasterize_layers(polys, adj, portal, bounds):
    """One layer per piece of surface a cell stands on.

    A cell's candidate surfaces that the navmesh joins inside the cell (+ MARGIN) are one piece of surface, so only
    one of them becomes a layer: a slope that spans more than CLIMB across one cell used to arrive several times, as
    its own floors, and each of those cost a node and its links. Surfaces that only meet elsewhere (a bridge over a
    road, a tunnel under ground) stay floors, and so does steep ground, which the player walks down and never across.
    Prefer the largest component, then the highest surface, so roofs cannot displace the city below; keep the other
    pieces at least CLIMB apart as floors; omit lake beds under water. Narrow passages anchor on a point of the
    passage at the poly's height there, because their cells may have no centre inside the mesh.
    """
    ax0, ax1, ay0, ay1 = bounds
    surf = defaultdict(list)  # cell -> [(component size, height, value, poly, point, late)]

    def at(x, y):
        gx, gy = int((x - X0) // CS), int((y - Y0) // CS)
        return gx * GH + gy if ax0 <= gx <= ax1 and ay0 <= gy <= ay1 else -1

    for pid in sorted(polys):
        p = polys[pid]
        v = 2 if p["water"] else 1
        xs, ys = [q[0] for q in p["pts"]], [q[1] for q in p["pts"]]
        for gx in range(max(ax0, int((min(xs) - X0) // CS)), min(ax1 + 1, int((max(xs) - X0) // CS) + 1)):
            for gy in range(max(ay0, int((min(ys) - Y0) // CS)), min(ay1 + 1, int((max(ys) - Y0) // CS) + 1)):
                c = (X0 + (gx + 0.5) * CS, Y0 + (gy + 0.5) * CS)
                if point_in_convex(c[0], c[1], p["pts"]):
                    surf[gx * GH + gy].append((p["size"], height(p, *c), v, pid, c, False))
    # Portals per cell: two polys joined by one inside a cell (+ MARGIN) are the same piece of surface there.
    edges = defaultdict(list)
    for (u, w), (e1, e2) in portal.items():
        if w < u:
            continue
        gx0 = max(ax0, int((min(e1[0], e2[0]) - MARGIN - X0) // CS))
        gx1 = min(ax1, int((max(e1[0], e2[0]) + MARGIN - X0) // CS))
        gy0 = max(ay0, int((min(e1[1], e2[1]) - MARGIN - Y0) // CS))
        gy1 = min(ay1, int((max(e1[1], e2[1]) + MARGIN - Y0) // CS))
        for gx in range(gx0, gx1 + 1):
            for gy in range(gy0, gy1 + 1):
                edges[gx * GH + gy].append((u, w))
    # Passages narrower than a cell: centroid -> shared edge midpoint -> centroid stays inside the two convex polygons.
    # These surfaces anchor on the sampled point of that line, since the cell centre may lie off the mesh, and take the
    # poly's own height there. The centroid's height is the poly's height somewhere else: on a ramp it misplaced a cell
    # by several yards, and the step beside it read as a climb past 50 degrees, so the Dun Algaz tunnel walked one way
    # only (#1011). Only the first passage through an empty cell may become its base; later ones can only add a floor.
    for u in sorted(adj):
        for w in sorted(adj[u]):
            if w <= u:
                continue
            pu, pw = polys[u], polys[w]
            e1, e2 = portal[(u, w)]
            mid = ((e1[0] + e2[0]) / 2, (e1[1] + e2[1]) / 2)
            for a, b, p, pid in ((pu["c"], mid, pu, u), (mid, pw["c"], pw, w)):
                steps = int(math.dist(a[:2], b[:2]) / (CS / 4)) + 1
                for t in range(steps + 1):
                    q = (a[0] + (b[0] - a[0]) * t / steps, a[1] + (b[1] - a[1]) * t / steps)
                    i = at(*q)
                    z = height(p, *q)
                    if i >= 0 and not any(abs(s[1] - z) < CLIMB for s in surf[i]):
                        surf[i].append((p["size"], z, 2 if p["water"] else 1, pid, q, bool(surf[i])))
    # A poly covering part of a cell but not its centre is still ground the player stands on in that cell: a stall or
    # a lamp post on a street's cell centre must not leave the cell only the ground under the city (#1046). It anchors
    # on the centroid of its part inside the cell and only adds a floor, never the base, so a cell's base and its
    # empty cells stay as the centre sample decides.
    stood = {i for i, ss in surf.items() if ss}
    for pid in sorted(polys):
        p = polys[pid]
        xs, ys = [q[0] for q in p["pts"]], [q[1] for q in p["pts"]]
        for gx in range(max(ax0, int((min(xs) - X0) // CS)), min(ax1 + 1, int((max(xs) - X0) // CS) + 1)):
            for gy in range(max(ay0, int((min(ys) - Y0) // CS)), min(ay1 + 1, int((max(ys) - Y0) // CS) + 1)):
                i = gx * GH + gy
                if i not in stood:
                    continue
                x0, y0 = X0 + gx * CS, Y0 + gy * CS
                c = centroid(clip_convex(p["pts"], (x0, x0 + CS, y0, y0 + CS)))
                if c is None:
                    continue
                z = height(p, *c)
                if not any(abs(s[1] - z) < CLIMB for s in surf[i]):
                    surf[i].append((p["size"], z, 2 if p["water"] else 1, pid, c, True))

    def pieces(ss, i):
        """The piece of surface each of the cell's candidates stands on, as a group number."""
        parent = {}

        def find(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        for u, w in edges.get(i, ()):
            if polys[u]["steep"] != polys[w]["steep"]:
                continue  # steep ground is walked down, never the same surface as the ground it leads to
            parent.setdefault(u, u)
            parent.setdefault(w, w)
            a, b = find(u), find(w)
            if a != b:
                parent[a] = b
        return [find(parent.setdefault(s[3], s[3])) for s in ss]

    layers = {}  # cell -> [(height, value, (poly, point))], base first, then floors by height
    for i, ss in surf.items():
        piece = pieces(ss, i)
        base = max((n for n, s in enumerate(ss) if not s[5]), key=lambda n: (ss[n][0], ss[n][1]))
        chosen, taken = [base], {piece[base]}
        # Ground under the top water surface is a lake or sea bed, never walked; the water itself stays (a river
        # under a bridge is still swum).
        water = max((s[1] for s in ss if s[2] == 2), default=-1e9)
        for n in sorted(range(len(ss)), key=lambda n: (ss[n][0], ss[n][1]), reverse=True):
            if piece[n] in taken or ss[n][1] < water:
                continue
            if all(abs(ss[n][1] - ss[c][1]) >= CLIMB for c in chosen):
                chosen.append(n)
                taken.add(piece[n])
        chosen[1:] = sorted(chosen[1:], key=lambda n: ss[n][1])
        layers[i] = [(ss[n][1], ss[n][2], (ss[n][3], ss[n][4])) for n in chosen]
        # Every layer's height comes from its anchor, so endpoint snapping and terrain matching use the same surface.
        for z, _, (pid, point) in layers[i]:
            if abs(z - height(polys[pid], *point)) > 0.01:
                raise ValueError(f"cell {i}: layer height {z:.2f} is not poly {pid}'s height at its anchor {point}")

    return layers


def pick_surface(layers, polys, candidates, x, y, z):
    """The (cell, layer) of the poly an endpoint lies on, chosen by the poly's own height at the point rather than
    the nearest cell anchor within CLIMB. candidates is (cell, dx, dy), the endpoint's own cell first."""
    best, rank = None, None
    for cell, dx, dy in candidates:
        for la, (_h, _v, (pid, _p)) in enumerate(layers.get(cell, ())):
            poly = polys[pid]
            # the heightfield samples points the simplified navmesh outline may just miss, so a poly within a step
            # outside the endpoint counts as the same surface
            dist = poly_distance2(x, y, poly["pts"])
            if dist > MARGIN:
                continue
            gap = abs(height(poly, x, y) - z)
            if gap > CLIMB:
                continue
            r = (gap, dist, 0 if (dx == 0 and dy == 0) else 1, abs(dx) + abs(dy), dx, dy)
            if rank is None or r < rank:
                best, rank = (cell, la), r
    return best


def dry_segment(polys, adj, portals, pa, a, pb, b):
    """Follow a straight segment through dry convex polygons in portal order."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    squared = dx * dx + dy * dy
    if pa == pb:
        return not polys[pa]["steep"] or height(polys[pa], *b) <= height(polys[pa], *a) + 0.01
    if squared == 0:
        return False
    eps = 1e-9
    best = {pa: 0.0}
    queue = [(0.0, pa)]
    while queue:
        at, u = heapq.heappop(queue)
        if at != best[u]:
            continue
        poly = polys[u]
        if poly["steep"]:
            gx, gy = poly["plane"][-2:]
            if gx * dx + gy * dy > 0.01:
                continue
        if u == pb:
            return True
        for v in adj.get(u, ()):
            if polys[v]["water"]:
                continue
            p, q = portals[u, v]
            px, py = p[0] - a[0], p[1] - a[1]
            ex, ey = q[0] - p[0], q[1] - p[1]
            cross = dx * ey - dy * ex
            if abs(cross) <= eps:
                if abs(px * dy - py * dx) > eps:
                    continue
                start, end = sorted(
                    (
                        (px * dx + py * dy) / squared,
                        ((q[0] - a[0]) * dx + (q[1] - a[1]) * dy) / squared,
                    )
                )
                crossing = max(at, start)
                if crossing > end + eps:
                    continue
            else:
                portal_at = (px * dy - py * dx) / cross
                crossing = (px * ey - py * ex) / cross
                if not -eps <= portal_at <= 1 + eps or crossing < at - eps:
                    continue
                crossing = max(at, crossing)
            if crossing <= 1 + eps and crossing < best.get(v, math.inf):
                best[v] = crossing
                heapq.heappush(queue, (crossing, v))
    return False


def dry_corridor(polys, adj, portals, pa, a, pb, b):
    """Certify the convex hull of two dry cells. Every interior mesh edge needs a bidirectional portal.

    A chord may start anywhere in the source cell. With no exposed interior edges it can follow the flat,
    dry mesh through to the target cell. The diagonal hull also covers the approaches to the shared corner.
    """
    eps = 1e-8
    radius = CS / 2
    x0, x1 = min(a[0], b[0]) - radius, max(a[0], b[0]) + radius
    y0, y1 = min(a[1], b[1]) - radius, max(a[1], b[1]) + radius
    sx, sy = b[0] - a[0], b[1] - a[1]
    diagonal = sx != 0 and sy != 0

    def band(p):
        return (p[0] - a[0]) * sy / CS - (p[1] - a[1]) * sx / CS

    def interior_span(p, q):
        clipped = clip_segment(p, q, (x0, x1, y0, y1))
        if clipped is None:
            return None
        u, v = clipped
        if diagonal:
            start, end = band(u), band(v)
            lo, hi = sorted((start, end))
            if lo >= CS - eps or hi <= -CS + eps:
                return None
            if lo < -CS or hi > CS:
                first = max(-CS, min(CS, start))
                last = max(-CS, min(CS, end))
                t0, t1 = (first - start) / (end - start), (last - start) / (end - start)
                u, v = tuple((u[0] + t * (v[0] - u[0]), u[1] + t * (v[1] - u[1])) for t in (t0, t1))
        mx, my = (u[0] + v[0]) / 2, (u[1] + v[1]) / 2
        if x0 + eps < mx < x1 - eps and y0 + eps < my < y1 - eps and math.dist(u, v) > eps:
            return u, v
        return None

    reached, pending = {pa}, [pa]
    while pending:
        u = pending.pop()
        poly = polys[u]
        if poly["water"] or poly["steep"]:
            return False
        for i, q in enumerate(poly["pts"]):
            p = poly["pts"][i - 1]
            span = interior_span(p, q)
            if span is None:
                continue
            start, stop = span
            dx, dy = q[0] - p[0], q[1] - p[1]
            length = math.hypot(dx, dy)
            dx, dy = dx / length, dy / length

            def side(point, dx=dx, dy=dy, p=p):
                return dx * (point[1] - p[1]) - dy * (point[0] - p[0])

            def along(point, dx=dx, dy=dy, p=p):
                return dx * (point[0] - p[0]) + dy * (point[1] - p[1])

            lo, hi = along(start), along(stop)
            openings = []
            for v in adj.get(u, ()):
                reciprocal = portals.get((v, u))
                other = polys[v]
                if reciprocal is None or other["water"] or other["steep"] or side(poly["c"]) * side(other["c"]) >= 0:
                    continue
                forward = portals[u, v]
                if any(abs(side(point)) > eps for point in (*forward, *reciprocal)):
                    continue
                left, right = sorted(map(along, forward))
                back_left, back_right = sorted(map(along, reciprocal))
                left, right = max(lo, left, back_left), min(hi, right, back_right)
                if right > left + eps:
                    openings.append((left, right))
                    if v not in reached:
                        reached.add(v)
                        pending.append(v)
            for left, right in sorted(openings):
                if left > lo + eps:
                    break
                lo = max(lo, right)
            if lo < hi - eps:
                return False
    return pb in reached


def rasterize_tile(rc):
    """Rasterize surfaces, outgoing step masks and floor links for one tile.

    The navmesh walk decides each direction independently, including diagonals. Only steps involving floors
    and costed drops need explicit destinations. A dry-clearance exception leaves the step walkable.
    """
    rr, cc = rc
    window = [(rr + dr, cc + dc) for dr in (-1, 0, 1) for dc in (-1, 0, 1) if (rr + dr, cc + dc) in TILES]
    polys, adj, portal = load_window(window)
    k = cluster_of_tile(rr, cc)
    tx0, tx1, ty0, ty1 = cluster_box(k)
    ax0, ax1 = max(0, tx0 - LAYER_MARGIN), min(GW - 1, tx1 + LAYER_MARGIN)
    ay0, ay1 = max(0, ty0 - LAYER_MARGIN), min(GH - 1, ty1 + LAYER_MARGIN)
    sx0, sx1 = max(0, tx0 - DROP_COLUMNS), min(GW - 1, tx1 + DROP_COLUMNS)
    sy0, sy1 = max(0, ty0 - DROP_COLUMNS), min(GH - 1, ty1 + DROP_COLUMNS)
    layers = rasterize_layers(polys, adj, portal, (ax0, ax1, ay0, ay1))

    def linked(i, la, j, lb):
        """Is there a navmesh path from cell i's surface la to cell j's surface lb inside the two cells (+ MARGIN)?

        Steep ground is crossed downhill only, so the search carries a ceiling: the highest the walk can be inside the
        poly it reached. Ordinary ground lifts it; on steep ground the walk leaves through a portal no higher than the
        ceiling, and leaves it at most as high as that portal's top. Without it a path could climb a steep face between
        two ordinary surfaces, such as the slope that joins the terrain under Stormwind to its streets."""
        (pa, a), (pb, b) = layers[i][la][2], layers[j][lb][2]
        steep = polys[pa]["steep"] or polys[pb]["steep"]
        if pa == pb and (not steep or height(polys[pb], *b) <= height(polys[pa], *a) + 0.01):
            return True
        (xi, yi), (xj, yj) = divmod(i, GH), divmod(j, GH)
        box = (
            X0 + min(xi, xj) * CS - MARGIN,
            X0 + (max(xi, xj) + 1) * CS + MARGIN,
            Y0 + min(yi, yj) * CS - MARGIN,
            Y0 + (max(yi, yj) + 1) * CS + MARGIN,
        )
        # Steep anchors go through the search below, which holds them to the downhill rule: a shortcut that joined
        # one poly or two neighbours outright let a flat cell climb onto the steep face beside it, and the step was
        # taken as written, up the mountain outside Ironforge's gate (#1011).
        if pb in adj.get(pa, ()) and not steep:
            # An edge shared anywhere is not a path between these two cells: a street and a keep floor that meet
            # only at a doorway far outside the box must not link every pair of cells facing each other (#890).
            return seg_in_box(*portal[(pa, pb)], box=box)
        hb = height(polys[pb], *b)
        best = {pa: height(polys[pa], *a) if polys[pa]["steep"] else math.inf}
        stack = [pa]
        while stack:
            u = stack.pop()
            ceiling = best[u]
            for v in adj.get(u, ()):
                # Only this part of the portal belongs to the step. Remote ends must not supply a higher
                # entry ceiling or a lower exit from steep ground outside the two cells.
                ends = clip_segment(*portal[(u, v)], box=box)
                if ends is None:
                    continue
                if polys[u]["steep"] and min(height(polys[u], *e) for e in ends) > ceiling + 0.01:
                    continue
                top = math.inf
                if polys[v]["steep"]:
                    top = max(height(polys[v], *e) for e in ends)
                    if polys[u]["steep"]:
                        top = min(top, ceiling)
                if v == pb or (point_in_convex(b[0], b[1], polys[v]["pts"]) and abs(height(polys[v], *b) - hb) < CLIMB):
                    if not polys[v]["steep"] or height(polys[v], *b) <= top + 0.01:
                        return True
                if best.get(v, -math.inf) >= top:
                    continue
                best[v] = top
                stack.append(v)
        return False

    masks = bytearray(CELLS * CELLS)
    floors, links = [], []
    for gx in range(tx0, tx1 + 1):
        for gy in range(ty0, ty1 + 1):
            i = gx * GH + gy
            surfaces = layers.get(i)
            if not surfaces:
                continue
            if len(surfaces) > 1:
                floors.append((i, [(v, z) for z, v, _ in surfaces[1:]]))
            local = (gx - tx0) * CELLS + gy - ty0
            a = (X0 + (gx + 0.5) * CS, Y0 + (gy + 0.5) * CS)
            for d, (dx, dy, _) in enumerate(MOVES):
                jx, jy = gx + dx, gy + dy
                if not (0 <= jx < GW and 0 <= jy < GH):
                    continue
                j = jx * GH + jy
                b = (X0 + (jx + 0.5) * CS, Y0 + (jy + 0.5) * CS)
                for la in range(len(surfaces)):
                    for lb in range(len(layers.get(j, ()))):
                        land = surfaces[la][1] == 1 and layers[j][lb][1] == 1
                        if not linked(i, la, j, lb):
                            continue
                        restriction = None
                        if land:
                            pa, anchor_a = surfaces[la][2]
                            pb, anchor_b = layers[j][lb][2]
                            # Refinement draws through cell coordinates; a passage sampled off-center may still be
                            # a valid walk, even when the drawn segment's endpoint is outside its polygon.
                            centre_clear = (
                                (a == anchor_a or point_in_convex(*a, polys[pa]["pts"]))
                                and (b == anchor_b or point_in_convex(*b, polys[pb]["pts"]))
                                and dry_segment(polys, adj, portal, pa, a, pb, b)
                            )
                            if not centre_clear:
                                restriction = WET_STEP
                            elif not dry_corridor(polys, adj, portal, pa, a, pb, b):
                                restriction = NARROW_STEP
                        if la or lb or restriction:
                            links.append((i, la, j, lb, restriction))
                        if not (la or lb):
                            masks[local] |= 1 << d

    # Ledge drops: the local bake's one-way off-mesh connections, from a ledge to a landing below it, as the surface
    # nodes the local bake's endpoints stand on. The fall costs free fall's time in running yards on top of the
    # horizontal step.
    def surface_at(x, y, z):
        """The grid surface (cell, layer) of the navmesh poly an endpoint lies on: the poly that contains the point
        (or is within a step of its simplified outline) and whose own height there is the drop's, not the nearest
        cell anchor. The poly may be rasterized in a neighbouring cell (a narrow ledge, or a landing just across a
        cell boundary), so look one cell out."""
        gx, gy = int((x - X0) // CS), int((y - Y0) // CS)
        candidates = []
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                cx, cy = gx + dx, gy + dy
                if sx0 <= cx <= sx1 and sy0 <= cy <= sy1:
                    candidates.append((cx * GH + cy, dx, dy))
        return pick_surface(layers, polys, candidates, x, y, z)

    for (x0, y0, z0), (x1, y1, z1) in read_tile(rc)[3]:
        ledge, landing = surface_at(x0, y0, z0), surface_at(x1, y1, z1)
        if ledge is None or landing is None:
            continue
        (i, la), (j, lb) = ledge, landing
        if i == j and la == lb:
            continue
        fall = z0 - z1
        if not 0 < fall <= FALL_LIMIT:
            continue
        cost = drop_cost(math.hypot(x1 - x0, y1 - y0), fall)
        links.append((i, layers[i][la][0], j, layers[j][lb][0], cost))
    cells = [layers.get(gx * GH + gy) for gx in range(tx0, tx1 + 1) for gy in range(ty0, ty1 + 1)]
    vals = bytes(surfaces[0][1] if surfaces else 0 for surfaces in cells)
    zs = [surfaces[0][0] if surfaces else None for surfaces in cells]
    terrain = sample_cluster(MAPS, MAP, rr, cc, CELLS, ZQ) if MAPS else None
    return rc, vals, zs, floors, links, masks, terrain


def step_ok(grid, cuts, ux, uy, vx, vy):
    """Orthogonal step into a walkable cell. `cuts` holds codes cell * 4 + d on the lower-x (else lower-y) cell:
    d = 0 closes the +x step, 1 closes the +y step, 2 opens the +x+y diagonal, 3 opens the +x-y diagonal.
    `grid(gx, gy)` is the cell value."""
    if not grid(vx, vy):
        return False
    if vx != ux:
        return (min(ux, vx) * GH + uy) * 4 not in cuts
    return (ux * GH + min(uy, vy)) * 4 + 1 not in cuts


def diag_ok(grid, cuts, ux, uy, vx, vy, step=None):
    """Diagonal step: either L-shaped detour open (so it never adds connectivity), or an explicit diagonal link.
    `step(ux, uy, vx, vy)` is the orthogonal test; the bake and the runtime pass one that leaves out a steep step
    with unequal stored heights, exactly as the old one-way record never fed a detour."""
    if not grid(vx, vy):
        return False
    if step is None:
        step = lambda ax, ay, bx, by: step_ok(grid, cuts, ax, ay, bx, by)  # noqa: E731
    if (step(ux, uy, vx, uy) and step(vx, uy, vx, vy)) or (step(ux, uy, ux, vy) and step(ux, vy, vx, vy)):
        return True
    ax, ay, by = (ux, uy, vy) if vx > ux else (vx, vy, uy)
    return (ax * GH + ay) * 4 + (2 if by > ay else 3) in cuts


MOVES = (
    (1, 0, 1.0),
    (-1, 0, 1.0),
    (0, 1, 1.0),
    (0, -1, 1.0),
    (1, 1, math.sqrt(2)),
    (1, -1, math.sqrt(2)),
    (-1, 1, math.sqrt(2)),
    (-1, -1, math.sqrt(2)),
)


def cell_of(n):
    return n if n < GW * GH else FLOOR_CELL[n - GW * GH]


def value_of(grid, n):
    return grid[n] if n < GW * GH else FLOOR_VAL[n - GW * GH]


def steep_ok(grid, ux, uy, vx, vy):
    """Steep ground (value 3) is walked downhill only, compared on the stored heights the file holds: the runtime's
    own rule, so the graph and the grid it emits cannot disagree about a step."""
    return steep_node_ok(grid, ux * GH + uy, vx * GH + vy)


def link_ok(grid, u, v):
    """May the runtime take the link u -> v? A step the bake's walk decided is taken as written; any other goes
    through the steep test."""
    return (u, v) in FREE or steep_node_ok(grid, u, v)


def steep_node_ok(grid, u, v):
    """The runtime's steep test between two nodes, base cells or floors: a step with a steep end goes downhill only,
    by the stored heights the file holds. Ordinary ground has no height test: the step exists only the ways linked()
    found a navmesh walk, and that navmesh holds the player's slope and step limits (#1011)."""
    return (value_of(grid, u) != 3 and value_of(grid, v) != 3) or stored_z(v) <= stored_z(u)


def bit_step(g, grid, cuts, ux, uy, vx, vy):
    """An orthogonal step a diagonal detour may take: open, and a steep step only with equal stored heights, exactly
    as the decoder leaves a one-way steep step as its own record instead of feeding the detour."""
    if not step_ok(g, cuts, ux, uy, vx, vy):
        return False
    u, v = ux * GH + uy, vx * GH + vy
    if not steep_node_ok(grid, u, v):
        return False
    if grid[u] == 3 or grid[v] == 3:
        return stored_z(u) == stored_z(v)
    return True


def step_walkable(g, grid, cuts, ux, uy, vx, vy):
    """Read a directed base mask, or recover the step from legacy cuts and stored heights during graph refresh."""
    if isinstance(cuts, bytearray):
        return bool(cuts[ux * GH + uy] & (1 << DIRS[(vx - ux, vy - uy)]))
    if not grid[vx * GH + vy]:
        return False
    if ux == vx or uy == vy:
        return step_ok(g, cuts, ux, uy, vx, vy) and steep_ok(grid, ux, uy, vx, vy)
    if not diag_ok(g, cuts, ux, uy, vx, vy, step=lambda ax, ay, bx, by: bit_step(g, grid, cuts, ax, ay, bx, by)):
        return False
    return steep_ok(grid, ux, uy, vx, vy)


def moves(g, grid, cuts, u, box, swim=SWIM):
    """(v, cost in yards) for the moves out of node u that stay in box: the base grid's 8-neighbour steps, then its
    links to and from floors; entering water costs swim. Every step is walked by the rule the runtime decodes from the
    same grid, cuts and links, so the abstract graph cannot take a step the grid refuses or miss one it allows."""
    gx0, gx1, gy0, gy1 = box
    ux, uy = divmod(cell_of(u), GH)
    if u < GW * GH:
        for dx, dy, length in MOVES:
            vx, vy = ux + dx, uy + dy
            if not (gx0 <= vx <= gx1 and gy0 <= vy <= gy1):
                continue
            if step_walkable(g, grid, cuts, ux, uy, vx, vy):
                v = vx * GH + vy
                yield v, length * CS * (swim if grid[v] == 2 else 1)
    for v, cost in sorted(LINKS.get(u, {}).items()):
        vx, vy = divmod(cell_of(v), GH)
        if gx0 <= vx <= gx1 and gy0 <= vy <= gy1:
            if not isinstance(cuts, bytearray) and not link_ok(grid, u, v):
                continue
            if cost is not None:
                yield v, cost
            else:
                length = math.sqrt(2) if vx != ux and vy != uy else 1.0
                yield v, length * CS * (swim if value_of(grid, v) == 2 else 1)


def cluster_box(k):
    kx, ky = divmod(k, NY)
    return (kx * CELLS, kx * CELLS + CELLS - 1, ky * CELLS, ky * CELLS + CELLS - 1)


def cluster_of_cell(c):
    gx, gy = divmod(cell_of(c), GH)
    return (gx // CELLS) * NY + gy // CELLS


def strong_components(order, out):
    """A directed graph's strongly connected components, by Kosaraju. A label is a node of its component, so two
    labels are equal exactly when the nodes can walk to each other inside the cluster."""
    seen, post = set(), []
    for start in order:
        if start in seen:
            continue
        seen.add(start)
        stack = [(start, iter(out.get(start, ())))]
        while stack:
            u, steps = stack[-1]
            for v in steps:
                if v not in seen:
                    seen.add(v)
                    stack.append((v, iter(out.get(v, ()))))
                    break
            else:
                stack.pop()
                post.append(u)
    back = defaultdict(list)
    for u, steps in out.items():
        for v in steps:
            back[v].append(u)
    label = {}
    for start in reversed(post):
        if start in label:
            continue
        label[start] = start
        stack = [start]
        while stack:
            u = stack.pop()
            for v in back.get(u, ()):
                if v not in label:
                    label[v] = start
                    stack.append(v)
    return label


_HPA = None  # (grid, cuts, nodes) for the forked graph workers, set by grid_hpa before each pool starts


def run_clusters(work, keys, jobs):
    """work(k) for each cluster key, in key order: in a forked pool that inherits _HPA when jobs > 1."""
    if jobs <= 1:
        yield from map(work, keys)
        return
    with multiprocessing.get_context("fork").Pool(jobs) as pool:
        yield from pool.imap(work, keys, chunksize=4)


def cluster_regions(k):
    """Cluster k's strongly connected parts as (node, label) pairs, under the grid's own directed steps."""
    assert _HPA is not None
    grid, cuts, _ = _HPA
    g = lambda gx, gy: grid[gx * GH + gy]  # noqa: E731
    box = cluster_box(k)
    cells = [gx * GH + gy for gx in range(box[0], box[1] + 1) for gy in range(box[2], box[3] + 1)]
    members = [c for c in cells + FLOORS_OF[k] if value_of(grid, c)]
    out = {u: [v for v, _ in moves(g, grid, cuts, u, box)] for u in members}
    return list(strong_components(members, out).items())


def cluster_edges(k):
    """Prune only with a fixed two-hop path certified over the entire road-factor interval."""
    assert _HPA is not None
    grid, cuts, nodes = _HPA
    assert nodes is not None
    g = lambda gx, gy: grid[gx * GH + gy]  # noqa: E731
    found = {}
    cells = nodes[k]
    box = cluster_box(k)
    dists, slopes = [], []
    adjacency = {}
    gx0, gx1, gy0, gy1 = box
    has_roads = any(gx0 <= c // GH <= gx1 and gy0 <= c % GH <= gy1 for c in ROAD_CELLS)
    modes = [(weight, 1.0) for weight in WEIGHTS]
    if has_roads:
        modes += [(weight, ROAD_FACTOR_MAX) for weight in WEIGHTS]
    for mode, (_weight, factor) in enumerate(modes):
        dist, slope = {}, {}
        for s in cells:
            gd, off, pq, left = {s: 0.0}, {s: 0.0}, [(0.0, s)], len(cells) - 1
            while pq and left:
                du, u = heapq.heappop(pq)
                if du > gd[u]:
                    continue
                if u != s and u in cells:
                    left -= 1
                    dist[(s, u)], slope[(s, u)] = du, off[u]
                if u not in adjacency:
                    adjacency[u] = tuple(
                        (v, tuple(c * (w if value_of(grid, v) == 2 else 1) for w in WEIGHTS))
                        for v, c in moves(g, grid, cuts, u, box, 1)
                    )
                for v, costs in adjacency[u]:
                    base = costs[mode % len(WEIGHTS)]
                    step_off = off_road(cell_of(v), base)
                    candidate = du + base + (factor - 1) * step_off
                    if candidate < gd.get(v, 1e18):
                        gd[v], off[v] = candidate, off[u] + step_off
                        heapq.heappush(pq, (candidate, v))
        dists.append(dist)
        slopes.append(slope)
    el = sorted(cells)

    def shorter(a, x, b, weight):
        # A certificate's two hops must each cost less than the edge it prunes, so every pruned edge rests on shorter
        # ones and the kept graph still holds a walk for it. Without that order, PRUNE's slack lets two entrances a
        # step apart certify each other's long edge, and both are dropped (#1063).
        plain = dists[weight]
        return plain.get((a, x), 1e18) < plain[a, b] and plain.get((x, b), 1e18) < plain[a, b]

    def redundant(a, b, weight, plain=False):
        if plain or not has_roads:
            dist = dists[weight]
            return any(
                dist.get((a, x), 1e18) + dist.get((x, b), 1e18) <= dist[a, b] * PRUNE and shorter(a, x, b, weight)
                for x in el
                if x not in (a, b)
            )
        low, high = dists[weight][a, b], dists[weight + len(WEIGHTS)][a, b]
        # Shortest costs are minima of affine path costs, hence concave and above their endpoint chord.
        # Pick ONE concrete two-hop walk (from either endpoint search). Its affine cost below PRUNE times
        # that chord at both ends stays below it everywhere, certifying all factors, including the default.
        # Independently optimal two-hop walks at the endpoints would NOT provide that certificate (#892).
        for mode in (weight, weight + len(WEIGHTS)):
            dist, slope = dists[mode], slopes[mode]
            factor = modes[mode][1]
            for x in el:
                if x in (a, b) or (a, x) not in dist or (x, b) not in dist or not shorter(a, x, b, weight):
                    continue
                cost, off = dist[a, x] + dist[x, b], slope[a, x] + slope[x, b]
                if cost + (1 - factor) * off <= low * PRUNE and cost + (ROAD_FACTOR_MAX - factor) * off <= high * PRUNE:
                    return True
        return False

    for a in el:
        for b in el:
            if a == b or (a, b) not in dists[0]:
                continue
            if all(redundant(a, b, weight) for weight in range(len(WEIGHTS))):
                continue
            # Runtime RoadEdges reweights these retained edges; stored travel costs stay physical.
            base = not all(redundant(a, b, weight, plain=True) for weight in range(len(WEIGHTS)))
            found[(a, b)] = (*tuple(dist[a, b] for dist in dists[: len(WEIGHTS)]), base)
    return found


def grid_entrances(grid, cuts, jobs=1):
    """HPA* over the grid. Every border crossing (orthogonal or diagonal) is grouped by the strongly connected parts
    of its two clusters it leaves and enters, in the direction it is walked: a crossing into a part the route cannot
    leave, or out of a part the route cannot reach, is of no use to it, so one entrance per such group guarantees a
    route wherever the grid has one. Each border run keeps an entrance every ENTRANCE_RUN crossings: a run is
    crossings a step apart on both sides, so separate doorways, and a bridge over the street it crosses, keep separate
    entrances even when both clusters join them elsewhere. Intra-cluster edges come
    from Dijkstra under each of WEIGHTS, dropped when a two-hop path is within PRUNE under every weight. An edge
    carries a cost per weight."""
    global _HPA
    g = lambda gx, gy: grid[gx * GH + gy]  # noqa: E731
    region = array("i", [-1]) * (GW * GH + len(FLOOR_CELL))
    _HPA = (grid, cuts, None)
    for parts in run_clusters(cluster_regions, range(NX * NY), jobs):
        for c, label in parts:
            region[c] = label
    edges = {}  # (a, b) cells -> cost per weight
    nodes = defaultdict(set)  # cluster -> cells

    def step_into(a, b, diagonal):
        """A base step's cost per weight, as the runtime charges it: the cell the step enters pays for its
        water, so the two directions of one pair can differ."""
        length = CS * (math.sqrt(2) if diagonal else 1)
        return tuple(length * (weight if value_of(grid, b) == 2 else 1) for weight in WEIGHTS)

    def records(groups, k, other, axis):
        """Link records between clusters k and other, each from the cluster that owns its direction. A link keeps its
        own direction and cost: its reverse, where the grid walks it back, is the other cluster's own crossing. A
        record's place along the border orders its entrances; clusters that meet at a corner (axis None) have none."""
        kx, ky = divmod(k, NY)
        for side, across in ((k, other), (other, k)):
            for u in LINKED_OF[side]:
                ux, uy = divmod(cell_of(u), GH)
                for w, cost in sorted(LINKS[u].items()):
                    if cluster_of_cell(w) != across:
                        continue
                    if not isinstance(cuts, bytearray) and not link_ok(grid, u, w):
                        continue
                    wx, wy = divmod(cell_of(w), GH)
                    t = 0 if axis is None else uy - ky * CELLS if axis == 0 else ux - kx * CELLS
                    groups[(region[u], region[w])].append((t, int(wx != ux and wy != uy), u, w, cost))

    near = {}

    def beside(a, b):
        """Whether nodes a and b of one cluster are the same or one step apart, either way."""
        if a == b:
            return True
        for x, y in ((a, b), (b, a)):
            if x not in near:
                near[x] = {v for v, _ in moves(g, grid, cuts, x, cluster_box(cluster_of_cell(x)))}
            if y in near[x]:
                return True
        return False

    def runs(crossings):
        """The sorted crossings split into runs: neighbours along the border join one when both their ends are a step
        apart. A wall between openings ends a run, and so does a height between them: whole-cluster connectivity does
        not make a wall a doorway, nor the street under a bridge the bridge's way across, and one opening for both
        can send a walk round an entire district (#910) or down off the bridge and back up."""
        root = list(range(len(crossings)))

        def find(i):
            while root[i] != i:
                root[i] = root[root[i]]
                i = root[i]
            return i

        first = 0
        for i, (t, _, u, w) in enumerate(crossings):
            while crossings[first][0] < t - 1:
                first += 1
            for j in range(first, i):
                if beside(u, crossings[j][2]) and beside(w, crossings[j][3]):
                    root[find(i)] = find(j)
        out = defaultdict(list)
        for i, crossing in enumerate(crossings):
            out[find(i)].append(crossing)
        return out.values()

    def entrances(groups):
        """Each run's entrances, with the edge the crossing walks."""
        for crossings in groups.values():
            # A pair may have a grid step and a drop. Keep one entrance candidate and its cheapest cost per mode.
            costs, pairs, steps = {}, {}, set()
            for t, diagonal, u, v, cost in crossings:
                pair = u, v
                price = step_into(u, v, diagonal) if cost is None else (cost,) * len(WEIGHTS)
                costs[pair] = tuple(map(min, zip(costs[pair], price, strict=True))) if pair in costs else price
                pairs[pair] = t, diagonal, u, v
                if cost is None:
                    steps.add(pair)
            crossings = sorted(pairs.values())
            for run in runs(crossings):
                for i in range(0, len(run), ENTRANCE_RUN):
                    chunk = run[i : i + ENTRANCE_RUN]
                    mid = chunk[len(chunk) // 2][0]
                    # prefer orthogonal, then the crossing nearest the chunk's middle
                    _, _, u, v = min(chunk, key=lambda c: (c[1], abs(c[0] - mid)))
                    edges[u, v] = costs[u, v]
                    nodes[cluster_of_cell(u)].add(u)
                    nodes[cluster_of_cell(v)].add(v)
            # A road crosses a border at a few points, often midway between the grid's entrances. Place an entrance
            # at each road-to-road crossing too, so a road-following walk does not leave the road to reach one
            # (#892). Roads come from Data/RoadCells.lua; without them nothing is added.
            for _, _, u, v in crossings:
                if (u, v) in steps and (u, v) not in edges and u in ROAD_CELLS and v in ROAD_CELLS:
                    edges[u, v] = costs[u, v]
                    nodes[cluster_of_cell(u)].add(u)
                    nodes[cluster_of_cell(v)].add(v)

    for k in range(NX * NY):
        # beside() only asks about cells of the clusters next to k, so its cache need not outlive them: kept for the
        # whole map it held a neighbour set for every border cell at once.
        near.clear()
        kx, ky = divmod(k, NY)
        for axis in (0, 1):
            if (axis == 0 and kx + 1 >= NX) or (axis == 1 and ky + 1 >= NY):
                continue
            groups = defaultdict(list)
            # The grid's steps are directed, so crossings are walked both ways and each direction keeps its own
            # entrances, grouped by the parts of the two clusters it leaves and enters. One pair never stands in for
            # both directions: a one-way step or a drop would then hide the other side's only crossing.
            for t in range(CELLS):
                if axis == 0:
                    a = (kx * CELLS + CELLS - 1, ky * CELLS + t)
                    b = ((kx + 1) * CELLS, ky * CELLS + t)
                else:
                    a = (kx * CELLS + t, ky * CELLS + CELLS - 1)
                    b = (kx * CELLS + t, (ky + 1) * CELLS)
                for (ux, uy), (vx, vy) in ((a, b), (b, a)):
                    if not grid[ux * GH + uy]:
                        continue
                    u = ux * GH + uy
                    for s in (0, -1, 1):
                        wx, wy = (vx, vy + s) if axis == 0 else (vx + s, vy)
                        if not 0 <= t + s < CELLS:
                            continue
                        if step_walkable(g, grid, cuts, ux, uy, wx, wy):
                            w = wx * GH + wy
                            groups[(region[u], region[w])].append((t, abs(s), u, w, None))
            other = k + (NY if axis == 0 else 1)
            records(groups, k, other, axis)
            entrances(groups)
        # Clusters that meet only at a corner: the diagonal step between the two corner cells, and any record that
        # lands across the corner, such as a drop.
        for dy in (1, -1):
            if kx + 1 >= NX or not 0 <= ky + dy < NY:
                continue
            groups = defaultdict(list)
            a = (kx * CELLS + CELLS - 1, ky * CELLS + (CELLS - 1 if dy > 0 else 0))
            b = ((kx + 1) * CELLS, (ky + dy) * CELLS + (0 if dy > 0 else CELLS - 1))
            for (ux, uy), (vx, vy) in ((a, b), (b, a)):
                if grid[ux * GH + uy] and step_walkable(g, grid, cuts, ux, uy, vx, vy):
                    u, w = ux * GH + uy, vx * GH + vy
                    groups[(region[u], region[w])].append((0, 1, u, w, None))
            records(groups, k, (kx + 1) * NY + ky + dy, None)
            entrances(groups)
    _HPA = None
    return nodes, edges


def grid_hpa(grid, cuts, jobs=1):
    """Build the border entrances, then their weighted paths inside each cluster."""
    global _HPA
    nodes, edges = grid_entrances(grid, cuts, jobs)
    inter = len(edges)
    _HPA = (grid, cuts, nodes)
    for found in run_clusters(cluster_edges, sorted(nodes), jobs):
        edges.update(found)
    _HPA = None
    print(f"grid HPA: nodes {sum(map(len, nodes.values()))}, edges {len(edges)} (inter {inter})", flush=True)
    return nodes, edges


def encode_grid_runs(values, *, directed):
    """RLE with 16 repeat symbols. Directed grids reserve symbol 47 for a literal outside the cluster palette."""
    out = []
    if directed:
        palette = [value for value, _ in Counter(values).most_common(47)]
        codes = {value: B64[i] for i, value in enumerate(palette)}
        out = [enc(len(palette), 1), *(enc(value, 2) for value in palette)]
    i = 0
    while i < len(values):
        value = values[i]
        j = i + 1
        while j < len(values) and values[j] == value:
            j += 1
        if directed:
            out.append(codes[value] if value in codes else B64[47] + enc(value, 2))
        else:
            out.append(B64[value])
        repeat = j - i - 1
        while repeat:
            n = min(repeat, 16)
            out.append(B64[47 + n])
            repeat -= n
        i = j
    return "".join(out)


def graph_varint(value):
    out = bytearray()
    while value >= 128:
        out.append(128 + value % 128)
        value //= 128
    out.append(value)
    return out


def graph_read_varint(raw, pos):
    value, scale = 0, 1
    while raw[pos] >= 128:
        value += (raw[pos] - 128) * scale
        pos += 1
        scale *= 128
    return value + raw[pos] * scale, pos + 1


def graph_cell(place, cells):
    if place < 2 * cells:
        return place if place < cells else (cells - 1) * cells + place - cells
    if place < 3 * cells - 2:
        return (place - 2 * cells + 1) * cells
    if place < 4 * cells - 4:
        return (place - 3 * cells + 3) * cells + cells - 1
    return place - (4 * cells - 4)


def graph_directory(raw):
    count, pos = graph_read_varint(raw, 0)
    lengths = []
    for _ in range(12):
        size, pos = graph_read_varint(raw, pos)
        lengths.append(size)
    starts = []
    for size in lengths:
        starts.append(pos)
        pos += size
    return count, starts


def encode_graph(cells, nodes, edges):
    """Indexed graph 1. Count, twelve stream lengths, then the streams in directory order.

    Metadata streams are perimeter positions, layers, components (zero names the cluster mode), degree,
    and the road-only suffix length. Edge streams are cluster direction, target deltas, walking residuals
    and swimming residuals. The last three streams give per-row byte counts beyond the degree.
    Edges carry their exact integer costs and keep the base prefix and full row order.
    """

    if len(nodes) > 4096:
        raise ValueError("An indexed cluster can hold at most 4096 entrances")

    def zig(value):
        return 2 * value if value >= 0 else -2 * value - 1

    streams = [bytearray() for _ in range(12)]
    positions, layers, components, degrees, suffixes, offsets, targets, walking, swimming, *extras = streams
    mode = Counter(node[2] for node in nodes).most_common(1)[0][0]
    components.extend(graph_varint(mode))
    cs, diagonal = T / cells, math.sqrt(2)
    for ordinal, ((cell, layer, comp, degree, base), row) in enumerate(zip(nodes, edges, strict=True)):
        x, y = divmod(cell, cells)
        if x == 0:
            place = y
        elif x == cells - 1:
            place = cells + y
        elif y == 0:
            place = 2 * cells + x - 1
        elif y == cells - 1:
            place = 3 * cells - 2 + x - 1
        else:
            place = 4 * cells - 4 + cell
        for stream, value in zip(
            streams[:5], (place, layer, 0 if comp == mode else comp + 1, degree, degree - base), strict=True
        ):
            stream.extend(graph_varint(value))
        starts = [len(stream) for stream in (targets, walking, swimming)]
        previous = {}
        for index, (offset, target, swim, walk) in enumerate(row):
            if index == base:
                previous.clear()
            if offset == 4:
                tx, ty = divmod(nodes[target][0], cells)
                dx, dy = abs(tx - x), abs(ty - y)
                prediction = math.floor((max(dx, dy) + (diagonal - 1) * min(dx, dy)) * cs + 0.5)
            else:
                corner = offset // 3 != 1 and offset % 3 != 1
                prediction = math.floor(cs * (diagonal if corner else 1) + 0.5)
            offsets.append(offset)
            targets.extend(graph_varint(zig(target - previous.get(offset, ordinal if offset == 4 else 0))))
            previous[offset] = target
            walking.extend(graph_varint(zig(walk - prediction)))
            swimming.extend(graph_varint(zig(swim - walk)))
        for stream, start, extra in zip((targets, walking, swimming), starts, extras, strict=True):
            extra.extend(graph_varint(len(stream) - start - degree))
    return graph_varint(len(nodes)) + b"".join(graph_varint(len(stream)) for stream in streams) + b"".join(streams)


def encode_map(nodes, edges, grid, cuts, *, collision=True):
    cells = sorted(c for cs in nodes.values() for c in cs)
    parent = {c: c for c in cells}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b in sorted(edges):
        parent[find(a)] = find(b)
    roots = {}
    comp = {c: roots.setdefault(find(c), len(roots)) for c in cells}
    local = {}
    order = {k: sorted(cs) for k, cs in nodes.items()}
    for cs in order.values():
        for i, c in enumerate(cs):
            local[c] = i
    nbrs = defaultdict(list)
    for (a, b), d in edges.items():
        nbrs[a].append((b, d))
    flags = defaultdict(int)
    if not isinstance(cuts, bytearray):
        for code in cuts:
            i, d = divmod(code, 4)
            flags[i] |= 1 << d

    floor_index = {}
    for fs in FLOORS_OF.values():
        for i, n in enumerate(fs):
            floor_index[n] = CELLS * CELLS + i

    def lcell(c):
        """A node's index inside its cluster: its local cell, or CELLS * CELLS + its floor index."""
        if c >= GW * GH:
            return floor_index[c]
        gx, gy = divmod(c, GH)
        return (gx % CELLS) * CELLS + gy % CELLS

    graph, grids, heights, floors, terrains = {}, {}, {}, {}, {}
    for k in range(NX * NY):
        kx, ky = divmod(k, NY)
        cs = order.get(k, [])
        if cs:
            records, rows = [], []
            for c in cs:
                layer = FLOOR_LAYER[c - GW * GH] if c >= GW * GH else 0
                neighbours = sorted(
                    nbrs[c], key=lambda edge: (len(edge[1]) > len(WEIGHTS) and not edge[1][-1], edge[0])
                )
                base_count = sum(len(d) == len(WEIGHTS) or d[-1] for _, d in neighbours)
                records.append((lcell(cell_of(c)), layer, comp[c], len(neighbours), base_count))
                row = []
                for m, d in neighbours:
                    km = cluster_of_cell(m)
                    dx, dy = km // NY - kx, km % NY - ky
                    assert abs(dx) <= 1 and abs(dy) <= 1
                    row.append(((dx + 1) * 3 + dy + 1, local[m], round(d[0]), round(d[1])))
                rows.append(row)
            graph[k] = base64.b64encode(encode_graph(CELLS, records, rows)).decode("ascii").rstrip("=")
        if not collision:
            continue
        vals = []
        for i in range(CELLS):
            for j in range(CELLS):
                c = (kx * CELLS + i) * GH + ky * CELLS + j
                if isinstance(cuts, bytearray):
                    vals.append(grid[c] * 256 + cuts[c])
                    continue
                v, f = grid[c], flags.get(c, 0)
                if v == 3:
                    # Steep ground rides the ground value's flag 8: a steep map reads it as value 3, while water
                    # keeps flag 8 for its -x-y diagonal. A ground cell's -x-y diagonal is a record instead.
                    v, f = 1, f | 8
                else:
                    assert v != 1 or not f & 8, f"ground cell {c} uses the steep flag"
                vals.append(v * 16 + f)
        if any(vals):
            grids[k] = encode_grid_runs(vals, directed=isinstance(cuts, bytearray))
            heights[k] = encode_heights(grid, k)
            if TERRAIN.get(k):
                # A cell with no floor has one place to stand, so it never needs an exception; only a ground that is
                # one of its floors does.
                base = [
                    round(BASE_Z[(kx * CELLS + i) * GH + ky * CELLS + j] / ZQ)
                    if grid[(kx * CELLS + i) * GH + ky * CELLS + j]
                    else None
                    for i in range(CELLS)
                    for j in range(CELLS)
                ]
                floor_z = {}
                for n in FLOORS_OF.get(k, ()):
                    floor_z.setdefault(lcell(cell_of(n)), []).append(round(FLOOR_Z[n - GW * GH]))
                text = encode_terrain(TERRAIN[k], base, CELLS, floor_z)
                if text:
                    terrains[k] = text
        if FLOORS_OF.get(k) or LINKED_OF.get(k) or WET_STEPS.get(k) or NARROW_STEPS.get(k):
            floors[k] = (
                encode_directed_floors(k, lcell) if isinstance(cuts, bytearray) else encode_floors(grid, k, lcell)
            )
    return graph, grids, heights, floors, terrains, len(roots)


def heights_header():
    """The emitted header's height entry, from encode_heights' docstring so the format is written down once."""
    doc = " ".join(cast(str, encode_heights.__doc__).split())
    first, *rest = wrap("height[k + 1]: " + doc[0].lower() + doc[1:], 110)
    return ["-- " + first, *("--   " + line for line in rest)]


def terrain_header():
    """The emitted header's terrain entry, from tools/baker/terrain.py's encode docstring."""
    doc = " ".join(cast(str, encode_terrain.__doc__).split())
    first, *rest = wrap("terrain[k + 1]: " + doc[0].lower() + doc[1:], 110)
    return ["-- " + first, *("--   " + line for line in rest)]


def emit(nodes, edges, grid, masks, out, name):
    graph, grids, heights, floors, terrains, components = encode_map(nodes, edges, grid, masks)
    lines = [
        "-- Generated by tools/baker/gen_nav.py; do not edit.",
        f"-- Source: {SOURCE}.",
        f"-- Generator: {generator_digest()}.",
        f"-- Map {MAP} ({name}), mmtile rows {ROWS.start}-{ROWS.stop - 1} x cols {COLS.start}-{COLS.stop - 1}.",
        "-- UnitPosition's frame (x north, y west). Cluster k (0-based) is the ADT tile x in [(cx0 + k // ny) T, +T),",
        "-- y in [(cy0 + k % ny) T, +T), T = 1600 / 3, cut into cells x cells cells, x-major.",
        "-- Graph format 1 stores indexed entrance records and ordered edges.",
        "-- Format 4 stores outgoing steps selected by the navmesh walk, including diagonals.",
        "-- Collision symbols are Base64 characters in the bake source and byte values in the bundle.",
        "-- grid[k + 1]: palette count(1), then palette entries(2) of value * 256 + outgoing base-to-base mask.",
        "--   Value 0 blocked, 1 ground, 2 water. Cell symbols 0-46 index the palette; 47 precedes a literal(2).",
        "--   Symbols 48-63 repeat the previous cell 1-16 times. Masks use the floor link direction order.",
        *heights_header(),
        *(
            "-- " + line
            for line in wrap("floor[k + 1]: " + " ".join(cast(str, encode_directed_floors.__doc__).split()), 110)
        ),
        *terrain_header(),
        "ShortestPathForeverPathData = ShortestPathForeverPathData or {}",
        "",
        "---@type SPFNavData",
        "-- stylua: ignore",
        f"ShortestPathForeverPathData[{MAP}] = {{",
        f"\tcx0 = {CX0},",
        f"\tcy0 = {CY0},",
        f"\tnx = {NX},",
        f"\tny = {NY},",
        f"\tcells = {CELLS},",
        f"\tswim = {SWIM:.6f},",
        f"\tzstep = {ZQ},",
        "\tformat = 4,",
        "\tgraphFormat = 1,",
        "\tfloorFormat = 1,",
    ]
    for key, table in (
        ("graph", graph),
        ("grid", grids),
        ("height", heights),
        ("floor", floors),
        ("terrain", terrains),
    ):
        lines.append(f"\t{key} = {{")
        for k in sorted(table):
            lines.append(f'\t\t[{k + 1}] = "{table[k]}",')
        lines.append("\t},")
    lines.append("}")
    src = "\n".join(lines) + "\n"
    atomic_write(Path(out), src)
    gb, rb = sum(map(len, graph.values())), sum(map(len, grids.values()))
    zb, fb = sum(map(len, heights.values())), sum(map(len, floors.values()))
    tb = sum(map(len, terrains.values()))
    print(f"emit: heights {zb / 1e3:.1f} KB, floors {fb / 1e3:.1f} KB, terrain {tb / 1e3:.1f} KB", flush=True)
    print(f"emit: graph edges {len(edges)}", flush=True)
    print(
        f"emit: components {components}, graph {gb / 1e3:.1f} KB, grids {rb / 1e3:.1f} KB "
        f"({len(grids)} clusters), file {len(src) / 1e3:.1f} KB",
        flush=True,
    )


def cheaper(old, new):
    # an ordinary step (no stored cost) is the base step's own price, so it wins a tie against a drop; among
    # drops, several connections can collapse onto one node pair and the cheapest is the one to keep
    if old is None:
        return False
    return new is None or new < old


def surface_node(c, z):
    """The base or floor node on cell c nearest height z, within CLIMB: a link endpoint's surface."""
    best, gap = c, abs(BASE_Z[c] - z)
    for n in FLOORS_AT.get(c, ()):
        if abs(FLOOR_Z[n - GW * GH] - z) < gap:
            best, gap = n, abs(FLOOR_Z[n - GW * GH] - z)
    return best if gap < CLIMB else None


class RawLinks:
    """The tiles' links as they come back from the workers, (i, za, j, zb, cost), held in flat arrays until
    assemble_floors matches them to surfaces. Map 0 returns over six million, and as tuples of boxed floats they
    held gigabytes through the whole graph build. Heights and costs are the workers' own doubles, so every value
    reads back exactly as it was sent."""

    NONE, FREE, COST, WET, NARROW = range(5)

    def __init__(self):
        self.i, self.j = array("i"), array("i")
        self.za, self.zb, self.cost = array("d"), array("d"), array("d")
        self.kind = bytearray()

    def extend(self, links):
        for i, za, j, zb, cost in links:
            self.i.append(i)
            self.za.append(za)
            self.j.append(j)
            self.zb.append(zb)
            if cost is None:
                self.kind.append(self.NONE)
                self.cost.append(0.0)
            elif cost == FREE_STEP:
                self.kind.append(self.FREE)
                self.cost.append(0.0)
            elif cost == WET_STEP:
                self.kind.append(self.WET)
                self.cost.append(0.0)
            elif cost == NARROW_STEP:
                self.kind.append(self.NARROW)
                self.cost.append(0.0)
            else:
                self.kind.append(self.COST)
                self.cost.append(cost)

    def __len__(self):
        return len(self.kind)

    def __iter__(self):
        sentinels = (None, FREE_STEP, None, WET_STEP, NARROW_STEP)
        for n, kind in enumerate(self.kind):
            cost = self.cost[n] if kind == self.COST else sentinels[kind]
            yield self.i[n], self.za[n], self.j[n], self.zb[n], cost


def assemble_floors(floors, links, *, directed=False):
    """Build floor nodes and resolve step layers and drop heights to node IDs."""
    nb = GW * GH
    at = FLOORS_AT
    for c, fs in sorted(floors):
        if directed and len(fs) > 62:
            raise ValueError(f"Cell {c} has layer 63, which exceeds the runtime link layer limit")
        at[c] = []
        for v, z in fs:
            at[c].append(nb + len(FLOOR_CELL))
            FLOOR_LAYER.append(len(at[c]))
            FLOOR_CELL.append(c)
            FLOOR_VAL.append(v)
            FLOOR_Z.append(z)
        FLOORS_OF[cluster_of_cell(c)] += at[c]

    for i, za, j, zb, cost in links:
        if directed and cost in (None, WET_STEP, NARROW_STEP):
            a = FLOORS_AT[i][int(za) - 1] if za else i
            b = FLOORS_AT[j][int(zb) - 1] if zb else j
        else:
            a, b = surface_node(i, za), surface_node(j, zb)
        if a is None or b is None:
            continue
        if cost in (WET_STEP, NARROW_STEP):
            restrictions = WET_STEPS if cost == WET_STEP else NARROW_STEPS
            restrictions[cluster_of_cell(a)].add((a, b))
            if a < nb and b < nb:
                continue  # the base grid mask already carries this step
            cost = None
        if cost == FREE_STEP:  # links come back pickled from worker processes, so compare by value
            FREE.add((a, b))
            cost = None
        current = LINKS[a]
        if b not in current or cheaper(current[b], cost):
            current[b] = cost
    for n in sorted(LINKS):
        LINKED_OF[cluster_of_cell(n)].append(n)
    print(
        f"floors {len(FLOOR_CELL)} on {len(at)} cells, linked nodes {len(LINKS)}, "
        f"links {sum(map(len, LINKS.values()))}",
        flush=True,
    )


def encode_heights(grid, k):
    """Base heights of a cluster's walkable cells in cell order, in zstep yards, each against its -y neighbour
    (else its -x neighbour, else the previous cell): symbols 0-46 add -23..23, 47 is followed by an absolute value
    + 2048 (2), and a symbol >= 48 repeats the previous difference (symbol - 47) more times."""
    kx, ky = divmod(k, NY)
    q, items, last = {}, [], 0
    for i in range(CELLS):
        for j in range(CELLS):
            c = (kx * CELLS + i) * GH + ky * CELLS + j
            if not grid[c]:
                continue
            v = round(BASE_Z[c] / ZQ)
            pred = q.get((i, j - 1), q.get((i - 1, j), last))
            items.append(("d", v - pred) if abs(v - pred) <= 23 else ("a", v))
            q[(i, j)] = last = v
    out, i = [], 0
    while i < len(items):
        kind, v = items[i]
        if kind == "a":
            out.append(B64[47] + enc(v + 2048, 2))
            i += 1
            continue
        out.append(B64[v + 23])
        j = i + 1
        while j < len(items) and items[j] == items[i]:
            j += 1
        repeat = j - i - 1
        while repeat > 0:
            n = min(repeat, 16)
            out.append(B64[48 + n - 1])
            repeat -= n
        i = j
    return "".join(out)


def stored_z(n):
    """A node's height as the data file stores it, so the runtime's height matching agrees with ours."""
    return round(BASE_Z[n] / ZQ) * ZQ if n < GW * GH else round(FLOOR_Z[n - GW * GH])


def matched(grid, u, d):
    """The surface in direction d from node u nearest u's height (the base surface first on a tie)."""
    ux, uy = divmod(cell_of(u), GH)
    ((dx, dy),) = [move for move, code in DIRS.items() if code == d]
    tx, ty = ux + dx, uy + dy
    if not (0 <= tx < GW and 0 <= ty < GH):
        return None
    c = tx * GH + ty
    cands = ([c] if grid[c] else []) + FLOORS_AT.get(c, [])
    return min(cands, key=lambda v: abs(stored_z(v) - stored_z(u))) if cands else None


def emit_delta(out, delta):
    """A cell or node delta: symbol 0-62 is the delta itself, 63 is followed by the delta - 63 in three characters.
    Both lists this encodes are sorted, so a delta is never negative."""
    assert delta >= 0, delta
    if delta < 63:
        out.append(B64[delta])
    else:
        out.append(B64[63] + enc(delta - 63, 3))


def encode_floors(grid, k, lnode):
    """A cluster's floors: n(3) | n x [cell(1-4) value(1) height + 2048(2) steps(2) landings] | m(3) |
    m x [node(1-4) direction(1) layer(1)] | q(3) | q x [node(3) x(1) y(1) layer(1) cost(2)].

    A cell or node is a delta from the one before it (sorted, so never negative): symbol 0-62 is the delta, 63 is
    followed by the delta - 63 in three characters. n lists the floors in cell order, so at[-(cell + 1)] is the
    first of a cell's run.

    A step bit is a step both ways may take, landing on the layer its node's landings name, one layer per set
    direction in ascending direction order. Layer 0 is the base surface, i the cell's ith floor from the bottom, so
    the decoder resolves the pair the bake linked and never a surface merely near its height. A bit with a steep end
    is allowed downhill only, by stored height. Every other link is one record from the node that owns it, once per
    pair: m's direction + 8 is a one-way step, and + 16 a step the bake's walk decided, taken with no steep test; q's
    is a drop, which lands on the surface (x, y) cells away (stored + 8,
    so (8, 8) is within the cell) at cost whole yards. Value 3 is steep ground."""
    floors = FLOORS_OF[k]
    out, extra, drops = [enc(len(floors), 3)], [], []
    cell = 0

    def offset(u, v):
        (ux, uy), (vx, vy) = divmod(cell_of(u), GH), divmod(cell_of(v), GH)
        return vx - ux, vy - uy

    def layer(v):
        return FLOOR_LAYER[v - GW * GH] if v >= GW * GH else 0

    def both_ways(u, v):
        """u steps to v and back at no cost, both read alike: the pair is symmetric, so one bit or one record carries
        it."""
        return (
            LINKS[u].get(v, 1) is None and LINKS.get(v, {}).get(u, 1) is None and ((u, v) in FREE) == ((v, u) in FREE)
        )

    def steps_of(u):
        """The step pairs out of u by direction: a pair that has a cost, a drop, is no step and is written apart."""
        found = {}
        for v, cost in LINKS.get(u, {}).items():
            if cost is not None:
                continue
            d = DIRS.get(offset(u, v))
            if d is not None:
                found.setdefault(d, []).append(v)
        return found

    dirs = {u: steps_of(u) for u in LINKED_OF[k]}
    carried = {}  # (u, v) -> (carrier, direction on the carrier, the layer it lands on)

    def carry(u, v):
        """One bit carries the pair: a bit is read before any record, so it may only carry a pair both ends would
        resolve first anyway. The carrier is the node whose direction points at the other end."""
        carrier, other = (u, v) if u >= GW * GH else (v, u)
        if carrier < GW * GH:
            return  # neither end is a floor node, so nothing here could carry the bit
        carried[u, v] = carried[v, u] = (carrier, DIRS.get(offset(carrier, other)), layer(other))

    # The bake's own bits come first, exactly as they always have: a floor node's two-way pair whose landing is the
    # surface nearest its height. Its entry, and the mirror it leaves, read where a record-only encoding read them.
    bits = {}
    for n in floors:
        bits[n] = {}
        for v in LINKS[n]:
            d = DIRS.get(offset(n, v))
            if d is None or d in bits[n] or cluster_of_cell(v) != k or not both_ways(n, v) or (n, v) in FREE:
                continue
            if matched(grid, n, d) == v:
                bits[n][d] = v
    # One side of a pair carries it: where both would, the higher node keeps it, so the pair is written once.
    for n in sorted(bits):
        for d, v in list(bits[n].items()):
            back = DIRS.get(offset(v, n))
            if back is not None and bits.get(v, {}).get(back) == n:
                del bits[n][d]
    for n in sorted(bits):
        for _d, v in sorted(bits[n].items()):
            carry(n, v)
    # A pair that is the only step in its direction at both ends may be a bit too: nothing else can land in that
    # direction, so moving it before the records cannot change what either end resolves.
    for u in sorted(dirs):
        for _d, vs in sorted(dirs[u].items()):
            if len(vs) != 1:
                continue
            v = vs[0]
            back = DIRS.get(offset(v, u))
            if back is None or cluster_of_cell(v) != k or not both_ways(u, v) or (u, v) in FREE:
                continue
            if len(dirs.get(v, {}).get(back, ())) != 1 or dirs[v][back][0] != u:
                continue
            if (u, v) in carried or (v, u) in carried:
                continue
            carry(u, v)

    steps = {}
    for pair, (carrier, slot, landing) in carried.items():
        if pair[0] == carrier and slot is not None:
            slots = steps.setdefault(carrier, {})
            assert slots.get(slot, landing) == landing, (pair, slot)
            slots[slot] = landing
    for n in floors:
        c = lnode(FLOOR_CELL[n - GW * GH])
        emit_delta(out, c - cell)
        cell = c
        slots = steps.get(n, {})
        mask = sum(1 << d for d in slots)
        out.append(enc(FLOOR_VAL[n - GW * GH], 1) + enc(stored_z(n) + 2048, 2) + enc(mask, 2))
        out += [enc(slots[d], 1) for d in sorted(slots)]
        KINDS["step bits"] += len(slots)
    for u in LINKED_OF[k]:
        for v, cost in sorted(LINKS[u].items()):
            d = DIRS.get(offset(u, v))
            if cost is not None:
                dx, dy = offset(u, v)
                assert -8 <= dx <= 7 and -8 <= dy <= 7, (dx, dy)
                drops.append((lnode(u), dx + 8, dy + 8, layer(v), round(cost)))
                continue
            assert d is not None, (u, v)
            if (u, v) in carried:
                continue  # a step bit carries both directions
            free = 16 if (u, v) in FREE else 0
            if both_ways(u, v):
                if u > v and cluster_of_cell(v) == k:
                    continue  # one record per pair; the lower node writes the two-way step
                KINDS["two-way records"] += 1
                extra.append((lnode(u), d + free, layer(v)))
            else:
                KINDS["one-way records"] += 1
                extra.append((lnode(u), d + 8 + free, layer(v)))
            KINDS["records taken as written"] += free > 0
    KINDS["drop records"] += len(drops)
    extra.sort()
    out.append(enc(len(extra), 3))
    node = 0
    for n, d, la in extra:
        emit_delta(out, n - node)
        node = n
        out.append(enc(d, 1) + enc(la, 1))
    out.append(enc(len(drops), 3))
    out += [enc(n, 3) + enc(dx, 1) + enc(dy, 1) + enc(la, 1) + enc(cost, 2) for n, dx, dy, la, cost in sorted(drops)]
    return "".join(out)


def implicit_landing(k, u, dx, dy):
    target = cell_of(u) + dx * GH + dy
    if cluster_of_cell(target) != k:
        return None
    count = len(FLOORS_AT.get(target, ()))
    if u < GW * GH:
        return 1 if count == 1 else None
    return 0 if count == 0 else None


def encode_directed_floors(k, lnode):
    """Floor count(3), then [cell delta, value(1), height(2), mask(2)]. Base-to-floor node count(3), then
    [node delta, mask(2)]. The override stream length(3) precedes [eligible direction delta, landing set].
    Within the cluster, a floor-to-base step implies layer 0 if the target has no extra floors, and a
    base-to-floor step implies layer 1 if the target has one extra floor. A different landing set for an
    eligible direction is an override. All other sets follow the overrides in header order. A landing set
    is a six-bit set of layers 0-5, or zero followed by count(2) and one symbol per layer. Each delta is
    0-62 or 63 followed by
    delta - 63(3). Drops follow as count(3), then [node(3), dx+8(1), dy+8(1), layer(1), cost(2)].
    An optional final stream of [node delta, direction(1), layer(1)] marks steps without a straight dry
    segment. A direction plus 8 marks steps with only centre-line clearance. The step stays in its mask.
    """
    floors = FLOORS_OF[k]
    out, landings, overrides, drops = [enc(len(floors), 3)], [], [], []
    ordinal, previous = 0, 0
    masks = defaultdict(dict)
    for u in LINKED_OF[k]:
        ux, uy = divmod(cell_of(u), GH)
        for v, cost in sorted(LINKS[u].items()):
            vx, vy = divmod(cell_of(v), GH)
            dx, dy = vx - ux, vy - uy
            layer = FLOOR_LAYER[v - GW * GH] if v >= GW * GH else 0
            if cost is not None:
                assert -8 <= dx <= 7 and -8 <= dy <= 7, (dx, dy)
                drops.append((lnode(u), dx + 8, dy + 8, layer, round(cost)))
            else:
                masks[u].setdefault(DIRS[dx, dy], []).append(layer)

    def emit_mask(u):
        nonlocal ordinal, previous
        slots = masks[u]
        out.append(enc(sum(1 << d for d in slots), 2))
        for d, layers in sorted(slots.items()):
            dx, dy, _ = MOVES[d]
            default = implicit_landing(k, u, dx, dy)
            if default is not None:
                ordinal += 1
                if layers == [default]:
                    continue
            if layers[-1] < 6:
                encoded = enc(sum(1 << layer for layer in layers), 1)
            else:
                encoded = "A" + enc(len(layers), 2) + "".join(enc(layer, 1) for layer in layers)
            if default is None:
                landings.append(encoded)
            else:
                emit_delta(overrides, ordinal - previous)
                overrides.append(encoded)
                previous = ordinal

    cell = 0
    for n in floors:
        local = lnode(cell_of(n))
        emit_delta(out, local - cell)
        cell = local
        out.append(enc(FLOOR_VAL[n - GW * GH], 1) + enc(stored_z(n) + 2048, 2))
        emit_mask(n)
    base = [n for n in masks if n < GW * GH]
    out.append(enc(len(base), 3))
    node = 0
    for n in sorted(base, key=lnode):
        local = lnode(n)
        emit_delta(out, local - node)
        node = local
        emit_mask(n)
    out.append(enc(sum(map(len, overrides)), 3))
    out.extend(overrides)
    out.extend(landings)
    out.append(enc(len(drops), 3))
    out.extend(
        enc(n, 3) + enc(dx, 1) + enc(dy, 1) + enc(layer, 1) + enc(cost, 2) for n, dx, dy, layer, cost in sorted(drops)
    )
    restrictions = []
    for pairs, flag in ((WET_STEPS, 0), (NARROW_STEPS, 8)):
        for u, v in pairs.get(k, ()):
            ux, uy = divmod(cell_of(u), GH)
            vx, vy = divmod(cell_of(v), GH)
            layer = FLOOR_LAYER[v - GW * GH] if v >= GW * GH else 0
            restrictions.append((lnode(u), DIRS[vx - ux, vy - uy] + flag, layer))
    node = 0
    for n, direction, layer in sorted(restrictions):
        emit_delta(out, n - node)
        node = n
        out.append(enc(direction, 1) + enc(layer, 1))
    return "".join(out)


def main():
    global SOURCE, LINKS, LINKED_OF
    args, provenance = arguments(Path(MM))
    SOURCE = source_label(provenance)
    started = time.perf_counter()
    phases = {}
    checkpoint = started
    map_id, jobs = args.map, args.jobs
    name = args.name or f"map {map_id}"
    out = args.out or f"Nav{map_id}.lua"
    configure(map_id, args.rows, args.cols)
    TERRAIN.clear()
    print(
        f"map {map_id}: {len(TILES)} tiles, rows {ROWS.start}-{ROWS.stop - 1}, cols {COLS.start}-{COLS.stop - 1}, "
        f"grid {GW}x{GH}",
        flush=True,
    )
    inputs = tile_hashes(TILES.values()) if args.metrics else {}
    code = tile_hashes(Path(__file__).parent.glob("*.py")) if args.metrics else {}
    components(places(map_id))
    phases["components"] = time.perf_counter() - checkpoint
    checkpoint = time.perf_counter()
    grid, masks = bytearray(GW * GH), bytearray(GW * GH)
    BASE_Z.frombytes(bytes(4 * GW * GH))
    floors, links = [], RawLinks()
    order = sorted(TILES, key=ORD.__getitem__)
    with multiprocessing.get_context("fork").Pool(jobs) as pool:  # workers inherit the pass-1 globals
        for n, (rc, vals, zs, tf, tl, tile_masks, terrain) in enumerate(pool.imap(rasterize_tile, order, chunksize=2)):
            kx, ky = divmod(cluster_of_tile(*rc), NY)
            for i in range(CELLS):
                row = (kx * CELLS + i) * GH + ky * CELLS
                grid[row : row + CELLS] = vals[i * CELLS : (i + 1) * CELLS]
                masks[row : row + CELLS] = tile_masks[i * CELLS : (i + 1) * CELLS]
                for j in range(CELLS):
                    if zs[i * CELLS + j] is not None:
                        BASE_Z[row + j] = zs[i * CELLS + j]
            if terrain is not None:
                TERRAIN[cluster_of_tile(*rc)] = terrain
            floors += tf
            links.extend(tl)
            if (n + 1) % 100 == 0:
                print(f"  rasterized {n + 1}/{len(order)} tiles", flush=True)
    print(f"grid {GW}x{GH}: ground {grid.count(1)}, water {grid.count(2)}", flush=True)
    phases["raster"] = time.perf_counter() - checkpoint
    checkpoint = time.perf_counter()
    assemble_floors(floors, links, directed=True)
    print(f"dry clearance: {sum(map(len, WET_STEPS.values()))} blocked, {sum(map(len, NARROW_STEPS.values()))} narrow")
    # matched into FLOORS_AT and LINKS; the raw lists, the last tile's included, are not needed again
    del floors, links, tf, tl
    phases["floors"] = time.perf_counter() - checkpoint
    checkpoint = time.perf_counter()
    # The graph is built from the very links and cuts the grid is emitted with, so the two cannot disagree.
    nodes, edges = grid_hpa(grid, masks, jobs)
    phases["graph"] = time.perf_counter() - checkpoint
    checkpoint = time.perf_counter()
    emit(nodes, edges, grid, masks, out, name)
    phases["emit"] = time.perf_counter() - checkpoint
    if args.metrics:
        record(
            args.metrics,
            phases,
            started,
            out,
            {
                "map": map_id,
                "build": args.build,
                "extractor": provenance,
                "source": SOURCE,
                "jobs": jobs,
                "rows": [ROWS.start, ROWS.stop - 1],
                "cols": [COLS.start, COLS.stop - 1],
                "tiles": inputs,
                "code_sha256": code,
                "nodes": sum(map(len, nodes.values())),
                "clusters": len(TILES),
            },
        )


if __name__ == "__main__":
    main()

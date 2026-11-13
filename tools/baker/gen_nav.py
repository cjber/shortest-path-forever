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
from collections import defaultdict
from pathlib import Path
from textwrap import wrap
from typing import cast

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from baker.geometry import height, plane, point_in_convex, poly_distance, poly_distance2, seg_in_box  # noqa: E402
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
LAYER_MARGIN = DROP_COLUMNS  # cells rasterized beyond a tile, so a drop's landing has a layer to land on
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
FLOORS_OF = defaultdict(list)  # cluster -> its floor nodes, by (cell, height)
LINKED_OF = defaultdict(list)  # cluster -> its nodes with LINKS, sorted
FLOORS_AT = {}  # cell -> its floor nodes, lowest first
TERRAIN = {}  # cluster -> its terrain field (tools/baker/terrain.py)
KINDS = defaultdict(int)  # how the encoded links came out: step bits, one-way records, drops


def configure(map_id, rows=None, cols=None):
    global MAP, TILES, ROWS, COLS, CX0, CY0, NX, NY, GW, GH, X0, Y0, ORD
    KINDS.clear()
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


def drop_cost(horizontal, fall):
    """A drop's cost in running yards: the horizontal step plus the time free fall takes at the client's gravity,
    run at the player's speed. Slope never changes how fast ground is crossed, so a fall is the only extra."""
    return horizontal + RUN * math.sqrt(2 * fall / GRAVITY)


def stored_layer_z(z, base):
    """A layer's height as the data stores it: base heights at the zstep grid, floors at whole yards. The runtime's
    steep test must use exactly these, so the bake and the decoder can never disagree."""
    return round(z / ZQ) * ZQ if base else round(z)


def steep_step(za, la, zb, lb):
    """May a step between surfaces at these levels be taken? Steep ground (value 3) is downhill only, and the
    comparison is between the stored heights the runtime sees."""
    return stored_layer_z(zb, lb == 0) <= stored_layer_z(za, la == 0)


def pair_carries_bit(za, la, zb, lb, forward, back, steep):
    """May a pair of surfaces ride the symmetric step bits, so neither direction needs a record of its own?

    A pair the navmesh walk joins both ways may. It also may when the walk refuses one direction, one end is steep,
    and the runtime's own steep test refuses that same direction on the same stored heights: the bit is mirrored at
    the far end and refused there, which is the one-way step the pair means. Ordinary ground has no such test, so a
    refusal there, a wall or a ledge, stays a record, and a pair neither direction joins is no step at all."""
    if forward and back:
        return True
    if not (forward or back) or not steep:
        return False
    if forward:
        return not steep_step(zb, lb, za, la)  # the walk refuses the way back, and so must the heights
    return not steep_step(za, la, zb, lb)  # the walk refuses the way forward, and so must the heights


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
    pieces at least CLIMB apart as floors; omit lake beds under water. Narrow passages anchor on the poly centroid,
    because their cells may have no centre inside the mesh.
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
    # These surfaces anchor on the poly centroid, since the cell centre may lie off the mesh. Only the first passage
    # through an empty cell may become its base; later ones can only add a floor.
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
                    i = at(a[0] + (b[0] - a[0]) * t / steps, a[1] + (b[1] - a[1]) * t / steps)
                    z = p["c"][2]
                    if i >= 0 and not any(abs(s[1] - z) < CLIMB for s in surf[i]):
                        surf[i].append((p["size"], z, 2 if p["water"] else 1, pid, p["c"][:2], bool(surf[i])))

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
        layers[i] = [(ss[n][1], 3 if polys[ss[n][3]]["steep"] else ss[n][2], (ss[n][3], ss[n][4])) for n in chosen]

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


def rasterize_tile(rc):
    """Pass 2 for one tile: its cells' surfaces (0 blocked, 1 ground, 2 water, 3 steep ground), heights, floors and
    step codes.

    A step between neighbouring cells is cut unless a 2D ray along the navmesh surface from one cell's anchor reaches
    the other's surface poly, so the grid cannot climb a cliff, pass a fence or wall, or drop off a bridge. A step
    onto or off steep ground keeps the ordinary symmetric code: the decoder allows it downhill only, comparing the
    stored heights the file holds, so no per-step record is needed. A step the navmesh joins one way only is cut and
    each legal direction is written out on its own. Floors link to neighbouring surfaces by the same test, and the
    local bake's one-way ledge drops become links from the ledge's surface to the landing's.
    Surfaces are computed LAYER_MARGIN cells beyond the tile, which is all its own steps, diagonals and drop landings
    read; everything comes from the 3x3 tiles around it.
    """
    rr, cc = rc
    window = [(rr + dr, cc + dc) for dr in (-1, 0, 1) for dc in (-1, 0, 1) if (rr + dr, cc + dc) in TILES]
    polys, adj, portal = load_window(window)
    k = cluster_of_tile(rr, cc)
    tx0, tx1, ty0, ty1 = cluster_box(k)
    ax0, ax1 = max(0, tx0 - LAYER_MARGIN), min(GW - 1, tx1 + LAYER_MARGIN)
    ay0, ay1 = max(0, ty0 - LAYER_MARGIN), min(GH - 1, ty1 + LAYER_MARGIN)
    layers = rasterize_layers(polys, adj, portal, (ax0, ax1, ay0, ay1))

    def linked(i, la, j, lb):
        """Is there a navmesh path from cell i's surface la to cell j's surface lb inside the two cells (+ MARGIN)?

        Steep ground is crossed downhill only, so the search carries a ceiling: the highest the walk can be inside the
        poly it reached. Ordinary ground lifts it; on steep ground the walk leaves through a portal no higher than the
        ceiling, and leaves it at most as high as that portal's top. Without it a path could climb a steep face between
        two ordinary surfaces, such as the slope that joins the terrain under Stormwind to its streets."""
        (pa, a), (pb, b) = layers[i][la][2], layers[j][lb][2]
        if pa == pb or pb in adj.get(pa, ()):
            return True
        (xi, yi), (xj, yj) = divmod(i, GH), divmod(j, GH)
        box = (
            X0 + min(xi, xj) * CS - MARGIN,
            X0 + (max(xi, xj) + 1) * CS + MARGIN,
            Y0 + min(yi, yj) * CS - MARGIN,
            Y0 + (max(yi, yj) + 1) * CS + MARGIN,
        )
        hb = height(polys[pb], *b)
        best = {pa: height(polys[pa], *a) if polys[pa]["steep"] else math.inf}
        stack = [pa]
        while stack:
            u = stack.pop()
            ceiling = best[u]
            for v in adj.get(u, ()):
                ends = portal[(u, v)]
                if not seg_in_box(*ends, box=box):
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

    def allows(i, la, j, lb):
        """May the player step from cell i's surface la to cell j's surface lb? Steep ground is entered and left
        downhill only, so the destination must not be above the source; ordinary ground keeps its two directions."""
        if not linked(i, la, j, lb):
            return False
        if layers[i][la][1] == 3 or layers[j][lb][1] == 3:
            return steep_step(layers[i][la][0], la, layers[j][lb][0], lb)
        return True

    def bit_carries(i, la, j, lb, one_cluster=False):
        """pair_carries_bit for two surfaces the walk has just been asked about.

        A floor's step bit is resolved with the target cluster's own surfaces, so one_cluster refuses a pair across
        two clusters; the base grid's bits name global cells and carry those."""
        if one_cluster and cluster_of_cell(i) != cluster_of_cell(j):
            return False
        return pair_carries_bit(
            layers[i][la][0],
            la,
            layers[j][lb][0],
            lb,
            linked(i, la, j, lb),
            linked(j, lb, i, la),
            layers[i][la][1] == 3 or layers[j][lb][1] == 3,
        )

    def base_steep(gx, gy):
        c = gx * GH + gy
        return c in layers and layers[c][0][1] == 3

    def bit_step_ok(ux, uy, vx, vy):
        """An orthogonal step as the base grid's symmetric bits carry it into diagonal detours: a steep step with
        unequal stored heights is its own directed link, so it cannot feed a detour."""
        if not step_ok(g, cuts, ux, uy, vx, vy):
            return False
        if base_steep(ux, uy) or base_steep(vx, vy):
            u, v = ux * GH + uy, vx * GH + vy
            return stored_layer_z(layers[u][0][0], True) == stored_layer_z(layers[v][0][0], True)
        return True

    g = lambda gx, gy: layers[gx * GH + gy][0][1] if gx * GH + gy in layers else 0  # noqa: E731
    inside = lambda gx, gy: tx0 <= gx <= tx1 and ty0 <= gy <= ty1 and 0 <= gx < GW and 0 <= gy < GH  # noqa: E731
    cuts, links = set(), []
    for gx in range(max(0, tx0 - 1), min(GW, tx1 + 2)):
        for gy in range(max(0, ty0 - 1), min(GH, ty1 + 2)):
            i = gx * GH + gy
            if not g(gx, gy):
                continue
            for d, jx, jy in ((0, gx + 1, gy), (1, gx, gy + 1)):
                if jx >= GW or jy >= GH or not g(jx, jy):
                    continue
                j = jx * GH + jy
                # Steep ground keeps the ordinary symmetric bit: the decoder allows it downhill only, from the same
                # stored heights. A pair whose refusal the heights do not explain still needs its own record.
                if bit_carries(i, 0, j, 0):
                    continue
                cuts.add(i * 4 + d)
                # the pair's step codes are symmetric, so an allowed direction is written out as its own link
                if inside(gx, gy) and allows(i, 0, j, 0):
                    links.append((i, layers[i][0][0], j, layers[j][0][0], None))
                if inside(jx, jy) and allows(j, 0, i, 0):
                    links.append((j, layers[j][0][0], i, layers[i][0][0], None))
    # Diagonal walkways narrower than a cell: open the diagonal step explicitly where both L-shaped detours are closed.
    own = set()
    for gx in range(tx0, min(tx1 + 1, GW - 1)):
        for gy in range(ty0, ty1 + 1):
            i = gx * GH + gy
            if not g(gx, gy):
                continue
            for d, dy in ((2, 1), (3, -1)):
                if not 0 <= gy + dy < GH:
                    continue
                j = i + GH + dy
                if g(gx + 1, gy + dy) and not diag_ok(g, cuts, gx, gy, gx + 1, gy + dy, step=bit_step_ok):
                    if linked(i, 0, j, 0) and linked(j, 0, i, 0):
                        if d == 3 and g(gx, gy) != 2:
                            # Flag 8 marks steep ground on a ground cell, so this diagonal stays a pair of records
                            # rather than a bit; water can still use the flag for its own diagonal.
                            links.append((i, layers[i][0][0], j, layers[j][0][0], None))
                            links.append((j, layers[j][0][0], i, layers[i][0][0], None))
                        else:
                            own.add(i * 4 + d)  # the symmetric diagonal; the decoder allows it downhill only
                    else:
                        # Each legal direction is its own link, as for orthogonal steps; the symmetric diagonal
                        # stays closed because both L-shaped detours are cut.
                        if allows(i, 0, j, 0) and inside(gx, gy):
                            links.append((i, layers[i][0][0], j, layers[j][0][0], None))
                        if allows(j, 0, i, 0) and inside(gx + 1, gy + dy):
                            links.append((j, layers[j][0][0], i, layers[i][0][0], None))
    own |= {c for c in cuts if tx0 <= c // 4 // GH <= tx1 and ty0 <= c // 4 % GH <= ty1}
    # Floors: every surface pair between a cell and a neighbour that involves a floor, by height at both ends. Both
    # directions are written out, since nothing is derived from a floor's own links any more.
    floors = []
    for gx in range(tx0, tx1 + 1):
        for gy in range(ty0, ty1 + 1):
            i = gx * GH + gy
            if i not in layers:
                continue
            if len(layers[i]) > 1:
                floors.append((i, [(v, z) for z, v, _ in layers[i][1:]]))
            for dx, dy, _ in MOVES:
                jx, jy = gx + dx, gy + dy
                j = jx * GH + jy
                if not (0 <= jx < GW and 0 <= jy < GH) or j not in layers:
                    continue
                if len(layers[i]) == 1 and len(layers[j]) == 1:
                    continue
                for la, (za, _, _) in enumerate(layers[i]):
                    for lb, (zb, _, _) in enumerate(layers[j]):
                        if not (la or lb):
                            continue
                        # A steep pair keeps both directions as an ordinary (no-cost) link, so encode_floors can
                        # carry it as a symmetric step bit; the decoder allows it downhill only.
                        if bit_carries(i, la, j, lb, one_cluster=True):
                            links.append((i, za, j, zb, None))
                            links.append((j, zb, i, za, None))
                        else:
                            if allows(i, la, j, lb):
                                links.append((i, za, j, zb, None))
                            if allows(j, lb, i, la):
                                links.append((j, zb, i, za, None))

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
                if ax0 <= cx <= ax1 and ay0 <= cy <= ay1:
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
    vals = bytes(g(gx, gy) for gx in range(tx0, tx1 + 1) for gy in range(ty0, ty1 + 1))
    zs = [
        layers[gx * GH + gy][0][0] if gx * GH + gy in layers else None
        for gx in range(tx0, tx1 + 1)
        for gy in range(ty0, ty1 + 1)
    ]
    terrain = sample_cluster(MAPS, MAP, rr, cc, CELLS, ZQ) if MAPS else None
    return rc, vals, zs, floors, links, sorted(own), terrain


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
    u, v = ux * GH + uy, vx * GH + vy
    if grid[u] == 3 or grid[v] == 3:
        return stored_z(v) <= stored_z(u)
    return True


def steep_node_ok(grid, u, v):
    """The runtime's steep test between two nodes, base cells or floors: a step with a steep end goes downhill only,
    by the stored heights the file holds."""
    if value_of(grid, u) == 3 or value_of(grid, v) == 3:
        return stored_z(v) <= stored_z(u)
    return True


def bit_step(g, grid, cuts, ux, uy, vx, vy):
    """An orthogonal step a diagonal detour may take: open, and a steep step only with equal stored heights, exactly
    as the decoder leaves a one-way steep step as its own record instead of feeding the detour."""
    if not step_ok(g, cuts, ux, uy, vx, vy):
        return False
    u, v = ux * GH + uy, vx * GH + vy
    if grid[u] == 3 or grid[v] == 3:
        return stored_z(u) == stored_z(v)
    return True


def step_walkable(g, grid, cuts, ux, uy, vx, vy):
    """May the emitted grid be walked from (ux, uy) to (vx, vy)? An orthogonal step is its symmetric bit or its own
    record, a diagonal is either L-shaped detour or the bake's explicit diagonal, and steep ground goes down only."""
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
            # A floor pair is written out both ways even where a steep end makes it one-way; the decoder decides the
            # direction by stored height, and so must the graph.
            if not steep_node_ok(grid, u, v):
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
    grid, cuts, _ = _HPA
    g = lambda gx, gy: grid[gx * GH + gy]  # noqa: E731
    box = cluster_box(k)
    cells = [gx * GH + gy for gx in range(box[0], box[1] + 1) for gy in range(box[2], box[3] + 1)]
    members = [c for c in cells + FLOORS_OF[k] if value_of(grid, c)]
    out = {u: [v for v, _ in moves(g, grid, cuts, u, box)] for u in members}
    return list(strong_components(members, out).items())


def cluster_edges(k):
    """Cluster k's intra-cluster edges between its entrances: Dijkstra under each of WEIGHTS, dropped when a
    two-hop path is within PRUNE under every weight."""
    grid, cuts, nodes = _HPA
    g = lambda gx, gy: grid[gx * GH + gy]  # noqa: E731
    found = {}
    cells = nodes[k]
    box = cluster_box(k)
    dists = []
    adjacency = {}
    for mode in range(len(WEIGHTS)):
        dist = {}
        for s in cells:
            gd, pq, left = {s: 0.0}, [(0.0, s)], len(cells) - 1
            while pq and left:
                du, u = heapq.heappop(pq)
                if du > gd[u]:
                    continue
                if u != s and u in cells:
                    left -= 1
                    dist[(s, u)] = du
                if u not in adjacency:
                    adjacency[u] = tuple(
                        (v, tuple(c * (weight if value_of(grid, v) == 2 else 1) for weight in WEIGHTS))
                        for v, c in moves(g, grid, cuts, u, box, 1)
                    )
                for v, costs in adjacency[u]:
                    c = costs[mode]
                    if du + c < gd.get(v, 1e18):
                        gd[v] = du + c
                        heapq.heappush(pq, (du + c, v))
        dists.append(dist)
    el = sorted(cells)
    for a in el:
        for b in el:
            if a == b:
                continue
            # Weights change costs, never reachability, so a pair is reached under all of them or none.
            ds = [dist.get((a, b)) for dist in dists]
            if ds[0] is None:
                continue
            ds = cast(list[float], ds)
            if all(
                any(dist.get((a, x), 1e18) + dist.get((x, b), 1e18) <= d * PRUNE for x in el if x not in (a, b))
                for dist, d in zip(dists, ds, strict=False)
            ):
                continue
            found[(a, b)] = tuple(ds)
    return found


def grid_hpa(grid, cuts, jobs=1):
    """HPA* over the grid. Every border crossing (orthogonal or diagonal) is grouped by the strongly connected parts
    of its two clusters it leaves and enters, in the direction it is walked: a crossing into a part the route cannot
    leave, or out of a part the route cannot reach, is of no use to it, so one entrance per such group guarantees a
    route wherever the grid has one. Each group keeps an entrance every ENTRANCE_RUN cells. Intra-cluster edges come
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
                    # a two-way record is still one-way at a steep pair, as the decoder reads it
                    if cost is None and not steep_node_ok(grid, u, w):
                        continue
                    wx, wy = divmod(cell_of(w), GH)
                    t = 0 if axis is None else uy - ky * CELLS if axis == 0 else ux - kx * CELLS
                    groups[(region[u], region[w])].append((t, int(wx != ux and wy != uy), u, w, cost))

    def entrances(groups):
        """Each group's entrances, one every ENTRANCE_RUN crossings, with the edge the crossing walks."""
        for crossings in groups.values():
            # A crossing carries its cost: None for an ordinary step, a float for a drop. Two identical crossings
            # (a step and a drop over the same pair) would make the tuple comparison fall through to the cost and
            # raise, so the order is the crossing itself and an ordinary step wins a tie (its reverse is a step).
            crossings.sort(key=lambda c: (c[0], c[1], c[2], c[3], c[4] is not None))
            for i in range(0, len(crossings), ENTRANCE_RUN):
                chunk = crossings[i : i + ENTRANCE_RUN]
                mid = chunk[len(chunk) // 2][0]
                # prefer orthogonal, then the crossing nearest the chunk's middle
                _, diagonal, u, v, cost = min(chunk, key=lambda c: (c[1], abs(c[0] - mid)))
                if cost is not None:
                    edges[(u, v)] = tuple(cost for _ in WEIGHTS)
                else:
                    edges[(u, v)] = step_into(u, v, diagonal)
                nodes[cluster_of_cell(u)].add(u)
                nodes[cluster_of_cell(v)].add(v)

    for k in range(NX * NY):
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
    inter = len(edges)
    _HPA = (grid, cuts, nodes)
    for found in run_clusters(cluster_edges, sorted(nodes), jobs):
        edges.update(found)
    _HPA = None
    print(f"grid HPA: nodes {sum(map(len, nodes.values()))}, edges {len(edges)} (inter {inter})", flush=True)
    return nodes, edges


def encode_map(nodes, edges, grid, cuts):
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
            rec, erec = [enc(len(cs), 2)], []
            for c in cs:
                layer = FLOOR_LAYER[c - GW * GH] if c >= GW * GH else 0
                rec.append(enc(lcell(cell_of(c)), 3) + enc(layer, 1) + enc(comp[c], 2) + enc(len(nbrs[c]), 1))
                for m, d in sorted(nbrs[c]):
                    km = cluster_of_cell(m)
                    dx, dy = km // NY - kx, km % NY - ky
                    assert abs(dx) <= 1 and abs(dy) <= 1
                    costs = "".join(enc(round(w), 2) for w in d)  # 4095 is ample: the longest baked is 2357
                    erec.append(enc((dx + 1) * 3 + dy + 1, 1) + enc(local[m], 2) + costs)
            graph[k] = "".join(rec) + "".join(erec)
        vals = []
        for i in range(CELLS):
            for j in range(CELLS):
                c = (kx * CELLS + i) * GH + ky * CELLS + j
                v, f = grid[c], flags.get(c, 0)
                if v == 3:
                    # Steep ground rides the ground value's flag 8: a steep map reads it as value 3, while water
                    # keeps flag 8 for its -x-y diagonal. A ground cell's -x-y diagonal is a record instead.
                    v, f = 1, f | 8
                else:
                    assert v != 1 or not f & 8, f"ground cell {c} uses the steep flag"
                vals.append(v * 16 + f)
        if any(vals):
            syms, i = [], 0
            while i < len(vals):
                j = i + 1
                while j < len(vals) and vals[j] == vals[i]:
                    j += 1
                syms.append(B64[vals[i]])
                repeat = j - i - 1
                while repeat > 0:
                    n = min(repeat, 16)
                    syms.append(B64[48 + n - 1])
                    repeat -= n
                i = j
            grids[k] = "".join(syms)
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
        if FLOORS_OF.get(k) or LINKED_OF.get(k):
            floors[k] = encode_floors(grid, k, lcell)
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


def emit(nodes, edges, grid, cuts, out, name):
    graph, grids, heights, floors, terrains, components = encode_map(nodes, edges, grid, cuts)
    lines = [
        "-- Generated by tools/baker/gen_nav.py — do not edit.",
        f"-- Source: {SOURCE}.",
        f"-- Generator: {generator_digest()}.",
        f"-- Map {MAP} ({name}), mmtile rows {ROWS.start}-{ROWS.stop - 1} x cols {COLS.start}-{COLS.stop - 1}.",
        "-- UnitPosition's frame (x north, y west). Cluster k (0-based) is the ADT tile x in [(cx0 + k // ny) T, +T),",
        "-- y in [(cy0 + k % ny) T, +T), T = 1600 / 3, cut into cells x cells cells, x-major. Base64 (A-Za-z0-9+/).",
        "-- format 3: a step both ways may take is one bit, as in format 1, and its floor node's landings name the",
        "-- layer it lands on, so the decoder resolves the pair the bake linked. `steep = true` marks steep ground in",
        "-- this map: a ground cell with flag 8, and a floor whose value is 3, are steep. A step with a steep end is a",
        "-- bit too, but the decoder allows it only when the destination's stored height is not above the source's.",
        "-- Only a step one way takes, a ledge drop or a step carrying a cost is its own record. A map without",
        "-- `steep` is the older format 2, whose flag 8 opens the -x-y diagonal and whose bits pick the surface",
        "-- nearest their height; without `format` it is format 1, whose links are symmetric.",
        "-- graph[k + 1]: n(2) | n x [cell(3) layer(1) component(2) degree(1)] | n x degree edges in node order, each",
        "--   [cluster offset(1): (dx + 1) * 3 + dy + 1, node(2), cost(2) swimming with water at swim, cost(2) walking",
        "--   on water, both in running yards]; the decoder builds each node's predecessors from them. grid[k + 1]:",
        "--   per cell value * 16 +",
        "--   flags, where value 0 blocked, 1 ground, 2 water; flags 1/2 close the step to the +x/+y neighbour, 4",
        "--   opens the +x+y diagonal, and 8 opens the -x-y diagonal, except that a ground cell's 8 is steep ground in",
        "--   a `steep` map (its -x-y diagonal is a record instead). Otherwise a diagonal is open when either L-shaped",
        "--   detour is. A symbol >= 48 repeats the previous cell (symbol - 47) more times. Nodes are local cells,",
        "--   then floors from cells * cells on.",
        *heights_header(),
        "-- floor[k + 1]: surfaces above or below the base one, numbered from cells * cells in order; the records that",
        "--   follow the step bits are one per pair, in the direction they are taken.",
        *("--   " + line for line in wrap(" ".join(cast(str, encode_floors.__doc__).split(": ", 1)[1].split()), 110)),
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
        "\tformat = 3,",
        "\tsteep = true,",
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
    print(f"emit: links {dict(KINDS)}, graph edges {len(edges)}", flush=True)
    print(
        f"emit: components {components}, graph {gb / 1e3:.1f} KB, grids+cuts {rb / 1e3:.1f} KB "
        f"({len(grids)} clusters, cuts {len(cuts)}), file {len(src) / 1e3:.1f} KB",
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


def assemble_floors(floors, links):
    """Floor nodes in (cell, height) order, and links between nodes, matched to surfaces by height."""
    nb = GW * GH
    at = FLOORS_AT
    for c, fs in sorted(floors):
        at[c] = []
        for v, z in fs:
            at[c].append(nb + len(FLOOR_CELL))
            FLOOR_LAYER.append(len(at[c]))
            FLOOR_CELL.append(c)
            FLOOR_VAL.append(v)
            FLOOR_Z.append(z)
        FLOORS_OF[cluster_of_cell(c)] += at[c]

    for i, za, j, zb, cost in links:
        a, b = surface_node(i, za), surface_node(j, zb)
        if a is None or b is None:
            continue
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
    pair: m's direction is a one-way step; q's is a drop, which lands on the surface (x, y) cells away (stored + 8,
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
        """u steps to v and back at no cost: the pair is symmetric, so one bit or one record carries it."""
        return LINKS[u].get(v, 1) is None and LINKS.get(v, {}).get(u, 1) is None

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
            if d is None or d in bits[n] or cluster_of_cell(v) != k or not both_ways(n, v):
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
            if back is None or cluster_of_cell(v) != k or not both_ways(u, v):
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
            if both_ways(u, v):
                if u > v and cluster_of_cell(v) == k:
                    continue  # one record per pair; the lower node writes the two-way step
                KINDS["two-way records"] += 1
                extra.append((lnode(u), d, layer(v)))
            else:
                KINDS["one-way records"] += 1
                extra.append((lnode(u), d + 8, layer(v)))
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
    grid, cuts = bytearray(GW * GH), set()
    BASE_Z.frombytes(bytes(4 * GW * GH))
    floors, links = [], []
    order = sorted(TILES, key=ORD.__getitem__)
    with multiprocessing.get_context("fork").Pool(jobs) as pool:  # workers inherit the pass-1 globals
        for n, (rc, vals, zs, tf, tl, own, terrain) in enumerate(pool.imap(rasterize_tile, order, chunksize=2)):
            kx, ky = divmod(cluster_of_tile(*rc), NY)
            for i in range(CELLS):
                row = (kx * CELLS + i) * GH + ky * CELLS
                grid[row : row + CELLS] = vals[i * CELLS : (i + 1) * CELLS]
                for j in range(CELLS):
                    if zs[i * CELLS + j] is not None:
                        BASE_Z[row + j] = zs[i * CELLS + j]
            if terrain is not None:
                TERRAIN[cluster_of_tile(*rc)] = terrain
            floors += tf
            links += tl
            cuts.update(own)
            if (n + 1) % 100 == 0:
                print(f"  rasterized {n + 1}/{len(order)} tiles", flush=True)
    print(f"grid {GW}x{GH}: ground {grid.count(1)}, water {grid.count(2)}, cut steps {len(cuts)}", flush=True)
    phases["raster"] = time.perf_counter() - checkpoint
    checkpoint = time.perf_counter()
    assemble_floors(floors, links)
    phases["floors"] = time.perf_counter() - checkpoint
    checkpoint = time.perf_counter()
    # The graph is built from the very links and cuts the grid is emitted with, so the two cannot disagree.
    nodes, edges = grid_hpa(grid, cuts, jobs)
    phases["graph"] = time.perf_counter() - checkpoint
    checkpoint = time.perf_counter()
    emit(nodes, edges, grid, cuts, out, name)
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

"""Reference walks on the raw navmesh a walking map is baked from, to check the planner's costs against.

A walk is Detour's own recipe: A* over the walkable polys between portal midpoints, then funnel string-pulling of the
corridor (dtNavMeshQuery::findPath and findStraightPath). Polys gen_nav.walkable refuses are left out; steep ground
(50 to 61.6 degrees) is left by a portal no higher than where the walk entered it, as gen_nav's linked() does, so it
is walked down only; the local bake's one-way ledge drops are followed in their own direction. Lengths are
horizontal yards, as the planner charges no slope; the 3D length is reported too.

    python3 tools/nav_reference.py MAP x1 y1 z1 x2 y2 z2 [...]   # one line per pair of points
    NAV_MM=<extract>/trinity<MAP>/mmaps, the tiles the map was baked from (their source.json names the build)

From Python, one load answers many walks: graph = load(map_id, tiles); path(graph, a, b) -> Walk or None;
locate(graph, x, y, z) -> poly; graph.adj[poly] -> neighbouring polys, graph.drops[poly] -> one-way drops.
"""

import heapq
import json
import math
import os
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "baker"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_nav  # noqa: E402
from baker.geometry import plane, point_in_convex, poly_distance  # noqa: E402


def tri2(a, b, c):
    return (c[0] - a[0]) * (b[1] - a[1]) - (b[0] - a[0]) * (c[1] - a[1])


def funnel(start, goal, portals):
    """Simple stupid funnel over portals given as (left, right) seen walking from start to goal."""
    portals = [(start, start), *portals, (goal, goal)]
    path = [start]
    apex, left, right = start, start, start
    ai = li = ri = 0
    i = 1
    while i < len(portals):
        pl, pr = portals[i]
        if tri2(apex, right, pr) <= 0:
            if apex == right or tri2(apex, left, pr) > 0:
                right, ri = pr, i
            else:
                path.append(left)
                apex, ai = left, li
                left = right = apex
                li = ri = ai
                i = ai + 1
                continue
        if tri2(apex, left, pl) >= 0:
            if apex == left or tri2(apex, right, pl) < 0:
                left, li = pl, i
            else:
                path.append(right)
                apex, ai = right, ri
                left = right = apex
                li = ri = ai
                i = ai + 1
                continue
        i += 1
    if path[-1] != goal:
        path.append(goal)
    return path


@dataclass
class Walk:
    length: float  # horizontal yards
    length3d: float
    points: list  # the straight path, (x, y, z)
    polys: list  # the corridor, (tile, poly index)


class Reference:
    def __init__(self, map_id, tiles=None):
        gen_nav.MM = os.environ.get("NAV_MM", gen_nav.MM)
        gen_nav.configure(map_id)
        manifest = Path(gen_nav.MM) / "source.json"
        source = json.loads(manifest.read_text()) if manifest.is_file() else {}
        self.source = {k: source.get(k) for k in ("map", "build", "recipe", "product")}
        self.polys, self.adj, self.portal, self.drops = {}, {}, {}, {}
        self.cells = {}  # 8 yd bucket -> the polys over it, so a point is located without a scan of the map
        border, drops = {}, []
        for rc in sorted(tiles or gen_nav.TILES):
            if rc in gen_nav.TILES:
                drops += self._tile(rc, border)
        for start, end in drops:
            a, b = self.locate(start), self.locate(end)
            if a and b and a != b:
                self.drops.setdefault(a, []).append((b, start, end))
        for key, es in border.items():
            es.sort(key=lambda t: t[1])
            for a in range(len(es)):
                for b in range(a + 1, len(es)):
                    if es[b][1] >= es[a][2] - 0.01:
                        break
                    u, w = es[a][0], es[b][0]
                    lo, hi = max(es[a][1], es[b][1]), min(es[a][2], es[b][2])
                    if u[0] != w[0] and hi - lo > 0.05 and abs(es[a][3] - es[b][3]) < 4:
                        axis, at = key
                        ends = ((lo, at), (hi, at)) if axis == "y" else ((at, lo), (at, hi))
                        self.adj.setdefault(u, set()).add(w)
                        self.adj.setdefault(w, set()).add(u)
                        self.portal[(u, w)] = self.portal[(w, u)] = ends

    def _tile(self, rc, border):
        tp, links, edges, drops = gen_nav.read_tile(rc)
        for i, pts, _, s in tp:
            c = tuple(sum(p[a] for p in pts) / len(pts) for a in range(3))
            self.polys[(rc, i)] = {"pts": pts, "xy": [p[:2] for p in pts], "plane": plane(pts, c), "steep": s}
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            for bx in range(int(min(xs) // 8), int(max(xs) // 8) + 1):
                for by in range(int(min(ys) // 8), int(max(ys) // 8) + 1):
                    self.cells.setdefault((bx, by), []).append((rc, i))
        for i, j, p1, p2 in links:
            self.adj.setdefault((rc, i), set()).add((rc, j))
            self.portal[((rc, i), (rc, j))] = (p1, p2)
        for key, i, lo, hi, z in edges:
            border.setdefault(key, []).append(((rc, i), lo, hi, z))
        return drops

    def height(self, key, x, y):
        cx, cy, cz, gx, gy = self.polys[key]["plane"]
        return cz + gx * (x - cx) + gy * (y - cy)

    def locate(self, point):
        """The poly a point stands on: one containing it at the nearest height, else the nearest poly within 24 yd."""
        x, y, z = point
        best = None
        near = {
            k
            for dx in range(-3, 4)
            for dy in range(-3, 4)
            for k in self.cells.get((int(x // 8) + dx, int(y // 8) + dy), ())
        }
        for key in sorted(near):
            p = self.polys[key]
            if point_in_convex(x, y, p["xy"]):
                d = abs(self.height(key, x, y) - z)
            else:
                d = poly_distance(point, p["pts"]) + 50
            if best is None or d < best[0]:
                best = (d, key)
        return best and best[1]

    def walk(self, a, b):
        """The reference walk from point a to point b, (x, y, z) each, or None when the navmesh has none."""
        s, t = self.locate(a), self.locate(b)
        goal = (b[0], b[1])
        dist, prev, at = {s: 0.0}, {}, {s: (a[0], a[1])}
        entry = {s: a[2]}  # the height the walk entered each poly at
        heap = [(math.dist(at[s], goal), 0.0, s)]
        while heap:
            _, d, u = heapq.heappop(heap)
            if u == t:
                break
            if d > dist[u]:
                continue
            steps = [(w, None) for w in self.adj.get(u, ()) if w in self.polys]
            steps += [(w, (start, end)) for w, start, end in self.drops.get(u, ())]
            for w, drop in steps:
                if drop:
                    m = drop[1][:2]
                    nd = d + math.dist(at[u], drop[0][:2]) + math.dist(drop[0][:2], m)
                else:
                    p1, p2 = self.portal[(u, w)]
                    m = ((p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2)
                    if self.polys[u]["steep"] and self.height(u, *m) > entry[u] + 0.01:
                        continue  # steep ground is left only below where the walk came onto it
                    nd = d + math.dist(at[u], m)
                if nd < dist.get(w, math.inf):
                    dist[w], prev[w], at[w] = nd, (u, drop), m
                    entry[w] = drop[1][2] if drop else self.height(w, *m)
                    heapq.heappush(heap, (nd + math.dist(m, goal), nd, w))
        if t not in dist:
            return None
        corridor = [(t, None)]
        while corridor[-1][0] != s:
            u, drop = prev[corridor[-1][0]]
            corridor[-1] = (corridor[-1][0], drop)
            corridor.append((u, None))
        corridor.reverse()
        # A drop has no portal: pull the string to its ledge, then on from its landing.
        points, portals, start = [], [], (a[0], a[1])
        for (u, _), (w, drop) in zip(corridor, corridor[1:], strict=False):
            if drop:
                points += funnel(start, drop[0][:2], portals)
                portals, start = [], drop[1][:2]
                continue
            p1, p2 = self.portal[(u, w)]
            m = ((p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2)
            c = self.polys[u]["plane"][:2]
            portals.append((p1[:2], p2[:2]) if tri2(c, m, p1) < 0 else (p2[:2], p1[:2]))
        points += funnel(start, goal, portals)
        flat = sum(math.dist(p, q) for p, q in zip(points, points[1:], strict=False) if p != q)
        lifted = [(x, y, self.height(self.locate((x, y, a[2])), x, y)) for x, y in points]
        lifted[0], lifted[-1] = tuple(a), tuple(b)
        return Walk(
            flat,
            sum(math.dist(p, q) for p, q in zip(lifted, lifted[1:], strict=False)),
            lifted,
            [u for u, _ in corridor],
        )


def load(map_id, tiles=None):
    return Reference(map_id, tiles)


def locate(graph, x, y, z):
    return graph.locate((x, y, z))


def path(graph, a, b):
    return graph.walk(a, b)


def tiles_around(a, b, pad=2):
    rows = sorted(int(32 - p[0] / gen_nav.T) for p in (a, b))
    cols = sorted(int(32 - p[1] / gen_nav.T) for p in (a, b))
    return [(r, c) for r in range(rows[0] - pad, rows[1] + pad + 1) for c in range(cols[0] - pad, cols[1] + pad + 1)]


def main():
    map_id, vals = int(sys.argv[1]), [float(v) for v in sys.argv[2:]]
    for n in range(0, len(vals), 6):
        a, b = tuple(vals[n : n + 3]), tuple(vals[n + 3 : n + 6])
        gen_nav.configure(map_id)
        walk = path(load(map_id, tiles_around(a, b)), a, b)
        print(f"{a} -> {b}: " + ("unreachable" if walk is None else f"{walk.length:.1f} yd ({len(walk.polys)} polys)"))


if __name__ == "__main__":
    main()

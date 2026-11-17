"""A road bends inside a cluster between two border crossings, past a plain-distance shortcut entrance."""

import heapq
import sys
from array import array
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.baker import gen_nav as nav  # noqa: E402

deep = "--deep" in sys.argv
bend = 46 if deep else 56
low = 41 if deep else 51

nav.NX, nav.NY, nav.GW, nav.GH = 3, 2, 201, 134
nav.BASE_Z = array("f", [0.0]) * (nav.GW * nav.GH)
grid = bytearray(nav.GW * nav.GH)
road = set()
for x in range(60, 141):
    for y in range(low, 72):
        grid[x * nav.GH + y] = 1
        if (
            (y == 66 and (x <= 67 or x >= 133))
            or (y == bend and 67 <= x <= 133)
            or (x in (67, 133) and bend <= y <= 66)
        ):
            road.add(x * nav.GH + y)
nav.ROAD_CELLS = road


# Collinear entrances A, X, B: plain-distance pruning removes A->B in favour of A->X->B.
# The road goes round X. Its border entrances must still connect without visiting X off the road.
def cell(x, y):
    return x * nav.GH + y


nodes = {
    0: {cell(66, 66)},
    2: {cell(67, 66), cell(100, 66), cell(133, 66)},
    3: {cell(100, 67)},
    4: {cell(134, 66)},
}
nav._HPA = grid, set(), nodes
edges = nav.cluster_edges(2)
nav.ROAD_CELLS = set()
plain = nav.cluster_edges(2)
nav.ROAD_CELLS = road
assert {edge for edge, costs in edges.items() if costs[2]} == set(plain), "base edges must match plain pruning exactly"
assert set(edges) - set(plain), "fixture must contain road-only edges"
if deep:

    def distance(start, goal, factor):
        costs, queue = {start: 0.0}, [(0.0, start)]
        while queue:
            cost, u = heapq.heappop(queue)
            if cost != costs[u]:
                continue
            if u == goal:
                return cost
            for v, step in nav.moves(lambda x, y: grid[cell(x, y)], grid, set(), u, nav.cluster_box(2), 1):
                candidate = cost + step * (1 if v in road else factor)
                if candidate < costs.get(v, float("inf")):
                    costs[v] = candidate
                    heapq.heappush(queue, (candidate, v))
        raise AssertionError("fixture entrances must connect")

    a, middle, b = cell(67, 66), cell(100, 66), cell(133, 66)
    # Verify the actual grid costs, including diagonal shortcuts, on both sides of the crossover.
    for factor, redundant in ((1.5, True), (3.0, False)):
        direct = distance(a, b, factor)
        via = distance(a, middle, factor) + distance(middle, b, factor)
        assert (via <= direct * nav.PRUNE) == redundant, (factor, direct, via)
    assert (a, b) in edges, "maximum road preference needs the border connection"

    # A->B has the extra path 10+f; going through entrance X costs min(7+3f, 13).
    # The direct connection wins at f=2, although X matches the best cost at 1, 1.5 and 3.
    # Endpoint searches must certify a single fixed replacement.
    original_moves, original_roads, original_hpa = nav.moves, nav.ROAD_CELLS, nav._HPA
    arcs = {0: ((3, 1), (4, 3), (2, 12)), 3: ((1, 10),), 4: ((2, 6),), 2: ((1, 1),)}
    try:
        nav.moves = lambda _g, _grid, _cuts, u, _box, _water: arcs.get(u, ())
        nav.ROAD_CELLS = {0, 1, 2}
        synthetic_grid = bytearray([1]) * len(grid)
        nav._HPA = synthetic_grid, set(), {0: {0, 1, 2}}
        assert (0, 1) in nav.cluster_edges(0), "interior road factor needs a connection redundant at both endpoints"
    finally:
        nav.moves, nav.ROAD_CELLS, nav._HPA = original_moves, original_roads, original_hpa


for a, b in (
    (cell(66, 66), cell(67, 66)),
    (cell(133, 66), cell(134, 66)),
    (cell(100, 66), cell(100, 67)),
):
    edges[a, b] = edges[b, a] = (nav.CS, nav.CS)
print("return {degreeWidth=2,baseDegreeWidth=2,cell={")
for x in range(60, 141):
    print(f"[{x}]={{" + ",".join(f"[{y}]={{z=0}}" for y in range(low, 72)) + "},")
print("},node={")
for cells in nodes.values():
    for u in sorted(cells):
        x, y = divmod(u, nav.GH)
        out = []
        for (a, b), costs in sorted(edges.items(), key=lambda edge: (len(edge[1]) > 2 and not edge[1][2], edge[0])):
            if a == u:
                bx, by = divmod(b, nav.GH)
                out.append(f"{{{bx},{by},{round(costs[0])},{round(costs[1])}}}")
        base = sum(a == u and (len(costs) == 2 or costs[2]) for (a, _b), costs in edges.items())
        print(f"{{{x},{y},1,base={base},out={{" + ",".join(out) + "}},")
print("},road={")
for k in nodes:
    cells = [f"[{(u // nav.GH % 67) * 67 + u % nav.GH % 67}]=1" for u in sorted(road) if nav.cluster_of_cell(u) == k]
    print(f"[{k}]={{" + ",".join(cells) + "},")
print("}}")

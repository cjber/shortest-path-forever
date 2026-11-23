"""Graph crossings and the legality of steps in the baked walking grid."""

import unittest
from array import array
from collections import defaultdict
from contextlib import contextmanager
from unittest.mock import patch

from tools.baker import gen_nav


class ClusterCrossingTest(unittest.TestCase):
    def test_a_step_and_a_drop_over_one_pair_keep_the_step(self):
        # A drop and an ordinary step can cross the same cluster border between the same two cells. Their crossing
        # tuples differ only in the cost (a float against None), which used to make the sort raise.
        c = gen_nav.CELLS
        grid = bytearray([1]) * (2 * c * c)
        u = (c - 1) * c + 10  # last column of cluster 0
        w = c * c + 10  # first column of cluster 1, the step's own crossing
        links = defaultdict(dict)
        links[u][w] = 12.0
        with (
            patch.object(gen_nav, "CELLS", c),
            patch.object(gen_nav, "NX", 2),
            patch.object(gen_nav, "NY", 1),
            patch.object(gen_nav, "GW", 2 * c),
            patch.object(gen_nav, "GH", c),
            patch.object(gen_nav, "LINKS", links),
            patch.object(gen_nav, "BASE_Z", array("f", [0.0]) * len(grid)),
            patch.object(gen_nav, "LINKED_OF", defaultdict(list, {0: [u]})),
            patch.object(gen_nav, "FLOOR_CELL", array("i")),
        ):
            _, edges = gen_nav.grid_hpa(grid, set())
        self.assertIn((u, w), edges)
        self.assertEqual(edges[(u, w)], edges[(w, u)], "the step keeps both directions")


class GraphLegalityTest(unittest.TestCase):
    """The abstract graph walks by exactly the rule the emitted grid decodes, so it cannot take a step the grid
    refuses or miss one it allows. A step's height rule is the stored height, never a raw one."""

    @contextmanager
    def world(self, heights, cuts=(), links=None, nx=1, ny=1):
        c = gen_nav.CELLS
        gw, gh = nx * c, ny * c
        grid = bytearray(gw * gh)
        base = array("f", [0.0] * (gw * gh))
        for cell, (value, z) in heights.items():
            grid[cell], base[cell] = value, z
        line = defaultdict(dict)
        for u, v, cost in links or ():
            line[u][v] = cost
        with (
            patch.object(gen_nav, "CELLS", c),
            patch.object(gen_nav, "GW", gw),
            patch.object(gen_nav, "GH", gh),
            patch.object(gen_nav, "NX", nx),
            patch.object(gen_nav, "NY", ny),
            patch.object(gen_nav, "BASE_Z", base),
            patch.object(gen_nav, "FLOOR_CELL", array("i")),
            patch.object(gen_nav, "FLOOR_VAL", bytearray()),
            patch.object(gen_nav, "FLOOR_LAYER", bytearray()),
            patch.object(gen_nav, "FLOOR_Z", array("f")),
            patch.object(gen_nav, "FLOORS_OF", defaultdict(list)),
            patch.object(gen_nav, "FLOORS_AT", {}),
            patch.object(gen_nav, "LINKS", line),
            patch.object(gen_nav, "LINKED_OF", defaultdict(list)),
        ):
            for node in line:
                gen_nav.LINKED_OF[gen_nav.cluster_of_cell(node)].append(node)
            yield grid, (lambda gx, gy: grid[gx * gen_nav.GH + gy])

    def steps(self, heights, cell, cuts=(), links=None):
        c = gen_nav.CELLS
        with self.world(heights, cuts, links) as (grid, g):
            return dict(gen_nav.moves(g, grid, set(cuts), cell, (0, c - 1, 0, c - 1)))

    def crossings(self, heights, cuts=(), links=None, ny=1):
        with self.world(heights, cuts, links, nx=2, ny=ny) as (grid, g):
            return gen_nav.grid_hpa(grid, set(cuts))[1], g, grid

    def test_separate_doorways_in_the_same_components_keep_their_entrances(self):
        # Each side joins the two doors behind the wall. Grouping by whole-cluster component alone kept only
        # one door, so a short walk through the other took the long way round (Ironforge, #910).
        c = gen_nav.CELLS
        for transpose in (False, True):
            with self.subTest(transpose=transpose):
                nx, ny = (1, 2) if transpose else (2, 1)

                def cell(x, y, ny=ny, transpose=transpose):
                    return y * ny * c + x if transpose else x * ny * c + y

                heights = {
                    cell(x, y): (1, 0.0)
                    for x in range(c - 2, c + 2)
                    for y in range(10, 21)
                    if x in (c - 2, c + 1) or y in (10, 20)
                }
                with self.world(heights, nx=nx, ny=ny) as (grid, _):
                    edges = gen_nav.grid_hpa(grid, set())[1]
                for y in (10, 20):
                    u, v = cell(c - 1, y), cell(c, y)
                    self.assertIn((u, v), edges)
                    self.assertIn((v, u), edges)

    def test_separate_floor_doorways_keep_each_layers_entrances(self):
        c = gen_nav.CELLS
        cells = {x * c + y for x in range(c - 2, c + 2) for y in range(10, 21) if x in (c - 2, c + 1) or y in (10, 20)}
        # Two disconnected storeys occupy the same cells. Each storey's two doors belong to the same pair of
        # cluster components, but neither the other door nor the other storey may replace one of its entrances.
        with self.world({cell: (1, 0.0) for cell in cells}, nx=2) as (grid, _):
            floors = {}
            for cell in sorted(cells):
                for layer, z in enumerate((30, 60), 1):
                    node = len(grid) + len(gen_nav.FLOOR_CELL)
                    floors[cell, layer] = node
                    gen_nav.FLOOR_CELL.append(cell)
                    gen_nav.FLOOR_VAL.append(1)
                    gen_nav.FLOOR_Z.append(z)
                    gen_nav.FLOOR_LAYER.append(layer)
                    gen_nav.FLOORS_OF[gen_nav.cluster_of_cell(node)].append(node)
                    gen_nav.FLOORS_AT.setdefault(cell, []).append(node)
            for (cell, layer), node in floors.items():
                x, y = divmod(cell, c)
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    other = floors.get(((x + dx) * c + y + dy, layer))
                    if other is not None:
                        gen_nav.LINKS[node][other] = None
                gen_nav.LINKED_OF[gen_nav.cluster_of_cell(node)].append(node)
            edges = gen_nav.grid_hpa(grid, set())[1]
            for layer in (1, 2):
                for y in (10, 20):
                    u, v = floors[(c - 1) * c + y, layer], floors[c * c + y, layer]
                    self.assertIn((u, v), edges)
                    self.assertIn((v, u), edges)

    def test_a_bridge_over_the_ground_keeps_its_own_entrance(self):
        # A bridge crosses the border over open ground, joined to it only at its far ends, so both share one pair of
        # cluster components and their crossings sit side by side along the border. Read as one run, its entrance
        # landed on the ground and a walk off the bridge went down and back up round its ends (Thunder Bluff).
        c = gen_nav.CELLS
        cells = {x * c + y for x in range(c - 2, c + 2) for y in range(10, 21)}
        with self.world({cell: (1, 0.0) for cell in cells}, nx=2) as (grid, _):
            bridge = {}
            for x in range(c - 2, c + 2):
                for y in range(10, 14):
                    node = len(grid) + len(gen_nav.FLOOR_CELL)
                    bridge[x, y] = node
                    gen_nav.FLOOR_CELL.append(x * c + y)
                    gen_nav.FLOOR_VAL.append(1)
                    gen_nav.FLOOR_Z.append(30)
                    gen_nav.FLOOR_LAYER.append(1)
                    gen_nav.FLOORS_OF[gen_nav.cluster_of_cell(node)].append(node)
                    gen_nav.FLOORS_AT.setdefault(x * c + y, []).append(node)
            for (x, y), node in bridge.items():
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    other = bridge.get((x + dx, y + dy))
                    if other is not None:
                        gen_nav.LINKS[node][other] = None
            for x in (c - 2, c + 1):
                gen_nav.LINKS[bridge[x, 10]][x * c + 10] = None
                gen_nav.LINKS[x * c + 10][bridge[x, 10]] = None
            for node in gen_nav.LINKS:
                gen_nav.LINKED_OF[gen_nav.cluster_of_cell(node)].append(node)
            edges = gen_nav.grid_hpa(grid, set())[1]
            on_bridge = set(bridge.values())
            for side in (0, 1):
                crossing = [
                    (u, v)
                    for u, v in edges
                    if {u, v} <= on_bridge and gen_nav.cluster_of_cell(u) == side != gen_nav.cluster_of_cell(v)
                ]
                self.assertTrue(crossing, f"the bridge keeps an entrance out of cluster {side}")

    def test_clusters_that_meet_at_a_corner_keep_the_crossings_between_them(self):
        # Four clusters; the only walkable cells are the two corner cells of clusters 0 and 3, which touch diagonally.
        # The runtime walks the bake's explicit diagonal between them, and a drop record may land across the corner,
        # so the graph needs an entrance there or HPA* calls the route unreachable.
        c = gen_nav.CELLS
        u, w = (c - 1) * 2 * c + c - 1, c * 2 * c + c
        edges, _, _ = self.crossings({u: (1, 0.0), w: (1, 0.0)}, cuts={u * 4 + 2}, ny=2)
        self.assertIn((u, w), edges)
        self.assertIn((w, u), edges)
        edges, _, _ = self.crossings({u: (1, 10.0), w: (1, 0.0)}, links=[(u, w, 12.0)], ny=2)
        self.assertIn((u, w), edges, "the drop lands across the corner")
        self.assertNotIn((w, u), edges)

    def test_a_steep_step_uses_the_stored_heights_the_decoder_reads(self):
        # 20.4 and 20.0 yards are both stored as 20, so the decoder walks the step both ways and the graph must too.
        # The removed shadow compared the raw heights and wrote only the downhill direction.
        c = gen_nav.CELLS
        a, b = 10 * c + 10, 11 * c + 10
        self.assertIn(b, self.steps({a: (3, 20.4), b: (1, 20.0)}, a))
        self.assertIn(a, self.steps({a: (3, 20.4), b: (1, 20.0)}, b))

    def test_a_steep_step_between_different_stored_heights_goes_down_only(self):
        c = gen_nav.CELLS
        a, b = 10 * c + 10, 11 * c + 10
        self.assertIn(b, self.steps({a: (3, 20.4), b: (1, 18.0)}, a))  # 18 <= 20: downhill
        self.assertNotIn(a, self.steps({a: (3, 20.4), b: (1, 18.0)}, b))  # 20 > 18: not uphill

    def test_an_open_step_on_ordinary_ground_is_walked_both_ways_whatever_its_rise(self):
        # Stairs rise ten yards in one cell, steeper than 50 degrees, in steps the client climbs. The bake leaves a
        # step open only where the navmesh walks it, so its stored heights must not close it again (#1011).
        c = gen_nav.CELLS
        a, b = 10 * c + 10, 11 * c + 10
        self.assertIn(b, self.steps({a: (1, 10.0), b: (1, 20.0)}, a))
        self.assertIn(a, self.steps({a: (1, 10.0), b: (1, 20.0)}, b))
        u, v = (c - 1) * c + 10, c * c + 10
        edges, _, _ = self.crossings({u: (1, 10.0), v: (1, 20.0)})
        self.assertIn((u, v), edges)
        self.assertIn((v, u), edges)

    def test_a_cliff_is_refused_by_its_cut_not_its_heights(self):
        # linked() finds no navmesh walk up a cliff, so the bake cuts the step; the grid and the graph honour the cut.
        c = gen_nav.CELLS
        a, b = 10 * c + 10, 11 * c + 10
        self.assertNotIn(b, self.steps({a: (1, 10.0), b: (1, 30.0)}, a, cuts={a * 4}))
        self.assertNotIn(a, self.steps({a: (1, 10.0), b: (1, 30.0)}, b, cuts={a * 4}))
        u, v = (c - 1) * c + 10, c * c + 10
        edges, _, _ = self.crossings({u: (1, 10.0), v: (1, 30.0)}, cuts={u * 4})
        self.assertNotIn((u, v), edges)
        self.assertNotIn((v, u), edges)

    def test_a_two_way_record_with_a_steep_end_is_one_way(self):
        # The bake writes a steep pair both ways as a record so the decoder can decide its direction by stored height;
        # the graph must apply that rule to the record, or it climbs a face the grid refuses.
        c = gen_nav.CELLS
        a, b = 10 * c + 10, 10 * c + 11
        links = [(a, b, None), (b, a, None)]
        self.assertIn(b, self.steps({a: (1, 20.4), b: (3, 18.0)}, a, links=links))  # 18 <= 20: downhill
        self.assertNotIn(a, self.steps({a: (1, 20.4), b: (3, 18.0)}, b, links=links))  # 20 > 18: not uphill

    def test_a_runtime_walkable_cluster_crossing_is_in_the_graph(self):
        c = gen_nav.CELLS
        u, w = (c - 1) * c + 10, c * c + 10  # the last column of cluster 0 and the first of cluster 1
        edges, _, _ = self.crossings({u: (3, 20.4), w: (1, 20.0)})
        self.assertIn((u, w), edges, "equal stored heights: the crossing is walkable both ways")
        self.assertIn((w, u), edges)
        self.assertEqual(edges[(u, w)], edges[(w, u)])

    def test_a_steep_cluster_crossing_keeps_its_downhill_direction(self):
        c = gen_nav.CELLS
        u, w = (c - 1) * c + 10, c * c + 10
        edges, _, _ = self.crossings({u: (3, 20.4), w: (1, 18.0)})
        self.assertIn((u, w), edges)
        self.assertNotIn((w, u), edges, "the graph must not climb a steep crossing")

    def test_a_one_way_record_crossing_keeps_its_direction(self):
        # A pair the navmesh joins one way only is cut and written as its own record: the reverse step is not open,
        # so the graph must not write it.
        c = gen_nav.CELLS
        u, w = (c - 1) * c + 10, c * c + 10
        edges, _, _ = self.crossings({u: (1, 20.0), w: (1, 20.0)}, cuts={u * 4}, links=[(u, w, None)])
        self.assertIn((u, w), edges)
        self.assertNotIn((w, u), edges)

    def test_a_one_way_step_does_not_hide_the_crossing_it_cannot_reach(self):
        # A steep step splits the border run: the low cell walks down from the high shelf but not back up. The old
        # fill reached every cell here from one seed, so the whole run was one group and the chunk kept its middle
        # entrance, on the high shelf, which the low cell can never reach; HPA* then called a route the grid walks
        # unreachable. Entrances are grouped by the strongly connected parts they leave and enter, so the low cell
        # keeps a crossing of its own.
        c = gen_nav.CELLS
        shelf = [8, 10, 11, 12, 13]  # the high border cells, joined behind the low one
        low = (c - 1) * c + 9
        heights = {(c - 1) * c + t: (3, 20.0) for t in shelf}
        heights.update({(c - 2) * c + t: (3, 20.0) for t in (8, 9, 10)})
        heights[low] = (1, 18.0)
        heights.update({c * c + i * c + j: (1, 18.0) for i in range(c) for j in range(c)})
        edges, _, _ = self.crossings(heights)
        self.assertIn((low, c * c + 9), edges, "the low side keeps a crossing of its own")
        self.assertIn((c * c + 9, low), edges, "and the grid walks it back")

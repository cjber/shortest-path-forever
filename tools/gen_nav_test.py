import math
import pickle
import unittest
from array import array
from collections import defaultdict
from contextlib import contextmanager
from unittest.mock import patch

from tools.baker import gen_nav
from tools.baker.gen_nav import decode_road_runs, drop_cost, pick_surface, walkable
from tools.baker.geometry import centroid, clip_convex, height, plane


class WalkableTest(unittest.TestCase):
    def test_ground_under_liquid_is_not_walkable(self):
        triangle = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
        self.assertTrue(walkable(triangle, 0, 11, 0))
        self.assertFalse(walkable(triangle, 0x40, 11, 0))
        self.assertFalse(walkable(triangle, 0x80, 11, 0))
        self.assertFalse(walkable(triangle, 0x40 | 0x80, 11, 0))

    def test_steep_ground_is_walkable_downhill(self):
        # ground the navmesh marks steep: its steps decide which way it may be crossed
        triangle = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
        self.assertTrue(walkable(triangle, 0, 10, 0))
        self.assertFalse(walkable(triangle, 0, 0, 0))


class DropCostTest(unittest.TestCase):
    def test_a_fall_costs_free_falls_time_at_run_speed(self):
        # 14.57 yards is the longest fall that does not hurt: sqrt(2 * 14.57 / 19.2911) seconds, run at 7 yd/s
        self.assertAlmostEqual(drop_cost(0.0, 14.57), 7.0 * (2 * 14.57 / 19.2911) ** 0.5)
        self.assertAlmostEqual(drop_cost(2.0, 4.0), 2.0 + 7.0 * (8.0 / 19.2911) ** 0.5)
        self.assertGreater(drop_cost(0.0, 14.57), drop_cost(0.0, 10.0))


def flat(z):
    """A square covering the fixture's points at height z, with the plane gen_nav's layer matching uses."""
    pts = [(-1.0, -1.0, z), (20.0, -1.0, z), (20.0, 20.0, z), (-1.0, 20.0, z)]
    c = tuple(sum(p[a] for p in pts) / len(pts) for a in range(3))
    return {"pts": [(p[0], p[1]) for p in pts], "plane": plane(pts, c), "steep": False}


class PickSurfaceTest(unittest.TestCase):
    def test_a_surface_rasterized_in_a_neighbouring_cell_is_found(self):
        # The ground cell's anchor is at 10, but the ledge 20 yards up is rasterized in the next cell because the
        # cell centre missed its narrow bridge. The old nearest-anchor pick found no layer at all.
        polys = {0: flat(10.0), 1: flat(20.0)}
        layers = {0: [(10.0, 1, (0, (0.0, 0.0)))], 1: [(20.0, 1, (1, (0.0, 0.0)))]}
        got = pick_surface(layers, polys, [(0, 0, 0), (1, 1, 0)], 0.5, 0.5, 20.2)
        self.assertEqual(got, (1, 0))

    def test_surfaces_are_picked_by_the_poly_at_the_point_not_the_cell_anchor(self):
        polys = {0: flat(10.0), 1: flat(20.0)}
        layers = {0: [(10.0, 1, (0, (0.0, 0.0))), (20.0, 1, (1, (0.0, 0.0)))]}
        self.assertEqual(pick_surface(layers, polys, [(0, 0, 0)], 0.5, 0.5, 20.2), (0, 1))
        self.assertEqual(pick_surface(layers, polys, [(0, 0, 0)], 0.5, 0.5, 9.8), (0, 0))


class RasterizeLayersTest(unittest.TestCase):
    """A cell's layers are the pieces of surface it stands on, not every time the bake sampled one."""

    def surface(self, x0, x1, z, steep=False):
        pts = [(x0, 0.0, z), (x1, 0.0, z), (x1, 8.0, z), (x0, 8.0, z)]
        c = tuple(sum(p[a] for p in pts) / len(pts) for a in range(3))
        return {"pts": [(p[0], p[1]) for p in pts], "plane": plane(pts, c), "c": c, "steep": steep,
                "water": False, "size": 1}  # fmt: skip

    def layers(self, polys, adj, portal):
        with (
            patch.object(gen_nav, "X0", 0.0),
            patch.object(gen_nav, "Y0", 0.0),
            patch.object(gen_nav, "GW", gen_nav.CELLS),
            patch.object(gen_nav, "GH", gen_nav.CELLS),
        ):
            return gen_nav.rasterize_layers(polys, adj, portal, (0, 0, 0, 0))

    def portal(self, a, b):
        return {(a, b): ((4.0, 0.0), (4.0, 8.0)), (b, a): ((4.0, 8.0), (4.0, 0.0))}

    def test_one_surface_sampled_twice_is_one_layer(self):
        # The cell centre stands on the lower half at 10; the passage fill samples the upper half at 20, ten yards
        # above. The navmesh joins them inside the cell, so they are one piece of ground, not a floor.
        polys = {0: self.surface(0.0, 4.0, 10.0), 1: self.surface(4.0, 8.0, 20.0)}
        layers = self.layers(polys, {0: {1}, 1: {0}}, self.portal(0, 1))
        self.assertEqual(len(layers[0]), 1)
        self.assertEqual(layers[0][0][0], 10.0)

    def test_a_surface_the_cell_does_not_reach_stays_a_floor(self):
        # A bridge deck directly over the road: the two are not joined inside the cell, so both stay layers.
        polys = {0: self.surface(0.0, 8.0, 10.0), 1: self.surface(0.0, 8.0, 30.0)}
        layers = self.layers(polys, {}, {})
        self.assertEqual(sorted(z for z, _, _ in layers[0]), [10.0, 30.0])

    def test_a_passage_cell_takes_the_ramps_height_where_the_passage_crosses_it(self):
        # A ramp a yard wide climbs one yard per yard north, so the cell centre is off the mesh and only the passage
        # fill reaches the cell. The lower poly's centroid stands six yards south of the cell and six yards below it,
        # and stored there it made the next step up read as a climb past 50 degrees (#1011, the Dun Algaz tunnel).
        def ramp(x0, x1):
            pts = [(x0, 0.0, x0), (x1, 0.0, x1), (x1, 2.0, x1), (x0, 2.0, x0)]
            c = tuple(sum(p[a] for p in pts) / len(pts) for a in range(3))
            return {"pts": [(p[0], p[1]) for p in pts], "plane": plane(pts, c), "c": c, "steep": False,
                    "water": False, "size": 1}  # fmt: skip

        portal = {(0, 1): ((4.0, 0.0), (4.0, 2.0)), (1, 0): ((4.0, 2.0), (4.0, 0.0))}
        layers = self.layers({0: ramp(-16.0, 4.0), 1: ramp(4.0, 24.0)}, {0: {1}, 1: {0}}, portal)
        self.assertEqual(len(layers[0]), 1)
        z, _, (_, point) = layers[0][0]
        self.assertTrue(0.0 <= z <= gen_nav.CS, z)
        self.assertAlmostEqual(z, point[0])  # the ramp's own height at the anchor

    def test_a_street_off_the_cell_centre_stays_a_floor(self):
        # A stall on the cell centre leaves the street only on the cell's eastern half; the ground under the city
        # spans the cell twenty yards below. The street is still where the player stands, so it is a layer (#1046).
        polys = {0: self.surface(0.0, 8.0, 10.0), 1: self.surface(4.5, 8.0, 30.0)}
        layers = self.layers(polys, {}, {})
        self.assertEqual(sorted(z for z, _, _ in layers[0]), [10.0, 30.0])
        self.assertEqual(layers[0][0][0], 10.0)  # the centre's surface stays the base

    def test_steep_ground_is_never_the_same_layer_as_the_ground_it_leads_to(self):
        # A face from 50 to 61.6 degrees is walked down and never across, so joining it to the flat ground beside it
        # inside one cell must not lose the level it leads up to.
        polys = {0: self.surface(0.0, 4.0, 10.0), 1: self.surface(4.0, 8.0, 20.0, steep=True)}
        layers = self.layers(polys, {0: {1}, 1: {0}}, self.portal(0, 1))
        self.assertEqual(sorted(z for z, _, _ in layers[0]), [10.0, 20.0])


class DiagonalTest(unittest.TestCase):
    def test_a_steep_diagonal_opens_the_symmetric_flag(self):
        # Steep ground is a value, not a direction in the file: the diagonal bit stays open and the decoder walks it
        # downhill only, from the two stored heights.
        c = gen_nav.CELLS
        i, j = 10 * c + 10, 11 * c + 11
        polys = {1: {**flat(10.0), "steep": True}}
        layers = {i: [(20.0, 3, (1, (0.0, 0.0)))], j: [(10.0, 1, (1, (0.0, 0.0)))]}
        with (
            patch.object(gen_nav, "TILES", {(0, 0): "tile"}),
            patch.object(gen_nav, "NX", 1),
            patch.object(gen_nav, "NY", 1),
            patch.object(gen_nav, "CX0", 31),
            patch.object(gen_nav, "CY0", 31),
            patch.object(gen_nav, "GW", c),
            patch.object(gen_nav, "GH", c),
            patch.object(gen_nav, "X0", 0.0),
            patch.object(gen_nav, "Y0", 0.0),
            patch.object(gen_nav, "load_window", lambda window: (polys, {}, {})),
            patch.object(gen_nav, "rasterize_layers", lambda polys, adj, portal, bounds: layers),
            patch.object(gen_nav, "read_tile", lambda rc: ([], [], [], [])),
        ):
            _, _, _, _, links, own, _ = gen_nav.rasterize_tile((0, 0))
        free = [(i, 20.0, j, 10.0, "free"), (j, 10.0, i, 20.0, "free")]
        self.assertEqual(sorted(links), sorted(free), "the walk climbs back up, which no bit can say (#1101)")
        self.assertNotIn(i * 4 + 2, own, "a bit would read the climb with the downhill-only rule")

    def test_a_ground_diagonal_across_a_cluster_edge_keeps_both_directions(self):
        # A -y diagonal on ground is a pair of records. Each tile writes the records whose source it holds, so the
        # pair must be looked at from both sides of the edge, or the reverse is lost and the crossing is one-way.
        c = gen_nav.CELLS
        polys = {1: {**flat(10.0), "pts": [(-1e4, -1e4), (1e4, -1e4), (1e4, 1e4), (-1e4, 1e4)]}}
        for nx, ny, (ix, iy), (jx, jy) in ((2, 1, (c - 1, 10), (c, 9)), (1, 2, (10, c), (11, c - 1))):
            gh = ny * c
            i, j = ix * gh + iy, jx * gh + jy
            layers = {i: [(10.0, 1, (1, (0.0, 0.0)))], j: [(10.0, 1, (1, (0.0, 0.0)))]}
            tiles = {(31 - x, 31 - y): "tile" for x in range(nx) for y in range(ny)}
            links = []
            with (
                patch.object(gen_nav, "TILES", tiles),
                patch.object(gen_nav, "NX", nx),
                patch.object(gen_nav, "NY", ny),
                patch.object(gen_nav, "CX0", 0),
                patch.object(gen_nav, "CY0", 0),
                patch.object(gen_nav, "GW", nx * c),
                patch.object(gen_nav, "GH", gh),
                patch.object(gen_nav, "X0", 0.0),
                patch.object(gen_nav, "Y0", 0.0),
                patch.object(gen_nav, "load_window", lambda window: (polys, {}, {})),
                patch.object(gen_nav, "rasterize_layers", lambda polys, adj, portal, bounds, layers=layers: layers),
                patch.object(gen_nav, "read_tile", lambda rc: ([], [], [], [])),
            ):
                for rc in tiles:
                    links += gen_nav.rasterize_tile(rc)[4]
            both = [(i, 10.0, j, 10.0, "free"), (j, 10.0, i, 10.0, "free")]
            self.assertEqual(sorted(links), sorted(both), f"each direction once, edge {'x' if nx > 1 else 'y'}")


class SteepStepTest(unittest.TestCase):
    def tile(self, polys, adj, portal, layers):
        """What one tile emits for this navmesh and these layers: (links, own)."""
        c = gen_nav.CELLS
        with (
            patch.object(gen_nav, "TILES", {(0, 0): "tile"}),
            patch.object(gen_nav, "NX", 1),
            patch.object(gen_nav, "NY", 1),
            patch.object(gen_nav, "CX0", 31),
            patch.object(gen_nav, "CY0", 31),
            patch.object(gen_nav, "GW", c),
            patch.object(gen_nav, "GH", c),
            patch.object(gen_nav, "X0", 0.0),
            patch.object(gen_nav, "Y0", 0.0),
            patch.object(gen_nav, "load_window", lambda window: (polys, adj, portal)),
            patch.object(gen_nav, "rasterize_layers", lambda polys, adj, portal, bounds: layers),
            patch.object(gen_nav, "read_tile", lambda rc: ([], [], [], [])),
        ):
            _, _, _, _, links, own, _ = gen_nav.rasterize_tile((0, 0))
        return links, own

    def face(self, x0, x1, z0, z1, steep):
        """A strip rising from z0 at x0 to z1 at x1, 8 yards deep, with the plane the bake reads heights from."""
        pts = [(x0, 0.0, z0), (x1, 0.0, z1), (x1, 8.0, z1), (x0, 8.0, z0)]
        c = tuple(sum(p[a] for p in pts) / len(pts) for a in range(3))
        return {"pts": [(p[0], p[1]) for p in pts], "plane": plane(pts, c), "c": c, "steep": steep,
                "water": False, "size": 1}  # fmt: skip

    def test_a_steep_step_the_walk_climbs_is_taken_as_written(self):
        # The steep floor's anchor is the face's top edge, where the navmesh walk steps up a 2 yard lip onto the
        # ground above. The decoder's stored-height rule refuses that step off steep ground: a bit would lose that
        # direction, so each walked direction is a record taken as written (#1101).
        c = gen_nav.CELLS
        i, j = 10 * c + 10, 11 * c + 10
        cs = gen_nav.CS
        polys = {
            0: self.face(i * cs, (i % c + 1) * cs, 236.0, 244.0, False),  # the cell's own ground
            1: self.face(i * cs, (i % c + 1) * cs, 240.0, 248.0, True),  # the face above it
            2: self.face(j * cs, (j % c + 1) * cs, 250.0, 250.0, False),
            3: self.face(j * cs, (j % c + 1) * cs, 250.0, 250.0, False),  # the ground it leads up to
        }
        layers = {
            i: [(236.0, 1, (0, (i * cs + 2.0, 2.0))), (248.0, 3, (1, (11 * cs, 2.0)))],
            j: [(250.0, 1, (2, (j * cs + 2.0, 2.0))), (250.0, 1, (3, (j * cs + 2.0, 2.0)))],
        }
        ends = ((11 * cs, 10 * cs), (11 * cs, 11 * cs))
        links, _ = self.tile(polys, {1: {3}, 3: {1}}, {(1, 3): ends, (3, 1): ends[::-1]}, layers)
        for edge in [(i, 248.0, j, 250.0, "free"), (j, 250.0, i, 248.0, "free")]:
            self.assertIn(edge, links, f"each walked direction is its own record: {edge}")
        self.assertNotIn((i, 248.0, j, 250.0, None), links, "and none rides a bit")

    def test_ground_beside_a_steep_face_does_not_climb_it(self):
        # A flat cell shares an edge with the foot of a steep face whose anchor stands 6.75 yards up it. The walk
        # comes down the face onto the ground and cannot climb it, so the pair rides the downhill-only bit and no
        # record climbs it as written: a shortcut for neighbouring polys did, up the mountain outside Ironforge (#1011).
        c = gen_nav.CELLS
        i, j = 10 * c + 10, 11 * c + 10
        cs = gen_nav.CS

        def poly(pts, steep):
            centre = tuple(sum(p[a] for p in pts) / len(pts) for a in range(3))
            return {"pts": [p[:2] for p in pts], "plane": plane(pts, centre), "c": centre, "steep": steep,
                    "water": False, "size": 1}  # fmt: skip

        x0, x1, x2, y0, y1 = 10 * cs, 11 * cs, 12 * cs, 10 * cs, 11 * cs
        polys = {
            0: poly([(x0, y0, 437.0), (x1, y0, 437.0), (x1, y1, 437.0), (x0, y1, 437.0)], False),
            1: poly([(x1, y0, 437.0), (x2, y0, 446.0), (x2, y1, 446.0), (x1, y1, 437.0)], True),
        }
        a, b = (x0 + 4.0, y0 + 4.0), (x1 + 6.0, y0 + 4.0)
        zb = height(polys[1], *b)
        layers = {i: [(437.0, 1, (0, a))], j: [(zb, 3, (1, b))]}
        ends = ((x1, y0), (x1, y1))
        links, own = self.tile(polys, {0: {1}, 1: {0}}, {(0, 1): ends, (1, 0): ends[::-1]}, layers)
        self.assertNotIn((i, 437.0, j, zb, "free"), links, "the face is never climbed as written")
        self.assertNotIn(i * 4, own, "the downhill-only bit carries the pair")

    def test_a_one_way_step_the_heights_refuse_rides_one_bit(self):
        # The walk takes the face down and refuses the climb; the stored heights refuse it too, and the far end is
        # steep, so one symmetric bit carries the pair. This is what keeps a continent of steep ground from costing
        # a record per step.
        self.assertTrue(gen_nav.pair_carries_bit(20.4, 0, 18.0, 0, True, False, True))
        self.assertFalse(gen_nav.pair_carries_bit(20.4, 0, 18.0, 0, False, True, True), "that is the climb")
        self.assertTrue(gen_nav.pair_carries_bit(18.0, 0, 20.4, 0, False, True, True), "the descent is the taken one")

    def test_a_refusal_the_runtime_cannot_check_keeps_its_record(self):
        # Ordinary ground has no steep test, so a bit would walk the pair both ways: a one-way wall the heights do
        # not explain must stay its own record, and a pair the walk joins neither way is no step.
        self.assertFalse(gen_nav.pair_carries_bit(20.0, 0, 18.0, 0, False, True, False))
        self.assertFalse(gen_nav.pair_carries_bit(20.4, 0, 18.0, 0, False, True, True), "heights allow the descent")
        self.assertFalse(gen_nav.pair_carries_bit(20.0, 0, 18.0, 0, False, False, True), "no walk, no step")

    def test_a_pair_the_walk_joins_both_ways_always_rides_a_bit(self):
        self.assertTrue(gen_nav.pair_carries_bit(20.0, 0, 30.0, 0, True, True, False))
        self.assertTrue(gen_nav.pair_carries_bit(20.0, 1, 20.0, 0, True, True, True))

    def test_a_steep_orthogonal_pair_the_walk_climbs_is_taken_as_written(self):
        c = gen_nav.CELLS
        i, j = 10 * c + 10, 11 * c + 10
        polys = {1: {**flat(10.0), "steep": True}}
        layers = {i: [(20.0, 3, (1, (0.0, 0.0)))], j: [(10.0, 1, (1, (0.0, 0.0)))]}
        with (
            patch.object(gen_nav, "TILES", {(0, 0): "tile"}),
            patch.object(gen_nav, "NX", 1),
            patch.object(gen_nav, "NY", 1),
            patch.object(gen_nav, "CX0", 31),
            patch.object(gen_nav, "CY0", 31),
            patch.object(gen_nav, "GW", c),
            patch.object(gen_nav, "GH", c),
            patch.object(gen_nav, "X0", 0.0),
            patch.object(gen_nav, "Y0", 0.0),
            patch.object(gen_nav, "load_window", lambda window: (polys, {}, {})),
            patch.object(gen_nav, "rasterize_layers", lambda polys, adj, portal, bounds: layers),
            patch.object(gen_nav, "read_tile", lambda rc: ([], [], [], [])),
        ):
            _, _, _, _, links, own, _ = gen_nav.rasterize_tile((0, 0))
        free = [(i, 20.0, j, 10.0, "free"), (j, 10.0, i, 20.0, "free")]
        self.assertEqual(sorted(links), sorted(free), "both walked directions survive the downhill-only rule")
        self.assertIn(i * 4, own, "the bit is cut: the records carry the pair")

    def test_steep_step_uses_the_stored_heights(self):
        # Base heights are stored on the 2-yard grid; a floor is stored at whole yards, like gen_nav.stored_z.
        self.assertTrue(gen_nav.steep_step(20.4, 0, 18.0, 0))
        self.assertFalse(gen_nav.steep_step(18.0, 0, 20.4, 0))
        self.assertTrue(gen_nav.steep_step(20.4, 0, 20.4, 0), "equal stored heights pass both ways")
        self.assertFalse(gen_nav.steep_step(20.4, 1, 21.0, 1), "a floor uses whole yards")

    def test_a_52_degree_face_is_walked_down_only(self):
        # One 8 yard cell of a 52 degree face rises CS * tan 52, inside the bake's steep band: the player walks it
        # down and cannot climb it. The comparison is between the stored heights, as the decoder reads them.
        rise = gen_nav.CS * math.tan(math.radians(52))
        low, high = 20.0, 20.0 + rise
        self.assertFalse(gen_nav.steep_step(low, 0, high, 0), "the player cannot climb a 52 degree face")
        self.assertTrue(gen_nav.steep_step(high, 0, low, 0), "the player walks a 52 degree face down")


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


class AssembleFloorsTest(unittest.TestCase):
    def assemble(self, links):
        c = gen_nav.CELLS
        base = array("f", [10.0] + [0.0] * (c * c - 1))
        floors = [(0, [(1, 20.0)])]
        with (
            patch.object(gen_nav, "GW", c),
            patch.object(gen_nav, "GH", c),
            patch.object(gen_nav, "NY", 1),
            patch.object(gen_nav, "CELLS", c),
            patch.object(gen_nav, "BASE_Z", base),
            patch.object(gen_nav, "FLOOR_CELL", array("i")),
            patch.object(gen_nav, "FLOOR_VAL", bytearray()),
            patch.object(gen_nav, "FLOOR_Z", array("f")),
            patch.object(gen_nav, "FLOOR_LAYER", bytearray()),
            patch.object(gen_nav, "LINKS", defaultdict(dict)),
            patch.object(gen_nav, "FLOORS_OF", defaultdict(list)),
            patch.object(gen_nav, "LINKED_OF", defaultdict(list)),
            patch.object(gen_nav, "FLOORS_AT", {}),
            patch.object(gen_nav, "FREE", set()),
        ):
            gen_nav.assemble_floors(floors, links)
            return gen_nav.LINKS[0][c * c], (0, c * c) in gen_nav.FREE

    def test_duplicate_collapsed_links_keep_the_cheapest(self):
        links = [(0, 10.0, 0, 20.0, 5.0), (0, 10.0, 0, 20.0, 3.0), (0, 10.0, 0, 20.0, 4.0)]
        self.assertEqual(self.assemble(links), (3.0, False))

    def test_a_free_step_from_a_worker_is_marked_free(self):
        # Tile links come back pickled from worker processes, so the marker is an equal string, not the same object.
        free = pickle.loads(pickle.dumps(gen_nav.FREE_STEP))
        self.assertEqual(self.assemble([(0, 10.0, 0, 20.0, 4.0), (0, 10.0, 0, 20.0, free)]), (None, True))

    def test_raw_links_read_back_exactly(self):
        # main holds the tiles' links in RawLinks, so it must hand assemble_floors the very tuples a list would.
        free = pickle.loads(pickle.dumps(gen_nav.FREE_STEP))
        sent = [
            (7, 0.1 + 0.2, 4_000_000, -1e-300, None),
            (0, 10.0, 3, 20.5, free),
            (5, 1.25, 6, 2.5, 3.0000000000000004),
        ]
        raw = gen_nav.RawLinks()
        raw.extend(sent[:1])
        raw.extend(sent[1:])
        self.assertEqual(len(raw), 3)
        self.assertEqual(list(raw), sent)
        for got, want in zip(raw, sent, strict=True):
            self.assertEqual([type(v) for v in got], [type(v) for v in want])
        both = gen_nav.RawLinks()
        both.extend([(0, 10.0, 0, 20.0, 5.0), (0, 10.0, 0, 20.0, 3.0), (0, 10.0, 0, 20.0, free)])
        self.assertEqual(self.assemble(both), (None, True))


class ReachableTest(unittest.TestCase):
    def components(self, spots):
        # A street and, 40 yards under it, sealed ground with no way between them, as under Stormwind.
        def square(z):
            return [(-8800.0, 800.0, z), (-8790.0, 800.0, z), (-8790.0, 810.0, z), (-8800.0, 810.0, z)]

        polys = [(0, square(100.0), False, False), (1, square(60.0), False, False)]
        with (
            patch.object(gen_nav, "TILES", {(48, 30): "tile"}),
            patch.object(gen_nav, "BASE", {}),
            patch.object(gen_nav, "SIZE", array("i")),
            patch.object(gen_nav, "read_tile", lambda rc: (polys, [], [], [])),
        ):
            gen_nav.components(spots)
            return list(gen_nav.SIZE)

    def test_ground_no_fixed_place_stands_on_is_dropped(self):
        self.assertEqual(self.components([(-8795.0, 805.0, 101.0)]), [1, 0])
        self.assertEqual(self.components([(-8795.0, 815.0, 58.0)]), [0, 1])

    def test_tiles_without_a_fixed_place_are_refused(self):
        with self.assertRaises(SystemExit):
            self.components([(0.0, 0.0, 0.0)])


class EmitDeltaTest(unittest.TestCase):
    """A sorted cell or node delta, as a format 3 cluster's floor list and record list write it."""

    def test_a_small_delta_is_one_symbol(self):
        out = []
        gen_nav.emit_delta(out, 0)
        gen_nav.emit_delta(out, 62)
        self.assertEqual(out, [gen_nav.B64[0], gen_nav.B64[62]])

    def test_a_large_delta_is_a_symbol_then_three(self):
        out = []
        gen_nav.emit_delta(out, 63 + 12345)
        self.assertEqual(len(out[0]), 4)
        self.assertEqual(out[0][0], gen_nav.B64[63])
        self.assertEqual(out[0][1:], gen_nav.enc(12345, 3))

    def test_a_negative_delta_is_refused(self):
        with self.assertRaises(AssertionError):
            gen_nav.emit_delta([], -1)


class RoadsTest(unittest.TestCase):
    def test_a_run_string_names_its_road_cells(self):
        # An off run of 10 then an on run of 3: cells 10, 11 and 12 are road.
        self.assertEqual(decode_road_runs("AKAAD/"), {10: 1.0, 11: 1.0, 12: 1.0})

    def test_a_run_keeps_its_coverage(self):
        # Off for 10, then 3 cells at coverage 1/63: faint paint is a road cell with its own coverage, as the runtime
        # reads it, not a full road.
        self.assertEqual(decode_road_runs("AKAADB"), dict.fromkeys((10, 11, 12), 1 / 63))


class RoadEntranceTest(unittest.TestCase):
    def test_a_road_crossing_gets_an_entrance_between_grid_ones(self):
        # One border, 67 crossings: the grid's runs put entrances near 9, 29, 49 and 63, but the road crosses at 10.
        c = gen_nav.CELLS
        grid = bytearray([1]) * (2 * c * c)
        u, w = (c - 1) * c + 10, c * c + 10
        with (
            patch.object(gen_nav, "CELLS", c),
            patch.object(gen_nav, "NX", 2),
            patch.object(gen_nav, "NY", 1),
            patch.object(gen_nav, "GW", 2 * c),
            patch.object(gen_nav, "GH", c),
            patch.object(gen_nav, "LINKS", defaultdict(dict)),
            patch.object(gen_nav, "LINKED_OF", defaultdict(list)),
            patch.object(gen_nav, "FLOOR_CELL", array("i")),
            patch.object(gen_nav, "ROAD_CELLS", {u: 1.0, w: 1.0}),
            patch.object(gen_nav, "BASE_Z", array("f", [0.0]) * len(grid)),
        ):
            nodes, edges = gen_nav.grid_hpa(grid, set())
        self.assertIn((u, w), edges, "the road crossing is an entrance")
        self.assertIn(u, nodes[0])
        self.assertIn(w, nodes[1])


class RoadCoveragePruneTest(unittest.TestCase):
    def test_faint_paint_does_not_prune_the_road_edge(self):
        # Entrances A, X and B on a straight lane painted at 1/63 coverage; a fully painted road bends from A to B
        # beside it. At the road factor the runtime charges the faint lane nearly the full off-road penalty, so the
        # road edge (A, B) is the only cheap way and must stay (#972). Counting faint cells as road would certify
        # A, X, B as a two-hop path at every factor and drop it.
        c = gen_nav.CELLS
        grid = bytearray(c * c)
        roads = {}
        for y in range(10, 51):
            grid[10 * c + y] = 1
            roads[10 * c + y] = 1 / 63
            grid[14 * c + y] = 1
            roads[14 * c + y] = 1.0
        for x in range(11, 14):
            for y in (10, 50):
                grid[x * c + y] = 1
                roads[x * c + y] = 1.0
        a, x, b = 10 * c + 10, 10 * c + 30, 10 * c + 50
        with (
            patch.object(gen_nav, "CELLS", c),
            patch.object(gen_nav, "NX", 1),
            patch.object(gen_nav, "NY", 1),
            patch.object(gen_nav, "GW", c),
            patch.object(gen_nav, "GH", c),
            patch.object(gen_nav, "LINKS", defaultdict(dict)),
            patch.object(gen_nav, "LINKED_OF", defaultdict(list)),
            patch.object(gen_nav, "FLOOR_CELL", array("i")),
            patch.object(gen_nav, "ROAD_CELLS", roads),
            patch.object(gen_nav, "BASE_Z", array("f", [0.0]) * len(grid)),
            patch.object(gen_nav, "_HPA", (grid, set(), {0: {a, x, b}})),
        ):
            found = gen_nav.cluster_edges(0)
        self.assertIn((a, x), found)
        self.assertIn((a, b), found, "the road edge survives faint paint beside it")


class MutualPruneTest(unittest.TestCase):
    def test_two_close_entrances_cannot_prune_each_others_edge(self):
        # A long corridor from A ends at a cell beside two entrances X and B, two cells apart. A to X and A to B cost
        # the same, and each is within the 2% prune slack of the other plus the short hop between them. Pruning
        # either against the other is fine alone, but both at once leave A with no edge to either (#1063): a
        # certificate's hops must each be shorter than the edge it prunes.
        c, length = 130, 120
        grid = bytearray(c * c)
        for y in range(0, length + 1):
            grid[10 * c + y] = 1
        for x in (9, 10, 11):
            grid[x * c + length + 1] = 1
        a, x, b = 10 * c, 9 * c + length + 1, 11 * c + length + 1
        with (
            patch.object(gen_nav, "CELLS", c),
            patch.object(gen_nav, "NX", 1),
            patch.object(gen_nav, "NY", 1),
            patch.object(gen_nav, "GW", c),
            patch.object(gen_nav, "GH", c),
            patch.object(gen_nav, "LINKS", defaultdict(dict)),
            patch.object(gen_nav, "LINKED_OF", defaultdict(list)),
            patch.object(gen_nav, "FLOOR_CELL", array("i")),
            patch.object(gen_nav, "ROAD_CELLS", {}),
            patch.object(gen_nav, "BASE_Z", array("f", [0.0]) * len(grid)),
            patch.object(gen_nav, "_HPA", (grid, set(), {0: {a, x, b}})),
        ):
            found = gen_nav.cluster_edges(0)
        self.assertTrue((a, x) in found or (a, b) in found, "A keeps an edge towards the pair")
        for edge in ((a, x), (a, b)):
            if edge in found:
                self.assertTrue(found[edge][-1], "the kept edge is a base edge")


class LinkedPortalBoxTest(unittest.TestCase):
    def test_a_steep_portal_cannot_borrow_height_outside_the_cells(self):
        c = gen_nav.CELLS
        i, j = 10 * c + 10, 11 * c + 10
        polys = {
            0: flat(0.0),
            1: {**flat(0.0), "steep": True, "plane": (85.0, 0.0, 0.0, 2.0, 0.0)},
            2: flat(8.0),
        }
        layers = {i: [(0.0, 1, (0, (83.0, 83.0)))], j: [(8.0, 1, (2, (91.0, 83.0)))]}
        # The entry touches the two-cell box near x=85, where the face is low. Its far end at x=95 is above
        # the exit, but outside the box in y: using that height invents a climb across the steep face.
        entry, exit = ((85.0, 86.0), (95.0, 100.0)), ((89.0, 82.0), (89.0, 84.0))
        portal = {(0, 1): entry, (1, 0): entry, (1, 2): exit, (2, 1): exit}
        with (
            patch.object(gen_nav, "TILES", {(0, 0): "tile"}),
            patch.object(gen_nav, "NX", 1),
            patch.object(gen_nav, "NY", 1),
            patch.object(gen_nav, "CX0", 31),
            patch.object(gen_nav, "CY0", 31),
            patch.object(gen_nav, "GW", c),
            patch.object(gen_nav, "GH", c),
            patch.object(gen_nav, "X0", 0.0),
            patch.object(gen_nav, "Y0", 0.0),
            patch.object(gen_nav, "load_window", lambda window: (polys, {0: {1}, 1: {0, 2}, 2: {1}}, portal)),
            patch.object(gen_nav, "rasterize_layers", lambda polys, adj, portal, bounds: layers),
            patch.object(gen_nav, "read_tile", lambda rc: ([], [], [], [])),
        ):
            _, _, _, _, links, own, _ = gen_nav.rasterize_tile((0, 0))
        self.assertIn(i * 4, own, "the ordinary two-way step is cut")
        uphill = [link for link in links if link[:4] == (i, 0.0, j, 8.0)]
        self.assertEqual(uphill, [], "no uphill link borrows the remote portal height")
        self.assertIn((j, 8.0, i, 0.0, "free"), links, "the downhill direction remains walkable")

    def test_a_shared_edge_outside_the_cells_does_not_link_them(self):
        # Two surfaces whose polygons meet only at a doorway far outside the two cells: the old early return counted
        # that shared edge as a path between every facing pair of cells (#890).
        c = gen_nav.CELLS
        i, j = 10 * c + 10, 10 * c + 11
        polys = {0: flat(10.0), 1: flat(10.0)}
        layers = {i: [(10.0, 1, (0, (0.0, 0.0)))], j: [(10.0, 1, (1, (0.0, 0.0)))]}
        portal = {
            (0, 1): ((1000.0, 1000.0), (1000.0, 1008.0)),
            (1, 0): ((1000.0, 1008.0), (1000.0, 1000.0)),
        }
        with (
            patch.object(gen_nav, "TILES", {(0, 0): "tile"}),
            patch.object(gen_nav, "NX", 1),
            patch.object(gen_nav, "NY", 1),
            patch.object(gen_nav, "CX0", 31),
            patch.object(gen_nav, "CY0", 31),
            patch.object(gen_nav, "GW", c),
            patch.object(gen_nav, "GH", c),
            patch.object(gen_nav, "X0", 0.0),
            patch.object(gen_nav, "Y0", 0.0),
            patch.object(gen_nav, "load_window", lambda window: (polys, {0: {1}, 1: {0}}, portal)),
            patch.object(gen_nav, "rasterize_layers", lambda polys, adj, portal, bounds: layers),
            patch.object(gen_nav, "read_tile", lambda rc: ([], [], [], [])),
        ):
            _, _, _, _, links, own, _ = gen_nav.rasterize_tile((0, 0))
        self.assertEqual(links, [], "no step is written across the doorway")
        self.assertIn(i * 4 + 1, own, "the +y step between the facing cells is cut")


if __name__ == "__main__":
    unittest.main()


class SliverTest(unittest.TestCase):
    """Map 0 tile (46, 34) poly 7089: a triangle whose float32 vertices are collinear in the horizontal plane."""

    PTS = [
        (-7565.86669921875, -1355.199951171875, 331.0),
        (-7565.33349609375, -1353.066650390625, 332.5),
        (-7566.39990234375, -1357.3333740234375, 333.0),
    ]
    BOX = (-7570.149253731344, -7562.188, -1353.233830845771, -1345.2736)

    def test_clipped_centroid_stays_inside_the_piece(self):
        piece = clip_convex([p[:2] for p in self.PTS], self.BOX)
        c = centroid(piece)
        self.assertIsNotNone(c)
        xs, ys = [p[0] for p in piece], [p[1] for p in piece]
        self.assertTrue(min(xs) - 1e-6 <= c[0] <= max(xs) + 1e-6, (c, piece))
        self.assertTrue(min(ys) - 1e-6 <= c[1] <= max(ys) + 1e-6, (c, piece))

    def test_height_stays_within_the_vertices(self):
        c = tuple(sum(p[a] for p in self.PTS) / 3 for a in range(3))
        p = {"plane": plane(self.PTS, c), "zs": (331.0, 333.0)}
        for x, y in ((-7549.0, -1350.2523148148148), (-7565.847040024495, -1355.2023423371702)):
            self.assertTrue(331.0 <= height(p, x, y) <= 333.0)

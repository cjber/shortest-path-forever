import math
import pickle
import unittest
from array import array
from collections import defaultdict
from unittest.mock import patch

from tools.baker import gen_nav
from tools.baker.gen_nav import decode_road_runs, drop_cost, pick_floor, pick_surface, walkable
from tools.baker.geometry import centroid, clip_convex, height, plane

# Include the graph cases in the existing gen_nav_test unittest entry point.
from tools.gen_nav_graph_test import ClusterCrossingTest as ClusterCrossingTest
from tools.gen_nav_graph_test import GraphLegalityTest as GraphLegalityTest


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


def square(x0, y0, side, z):
    """A square poly from (x0, y0) at height z."""
    pts = [(x0, y0, z), (x0 + side, y0, z), (x0 + side, y0 + side, z), (x0, y0 + side, z)]
    c = tuple(sum(p[a] for p in pts) / len(pts) for a in range(3))
    return {"pts": [(p[0], p[1]) for p in pts], "plane": plane(pts, c), "steep": False}


def one_cell(_x, _y):
    return [(0, 0, 0)]


class PickFloorTest(unittest.TestCase):
    def test_a_trigger_above_its_floor_finds_the_floor_under_it(self):
        # Stormwind's Sanctum trigger 702 floats 3.9 yards over the basement floor, past pick_surface's CLIMB; the
        # tower room 115 yards up is no floor of it.
        polys = {0: flat(29.6), 1: flat(148.6)}
        layers = {0: [(29.6, 1, (0, (0.0, 0.0))), (148.6, 1, (1, (0.0, 0.0)))]}
        self.assertIsNone(pick_surface(layers, polys, [(0, 0, 0)], 0.5, 0.5, 33.5))
        self.assertEqual(pick_floor(layers, polys, one_cell, 0.5, 0.5, 33.5, 7.0), (0, 0))
        self.assertEqual(pick_floor(layers, polys, one_cell, 0.5, 0.5, 151.6, 7.0), (0, 1))
        self.assertIsNone(pick_floor(layers, polys, one_cell, 0.5, 0.5, 40.0, 7.0))

    def test_the_floor_is_any_poly_under_the_trigger_not_only_the_layer_anchor(self):
        # The basement layer's anchor lies 1.8 yards from trigger 702; another poly of that floor lies under it.
        polys = {0: square(3.0, -1.0, 2.0, 29.6), 1: square(-0.5, -1.0, 2.0, 29.8), 2: flat(148.6)}
        layers = {0: [(29.6, 1, (0, (4.0, 0.5))), (148.6, 1, (2, (0.0, 0.0)))], 1: [(29.7, 1, (1, (0.5, 0.5)))]}
        self.assertEqual(pick_floor(layers, polys, lambda x, y: [(0, 0, 0), (1, 1, 0)], 0.5, 0.5, 33.5, 7.0), (0, 0))

    def test_a_trigger_over_a_hole_finds_the_floor_around_it(self):
        # Trigger 704's centre floats over the tower portal, where the navmesh has a hole; the floor beside it, inside
        # the trigger's radius, is its floor, in the cell of the floor's nearest point.
        polys = {0: square(4.0, -2.0, 4.0, 148.7), 1: square(-2.0, -2.0, 1.0, 30.0)}
        layers = {0: [(30.0, 1, (1, (0.0, 0.0)))], 1: [(148.7, 1, (0, (5.0, 0.0)))]}

        def around(x, _y):
            return [(1 if x >= 4.0 else 0, 0, 0)]

        self.assertEqual(pick_floor(layers, polys, around, 0.0, 0.0, 151.6, 7.0), (1, 0))
        self.assertIsNone(pick_floor(layers, polys, around, 0.0, 0.0, 151.6, 3.0))


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

    def test_a_tunnel_under_water_stays_a_floor(self):
        # The ruins' water lies far above the Apothecarium ramp with solid ground between: the patch leaves the ramp
        # ground, so it stays a layer under the water rather than being dropped as a lake bed (#1015).
        water = dict(self.surface(0.0, 8.0, 33.0), water=True)
        layers = self.layers({0: water, 1: self.surface(0.0, 8.0, -77.0)}, {}, {})
        self.assertEqual(sorted(z for z, _, _ in layers[0]), [-77.0, 33.0])

    def test_ground_wins_over_a_steep_face_within_a_step(self):
        # A steep sliver two yards above a ledge is not the cell's surface: as the base it left the ledge's ground no
        # way out, since steep ground is only walked down (#1015, Lord Melenas).
        polys = {0: self.surface(0.0, 8.0, 10.0), 1: self.surface(0.0, 8.0, 12.0, steep=True)}
        layers = self.layers(polys, {}, {})
        self.assertEqual([(z, v) for z, v, _ in layers[0]], [(10.0, 1)])

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
            _, _, _, _, links, own, _, _ = gen_nav.rasterize_tile((0, 0))
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
            _, _, _, _, links, own, _, _ = gen_nav.rasterize_tile((0, 0))
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
            _, _, _, _, links, own, _, _ = gen_nav.rasterize_tile((0, 0))
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
    def components(self, spots, joins=(), drops=(), tiles=None, minimum=1):
        # A street and, 40 yards under it, sealed ground with no way between them, as under Stormwind.
        def square(z):
            return [(-8800.0, 800.0, z), (-8790.0, 800.0, z), (-8790.0, 810.0, z), (-8800.0, 810.0, z)]

        polys = [(0, square(100.0), False, False), (1, square(60.0), False, False)]
        tiles = tiles or {(48, 30): (polys, list(drops))}
        with (
            patch.object(gen_nav, "TILES", dict.fromkeys(tiles, "tile")),
            patch.object(gen_nav, "BASE", {}),
            patch.object(gen_nav, "SIZE", array("i")),
            patch.object(gen_nav, "MIN_COMPONENT", minimum),
            patch.object(gen_nav, "read_tile", lambda rc: (tiles[rc][0], [], [], tiles[rc][1])),
        ):
            gen_nav.components(spots, joins)
            return list(gen_nav.SIZE)

    def test_ground_no_fixed_place_stands_on_is_dropped(self):
        self.assertEqual(self.components([(-8795.0, 805.0, 101.0)]), [1, 0])
        self.assertEqual(self.components([(-8795.0, 815.0, 58.0)]), [0, 1])

    def test_a_hop_joins_the_ground_it_lands_on(self):
        # A teleport from the street down to the sealed ground keeps that ground, as one component with the street.
        hop = ((-8795.0, 805.0, 101.0), 7.0, (-8795.0, 805.0, 60.0))
        self.assertEqual(self.components([(-8795.0, 805.0, 101.0)], [hop]), [2, 2])

    def test_a_drop_keeps_the_ground_it_lands_on_and_never_its_ledge(self):
        drop = ((-8795.0, 805.0, 100.0), (-8795.0, 805.0, 60.0))
        self.assertEqual(self.components([(-8795.0, 805.0, 101.0)], drops=[drop]), [1, 1])
        self.assertEqual(self.components([(-8795.0, 805.0, 58.0)], drops=[drop]), [0, 1])

    def test_a_drop_keeps_a_speck_only_a_place_would_lose(self):
        # Under a minimum of 2 polys the one-poly pit is a speck: no place keeps it, a drop from kept ground does, and
        # whether the walk leaves it is then the grid's question, even with a place on it.
        def half(n, z, upper):
            corner = (-8790.0, 800.0, z) if upper else (-8800.0, 810.0, z)
            return (n, [(-8800.0, 800.0, z), corner, (-8790.0, 810.0, z)], False, False)

        polys = [half(0, 100.0, True), half(1, 100.0, False), half(2, 60.0, True)]
        drop = ((-8792.0, 802.0, 100.0), (-8792.0, 802.0, 60.0))
        street, pit = (-8795.0, 803.0, 101.0), (-8792.0, 802.0, 61.0)
        for drops, spots, want in (
            ([], [street], [2, 2, 0]),
            ([drop], [street], [2, 2, 1]),
            ([drop], [street, pit], [2, 2, 1]),
        ):
            with (
                patch.object(gen_nav, "TILES", {(48, 30): "tile"}),
                patch.object(gen_nav, "BASE", {}),
                patch.object(gen_nav, "SIZE", array("i")),
                patch.object(gen_nav, "POCKET", {}),
                patch.object(gen_nav, "MIN_COMPONENT", 2),
                patch.object(gen_nav, "read_tile", lambda rc, d=drops: (polys, [(0, 1, None, None)], [], d)),
            ):
                gen_nav.components(spots)
                self.assertEqual(list(gen_nav.SIZE), want)
                self.assertEqual(list(gen_nav.POCKET), [2] if drops else [])

    def test_a_drop_landing_in_a_tile_read_before_its_ledge_counts(self):
        # The ledge's tile (48, 30) sorts after the landing's tile (47, 30), which is read first.
        lower = [(0, [(-8270.0, 800.0, 60.0), (-8260.0, 800.0, 60.0), (-8260.0, 810.0, 60.0)], False, False)]
        upper = [(0, [(-8800.0, 800.0, 100.0), (-8790.0, 800.0, 100.0), (-8790.0, 810.0, 100.0)], False, False)]
        drop = ((-8792.0, 802.0, 100.0), (-8262.0, 802.0, 60.0))
        tiles = {(47, 30): (lower, []), (48, 30): (upper, [drop])}
        self.assertEqual(self.components([(-8792.0, 802.0, 101.0)], tiles=tiles), [1, 1])

    def test_tiles_without_a_fixed_place_are_refused(self):
        with self.assertRaises(SystemExit):
            self.components([(0.0, 0.0, 0.0)])


class TrappedTest(unittest.TestCase):
    """A pocket a drop alone reaches is kept only where the grid walks out of it, as the router would."""

    def trapped(self, ground, pocket, links=()):
        heights = dict.fromkeys(ground, (1, 0.0))
        with GraphLegalityTest.world(self, heights, links=links) as (grid, _):
            return gen_nav.trapped(grid, set(), pocket)

    def test_a_pocket_with_no_step_out_is_trapped_and_one_a_step_leaves_is_not(self):
        # Kept ground at cells 0 and 1; pocket 7 (cell 1 + GH) steps onto it, pocket 8 (cell 10) has no neighbour.
        gh = gen_nav.CELLS
        drops = [(0, 10, 5.0), (1, 1 + gh, 5.0)]
        self.assertEqual(self.trapped([0, 1, 1 + gh, 10], {1 + gh: 7, 10: 8}, drops), {8})

    def test_a_pocket_left_through_another_pocket_is_not_trapped(self):
        # Pocket 8 at cell 10 drops into pocket 7 at cell 20, which steps out onto kept ground at cell 21.
        drops = [(0, 10, 5.0), (10, 20, 5.0)]
        self.assertEqual(self.trapped([0, 10, 20, 21], {10: 8, 20: 7}, drops), set())

    def test_a_pocket_whose_only_way_out_is_up_a_drop_is_trapped(self):
        # VALLEY: the drop in is one way, so standing in the pit holds no step back to the ledge.
        self.assertEqual(self.trapped([0, 10, 11], {10: 7, 11: 7}, [(0, 10, 5.0)]), {7})


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
            _, _, _, _, links, own, _, _ = gen_nav.rasterize_tile((0, 0))
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
            _, _, _, _, links, own, _, _ = gen_nav.rasterize_tile((0, 0))
        self.assertEqual(links, [], "no step is written across the doorway")
        self.assertIn(i * 4 + 1, own, "the +y step between the facing cells is cut")


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


if __name__ == "__main__":
    unittest.main()

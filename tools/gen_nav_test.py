import unittest
from array import array
from collections import defaultdict
from unittest.mock import patch

from tools.baker import gen_nav
from tools.baker.gen_nav import drop_cost, pick_surface, walkable
from tools.baker.geometry import plane


class WalkableTest(unittest.TestCase):
    def test_ground_under_liquid_is_not_walkable(self):
        triangle = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
        self.assertTrue(walkable(triangle, 0, 11, 0))
        self.assertFalse(walkable(triangle, 0x40, 11, 0))
        self.assertFalse(walkable(triangle, 0x80, 11, 0))
        self.assertFalse(walkable(triangle, 0x40 | 0x80, 11, 0))

    def test_steep_ground_is_walkable_downhill(self):
        # 50 to 61.6 degrees: the navmesh marks it steep, and its steps decide which way it may be crossed
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
            _, _, _, _, links, own, _, _, _ = gen_nav.rasterize_tile((0, 0))
        self.assertEqual(links, [])
        self.assertIn(i * 4 + 2, own, "the symmetric diagonal opens for the decoder's height check")


class SteepStepTest(unittest.TestCase):
    def test_a_steep_orthogonal_pair_keeps_its_symmetric_bit(self):
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
            _, _, _, _, links, own, _, _, _ = gen_nav.rasterize_tile((0, 0))
        self.assertEqual(links, [])
        self.assertNotIn(i * 4, own, "the steep step is not cut")

    def test_steep_step_uses_the_stored_heights(self):
        # Base heights are stored on the 2-yard grid; a floor is stored at whole yards, like gen_nav.stored_z.
        self.assertTrue(gen_nav.steep_step(20.4, 0, 18.0, 0))
        self.assertFalse(gen_nav.steep_step(18.0, 0, 20.4, 0))
        self.assertTrue(gen_nav.steep_step(20.4, 0, 20.4, 0), "equal stored heights pass both ways")
        self.assertFalse(gen_nav.steep_step(20.4, 1, 21.0, 1), "a floor uses whole yards")


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
            patch.object(gen_nav, "LINKED_OF", defaultdict(list, {0: [u]})),
            patch.object(gen_nav, "FLOOR_CELL", array("i")),
        ):
            _, edges = gen_nav.grid_hpa(grid, set())
        self.assertIn((u, w), edges)
        self.assertEqual(edges[(u, w)], edges[(w, u)], "the step keeps both directions")


class AssembleFloorsTest(unittest.TestCase):
    def test_duplicate_collapsed_links_keep_the_cheapest(self):
        c = gen_nav.CELLS
        base = array("f", [10.0] + [0.0] * (c * c - 1))
        floors = [(0, [(1, 20.0)])]
        links = [(0, 10.0, 0, 20.0, 5.0), (0, 10.0, 0, 20.0, 3.0), (0, 10.0, 0, 20.0, 4.0)]
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
        ):
            gen_nav.assemble_floors(floors, links)
            self.assertEqual(gen_nav.LINKS[0][c * c], 3.0)


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


if __name__ == "__main__":
    unittest.main()

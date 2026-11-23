import math
import unittest

from tools.baker.geometry import plane
from tools.nav_reference import Reference, funnel


class FunnelTest(unittest.TestCase):
    """String-pulling through a corridor's portals, given as (left, right) seen from the walk."""

    def test_a_straight_corridor_is_one_segment(self):
        portals = [((x, 1.0), (x, -1.0)) for x in (2.0, 4.0, 6.0)]
        self.assertEqual(funnel((0.0, 0.0), (8.0, 0.0), portals), [(0.0, 0.0), (8.0, 0.0)])

    def test_a_corner_bends_the_walk_at_its_inner_vertex(self):
        # East along y = 0 to x = 10, then north: the portals narrow to the inner corner (9, 1).
        portals = [((5.0, 1.0), (5.0, -1.0)), ((9.0, 1.0), (11.0, -1.0)), ((9.0, 5.0), (11.0, 5.0))]
        path = funnel((0.0, 0.0), (10.0, 10.0), portals)
        self.assertEqual(path, [(0.0, 0.0), (9.0, 1.0), (10.0, 10.0)])
        self.assertAlmostEqual(sum(math.dist(p, q) for p, q in zip(path, path[1:], strict=False)), 9.055 + 9.055, 2)


def mesh(polys, portals):
    """A Reference over hand-made polys: name -> (corners (x, y, z), steep); portals: (a, b) -> two ends, both ways."""
    ref = Reference.__new__(Reference)
    ref.polys, ref.adj, ref.portal, ref.drops, ref.cells = {}, {}, {}, {}, {}
    for key, (pts, steep) in polys.items():
        c = tuple(sum(p[a] for p in pts) / len(pts) for a in range(3))
        ref.polys[key] = {"pts": pts, "xy": [p[:2] for p in pts], "plane": plane(pts, c), "steep": steep}
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        for bx in range(int(min(xs) // 8), int(max(xs) // 8) + 1):
            for by in range(int(min(ys) // 8), int(max(ys) // 8) + 1):
                ref.cells.setdefault((bx, by), []).append(key)
    for (a, b), (p1, p2) in portals.items():
        ref.adj.setdefault(a, set()).add(b)
        ref.adj.setdefault(b, set()).add(a)
        ref.portal[(a, b)], ref.portal[(b, a)] = (p1, p2), (p2, p1)
    return ref


def square(x0, x1, y0, y1, z=lambda x, y: 0.0):
    return [(x, y, z(x, y)) for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1))]


class WalkTest(unittest.TestCase):
    """Reference.walk over a hand-made navmesh."""

    def setUp(self):
        # A steep face rises one yard per yard north, 0 at its south edge and 10 at its north edge. The goal is off
        # its east edge at height 9, so it is reached only by coming onto the face from above, round the west.
        self.ref = mesh(
            {
                "s": (square(0, 10, -10, 0), False),
                "w": (square(-10, 0, -10, 20, lambda x, y: 10.0), False),
                "h": (square(0, 10, 10, 20, lambda x, y: 10.0), False),
                "steep": (square(0, 10, 0, 10, lambda x, y: y), True),
                "t": (square(10, 20, 8, 10, lambda x, y: 9.0), False),
            },
            {
                ("s", "steep"): ((0, 0, 0), (10, 0, 0)),
                ("s", "w"): ((0, -10, 0), (0, 0, 0)),
                ("w", "h"): ((0, 10, 10), (0, 20, 10)),
                ("h", "steep"): ((0, 10, 10), (10, 10, 10)),
                ("steep", "t"): ((10, 8, 8), (10, 10, 10)),
            },
        )

    def test_steep_ground_entered_low_still_lets_a_higher_entry_through(self):
        # Straight up from s the face is entered at 0 and cannot be left at 9; the walk round by w and h enters it at
        # 10. Keying the search by poly alone let the cheaper low entry claim the face and the goal read unreachable.
        walk = self.ref.walk((5, -5, 0), (15, 9, 9))
        self.assertIsNotNone(walk)
        self.assertEqual(walk.polys, ["s", "w", "h", "steep", "t"])

    def test_steep_ground_is_left_only_below_its_entry(self):
        self.ref.adj["s"].discard("w")  # only the low entry is left
        self.assertIsNone(self.ref.walk((5, -5, 0), (15, 9, 9)))

    def test_a_point_far_off_the_mesh_has_no_poly(self):
        self.assertEqual(self.ref.locate((5, -5, 0)), "s")
        self.assertEqual(self.ref.locate((5, -20, 0)), "s")  # 10 yd off the mesh
        self.assertIsNone(self.ref.locate((5, -40, 0)))  # 30 yd off the mesh

    def test_a_drop_end_is_the_nearest_poly_not_the_floor_under_it(self):
        # A ledge point half a yard off its poly's outline, twenty yards above a floor whose outline holds it.
        ref = mesh(
            {"floor": (square(0, 10, 0, 10, lambda x, y: -20.0), False), "ledge": (square(0, 4.5, 0, 10), False)}, {}
        )
        self.assertEqual(ref.locate((5, 5, 0)), "floor")
        self.assertEqual(ref.nearest((5, 5, 0)), "ledge")

    def test_ends_off_the_mesh_have_no_walk(self):
        self.assertIsNone(self.ref.walk((5, -40, 0), (15, 9, 9)))
        self.assertIsNone(self.ref.walk((100000, 100000, 0), (100100, 100100, 0)))


if __name__ == "__main__":
    unittest.main()

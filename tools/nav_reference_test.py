import math
import unittest

from tools.nav_reference import funnel


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


if __name__ == "__main__":
    unittest.main()

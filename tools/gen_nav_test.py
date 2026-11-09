import unittest
from array import array
from unittest.mock import patch

from tools.baker import gen_nav
from tools.baker.gen_nav import walkable


class WalkableTest(unittest.TestCase):
    def test_ground_under_liquid_is_not_walkable(self):
        triangle = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
        self.assertTrue(walkable(triangle, 0, 11, 0))
        self.assertFalse(walkable(triangle, 0x40, 11, 0))
        self.assertFalse(walkable(triangle, 0x80, 11, 0))
        self.assertFalse(walkable(triangle, 0x40 | 0x80, 11, 0))


class ReachableTest(unittest.TestCase):
    def components(self, spots):
        # A street and, 40 yards under it, sealed ground with no way between them, as under Stormwind.
        def square(z):
            return [(-8800.0, 800.0, z), (-8790.0, 800.0, z), (-8790.0, 810.0, z), (-8800.0, 810.0, z)]

        polys = [(0, square(100.0), False), (1, square(60.0), False)]
        with (
            patch.object(gen_nav, "TILES", {(48, 30): "tile"}),
            patch.object(gen_nav, "BASE", {}),
            patch.object(gen_nav, "SIZE", array("i")),
            patch.object(gen_nav, "read_tile", lambda rc: (polys, [], [])),
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

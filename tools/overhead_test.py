"""Check height and source at walkable cells under terrain and model collision."""

import os
import unittest
from pathlib import Path
from struct import pack
from tempfile import TemporaryDirectory

from tools.baker.overhead import ClusterSurfaces


def flat_terrain(height):
    header = pack("<4s10I", b"MAPS", 10, 71037, 0, 0, 44, 16, 0, 0, 0, 0)
    return header + pack("<4sIff", b"MHGT", 1, height, height)


def model(*heights):
    vertices = [coord for z in heights for pt in [(0, 0, z), (10, 0, z), (0, 10, z)] for coord in pt]
    triangles = list(range(len(vertices) // 3))
    bih = pack("<6fII", *([0] * 8))
    return (
        b"VMAP_4.EWMOD"
        + pack("<3I", 8, 0, 0)
        + b"GMOD"
        + pack("<I6f2I", 1, *([0] * 8))
        + b"VERT"
        + pack("<II", 4 + len(vertices) * 4, len(vertices) // 3)
        + pack(f"<{len(vertices)}f", *vertices)
        + b"TRIM"
        + pack("<II", 4 + len(triangles) * 4, len(triangles) // 3)
        + pack(f"<{len(triangles)}I", *triangles)
        + b"MBIH"
        + bih
        + b"LIQU\0\0\0\0GBIH"
        + bih
    )


class OverheadTest(unittest.TestCase):
    def setUp(self):
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        self.maps = root / "maps"
        self.maps.mkdir()
        self.vmaps = root / "vmaps"
        (self.vmaps / "0000").mkdir(parents=True)
        (self.maps / "0000_32_32.map").write_bytes(flat_terrain(0))

    def build(self, *heights):
        name = b"house"
        (self.vmaps / "house.vmo").write_bytes(model(*heights))
        offset = 32 * (1600.0 / 3.0)
        spawn = pack("<2BI7fI", 0, 0, 1, offset, offset, 0, 0, 0, 0, 1, len(name))
        (self.vmaps / "0000/0000_32_32.vmtile").write_bytes(b"VMAP_4.E" + pack("<I", 1) + spawn + name)
        return ClusterSurfaces(self.maps, 0, 32, 32, 128)

    def test_building_interior(self):
        sampler = self.build(0, 7)
        self.assertEqual(sampler.above(-2, -2, 0), (7, "structure"))
        self.assertIsNone(sampler.above(-20, -20, 0))

    def test_ground_matches_source(self):
        sampler = self.build(0, 7)
        self.assertEqual(sampler.above(-2, -2, -0.1), (7, "structure"))
        self.assertIsNone(sampler.above(-20, -20, -0.1))
        self.assertEqual(sampler.above(-20, -20, -1, water=True), (0, "terrain"))

    def test_stacked_floors(self):
        sampler = self.build(0, 7, 14)
        self.assertEqual(sampler.above(-2, -2, 0), (7, "structure"))
        self.assertEqual(sampler.above(-2, -2, 7), (14, "structure"))
        self.assertIsNone(sampler.above(-2, -2, 14))

    @unittest.skipUnless(os.environ.get("NAV_MAPS"), "set NAV_MAPS to the extracted 71037 maps")
    def test_cave_witnesses(self):
        for row, col, x, y, z, upper in [
            (49, 33, -9086.57, -545.27, 62, 139.1),
            (53, 29, -11331.34, 1564.18, 28, 126.0),
        ]:
            with self.subTest(x=x, y=y):
                sampler = ClusterSurfaces(os.environ["NAV_MAPS"], 0, row, col, 128)
                height, kind = sampler.above(x, y, z)
                self.assertEqual(kind, "terrain")
                self.assertAlmostEqual(height, upper, delta=0.15)


if __name__ == "__main__":
    unittest.main()

import struct
import tempfile
import unittest
from pathlib import Path

from tools.baker.tiles import load_tile


class BakeTileTest(unittest.TestCase):
    def test_reads_detour_polygon_and_rejects_incomplete_tiles(self):
        header = struct.pack("<4s14i10f", b"VAND", 7, 0, 0, 0, 0, 1, 3, *([0] * 7), *([0.0] * 10))
        vertices = struct.pack("<9f", 10, 20, 30, 11, 20, 30, 10, 20, 31)
        polygon = struct.pack("<I6H6HHBB", 0, 0, 1, 2, 0, 0, 0, *([0] * 6), 1, 3, 11)
        payload = header + vertices + polygon
        tile = struct.pack("<4IB3x", 0x4D4D4150, 7, 16, len(payload), 1) + payload
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "0000_30_31.mmtile"
            path.write_bytes(tile)
            verts, polys = load_tile(path)
            self.assertEqual(verts[:3], (10, 20, 30))
            self.assertEqual(polys, [([0, 1, 2], [0, 0, 0], 1, 11, 0)])
            path.write_bytes(tile[:-1])
            with self.assertRaisesRegex(ValueError, "incomplete"):
                load_tile(path)
            path.write_bytes(tile[:8] + struct.pack("<I", 17) + tile[12:])
            with self.assertRaisesRegex(ValueError, "Unsupported"):
                load_tile(path)

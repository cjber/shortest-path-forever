import struct
import tempfile
import unittest

from tools.baker.terrain import (
    CELL_SIZE,
    CELLS_PER_GRID,
    HEIGHT_AS_INT8,
    HEIGHT_AS_INT16,
    NO_HEIGHT,
    Tile,
    decode_base,
    decode_sparse,
    encode_sparse,
    floor_heights,
)

MAGIC, VERSION, BUILD = b"MAPS", 10, 70862


def map_file(kind, v9, v8, grid_height=0.0, grid_max=0.0, holes=None):
    flags = {"flat": NO_HEIGHT, "int16": HEIGHT_AS_INT16, "int8": HEIGHT_AS_INT8}.get(kind, 0)
    values = b""
    if kind == "float":
        values = struct.pack(f"<{len(v9) + len(v8)}f", *v9, *v8)
    elif kind == "int16":
        values = struct.pack(f"<{len(v9) + len(v8)}H", *v9, *v8)
    elif kind == "int8":
        values = struct.pack(f"<{len(v9) + len(v8)}B", *v9, *v8)
    height = struct.pack("<4sIff", b"MHGT", flags, grid_height, grid_max) + values
    height_offset = 44
    holes_offset = height_offset + len(height) if holes else 0
    header = struct.pack(
        "<4s10I", MAGIC, VERSION, BUILD, 0, 0, height_offset, len(height), 0, 0, holes_offset, len(holes or b"")
    )
    return header + height + (holes or b"")


def hole_bitmap(row, col):
    holes = bytearray(CELLS_PER_GRID * CELLS_PER_GRID * CELL_SIZE)
    index = (row // CELL_SIZE) * CELLS_PER_GRID * CELL_SIZE + (col // CELL_SIZE) * CELL_SIZE + row % CELL_SIZE
    holes[index] |= 1 << (col % CELL_SIZE)
    return bytes(holes)


class TerrainTileTest(unittest.TestCase):
    def test_flat_tile_is_one_height(self):
        tile = Tile(map_file("flat", [], [], 7.25, 7.25), "flat")
        self.assertEqual(tile.height(0.5, 0.5), 7.25)

    def test_float_tile_interpolates_the_server_triangles(self):
        # A plane V9[i][j] = i + j, with each V8 the mean of its four corners, is exact under GridMap's triangles.
        v9 = [float(i + j) for i in range(129) for j in range(129)]
        v8 = [float(i + j + 1) for i in range(128) for j in range(128)]
        tile = Tile(map_file("float", v9, v8), "float")
        self.assertAlmostEqual(tile.height(65.5 / 128, 33.5 / 128), 99.0)

    def test_int16_and_int8_tiles_scale_between_their_bounds(self):
        tile = Tile(map_file("int16", [65535] * (129 * 129), [65535] * (128 * 128), -10.0, 10.0), "int16")
        self.assertEqual(tile.height(0.5, 0.5), 10.0)
        tile = Tile(map_file("int8", [255] * (129 * 129), [255] * (128 * 128), -10.0, 10.0), "int8")
        self.assertEqual(tile.height(0.5, 0.5), 10.0)

    def test_a_hole_has_no_terrain(self):
        tile = Tile(
            map_file("float", [0.0] * (129 * 129), [0.0] * (128 * 128), holes=hole_bitmap(64, 64)),
            "holes",
        )
        self.assertIsNone(tile.height(0.5, 0.5))
        self.assertEqual(tile.height(0.5, 0.6), 0.0)

    def test_a_missing_tile_has_no_terrain(self):
        with tempfile.TemporaryDirectory() as temporary:
            from tools.baker.terrain import Terrain

            self.assertIsNone(Terrain(temporary, 0).height(0.0, 0.0))

    def test_rejects_another_map_version(self):
        data = bytearray(map_file("flat", [], [], 1.0, 1.0))
        struct.pack_into("<I", data, 4, 9)
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            Tile(bytes(data), "old")


class TerrainEncodingTest(unittest.TestCase):
    def test_round_trip_stores_only_a_ground_that_is_a_floor(self):
        # Terrain at 16 yards (step 2): cell 0's floor is the ground, cell 1's base ties it (the tie is the base),
        # cell 2 has no floor and is left out, cell 3 has floors over no terrain, cell 4 stores its second floor.
        cells, heights, base, floors = 5, [None] * 25, [None] * 25, {}
        heights[0], base[0], floors[0] = 8, 10, [16]
        heights[1], base[1], floors[1] = 9, 10, [16, 20]
        heights[2], base[2] = 3, 10
        heights[3], base[3], floors[3] = None, 10, [16]
        heights[4], base[4], floors[4] = 19, 10, [16, 40]
        text = encode_sparse(heights, base, cells, floors)
        self.assertEqual(decode_sparse(text, base, cells), {0: 1, 3: None, 4: 2})
        self.assertEqual(decode_sparse(encode_sparse([3], [10], 1, {0: [5]}), [10], 1), {0: 1})

    def test_a_floorless_cell_and_a_base_ground_are_left_out(self):
        self.assertEqual(encode_sparse([10], [10], 1, {}), "")
        self.assertEqual(encode_sparse([2], [10], 1, {}), "")
        self.assertEqual(encode_sparse([9], [10], 1, {0: [16]}), "")
        self.assertEqual(encode_sparse([4], [None], 1, {}), "")
        self.assertEqual(decode_sparse("", [], 1), {})

    def test_a_cell_with_floors_over_no_terrain_stores_the_no_ground_marker(self):
        self.assertEqual(encode_sparse([None], [10], 1, {0: [16]}), "A/")
        self.assertEqual(decode_sparse("A/", [10], 1), {0: None})

    def test_floor_heights_read_the_floor_field(self):
        self.assertEqual(floor_heights(""), {})
        self.assertEqual(floor_heights("AABAAABBgQAAAAA"), {0: [16]})

    def test_base_heights_decode_from_the_walking_fields(self):
        self.assertEqual(decode_base("QA", "c", 2), [5, None, None, None])
        self.assertEqual(decode_base("Q", "", 1), [None])


if __name__ == "__main__":
    unittest.main()

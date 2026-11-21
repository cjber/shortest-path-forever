import unittest

from tools.gen_roads import TEXELS, cells_of, decode_trail_tile, encode, encode_trails


def painted(cells, cover):
    """A tile's texels with the given {(i, j): share} painted road, in cells_of's x-major order."""
    weights = bytearray(TEXELS * TEXELS)
    edges = [round(TEXELS * (1 - n / cells)) for n in range(cells + 1)]
    for (i, j), share in cover.items():
        rows, columns = range(edges[i + 1], edges[i]), list(range(edges[j + 1], edges[j]))
        area = len(rows) * len(columns)
        total = round(area * share)
        done = 0
        for row in rows:
            for column in columns:
                if done >= total:
                    break
                weights[row * TEXELS + column] = 255
                done += 1
    return weights


class RoadCellsTest(unittest.TestCase):
    def test_polestar_levels_and_axis_order(self):
        # Same cell twice with a falling level, then the next row (a multibyte cell delta).
        tiles = list(decode_trail_tile(rb"\005(\003\005\254\003\002"))
        self.assertEqual(tiles, [(1, 20, 1), (1, 17, 3), (128, 18, 2)])
        # Polestar advances south and east, while the walking grid advances north and west.
        self.assertEqual(encode_trails([(0, 0, 3), (128, 0, 1)], 128), "D9/gABD//gAD")

    def test_a_narrow_diagonal_road_stays_joined(self):
        # A one-cell diagonal road covers only part of each crossed cell; each painted cell must survive.
        cells = 67
        cover = {(i, i): 0.3 for i in range(10, 20)}
        road = cells_of(painted(cells, cover), cells)
        for i in range(10, 20):
            self.assertIn(i * cells + i, road)

    def test_partial_alpha_survives_without_painting_bare_ground(self):
        cells = 67
        cover = {(i, i): (0.1 + (i % 4) * 0.06) for i in range(10, 20)}
        road = cells_of(painted(cells, cover), cells)
        self.assertEqual(set(road), {i * cells + i for i in range(10, 20)})
        for (i, j), fraction in cover.items():
            self.assertAlmostEqual(road[i * cells + j] / 63, fraction, delta=1 / 63)

    def test_smallest_positive_paint_survives(self):
        weights = bytearray(TEXELS * TEXELS)
        weights[0] = 1
        self.assertEqual(cells_of(weights, 67), {66 * 67 + 66: 1})

    def test_weighted_runs_round_trip_and_split_long_runs(self):
        from tools.baker.gen_nav import decode_road_runs

        for road, count in [({10: 1, 11: 32, 12: 63}, 4489), ({}, 4489), ({4488: 63}, 4489)]:
            self.assertEqual(decode_road_runs(encode(road, count)), {cell: level / 63 for cell, level in road.items()})


if __name__ == "__main__":
    unittest.main()

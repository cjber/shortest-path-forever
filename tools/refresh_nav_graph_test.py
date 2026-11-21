import json
import sys
import unittest
from array import array
from collections import defaultdict
from contextlib import ExitStack
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from refresh_nav_graph import COMPATIBILITY, collision_compatible, decode, nav  # noqa: E402


class StoredGridTest(unittest.TestCase):
    def test_only_the_reviewed_exact_producer_transition_is_accepted(self):
        compatibility = json.loads(COMPATIBILITY.read_text())
        current = compatibility["generator"]
        for original in compatibility["collision_generators"]:
            self.assertTrue(collision_compatible(original, current))
            self.assertFalse(collision_compatible(original, "futureGraphOrGeometry"))
        self.assertTrue(collision_compatible(current, current))
        self.assertFalse(collision_compatible("unlisted", current))

    def test_missing_metadata_and_older_formats_are_rejected(self):
        fields = {name: {} for name in ("graph", "grid", "height", "floor", "terrain")}
        with self.assertRaisesRegex(ValueError, "Missing navigation metadata"):
            decode("", fields, 0)
        with self.assertRaisesRegex(ValueError, "requires format 3"):
            decode("\tformat = 2,", fields, 0)

    def test_encoded_geometry_restores_every_directed_step_and_stored_cost(self):
        state = {
            "MAP": 0,
            "CELLS": 4,
            "NX": 2,
            "NY": 1,
            "GW": 8,
            "GH": 4,
            "CX0": 0,
            "CY0": 0,
            "CS": nav.T / 4,
            "ZQ": 3,
            "BASE_Z": array("f", [3.0] * 32),
            "FLOOR_CELL": array("i"),
            "FLOOR_Z": array("f"),
            "FLOOR_VAL": bytearray(),
            "FLOOR_LAYER": bytearray(),
            "FLOORS_OF": defaultdict(list),
            "FLOORS_AT": {},
            "LINKS": defaultdict(dict),
            "LINKED_OF": defaultdict(list),
            "TERRAIN": {},
            "ROAD_CELLS": {},
        }
        with ExitStack() as stack:
            for name, value in state.items():
                stack.enter_context(patch.object(nav, name, value))
            stack.enter_context(patch.object(nav, "read_roads", return_value={}))
            grid, cuts = bytearray([1] * 32), {12 * 4, 9 * 4 + 1, 10 * 4 + 2}
            grid[0], grid[2], grid[7] = 0, 2, 3
            nav.BASE_Z[7], nav.BASE_Z[8], nav.BASE_Z[31] = 12, 6, 300
            # Two layers on both sides of the border, a same-cluster bit, a one-way floor step, and a directed drop.
            nav.assemble_floors(
                [(cell, [(1, 31), (3, 61)]) for cell in (8, 12, 16)],
                [
                    (8, 31, 12, 31, None),
                    (12, 31, 8, 31, None),
                    (12, 31, 16, 31, None),
                    (16, 31, 12, 31, None),
                    (12, 61, 16, 61, None),
                    (16, 61, 12, 31, 17.0),
                    (12, 3, 16, 3, None),
                ],
            )
            fields = {
                name: {key + 1: text for key, text in entries.items()}
                for name, entries in zip(
                    ("graph", "grid", "height", "floor", "terrain"), nav.encode_map({}, {}, grid, cuts)[:5], strict=True
                )
            }
            source = (
                "\n".join(
                    f"\t{name} = {value},"
                    for name, value in (
                        ("format", 3),
                        ("cells", 4),
                        ("nx", 2),
                        ("ny", 1),
                        ("cx0", 0),
                        ("cy0", 0),
                        ("zstep", 3),
                        ("swim", 3.0),
                    )
                )
                + "\n\tsteep = true,"
            )

            def adjacency(grid, cuts):
                g = lambda x, y: grid[x * nav.GH + y]  # noqa: E731
                return {
                    u: dict(nav.moves(g, grid, cuts, u, (0, 7, 0, 3)))
                    for u in range(len(grid) + len(nav.FLOOR_CELL))
                    if nav.value_of(grid, u)
                }

            expected = adjacency(grid, cuts)
            original_fields = deepcopy(fields)
            restored, restored_cuts = decode(source, fields, 0)
            self.assertEqual(fields, original_fields)
            self.assertEqual(restored, grid)
            self.assertEqual(restored_cuts, cuts)
            self.assertEqual(adjacency(restored, restored_cuts), expected)
            encoded = nav.encode_map({}, {}, restored, restored_cuts)
            for name, entries in zip(("grid", "height", "floor"), encoded[1:4], strict=True):
                self.assertEqual({k + 1: v for k, v in entries.items()}, fields[name])


if __name__ == "__main__":
    unittest.main()

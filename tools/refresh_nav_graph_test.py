import base64
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
from refresh_nav_graph import COMPATIBILITY, collision_compatible, decode, graph_nodes, nav  # noqa: E402


class StoredGridTest(unittest.TestCase):
    def test_only_the_reviewed_exact_producer_transition_is_accepted(self):
        compatibility = json.loads(COMPATIBILITY.read_text())
        current = compatibility["generator"]
        for original in compatibility["collision_generators"]:
            self.assertTrue(collision_compatible(original, current))
            self.assertFalse(collision_compatible(original, "futureGraphOrGeometry"))
        self.assertTrue(collision_compatible(current, current))
        self.assertFalse(collision_compatible("unlisted", current))

    def test_inspection_resolves_indexed_entrances_to_floor_nodes(self):
        raw = nav.encode_graph(4, [(5, 1, 6, 0, 0), (15, 0, 2, 0, 0)], [[], []])
        text = base64.b64encode(raw).decode("ascii").rstrip("=")
        with (
            patch.object(nav, "CELLS", 4),
            patch.object(nav, "NY", 1),
            patch.object(nav, "GH", 4),
            patch.object(nav, "FLOORS_AT", {21: [32]}),
        ):
            self.assertEqual(graph_nodes({"graph": {2: text}}, indexed=True), {1: {31, 32}})

    def test_missing_metadata_and_older_formats_are_rejected(self):
        fields = {name: {} for name in ("graph", "grid", "height", "floor", "terrain")}
        with self.assertRaisesRegex(ValueError, "Missing navigation metadata"):
            decode("", fields, 0)
        with self.assertRaisesRegex(ValueError, "requires format 3"):
            decode("\tformat = 2,", fields, 0)

    def test_format_3_restores_every_directed_step_and_stored_cost(self):
        self.assert_round_trip(3)

    def test_format_4_restores_every_directed_step_and_stored_cost(self):
        self.assert_round_trip(4)

    def assert_round_trip(self, fmt):
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
            "WET_STEPS": defaultdict(set),
            "NARROW_STEPS": defaultdict(set),
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
                [(cell, [(1, 31), (3, 61)]) for cell in (8, 12, 16)] + [(9, [(1, 30)])],
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
            if fmt == 4:
                nav.LINKS[8][nav.FLOORS_AT[9][0]] = None
                nav.LINKS[8][9] = None
                nav.LINKS[nav.FLOORS_AT[9][0]][10] = None
                nav.LINKED_OF[0].extend((8, nav.FLOORS_AT[9][0]))
                grid[7] = 1
                cuts = bytearray(32)
                cuts[9], cuts[12] = 16, 1
                nav.FLOOR_VAL = bytearray(1 if v == 3 else v for v in nav.FLOOR_VAL)
                nav.LINKS[12][nav.FLOORS_AT[16][-1]] = None
                nav.NARROW_STEPS[0].add((8, nav.FLOORS_AT[9][0]))
                nav.WET_STEPS[0].update({(12, 16), (12, nav.FLOORS_AT[16][-1])})
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
                        ("format", fmt),
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
                + ("\n\tfloorFormat = 1," if fmt == 4 else "")
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

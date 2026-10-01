"""Paid path records do not make a hidden taxi node a usable flight master."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_transit import taxis


class TaxiVisibilityTest(unittest.TestCase):
    def test_paid_paths_require_flight_map_flags(self):
        nodes = [
            {
                "ID": node,
                "Flags": 1,
                "ContinentID": 0,
                "Name_lang": name,
                "ConditionID": 0,
                "VisibilityConditionID": 0,
                "MountCreatureID_0": 0,
                "MountCreatureID_1": 541,
                "Pos_0": x,
                "Pos_1": 0,
                "Pos_2": 0,
            }
            for node, name, x in [(3275, "Powderfuse Port", 0), (3276, "Farholde Keep", 100)]
        ]
        paths = [{"ID": 11582, "FromTaxiNode": 3275, "ToTaxiNode": 3276, "Cost": 330}]
        geometry = [
            {
                "PathID": 11582,
                "NodeIndex": i,
                "Flags": 0,
                "ContinentID": 0,
                "Loc_0": x,
                "Loc_1": 0,
                "Loc_2": 0,
            }
            for i, x in enumerate([0, 100])
        ]
        for flags in [0, 4, 1024, 1, 2, 3, 1025]:
            with self.subTest(flags=flags):
                nodes[0]["Flags"] = flags
                generated, connections = taxis(nodes, paths, geometry, {})
                if flags & 3:
                    self.assertEqual(set(generated), {3275, 3276})
                    self.assertEqual([(p["from"], p["to"]) for p in connections], [(3275, 3276)])
                else:
                    self.assertEqual(generated, {})
                    self.assertEqual(connections, [])

"""Paid path records do not make a hidden taxi node a usable flight master."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_transit import LIFT_GUARDS, lift_guard_factions, taxis


class LiftGuardTest(unittest.TestCase):
    def setUp(self):
        self.templates = {npc: {"Name": name, "Faction": "104"} for npc, name, _, _ in LIFT_GUARDS.values()}
        self.spawns = {guid: {"id": str(npc), "map": str(map_id)} for npc, _, guid, map_id in LIFT_GUARDS.values()}
        self.factions = {104: {"FriendGroup": "4", "EnemyGroup": "2"}}

    def test_each_site_requires_its_exact_witness(self):
        self.assertEqual(set(lift_guard_factions(self.templates, self.spawns, self.factions).values()), {"Horde"})
        for _, _, guid, _ in LIFT_GUARDS.values():
            with self.subTest(guid=guid):
                changed = {key: dict(row) for key, row in self.spawns.items()}
                changed[guid]["id"] = "1"
                with self.assertRaisesRegex(ValueError, "landing guard witness"):
                    lift_guard_factions(self.templates, changed, self.factions)

    def test_side_comes_from_reaction_not_site_name(self):
        self.factions[104] = {"FriendGroup": "2", "EnemyGroup": "4"}
        self.assertEqual(set(lift_guard_factions(self.templates, self.spawns, self.factions).values()), {"Alliance"})
        self.factions[104] = {"FriendGroup": "0", "EnemyGroup": "0"}
        with self.assertRaisesRegex(ValueError, "unambiguous"):
            lift_guard_factions(self.templates, self.spawns, self.factions)


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

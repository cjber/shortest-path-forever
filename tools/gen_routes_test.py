"""Generator tests: walk endpoints are appended to docks without touching transport data."""

import importlib.util
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT / "tools"))
SPEC = importlib.util.spec_from_file_location("gen_routes", ROOT / "tools/gen_routes.py")
GEN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GEN)

DOCKS = [(1, -1005.64, -3841.6, 0.0), (0, -14277.7, 582.9, -0.04)]
ROUTES = {
    241: {
        "kind": "boat",
        "period": 350.818,
        "stops": [{"dock": 0, "arrive": 1.0, "depart": 2.5}, {"dock": 1, "arrive": 100.0, "depart": 110.0}],
        "frames": [
            {"arrive": 1.0, "depart": 2.5, "map": 1, "pos": (-1005.6, -3841.6), "teleport": False},
            {"arrive": 100.0, "depart": 110.0, "map": 0, "pos": (-14277.7, 582.9), "teleport": True},
        ],
    }
}
WALKS = ["{ map = 1, x = -991.0, y = -3832.8, z = 6.0 }", "nil"]


def split(text):
    """The Routes table, which carries every raw transport field."""
    return text[text.index("ns.Routes = {") :]


class RenderTests(unittest.TestCase):
    def test_walk_endpoints_leave_transport_data_unchanged(self):
        plain, walked = GEN.render(ROUTES, DOCKS), GEN.render(ROUTES, DOCKS, WALKS)
        self.assertEqual(split(plain), split(walked))
        self.assertIn("{ 1000, 2500, 1, -1005.6, -3841.6 },", split(walked))
        self.assertIn("{ 100000, 110000, 0, -14277.7, 582.9, 1 },", split(walked))
        self.assertIn("period = 350818,", split(walked))

    def test_walk_is_appended_after_the_raw_dock_position(self):
        docks = GEN.render(ROUTES, DOCKS, WALKS).split("ns.Docks = {")[1].split("\n}")[0].splitlines()
        self.assertEqual(docks[1], "\t{ map = 1, x = -1005.6, y = -3841.6, z = 0.0, walk = " + WALKS[0] + " },")
        self.assertEqual(docks[2], "\t{ map = 0, x = -14277.7, y = 582.9, z = 0.0 },")  # nil walk, -0.04 rounds to 0.0

    def test_render_without_endpoints_has_no_walk_field(self):
        text = GEN.render(ROUTES, DOCKS)
        self.assertNotIn("walk =", text)
        self.assertEqual(len(re.findall(r"^\t\{ map = ", text, re.M)), len(DOCKS))
        self.assertTrue(text.endswith("}\n"))

    def test_all_nil_endpoints_match_no_endpoints(self):
        self.assertEqual(GEN.render(ROUTES, DOCKS, ["nil", "nil"]), GEN.render(ROUTES, DOCKS))


if __name__ == "__main__":
    unittest.main()

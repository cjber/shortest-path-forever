"""Generator tests: the zone cell dump becomes one run string per column."""

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
SPEC = importlib.util.spec_from_file_location("gen_zone_cells", ROOT / "tools/gen_zone_cells.py")
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load tools/gen_zone_cells.py")
GEN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GEN)

DUMP = """noise
Z1 -2 -1 100x1 0x2
Z1 -1 -1 100x3
Z0 5 7 12x4
spf1080 zone cells done in 9 ms, 3 columns
"""


class ZoneCellsTest(unittest.TestCase):
    def test_render(self):
        text = GEN.render(GEN.parse(DUMP))
        self.assertIn('[0] = { i0 = 5, j0 = 7, columns = {\n\t\t"12 4",', text)
        self.assertIn('[1] = { i0 = -2, j0 = -1, columns = {\n\t\t"100 1 0 2",\n\t\t"100 3",', text)

    def test_gap_refused(self):
        with self.assertRaises(SystemExit):
            GEN.render(GEN.parse("Z1 0 0 1x1\nZ1 2 0 1x1\n"))


if __name__ == "__main__":
    unittest.main()

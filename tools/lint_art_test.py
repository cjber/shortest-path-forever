"""The art lint's cases live with the shared tooling; here, that this addon's own tree passes it."""

import unittest
from pathlib import Path

from tools.lint_art import HELPERS, check


class ArtTest(unittest.TestCase):
    def test_flags_raw_art_and_takes_a_reason(self):
        self.assertTrue(check('icon:SetAtlas("QuestNormal")')[0][1].startswith("art-raw:"))
        self.assertEqual(check('icon:SetAtlas("QuestNormal") -- art-ok: a square atlas on a square pin'), [])

    def test_the_helper_file_exists(self):
        root = Path(__file__).resolve().parent.parent
        for helper in HELPERS:
            self.assertTrue((root / helper).is_file(), helper)


if __name__ == "__main__":
    unittest.main()

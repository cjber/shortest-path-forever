import json
import tempfile
import unittest
from pathlib import Path

from tools.baker.inputs import complete


class BakeInputTest(unittest.TestCase):
    def test_statuses_and_files_must_match_expected_tiles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "status").mkdir()
            (root / "source.json").write_text(
                json.dumps(
                    {
                        "schema": 1,
                        "map": 0,
                        "build": "1.60.1.69913",
                        "recipe": "abc",
                        "tiles": ["0000_30_30", "0000_30_31"],
                    }
                )
            )
            (root / "0000_30_30.mmtile").write_bytes(b"fixture")
            (root / "status/0000_30_30").write_text("ok polys=12\n")
            with self.assertRaisesRegex(ValueError, "missing"):
                complete(root, 0)
            (root / "status/0000_30_31").write_text("FAILED\n")
            with self.assertRaisesRegex(ValueError, "FAILED"):
                complete(root, 0)
            (root / "status/0000_30_31").write_text("empty\n")
            self.assertEqual(complete(root, 0)["build"], "1.60.1.69913")
            (root / "0000_30_31.mmtile").write_bytes(b"stale")
            with self.assertRaisesRegex(ValueError, "disagree"):
                complete(root, 0)

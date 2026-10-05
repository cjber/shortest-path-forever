import base64
import re
import tempfile
import unittest
import zlib
from pathlib import Path

from tools.pack_nav import BLOCK_BYTES, read_map, read_packed, write_bundle


class NavigationPackingTest(unittest.TestCase):
    def source(self, root):
        directory = root / "ShortestPathForever_Nav0"
        directory.mkdir()
        path = directory / "Nav0.lua"
        path.write_text(
            "ShortestPathForeverPathData = ShortestPathForeverPathData or {}\n"
            "-- stylua: ignore\nShortestPathForeverPathData[0] = {\n"
            '\tcells = 67,\n\tgraph = {\n\t\t[1] = "AAA",\n\t},\n'
            '\tgrid = {\n\t\t[1] = "' + "ABCD" * 9000 + '",\n\t},\n'
            '\theight = {\n\t\t[1] = "EEE",\n\t},\n'
            '\tfloor = {\n\t\t[2] = "GGG",\n\t},\n}\n'
        )
        (directory / "ShortestPathForever_Nav0.toc").write_text("## LoadOnDemand: 1\n\nNav0.lua\n")
        return path

    def test_bundle_preserves_data_and_is_stable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = self.source(root)
            before = read_map(path, 0)[1]
            write_bundle(root, [path])
            bundled = root / "Nav/Nav0.lua"
            self.assertEqual(before, read_packed(bundled, 0)[1])
            for part in (root / "Nav").glob("Nav0_*.lua"):
                for block in re.findall(r'"([A-Za-z0-9+/=]+)"', part.read_text()):
                    self.assertLessEqual(len(zlib.decompress(base64.b64decode(block))), BLOCK_BYTES)
            self.assertFalse(list(root.glob("ShortestPathForever_Nav*")))
            first = {p.relative_to(root): p.read_bytes() for p in root.rglob("*") if p.is_file()}
            write_bundle(root, [bundled])
            self.assertEqual(first, {p.relative_to(root): p.read_bytes() for p in root.rglob("*") if p.is_file()})

    def test_replacing_one_map_preserves_other_maps(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = self.source(root)
            other = root / "Nav1.lua"
            other.write_text(source.read_text().replace("PathData[0]", "PathData[1]"))
            write_bundle(root, [source, other])
            before = read_packed(root / "Nav/Nav1.lua", 1)[1]
            write_bundle(root, [root / "Nav/Nav0.lua"])
            self.assertEqual(before, read_packed(root / "Nav/Nav1.lua", 1)[1])
            self.assertIn("Nav1.lua", (root / "Nav/Nav.xml").read_text())

    def test_missing_compressed_file_fails_before_repacking(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_bundle(root, [self.source(root)])
            (root / "Nav/Nav0_1.lua").unlink()
            metadata = (root / "Nav/Nav0.lua").read_bytes()
            with self.assertRaisesRegex(ValueError, "inventory"):
                write_bundle(root, [root / "Nav/Nav0.lua"])
            self.assertEqual(metadata, (root / "Nav/Nav0.lua").read_bytes())

    def test_bad_input_leaves_previous_layout_untouched(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = self.source(root)
            source = path.read_bytes()
            with self.assertRaises(ValueError):
                write_bundle(root, [path], limit=128)
            self.assertEqual(source, path.read_bytes())
            self.assertFalse((root / "Nav").exists())


if __name__ == "__main__":
    unittest.main()

import tempfile
import unittest
from pathlib import Path

from tools.pack_nav import PART_BYTES, read_map, update_package, write_map


class NavigationPackingTest(unittest.TestCase):
    def test_partition_preserves_data_and_is_stable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / "ShortestPathForever_Nav0"
            directory.mkdir()
            path = directory / "Nav0.lua"
            path.write_text(
                "ShortestPathForeverPathData = ShortestPathForeverPathData or {}\n"
                "-- stylua: ignore\nShortestPathForeverPathData[0] = {\n"
                '\tcells = 67,\n\tgraph = {\n\t\t[1] = "AAA",\n\t\t[2] = "BBB",\n\t},\n'
                '\tgrid = {\n\t\t[1] = "CCC",\n\t\t[2] = "DDD",\n\t},\n'
                '\theight = {\n\t\t[1] = "EEE",\n\t\t[2] = "FFF",\n\t},\n'
                '\tfloor = {\n\t\t[2] = "GGG",\n\t},\n}\n'
            )
            (directory / "ShortestPathForever_Nav0.toc").write_text("## LoadOnDemand: 1\n\nNav0.lua\n")
            (root / ".pkgmeta").write_text("move-folders:\n\nignore:\n  - tools\n")
            before = read_map(path, 0)[1]
            write_map(path, limit=360)
            update_package(root)
            self.assertEqual(before, read_map(path, 0)[1])
            first = {p.relative_to(root): p.read_bytes() for p in root.rglob("*") if p.is_file()}
            write_map(path, limit=360)
            update_package(root)
            second = {p.relative_to(root): p.read_bytes() for p in root.rglob("*") if p.is_file()}
            self.assertEqual(first, second)
            self.assertTrue((root / "ShortestPathForever_Nav0_2").is_dir())
            write_map(path, limit=PART_BYTES)
            self.assertFalse((root / "ShortestPathForever_Nav0_2").exists())
            self.assertEqual(before, read_map(path, 0)[1])
            self.assertIn("ShortestPathForever_Nav0_1", (root / ".pkgmeta").read_text())
            self.assertTrue(
                all(p.stat().st_size <= PART_BYTES for p in root.glob("ShortestPathForever_Nav0_*/Data.lua"))
            )
            part = root / "ShortestPathForever_Nav0_1/Data.lua"
            part.write_text(part.read_text().replace('data.graph[1] = "AAA"\n', ""))
            with self.assertRaisesRegex(ValueError, "graph inventory"):
                write_map(path)

    def test_oversized_cluster_leaves_input_untouched(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "ShortestPathForever_Nav0"
            directory.mkdir()
            path = directory / "Nav0.lua"
            source = 'ShortestPathForeverPathData[0] = {\n\tgrid = {\n\t\t[1] = "' + "A" * 1000 + '",\n\t},\n}\n'
            path.write_text(source)
            (directory / "ShortestPathForever_Nav0.toc").write_text("Nav0.lua\n")
            with self.assertRaises(ValueError):
                write_map(path, limit=400)
            self.assertEqual(source, path.read_text())


if __name__ == "__main__":
    unittest.main()

import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from tools.baker import trinity
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
            (root / "status/0000_30_31").write_text("\n")
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


class TrinityDriverTest(unittest.TestCase):
    def test_active_build_needs_exactly_one_active_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            head = "Active!DEC:1|Version!STRING:0|Product!STRING:0\n"
            (root / ".build.info").write_text(head + "1|1.60.1.70205|wow_classic_beta\n0|1.0.0.1|wow_classic_beta\n")
            self.assertEqual(trinity.active_build(root, "wow_classic_beta"), "1.60.1.70205")
            (root / ".build.info").write_text(head + "1|1.60.1.70205|wow_classic_beta\n1|1.60.1.1|wow_classic_beta\n")
            with self.assertRaisesRegex(ValueError, "one active"):
                trinity.active_build(root, "wow_classic_beta")
            with self.assertRaisesRegex(ValueError, "one active"):
                trinity.active_build(root, "wow_other")
            (root / ".build.info").write_text(head + "1|1.60.1.70205|wow_classic_beta\n" * 2)
            with self.assertRaisesRegex(ValueError, "one active"):
                trinity.active_build(root, "wow_classic_beta")

    def test_expected_tiles_are_validated(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "0000.expected"
            with self.assertRaisesRegex(ValueError, "no tile inventory"):
                trinity.expected_tiles(path, 0)
            path.write_text("0000_30_31\n0000_30_30\n")
            self.assertEqual(trinity.expected_tiles(path, 0), [(30, 30), (30, 31)])
            path.write_text("0001_30_30\n")
            with self.assertRaisesRegex(ValueError, "Invalid"):
                trinity.expected_tiles(path, 0)
            path.write_text("0000_30_30\n0000_30_30\n")
            with self.assertRaisesRegex(ValueError, "repeats"):
                trinity.expected_tiles(path, 0)

    def test_prepare_refuses_changed_or_unproven_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            manifest = {"schema": 1, "map": 0, "tiles": ["0000_30_30"]}
            (output / "mmaps/status").mkdir(parents=True)
            (output / "mmaps/status/0000_30_30").write_text("ok\n")
            with self.assertRaisesRegex(ValueError, "without source.json"):
                trinity.prepare(output, manifest)
            (output / "mmaps/status/0000_30_30").unlink()
            trinity.prepare(output, manifest)
            trinity.prepare(output, manifest)
            with self.assertRaisesRegex(ValueError, "differs"):
                trinity.prepare(output, {**manifest, "build": "other"})

    def test_missing_status_is_pending_never_empty(self):
        with tempfile.TemporaryDirectory() as directory:
            mmaps = Path(directory)
            (mmaps / "status").mkdir()
            (mmaps / "status/0000_30_30").write_text("ok polys=3\n")
            (mmaps / "status/0000_30_31").write_text("empty\n")
            (mmaps / "status/0000_30_32").write_text("FAILED\n")
            targets = [(30, 30), (30, 31), (30, 32), (30, 33)]
            self.assertEqual(trinity.pending(mmaps, targets, 0), [(30, 32), (30, 33)])

    def test_measured_stage_fails_on_nonzero_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            usage = trinity.measured(["true"], root, root / "log")
            self.assertGreaterEqual(usage["max_rss_kib"], 0)
            with self.assertRaisesRegex(RuntimeError, "exited 3"):
                trinity.measured(["sh", "-c", "exit 3"], root, root / "log")

    def test_recipe_ignores_paths_and_threads_but_keeps_binary_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            patch = root / "terrain.patch"
            patch.write_text("pinned patch")
            args = SimpleNamespace(product="wow_classic_beta", rev="pinned", patch=[patch], bin=root, threads=2)
            commands = trinity.stage_commands(args, 0)
            for name in commands:
                (root / name).write_bytes(b"binary with first build path")
            first, provenance = trinity.recipe(args, "1.60.1.70205", commands)
            args.threads = 6
            (root / "mapextractor").write_bytes(b"binary with second build path")
            second, changed = trinity.recipe(args, "1.60.1.70205", trinity.stage_commands(args, 0))
            self.assertEqual(first, second)
            self.assertNotEqual(provenance["binaries"], changed["binaries"])
            expanded = trinity.expand(commands["mmaps_generator"], root, root, root, root, args.threads)
            self.assertEqual(expanded[expanded.index("--threads") + 1], "6")
            patch.write_text("changed patch")
            self.assertNotEqual(second, trinity.recipe(args, "1.60.1.70205", commands)[0])

    def test_publish_addons_replaces_helpers_and_refuses_unrecognised_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            staged, output = root / "staged", root / "output"
            base = "ShortestPathForever_Nav0"
            (staged / base).mkdir(parents=True)
            (staged / base / "Nav0.lua").write_text("new manifest")
            (output / (base + "_2")).mkdir(parents=True)
            stale = output / (base + "_2")
            (stale / "Data.lua").write_text("old data")
            (stale / (stale.name + ".toc")).write_text("old toc")
            trinity.publish_addons(staged, output, 0)
            self.assertFalse(stale.exists())
            trinity.publish_addons(staged, output, 0)
            self.assertEqual((output / base / "Nav0.lua").read_text(), "new manifest")
            (output / base / "personal.txt").write_text("keep")
            (staged / base / "Nav0.lua").write_text("changed")
            with self.assertRaisesRegex(ValueError, "Unrecognised"):
                trinity.publish_addons(staged, output, 0)
            self.assertEqual((output / base / "Nav0.lua").read_text(), "new manifest")

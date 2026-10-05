import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from tools.baker import trinity
from tools.baker.inputs import arguments, complete, source_label
from tools.pack_nav import read_packed, write_bundle


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

    def raw(self, path, map_id, grid):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "ShortestPathForeverPathData = ShortestPathForeverPathData or {}\n"
            f"-- stylua: ignore\nShortestPathForeverPathData[{map_id}] = {{\n"
            '\tcells = 67,\n\tgraph = {\n\t\t[1] = "AAA",\n\t},\n'
            f'\tgrid = {{\n\t\t[1] = "{grid}",\n\t}},\n'
            '\theight = {\n\t\t[1] = "EEE",\n\t},\n\tfloor = {\n\t},\n}\n'
        )
        return path

    def test_bundle_is_staged_whole_before_it_replaces_the_published_one(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "output"
            write_bundle(
                output, [self.raw(root / "raw/Nav0.lua", 0, "ABCD"), self.raw(root / "raw/Nav1.lua", 1, "EFGH")]
            )
            stale = output / "Nav/Nav1_9.lua"
            stale.write_text("left by an interrupted publish")
            staged = root / "staged"
            trinity.stage_bundle(staged, output)
            self.assertFalse((staged / "Nav" / stale.name).exists())
            write_bundle(staged, [self.raw(root / "raw/Nav0.lua", 0, "IJKL")])
            self.assertEqual(read_packed(output / "Nav/Nav0.lua", 0)[1]["grid"], {1: "ABCD"})
            trinity.publish_bundle(staged, output)
            self.assertFalse(stale.exists())
            self.assertEqual(read_packed(output / "Nav/Nav0.lua", 0)[1]["grid"], {1: "IJKL"})
            self.assertEqual(read_packed(output / "Nav/Nav1.lua", 1)[1]["grid"], {1: "EFGH"})
            self.assertEqual((output / "Nav/Nav.xml").read_text().count("<Script"), 4)

    def test_bundle_publish_refuses_unrecognised_and_incomplete_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output, staged = root / "output", root / "staged"
            write_bundle(output, [self.raw(root / "raw/Nav0.lua", 0, "ABCD")])
            before = {p.name: p.read_bytes() for p in (output / "Nav").iterdir()}
            (staged / "Nav").mkdir(parents=True)
            (staged / "Nav/Nav0.lua").write_text("metadata without an index")
            with self.assertRaisesRegex(ValueError, "no Nav.xml"):
                trinity.publish_bundle(staged, output)
            (staged / "Nav/Nav.xml").write_text("<Ui/>")
            (output / "Nav/personal.txt").write_text("keep")
            for step in (trinity.publish_bundle, trinity.stage_bundle):
                with self.assertRaisesRegex(ValueError, "Unrecognised"):
                    step(staged, output)
            (output / "Nav/personal.txt").unlink()
            self.assertEqual(before, {p.name: p.read_bytes() for p in (output / "Nav").iterdir()})

    def test_source_label_uses_manifest_and_preserves_historical_default(self):
        manifest = {
            "product": "wow_classic_beta",
            "build": "1.60.1.70205",
            "recipe": "digest",
            "provenance": {"code": {"trinitycore": "pinned"}},
        }
        with patch.dict("os.environ", {}, clear=True):
            self.assertEqual(
                source_label(manifest), "local wow_classic_beta 1.60.1.70205, TrinityCore pinned, recipe digest"
            )
            self.assertIn("Mappster/DotRecast", source_label(None))
        with patch.dict("os.environ", {"NAV_SOURCE": "explicit source"}):
            self.assertEqual(source_label(manifest), "explicit source")

    def test_direct_generator_validates_an_existing_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = {"schema": 1, "map": 0, "build": "1.60.1.70205", "recipe": "digest", "tiles": ["0000_48_30"]}
            (root / "source.json").write_text(json.dumps(manifest))
            with patch("sys.argv", ["gen_nav.py", "--map", "0"]):
                with self.assertRaisesRegex(ValueError, "missing"):
                    arguments(root)
                (root / "status").mkdir()
                (root / "status/0000_48_30").write_text("empty")
                args, provenance = arguments(root)
                self.assertEqual(args.build, manifest["build"])
                self.assertEqual(provenance, manifest)

"""The type gate must cover the files the client actually loads."""

import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from tools.typecheck_coverage import main, runtime_files


class CoverageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("Addon.toc", "Core.lua\nFrames.xml\n")
        self.write("Core.lua", "local value = 1")
        self.write("Frames.xml", '<Ui><Include file="Nested.xml"/></Ui>')
        self.write("Nested.xml", '<Ui><Script file="Widget.lua"/></Ui>')
        self.write("Widget.lua", "local widget = {}")
        self.config = {
            "workspace.useGitIgnore": False,
            "workspace.ignoreDir": ["tests", "tools", ".types"],
            "workspace.preloadFileSize": 2000,
            "workspace.maxPreload": 10000,
        }

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def run_gate(self):
        self.write(".luarc.json", json.dumps(self.config))
        previous = Path.cwd()
        try:
            os.chdir(self.root)
            with contextlib.redirect_stdout(io.StringIO()):
                return main()
        finally:
            os.chdir(previous)

    def test_nested_xml_and_child_addon_are_checked(self):
        self.write("Child/Child.toc", "Child.lua")
        self.write("Child/Child.lua", "local child = {}")
        self.write(".worktrees/Other/Other.toc", "Missing.lua")
        self.assertEqual(len(runtime_files(self.root)), 3)
        self.assertEqual(self.run_gate(), 0)

    def test_missing_xml_script_fails(self):
        (self.root / "Widget.lua").unlink()
        with self.assertRaisesRegex(ValueError, "Missing runtime file"):
            self.run_gate()

    def test_excluded_runtime_file_fails(self):
        self.config["workspace.ignoreDir"] = ["Widget.lua"]
        with self.assertRaisesRegex(ValueError, "Runtime file excluded"):
            self.run_gate()

    def test_preload_limits_fail(self):
        self.config["workspace.maxPreload"] = 1
        with self.assertRaisesRegex(ValueError, "exceed workspace.maxPreload"):
            self.run_gate()
        self.config["workspace.maxPreload"] = 10000
        self.config["workspace.preloadFileSize"] = 0
        with self.assertRaisesRegex(ValueError, "exceeds workspace.preloadFileSize"):
            self.run_gate()

    def test_gitignore_cannot_hide_runtime_files(self):
        self.config["workspace.useGitIgnore"] = True
        with self.assertRaisesRegex(ValueError, "workspace.useGitIgnore=false"):
            self.run_gate()

    def test_orphaned_runtime_file_fails(self):
        self.write("Forgotten.lua", "local missing = true")
        with self.assertRaisesRegex(ValueError, "not loaded"):
            self.run_gate()

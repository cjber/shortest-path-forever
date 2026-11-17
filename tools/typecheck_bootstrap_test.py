"""Exercise concurrent annotation installation without network or LuaLS."""

import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


class BootstrapTests(unittest.TestCase):
    def test_concurrent_install_is_clean(self):
        scratch = Path.home() / ".cache/agent-scratch/spf-961"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            root = Path(directory)
            tools = root / "tools"
            tools.mkdir()
            shutil.copyfile(Path(__file__).with_name("typecheck.sh"), tools / "typecheck.sh")
            remote = root / "annotations.git"

            def git(*args):
                return subprocess.check_output(["git", *map(str, args)], text=True).strip()

            git("init", "--bare", "--quiet", remote)
            source = root / "source"
            git("init", "--quiet", source)
            (source / "annotations.lua").write_text("-- fixture\n")
            git("-C", source, "add", ".")
            git(
                "-C",
                source,
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--quiet",
                "-m",
                "fixture",
            )
            revision = git("-C", source, "rev-parse", "HEAD")
            git("-C", source, "push", "--quiet", remote, "HEAD:refs/heads/main")
            (tools / "toolchain.json").write_text(
                json.dumps({"tools": {"annotations": {"commit": revision}, "luals": {"version": "fixture"}}})
            )
            binaries = root / "bin"
            binaries.mkdir()
            real_git = shutil.which("git")
            wrapper = binaries / "git"
            wrapper.write_text(
                "#!/usr/bin/env python3\n"
                "import os, pathlib, sys, time\n"
                "root = pathlib.Path(os.environ['BOOTSTRAP_ROOT'])\n"
                "if 'fetch' in sys.argv:\n"
                "    (root / ('fetch-' + os.environ['BOOTSTRAP_ID'])).touch()\n"
                "    deadline = time.monotonic() + 15\n"
                "    while not (root / 'release').exists():\n"
                "        if time.monotonic() > deadline: sys.exit(90)\n"
                "        time.sleep(0.01)\n"
                f"os.execv({real_git!r}, [{real_git!r}, *sys.argv[1:]])\n"
            )
            wrapper.chmod(0o755)
            # Stop after real bootstrap validation, before the unrelated project gates.
            server = binaries / "lua-language-server"
            server.write_text("#!/bin/sh\necho bootstrap-complete\n")
            server.chmod(0o755)
            env = dict(
                os.environ,
                PATH=f"{binaries}:{os.environ['PATH']}",
                WOW_API_REMOTE=str(remote),
                BOOTSTRAP_ROOT=str(root),
            )
            processes = []

            def wait_for(predicate):
                deadline = time.monotonic() + 10
                while not predicate():
                    self.assertLess(time.monotonic(), deadline, "bootstrap did not reach barrier")
                    time.sleep(0.01)

            with (root / "first.log").open("w+") as first, (root / "second.log").open("w+") as second:
                try:
                    for identity, log in (("first", first), ("second", second)):
                        processes.append(
                            subprocess.Popen(
                                ["bash", "-x", "tools/typecheck.sh"],
                                cwd=root,
                                env=dict(env, BOOTSTRAP_ID=identity),
                                stdout=log,
                                stderr=log,
                            )
                        )
                        if identity == "first":
                            wait_for(lambda: (root / "fetch-first").exists())
                    # With the fix, process two blocks on flock. Before the fix, it
                    # reaches fetch, proving both processes passed the missing check.
                    wait_for(
                        lambda: (root / "fetch-second").exists() or "flock -x" in (root / "second.log").read_text()
                    )
                    (root / "release").touch()
                    for process in processes:
                        process.wait(timeout=20)
                    library = root / ".types/vscode-wow-api"
                    self.assertEqual(list(library.rglob("wow-api.*")), [])
                    self.assertEqual(git("-C", library, "status", "--porcelain"), "")
                    self.assertEqual(git("-C", library, "rev-parse", "HEAD"), revision)
                    self.assertEqual(list((root / ".types").glob("wow-api.*")), [])
                    for name in ("first", "second"):
                        log = (root / f"{name}.log").read_text()
                        self.assertIn("Install lua-language-server fixture to match CI.", log)
                finally:
                    (root / "release").touch()
                    for process in processes:
                        if process.poll() is None:
                            process.kill()
                        process.wait()


if __name__ == "__main__":
    unittest.main()

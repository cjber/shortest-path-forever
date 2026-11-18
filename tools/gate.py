#!/usr/bin/env python3
"""The fast local gate: the CI checks that need no packager, game build or network, and nothing else.

    python3 tools/gate.py             # every step
    python3 tools/gate.py --changed   # only the steps the diff against origin/main reaches; tools/ reaches all

Every step runs even after one fails, as in CI, and the exit status is 1 when any failed. The specs load ForeverCore
from $FOREVER_CORE, else the sibling ../forever-core checkout; set it when working from a worktree. The simulator,
package, workflow and secret jobs stay in CI.
"""

import argparse
import fnmatch
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UV = ("uv", "run", "--project", "tools", "--frozen", "--group", "dev")
LUA = ("*.lua", "*.toc", "*.xml")


@dataclass(frozen=True)
class Step:
    name: str
    argv: tuple[str, ...]
    # fnmatch patterns over changed paths ("*" crosses folders); empty means the step runs for any change.
    reaches: tuple[str, ...] = ()


STEPS = (
    Step("stylua", ("stylua", "--check", "."), ("*.lua", "stylua.toml", ".styluaignore")),
    Step("luacheck", ("luacheck", "."), ("*.lua", ".luacheckrc")),
    Step(
        "typecheck",
        ("bash", "tools/typecheck.sh"),
        LUA
        + (
            "types/*",
            "Locales/*",
            "docs/*",
            "README.md",
            ".luarc.json",
            ".editorconfig",
            "stylua.toml",
            "ruff.toml",
            ".pkgmeta",
        ),
    ),
    Step("specs", ("python3", "-m", "tools.forever_tools.specs"), LUA),
    Step("deadcode", ("python3", "tools/deadcode.py", "--check"), LUA),
    Step("ruff check", (*UV, "ruff", "check", "."), ("*.py", "ruff.toml", "tools/pyproject.toml")),
    Step("ruff format", (*UV, "ruff", "format", "--check", "."), ("*.py", "ruff.toml", "tools/pyproject.toml")),
    Step(
        "assets",
        ("python3", "-m", "tools.forever_tools.assets"),
        LUA + ("media/*", "*.png", "*.tga", "*.blp", ".pkgmeta"),
    ),
    Step(
        "changelog",
        ("python3", "tools/changelog.py", "--check", "--base", "origin/main"),
        ("CHANGELOG.md", "changes/*", "tools/changelog.py"),
    ),
    Step(
        "credits",
        ("python3", "tools/forever_tools/credits.py", "--check"),
        ("THIRD_PARTY.md", "README.md", "docs/curseforge.md", "Data/Credits.lua"),
    ),
    Step("api docs", ("python3", "tools/check_api_docs.py"), ("*API*.lua", "docs/api.md")),
    Step("menu scroll", ("python3", "tools/check_menu_scroll.py"), LUA),
    Step("screenshots", ("python3", "tools/check_screenshots.py")),
    Step(
        "generated", ("python3", "tools/check_generated.py", "--offline"), ("Data/*", "Nav/*", "media/*", "Locales/*")
    ),
    Step("nav", ("python3", "tools/check_nav.py"), ("Data/*", "Nav/*", "media/*", "Locales/*")),
    Step("repo rules", ("python3", "tools/repo_rules.py", "--base", "origin/main")),
)


def git(*args: str) -> list[str]:
    done = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True)
    return done.stdout.split("\n") if done.stdout else []


def changed_paths(base: str) -> set[str]:
    merge_base = git("merge-base", base, "HEAD")[0]
    paths = git("diff", "--name-only", merge_base) + git("ls-files", "--others", "--exclude-standard")
    return {path for path in paths if path}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--changed", action="store_true", help="run only the steps the diff against --base reaches")
    parser.add_argument("--base", default="origin/main", help="the branch to diff against (default: origin/main)")
    args = parser.parse_args()
    env = dict(os.environ)
    core = Path(env.get("FOREVER_CORE") or ROOT.parent / "forever-core")
    if not core.is_dir():
        print(
            f"ForeverCore checkout not found at {core}: set FOREVER_CORE to a cjber/forever-core checkout",
            file=sys.stderr,
        )
        return 2
    env["FOREVER_CORE"] = str(core)
    changed = changed_paths(args.base) if args.changed else set()
    # A change under tools/ can alter any check, so it reaches every step.
    everything = not args.changed or any(path.startswith("tools/") for path in changed)
    failed: list[str] = []
    for step in STEPS:
        if not everything and step.reaches and not any(fnmatch.fnmatch(p, g) for p in changed for g in step.reaches):
            print(f"-- {step.name}: skipped, the diff does not reach it", flush=True)
            continue
        print(f"== {step.name}: {' '.join(step.argv)}", flush=True)
        started = time.monotonic()
        code = subprocess.run(step.argv, cwd=ROOT, env=env, stdin=subprocess.DEVNULL).returncode
        print(
            f"== {step.name}: {'ok' if code == 0 else f'FAILED (exit {code})'} in {time.monotonic() - started:.1f}s",
            flush=True,
        )
        if code != 0:
            failed.append(step.name)
    if failed:
        print("Failed: " + ", ".join(failed), file=sys.stderr)
        return 1
    print("Gate passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

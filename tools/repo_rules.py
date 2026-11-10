#!/usr/bin/env python3
"""Check the rules this repository holds that no linter covers. CI runs it in the `project-rules` job.

- `file-size-no-growth`: a change may not add a file over LIMIT lines, or grow one that is already over it. Split
  the file along its responsibilities first, or put the new code in a new file. A file that is one unit by design
  says why in its first lines: `rule-ignore: file-size-no-growth - <reason of three words or more>`.
"""

import argparse
import fnmatch
import re
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULE = "file-size-no-growth"
LIMIT = 1000
MARKER_LINES = 5
MARKER = re.compile(rf"rule-ignore:\s*{RULE}\s+-\s+(\S+(?:\s+\S+){{2,}})")
EXCLUDE = (
    "*.lock",
    "*-lock.json",
    "*-lock.yaml",
    "Data/*.lua",
    "Nav/*.lua",
    # Byte-for-byte producer code, verified by tools/forever_sim/sync.py check in CI.
    "tools/forever_sim/*",
    # Byte-for-byte producer tooling and its pinned-build data, verified by tools/forever_tools/sync.py check in CI.
    "tools/forever_tools/*",
)


def lines(data: bytes | None) -> list[bytes] | None:
    """The file's lines, or None for a binary or missing file."""
    return None if data is None or b"\0" in data else data.splitlines()


def oversize_growth(
    rows: list[tuple[str, str, str]], head: Callable[[str], bytes | None], base: Callable[[str], bytes | None]
) -> list[str]:
    """Each (status, old path, new path) row whose new file is over LIMIT and longer than its base."""
    hits = []
    for status, old, new in rows:
        if status == "D" or any(fnmatch.fnmatch(new, pattern) for pattern in EXCLUDE):
            continue
        after = lines(head(new))
        if after is None or len(after) <= LIMIT:
            continue
        if any(MARKER.search(line.decode("utf-8", "replace")) for line in after[:MARKER_LINES]):
            continue
        before = len(lines(base(old)) or [])
        if len(after) > before:
            hits.append(f"{new}:1: {RULE}: grew from {before} to {len(after)} lines, over the {LIMIT}-line limit")
    return hits


def git(*args: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, check=False)


def changed(merge_base: str) -> list[tuple[str, str, str]]:
    fields = git("diff", "-z", "--name-status", "-M", merge_base).stdout.decode().split("\0")
    rows, i = [], 0
    while i < len(fields) - 1:
        status = fields[i][0]
        if status in "RC":
            rows.append((status, fields[i + 1], fields[i + 2]))
            i += 3
        else:
            rows.append((status, fields[i + 1], fields[i + 1]))
            i += 2
    return rows


def read_head(path: str) -> bytes | None:
    file = ROOT / path
    return file.read_bytes() if file.is_file() else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="origin/main", help="the branch this change merges into")
    args = parser.parse_args()
    result = git("merge-base", args.base, "HEAD")
    if result.returncode:
        sys.exit(f"no merge base with {args.base}: {result.stderr.decode().strip()}")
    merge_base = result.stdout.decode().strip()

    def read_base(path: str) -> bytes | None:
        shown = git("show", f"{merge_base}:{path}")
        return shown.stdout if shown.returncode == 0 else None

    hits = oversize_growth(changed(merge_base), read_head, read_base)
    for hit in hits:
        print(hit)
    return int(bool(hits))


if __name__ == "__main__":
    sys.exit(main())

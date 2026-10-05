"""Reject art drawn outside the Art helpers, where nothing keeps its shape (forever_tools.art)."""

import argparse
import sys
from pathlib import Path

try:
    from tools.forever_tools import art
    from tools.typecheck_coverage import runtime_files
except ModuleNotFoundError:
    from forever_tools import art
    from typecheck_coverage import runtime_files

# The one file that may set art: every helper in it is under spec (tests/art_spec.lua).
HELPERS = frozenset({"UI/Art.lua"})
check = art.check
__all__ = ["HELPERS", "check", "main"]


def main() -> int:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("files", nargs="*", type=Path)
    root = Path(__file__).resolve().parent.parent
    files = args.parse_args().files or [*runtime_files(root), *(root / "UI").rglob("*.xml")]
    return art.run(root, files, HELPERS)


if __name__ == "__main__":
    sys.exit(main())

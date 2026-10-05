"""Reject accidental expansion of select() in Lua 5.1 expression lists."""

import argparse
import sys
from pathlib import Path

try:
    from tools.forever_tools import multivalue
    from tools.forever_tools.lua import LuaSyntaxError
    from tools.typecheck_coverage import runtime_files
except ModuleNotFoundError:
    from forever_tools import multivalue
    from forever_tools.lua import LuaSyntaxError
    from typecheck_coverage import runtime_files

check = multivalue.check
__all__ = ["LuaSyntaxError", "check", "main", "runtime_files"]


def main() -> int:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("files", nargs="*", type=Path)
    paths = args.parse_args().files or runtime_files(Path(__file__).resolve().parent.parent)
    return multivalue.run(paths)


if __name__ == "__main__":
    sys.exit(main())

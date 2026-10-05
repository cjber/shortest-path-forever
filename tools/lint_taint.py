"""Reject addon code that writes into or hooks Blizzard's objects, or runs Blizzard code whose state it would taint.

See AGENTS.md for the ways to hook that stay clean; the rules live in `tools/forever_tools/taint.py`.
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import taint
    from tools.typecheck_coverage import runtime_files
except ModuleNotFoundError:
    from forever_tools import taint
    from typecheck_coverage import runtime_files

check = taint.check


def main() -> int:
    return taint.run([Path(arg) for arg in sys.argv[1:]] or runtime_files(Path.cwd().resolve()))


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Reject unguarded reads of values the client may keep secret, and tooltip hooks that touch a forbidden tooltip
(forever_tools.readable). Read them through `ns.Readable`; start a tooltip hook with `if not ns.Usable(tooltip)`.
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import readable as secret
    from tools.typecheck_coverage import runtime_files
except ModuleNotFoundError:
    from forever_tools import readable as secret
    from typecheck_coverage import runtime_files

POLICY = secret.DEFAULT_POLICY
check = secret.check


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    return secret.run([Path(arg) for arg in sys.argv[1:]] or runtime_files(root), POLICY)


if __name__ == "__main__":
    sys.exit(main())

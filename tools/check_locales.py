#!/usr/bin/env python3
"""Check every Locales/<locale>.lua against Locales/phrases.txt (forever_tools.locales, WFA-34) and print each
locale's coverage. A gap falls back to English and only fails with --release.

python3 tools/check_locales.py             # in typecheck.sh
python3 tools/check_locales.py --release   # release prep: every shipped locale at 100%
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import locales
except ModuleNotFoundError:
    from forever_tools import locales


if __name__ == "__main__":
    sys.exit(locales.main(Path(__file__).resolve().parent.parent))

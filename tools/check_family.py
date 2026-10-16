#!/usr/bin/env python3
"""Check the shared Forever family block in README.md and docs/curseforge.md (forever_tools.family).

python3 tools/check_family.py          # check both files
python3 tools/check_family.py --fix    # rewrite the text between the markers after a sync
python3 tools/check_family.py --print  # print the block
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import family
except ModuleNotFoundError:
    from forever_tools import family


if __name__ == "__main__":
    sys.exit(family.main(Path(__file__).resolve().parent.parent))

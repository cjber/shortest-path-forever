#!/usr/bin/env python3
"""Check docs/curseforge.md against the forever-core store page template (forever_tools.store_page, WFA-11).

python3 tools/check_store_page.py          # check the page
python3 tools/check_store_page.py --words  # also print its prose word count
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import store_page
except ModuleNotFoundError:
    from forever_tools import store_page


if __name__ == "__main__":
    sys.exit(store_page.main(Path(__file__).resolve().parent.parent))

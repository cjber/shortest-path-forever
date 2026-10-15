#!/usr/bin/env python3
"""Check .editorconfig against the family template, stylua.toml and ruff.toml (forever_tools.editorconfig).

python3 tools/check_editorconfig.py
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import editorconfig
except ModuleNotFoundError:
    from forever_tools import editorconfig


if __name__ == "__main__":
    sys.exit(editorconfig.main(Path(__file__).resolve().parent.parent))

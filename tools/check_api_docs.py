#!/usr/bin/env python3
"""Check docs/api.md names every function Core/API.lua publishes and its minor version.

The shared implementation is `tools/forever_tools/docs_contract.py`.
"""

from pathlib import Path

try:
    from tools.forever_tools.docs_contract import main
except ModuleNotFoundError:
    from forever_tools.docs_contract import main

if __name__ == "__main__":
    raise SystemExit(main(Path(__file__).resolve().parent.parent))

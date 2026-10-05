#!/usr/bin/env python3
"""Print one version's CHANGELOG.md section, or check that every release has one (stdlib only).

    python3 tools/changelog.py 0.2.0           # that version's entry (a leading v is fine)
    python3 tools/changelog.py --check         # every v* tag has an entry, and Unreleased is there
    python3 tools/changelog.py --check 0.3.0   # that version has an entry, before it is tagged

The shared implementation is `tools/forever_tools/changelog.py`.
"""

from pathlib import Path

try:
    from tools.forever_tools.changelog import main
except ModuleNotFoundError:
    from forever_tools.changelog import main

if __name__ == "__main__":
    main(Path(__file__).resolve().parent.parent)

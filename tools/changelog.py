#!/usr/bin/env python3
"""Print one version's CHANGELOG.md section, write a release from changes/*.md, or check the changelog (stdlib only).

    python3 tools/changelog.py 0.2.0                      # that version's entry (a leading v is fine)
    python3 tools/changelog.py unreleased                 # the pending changes/*.md notes, without a heading
    python3 tools/changelog.py release 0.3.0              # write that section from changes/*.md, deleting them
    python3 tools/changelog.py fragment 123               # move an old ## [Unreleased] section into changes/123.md
    python3 tools/changelog.py --check                    # every v* tag has an entry, and every fragment is well formed
    python3 tools/changelog.py --check 0.3.0              # that version has an entry and no fragment is left
    python3 tools/changelog.py --check --base origin/main # a pull request adds only whole new release sections

The shared implementation is `tools/forever_tools/changelog.py`.
"""

from pathlib import Path

try:
    from tools.forever_tools.changelog import main
except ModuleNotFoundError:
    from forever_tools.changelog import main

if __name__ == "__main__":
    main(Path(__file__).resolve().parent.parent)

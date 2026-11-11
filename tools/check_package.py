#!/usr/bin/env python3
"""Check the packager's output before an upload (forever_tools.package): every file the TOC and XML load ships,
nothing from development does, a licence file and THIRD_PARTY.md do (with README's `## Credits` and THIRD_PARTY's
`## Ideas and contributors`, WFA-10 and WFA-31), and the smoke and core dependency specs pass on the packaged
files.

    printf 'Package check\\n' > .release-notes.md
    <BigWigs packager release.sh> -d -z    # CI: the package job, with the release workflow's pinned packager
    python3 tools/check_package.py
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import package
except ModuleNotFoundError:
    from forever_tools import package

ROOT = Path(__file__).resolve().parent.parent
# The smoke spec fetches the pinned Blizzard UI fixture with tools/fetch_blizzard_ui.sh on first run.
POLICY = package.Policy(
    addons=("ShortestPathForever", "ForeverCore"),
    specs=("tests/smoke_spec.lua", "tests/core_dependency_spec.lua"),
    support=("tests", "tools/fetch_blizzard_ui.sh", "tools/forever_sim/toc.lua"),
)

if __name__ == "__main__":
    sys.exit(package.main(ROOT, POLICY))

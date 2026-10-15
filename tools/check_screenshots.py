#!/usr/bin/env python3
"""Fail when a screenshot is older than what it shows (WFA-9, forever_tools.screens).

tools/screenshots.py draws every scene itself from wowmock, and runs the addon's planner, paths and flight lines
under LuaJIT for the routes it draws. Each image's dump is those files' hashes, so a change to any of them needs a
fresh render. Generated `Data/` is left out: the daily data refresh moves it and cannot render, and the release re-
renders every image (the release skill). docs/screenshots/scenes.sha256 holds each image's hash beside its dump's;
After a render, `--record` rewrites it (with `--force` for an image that came out the same).

    python3 tools/check_screenshots.py           # CI: fail on a stale image
    python3 tools/check_screenshots.py --record  # after tools/screenshots.py renders
"""

import functools
import sys
from pathlib import Path

try:
    from tools.forever_tools import screens
except ModuleNotFoundError:
    from forever_tools import screens

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/screenshots"
SOURCES = (
    "Locales/enUS.lua",
    "tools/screenshots*.py",
    "tools/load_nav.lua",
    "Transport/Model.lua",
    "Routing/*.lua",
    "UI/FlightLines.lua",
    "UI/Arrow.lua",
    "media/zeppelin.tga",
)
SCENES = {
    path.name: functools.partial(screens.files, ROOT, SOURCES)
    for pattern in screens.IMAGES
    for path in sorted(OUT.glob(pattern))
}


if __name__ == "__main__":
    sys.exit(screens.main(OUT, SCENES))

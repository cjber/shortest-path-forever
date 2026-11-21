#!/usr/bin/env python3
"""Fail when a screenshot is older than what it shows (WFA-9, forever_tools.screens).

tools/screenshots.py draws every scene itself from wowmock, and runs the addon's planner, paths and flight lines
under LuaJIT for the routes it draws. Each image's dump is the hashes of the files that image is drawn from: the
shared render code, its own render module, and the planner sources when it draws a route. A change to one of them
needs a fresh render of only the images that read it. Generated `Data/` is left out: the daily data refresh moves it
and cannot render, and the release re-renders every image (the release skill). Each image's record is
docs/screenshots/scenes/<image>.sha256. After a render, `--record` rewrites them (with `--force` for an image that
came out the same).

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
# Imported by tools/screenshots.py for every scene.
SHARED = (
    "Locales/enUS.lua",
    "tools/screenshots.py",
    "tools/screenshots_art.py",
    "tools/screenshots_maps.py",
    "tools/screenshot_docks.py",
)
# What tools/screenshots.py data() runs under LuaJIT for the routes, docks and stops it draws.
PLANNER = (
    "tools/load_nav.lua",
    "Transport/Model.lua",
    "Routing/PathGrid.lua",
    "Routing/Path.lua",
    "Routing/Planner.lua",
    "Routing/LegPoints.lua",
    "UI/FlightLines.lua",
)
TRACKER = ("tools/screenshots_tracker.py", *PLANNER)
SERVICES = ("tools/screenshots_services.py",)
TOWN = ("tools/screenshots_town.py", "media/TownGroup.tga")
SOURCES = {
    "arrival.png": ("tools/screenshots_arrival.py",),
    "cast_prompt.png": ("UI/Arrow.lua",),
    "compass.png": (),
    "compass_behind.png": (),
    "darkshore.png": PLANNER,
    "demo.gif": PLANNER,
    "detached.png": TRACKER,
    "docks.png": PLANNER,
    "flight.png": PLANNER,
    "floors.png": ("tools/screenshots_floors.py",),
    "kalimdor.png": PLANNER,
    "minimap.png": PLANNER,
    "services.png": SERVICES,
    "services_better.png": SERVICES,
    "services_filters.png": SERVICES,
    "services_roles.png": SERVICES,
    "services_search.png": SERVICES,
    "services_transmog.png": SERVICES,
    "stops.png": PLANNER,
    "town_services.png": TOWN,
    "town_services_zoom.png": TOWN,
    "tracker.png": TRACKER,
}
SCENES = {name: functools.partial(screens.files, ROOT, (*SHARED, *sources)) for name, sources in SOURCES.items()}


if __name__ == "__main__":
    sys.exit(screens.main(OUT, SCENES))

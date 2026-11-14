"""The step and dock art shared with tools/screenshots.py.

Zeppelins stopped borrowing Blizzard's ferry atlas, so the mock renderer reads the same
media file the addon ships. The numbered markers are ForeverCore's, so they come from the
shared checkout. Kept beside screenshots.py so that file stays under its line limit.
"""

import os
from functools import cache
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
# The checkout the markers render from, the same FOREVER_CORE tools/screenshots.py selects.
FOREVER_CORE = Path(os.environ.get("FOREVER_CORE", ROOT.parent / "forever-core")).expanduser()


@cache
def zeppelin_art():
    """The addon's own zeppelin icon, media/Zeppelin.tga."""
    with Image.open(ROOT / "media" / "Zeppelin.tga") as source:
        return source.convert("RGBA")


@cache
def pin_art():
    """The addon's own gold goal pin, media/Pin.tga, square with the point at its bottom centre."""
    with Image.open(ROOT / "media" / "Pin.tga") as source:
        return source.convert("RGBA")


@cache
def number_art(number):
    """ForeverCore's numbered step marker, media/Numbers/<number>.tga in its checkout: a square gold ring."""
    with Image.open(FOREVER_CORE / "media" / "Numbers" / f"{number}.tga") as source:
        return source.convert("RGBA")


def dock_kinds(routes):
    """Dock id to route kind, the lookup ns.DockKind serves in game."""
    return {int(stop["dock"]): route["kind"] for route in routes.values() for stop in route["stops"].values()}

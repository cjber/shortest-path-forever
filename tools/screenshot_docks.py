"""The addon's own dock art, shared with tools/screenshots.py.

Zeppelins stopped borrowing Blizzard's ferry atlas, so the mock renderer reads the same
media file the addon ships. Kept beside screenshots.py so that file stays under its
line limit.
"""

from functools import cache
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


@cache
def zeppelin_art():
    """The addon's own zeppelin icon, media/Zeppelin.tga."""
    with Image.open(ROOT / "media" / "Zeppelin.tga") as source:
        return source.convert("RGBA")


def dock_kinds(routes):
    """Dock id to route kind, the lookup ns.DockKind serves in game."""
    return {int(stop["dock"]): route["kind"] for route in routes.values() for stop in route["stops"].values()}

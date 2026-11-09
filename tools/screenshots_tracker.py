"""The Journey tracker scene and the shared tracker grip from UI/TrackerHost.lua."""

import math

from screenshot_docks import pin_art
from wowmock import DISABLED, FONTS, TrackerBlock, TrackerModule, colored, objective_tracker, scene


def countdown(seconds):
    return f"{max(0, seconds) // 60}:{max(0, seconds) % 60:02d}"


def tracker_canvas(ui, dock_title, seconds=0):
    # Reference 21 is a captured itinerary, not a new optimality claim for these timings.
    # UI/Tracker.lua's ICON_SIZE: each mode's mark is 12 units high, at the atlas's native shape, and stands in the
    # dash column, so the text and its wrapped lines hang after it. The place wears the header gold and the time the
    # client's grey, as the addon's own rows do.
    gold = ui.global_color("OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR")[:3]
    assert FONTS["ObjectiveTrackerLineFont"].height == 12

    def mark(atlas):
        art = ui.atlas(atlas)
        width = max(1, math.floor(12 * art.width / art.height + 0.5))
        return f"|A:{atlas}:12:{width}|a"

    def row(atlas, verb, place, detail):
        return (f"{verb} {colored(place, gold)}   {colored(detail, DISABLED)}", f"{mark(atlas)} ")

    rows = [
        row("poi-traveldirections-arrow", "Walk to", dock_title(10), countdown(120 - seconds)),
        row("flightmasterferry", "Boat to", "Wetlands", "leaves in 2:28 · 1:20"),
        row("poi-traveldirections-arrow", "Walk to", dock_title(5), "1:31"),
        row("flightmasterferry", "Boat to", "Dustwallow Marsh", "leaves in about 2:45 · 1:44"),
        row("poi-traveldirections-arrow", "Walk to", "Silithus", "33:02"),
    ]
    # UI/Art.lua's FileMarkup for the goal pin, whose addon media the shared renderer cannot look up; hand it the
    # addon's own square pin while the tracker measures and draws.
    pin = "Interface\\AddOns\\ShortestPathForever\\media\\Pin"
    module = TrackerModule(
        f"Journey  {countdown(2687 - seconds)} · 9.2k yd",
        [TrackerBlock(f"|T{pin}:12:12|t Journey to " + colored("Silithus", gold), rows)],
    )
    texture = ui.texture

    def addon_texture(ref):
        if isinstance(ref, str) and "shortestpathforever/media/pin" in ref.lower().replace("\\", "/"):
            return pin_art()
        return texture(ref)

    ui.texture = addon_texture
    try:
        canvas, _ = objective_tracker(ui, [module], container=False)
    finally:
        ui.texture = texture
    return canvas


def detached_tracker(ui, tracker):
    column = ui.canvas(tracker.width, tracker.height + 24)
    column.text(0, 12, "Forever tracker", FONTS["GameFontNormal"], justify="CENTER", width=tracker.width)
    column.paste(tracker, 0, 24)
    return scene(ui, [(column, 0, 0)])

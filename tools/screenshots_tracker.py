"""The shared tracker grip from UI/TrackerHost.lua."""

from wowmock import FONTS, scene


def detached_tracker(ui, tracker):
    column = ui.canvas(tracker.width, tracker.height + 24)
    column.text(0, 12, "Forever tracker", FONTS["GameFontNormal"], justify="CENTER", width=tracker.width)
    column.paste(tracker, 0, 24)
    return scene(ui, [(column, 0, 0)])

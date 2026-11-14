"""The world map frame and its native-aspect icons, shared by the map scenes."""

from functools import cache

from wowmock import draw_overlay, map_art, map_overlays, world_map_frame  # ty: ignore[import-not-found]

MAP_NAMES = {
    947: ("World",),
    1414: ("World", "Kalimdor"),
    1439: ("World", "Kalimdor", "Darkshore"),
    1429: ("World", "Eastern Kingdoms", "Elwynn Forest"),
    1436: ("World", "Eastern Kingdoms", "Westfall"),
    1432: ("World", "Eastern Kingdoms", "Loch Modan"),
    1453: ("World", "Eastern Kingdoms", "Stormwind City"),
}


def icon(canvas, name, x, y, size=None, alpha=1):
    """One client atlas at its native shape, centred on x, y: Art.Fit with no box to fit inside."""
    art = canvas.ui.atlas(name)
    factor = size / max(art.width, art.height) if size else 1
    w, h = art.width * factor, art.height * factor
    canvas.draw(art, x - w / 2, y - h / 2, w, h, (1, 1, 1, alpha))


@cache
def map_base(ui, map_id):
    """The map frame with its map art and overlays, and where the map area sits in it."""
    art = map_art(ui.data, map_id)
    for overlay in map_overlays(ui.data, map_id):
        draw_overlay(ui.data, art, overlay.offset_x, overlay.offset_y, overlay.width, overlay.height, overlay.tiles)
    names = MAP_NAMES[map_id]
    return world_map_frame(ui, art, names, arrows=names[1:])

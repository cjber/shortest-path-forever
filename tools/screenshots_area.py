"""A held objective area outlined on the world map in Strokes.lua's own yellow.

The area belongs to the addon that named it, so Route.lua draws the outline in place of the journey while the
player stands inside. The centre is a real QuestPOIBlob on Elwynn Forest; the radius is a chosen scene fixture,
because the area's size comes from the addon that named it. The client's own minimap blob is not mocked.
"""

import math

from wowmock import scene

AREA_COLOR = (1, 0.82, 0.25)
AREA_POINT = {"map": 0, "x": -8808.0, "y": 328.0}
AREA_RADIUS = 140
MAP_ID = 1429


def render(ui, map_frame, project, line, flush, landmarks, icon):
    """Elwynn Forest, standing inside a guide's objective area. Cropped to the area."""
    base, rects = map_frame(ui, MAP_ID)
    canvas = ui.canvas(base.width, base.height)
    canvas.image = base.image.copy()
    mx, my, mw, mh = rects["map"]
    route = ui.canvas(mw, mh)

    def point(p):
        normal = project(ui, p, MAP_ID)
        return (normal[0] * mw, normal[1] * mh)

    cx, cy = point(AREA_POINT)
    # World x runs north and world y west, so each world radius gives the map's other axis.
    ex, _ = point({"map": 0, "x": AREA_POINT["x"], "y": AREA_POINT["y"] + AREA_RADIUS})
    _, ey = point({"map": 0, "x": AREA_POINT["x"] + AREA_RADIUS, "y": AREA_POINT["y"]})
    rx, ry = abs(ex - cx), abs(ey - cy)
    # Strokes.lua's AREA_STEPS: each circle is a 48-segment ellipse, the arcs outside any other circle drawn.
    previous = (cx + rx, cy)
    for step in range(1, 49):
        angle = step / 48 * 2 * math.pi
        current = (cx + rx * math.cos(angle), cy + ry * math.sin(angle))
        line(route, previous, current, AREA_COLOR)
        previous = current
    flush(route)
    canvas.paste(route, mx, my)
    landmarks(canvas, MAP_ID, rects["map"])
    icon(canvas, "UI-WorldMapArrow", mx + cx, my + cy, 27)
    margin = 120
    left, top = mx + cx - rx - margin, my + cy - ry - margin
    crop = ui.canvas(2 * rx + 2 * margin, 2 * ry + 2 * margin)
    crop.image = canvas.image.crop(
        (canvas.px(left), canvas.px(top), canvas.px(left) + crop.image.width, canvas.px(top) + crop.image.height)
    )
    return scene(ui, [(crop, 0, 0)])

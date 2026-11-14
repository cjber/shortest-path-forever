"""A stop above the ground: Westfall at Sentinel Hill, where the current stop wears the map's up arrow.

Scout Riell gives [17] Red Silk Bandanas at the top of the Sentinel Hill tower (classic DB creature 820, his one
spawn). Adventure Guide passes his height, and the walking map's ground floor there is the tower's base, so StopPin.lua
anchors `poi-door-arrow-up` at the atlas's own 13 by 14, its top right BADGE_OFFSET out from the 20-unit pin's top
right, as the action badge stands out from the lower right. The tooltip is OnMouseEnter's for the current stop of a
three-stop guide route: the count with the journey's time and distance, the place, "Above ground level", the stop's
detail line and the clear hint, placed as ANCHOR_RIGHT puts it.
"""

from wowmock import NORMAL, WHITE, TooltipLine, scene, tooltip  # ty: ignore[import-not-found]

SCOUT_RIELL = {"map": 0, "x": -10504.8, "y": 1033.25}
WESTFALL = 1436
ARROW_W, ARROW_H, BADGE_OFFSET = 13, 14, 4


def render(ui):
    # screenshots.py imports this scene before it defines its helpers, so ask for them at render time.
    from screenshots import STOP_SIZE, map_base, projection, stop_pin

    base, rects = map_base(ui, WESTFALL)
    canvas = ui.canvas(base.width, base.height)
    canvas.image = base.image.copy()
    mx, my, mw, mh = rects["map"]
    nx, ny = projection(ui, SCOUT_RIELL, WESTFALL)
    px, py = mx + nx * mw, my + ny * mh
    stop_pin(canvas, px, py, 1, "QuestNormal", False)
    right, top = px + STOP_SIZE / 2 + BADGE_OFFSET, py - STOP_SIZE / 2 - BADGE_OFFSET
    canvas.draw(ui.atlas("poi-door-arrow-up"), right - ARROW_W, top, ARROW_W, ARROW_H)
    left, top = px - 150, py - 130
    crop = ui.canvas(320, 230)
    crop.image = canvas.image.crop(
        (canvas.px(left), canvas.px(top), canvas.px(left) + crop.image.width, canvas.px(top) + crop.image.height)
    )
    tip = tooltip(
        ui,
        [
            TooltipLine("Stop 1 of 3", WHITE, "0:06 · 34 yd"),
            TooltipLine("Sentinel Hill"),
            TooltipLine("Above ground level"),
            TooltipLine("[17] Red Silk Bandanas", NORMAL),
            TooltipLine(""),
            TooltipLine("Right-click to clear", NORMAL),
        ],
    )
    pin_x, pin_y = px - left, py - top
    return scene(ui, [(crop, 0, 0), (tip, pin_x + STOP_SIZE / 2, pin_y - STOP_SIZE / 2 - tip.height)])

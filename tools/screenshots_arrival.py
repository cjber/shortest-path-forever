"""The direction arrow on arrival: the addon's gold goal pin with the stop's title and objectives, and the compass
ribbon tinted green.

UI/Arrow.lua's ShowArrival keeps the arrow's own pin, ns.PIN_FILE (`media/Pin.tga`), at its normal 36 by 36 while it
hides the arrow, distance and progress, and shows the stop's title (GameFontNormal, gold) 8 units below it and up to
three objective lines (GameFontHighlightSmall, white) 4 below the title, all in a centred 240-unit column. The compass
keeps its ribbon and tints it with Compass.lua's ARRIVED_TICK_COLOR and ARRIVED_CENTER_COLOR; its markers are gone
because the guide has no targets while it waits in the area.

The stop is Adventure Guide's objective area for quest 878, "Tribes at War" (Mangletooth, the Barrens), whose three
objectives are the three lines below the pin.
"""

from wowmock import FONTS, NORMAL, WHITE, scene

PIN_BOX = 36
COLUMN = 240
QUEST = "Tribes at War"
OBJECTIVES = (
    "Kill 6 Bristleback Water Seekers",
    "Kill 12 Bristleback Thornweavers",
    "Kill 12 Bristleback Geomancers",
)
# Compass.lua stands its ribbon 42 units under the screen's top and Arrow.lua its 100-unit frame 120, so the pin's
# 36-unit box begins 110 units under the ribbon's top. The title and lines follow the frame's own 8 and 4 offsets.
WIDTH, HEIGHT = 360, 214
PIN_TOP, TITLE_TOP, LINES_TOP = 110, 154, 170


def render(ui, compass):
    # screenshots.py imports this scene before it defines pin_icon, so ask for the shared helper at render time.
    from screenshots import pin_icon

    canvas = ui.canvas(WIDTH, HEIGHT)
    canvas.paste(compass(ui, arrived=True), 0, 0)
    pin_icon(canvas, WIDTH / 2, PIN_TOP + PIN_BOX / 2, PIN_BOX)
    canvas.text(
        WIDTH / 2 - COLUMN / 2,
        TITLE_TOP,
        QUEST,
        FONTS["GameFontNormal"],
        NORMAL,
        justify="CENTER",
        width=COLUMN,
    )
    canvas.text(
        WIDTH / 2 - COLUMN / 2,
        LINES_TOP,
        "\n".join(OBJECTIVES),
        FONTS["GameFontHighlightSmall"],
        WHITE,
        justify="CENTER",
        width=COLUMN,
    )
    return scene(ui, [(canvas, 0, 0)])

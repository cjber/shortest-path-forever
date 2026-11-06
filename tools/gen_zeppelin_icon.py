#!/usr/bin/env python3
"""Draw media/Zeppelin.tga, a side-on airship in the flightmasterferry atlas's white-and-dark style.

    python3 tools/gen_zeppelin_icon.py

The Forever client has no zeppelin map atlas, so the addon ships its own. The artwork is drawn at eight times
its 32-pixel size and reduced, giving the outline and rounded hull clean edges at the world map's 20 pixels and
the minimap's 16.
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 32
SCALE = 8
OUTLINE = 1.6
WHITE = (244, 244, 244, 255)
DARK = (24, 24, 24, 255)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "media" / "Zeppelin.tga"


def scaled(points):
    return [(x * SCALE, y * SCALE) for x, y in points]


def draw_icon():
    canvas = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    stroke = round(OUTLINE * SCALE)

    tail = [
        scaled([(6, 13), (1, 4), (4, 3), (10, 10), (10, 15)]),
        scaled([(6, 16), (1, 25), (4, 26), (10, 19), (10, 14)]),
    ]
    for fin in tail:
        draw.polygon(fin, fill=WHITE, outline=DARK, width=stroke)

    body = (3 * SCALE, 8 * SCALE, 30 * SCALE, 21 * SCALE)
    draw.ellipse(body, fill=WHITE, outline=DARK, width=stroke)

    for x in (13, 19):
        draw.line(scaled([(x, 18.5), (x, 22)]), fill=DARK, width=round(1.1 * SCALE))

    gondola = (10 * SCALE, 20 * SCALE, 22 * SCALE, 27 * SCALE)
    draw.rounded_rectangle(gondola, radius=2.2 * SCALE, fill=WHITE, outline=DARK, width=stroke)

    for x in (13, 16, 19):
        window = (x - 0.7) * SCALE, 22 * SCALE, (x + 0.7) * SCALE, 23.4 * SCALE
        draw.ellipse(window, fill=DARK)

    return canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main():
    draw_icon().save(OUT, orientation=1)


if __name__ == "__main__":
    main()

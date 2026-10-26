#!/usr/bin/env python3
"""Side-by-side and enlarged sheets for checking renders against reference captures.

Split out of tools/screenshots.py, which had grown past the suite's 1000-line gate:
the comparison sheets are only written on demand (`--refs`), never for the README gallery.
"""

from pathlib import Path

from PIL import Image, ImageDraw


def comparison_sheet(root, name, pairs):
    """Write <root>/docs/verification/<name>.png: each pair's two images side by side, labelled."""
    width = max(a.width + b.width for _, a, _, b in pairs) + 30
    height = sum(max(a.height, b.height) + 40 for _, a, _, b in pairs)
    sheet = Image.new("RGB", (width, height), (28, 29, 33))
    draw, y = ImageDraw.Draw(sheet), 0
    for left, a, right, b in pairs:
        draw.text((10, y + 6), left, fill="white")
        draw.text((a.width + 20, y + 6), right, fill="white")
        sheet.paste(a, (10, y + 27))
        sheet.paste(b, (a.width + 20, y + 27))
        y += max(a.height, b.height) + 40
    path = Path(root) / "docs/verification" / (name + ".png")
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, optimize=True)
    print(path.relative_to(Path(root)), flush=True)


def enlarged(image, factor=2):
    """Upscale with nearest-neighbour so atlas pixel edges stay readable."""
    return image.resize((round(image.width * factor), round(image.height * factor)), Image.Resampling.NEAREST)

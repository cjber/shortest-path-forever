"""Export the goal pin and numbered marker textures from their generated sources in tools/pin_source.

The sources are AI-assisted originals on a flat magenta (#FF00FF) background, made for this addon with no Blizzard
art. This keys the magenta to alpha, crops to the art, centres it at its native aspect on a square canvas and writes
media/Pin.tga, the goal pin, and media/Numbers/<n>.tga, the numbered markers.
"""

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SIZE = 128
NUMBER_SIZE = 64
PINS = {"pin-gold.png": "Pin.tga"}
MAX_NUMBER = 25
NUMBERS = range(1, MAX_NUMBER + 1)


def key_magenta(image: Image.Image) -> Image.Image:
    """Magenta to alpha, with a soft edge and the magenta spill pulled out of the rim."""
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, _ = pixels[x, y]
            distance = max(abs(r - 255), g, abs(b - 255))
            if distance < 60:
                pixels[x, y] = (r, g, b, 0)
            elif distance < 120:
                pixels[x, y] = (min(r, g + 40), g, min(b, g + 40), int(255 * (distance - 60) / 60))
    return image


def export(source: Path, target: Path, size: int = SIZE) -> None:
    pin = key_magenta(Image.open(source))
    pin = pin.crop(pin.getbbox())
    scale = size / max(pin.size)  # one factor for both axes: the art keeps its shape
    pin = pin.resize((round(pin.width * scale), round(pin.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size))
    canvas.paste(pin, ((size - pin.width) // 2, (size - pin.height) // 2))
    target.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(target, compression=None)


def main() -> int:
    for source, target in PINS.items():
        export(ROOT / "tools/pin_source" / source, ROOT / "media" / target)
        print(f"wrote media/{target}")
    for number in NUMBERS:
        export(
            ROOT / "tools/pin_source/numbers" / f"{number}.png",
            ROOT / "media/Numbers" / f"{number}.tga",
            NUMBER_SIZE,
        )
    print(f"wrote media/Numbers/1.tga to media/Numbers/{MAX_NUMBER}.tga")
    return 0


if __name__ == "__main__":
    sys.exit(main())

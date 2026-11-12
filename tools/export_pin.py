"""Export the goal pin, numbered marker and town services group pin textures from their generated sources in
tools/pin_source.

The sources are AI-assisted originals on a flat magenta (#FF00FF) background, made for this addon with no Blizzard
art. This keys the magenta to alpha, crops to the art, centres it at its native aspect on a square canvas and writes
media/Pin.tga, the goal pin, media/PinInactive.tga, its bronze untracked twin, media/Numbers/<n>.tga, the numbered
markers, and media/TownGroup.tga, the market stall a town services pin wears when it stands for a group of NPCs.
"""

import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SIZE = 128
NUMBER_SIZE = 64
PINS = {"pin-gold.png": "Pin.tga", "pin-bronze.png": "PinInactive.tga"}
MAX_NUMBER = 25
NUMBERS = range(1, MAX_NUMBER + 1)
# The group pin: the stall 52 across on a 64 canvas, which leaves room for the halo the client's tracking icons wear.
TOWN_GROUP_SIZE = 64
TOWN_GROUP_ART = 52
# The magenta is keyed at 512 pixels across the source's larger side, before the art is scaled down to the canvas.
TOWN_GROUP_KEY = 512
# The halo: the art's own silhouette grown and blurred, in the client tracking icons' near-black brown.
HALO_COLOUR = (12, 8, 4)
HALO_GROW = 5
HALO_BLUR = 1.6
HALO_GAIN = 1.3


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


def export_town_group(source: Path, target: Path) -> None:
    """The group pin: the stall centred on a 64 canvas over the dark halo a client tracking icon wears."""
    art = Image.open(source).convert("RGBA")
    # Key the magenta at 512 pixels across the source's larger side: soft enough to key, small enough to be quick.
    scale = TOWN_GROUP_KEY / max(art.size)
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.Resampling.LANCZOS)
    art = key_magenta(art)
    solid = art.getchannel("A").point(lambda value: 255 if value > 40 else 0)
    art = art.crop(solid.getbbox())
    scale = TOWN_GROUP_ART / max(art.size)  # one factor for both axes: the art keeps its shape
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (TOWN_GROUP_SIZE, TOWN_GROUP_SIZE))
    canvas.paste(art, ((TOWN_GROUP_SIZE - art.width) // 2, (TOWN_GROUP_SIZE - art.height) // 2))
    halo = canvas.getchannel("A").filter(ImageFilter.MaxFilter(HALO_GROW)).filter(ImageFilter.GaussianBlur(HALO_BLUR))
    halo = halo.point(lambda value: min(255, round(value * HALO_GAIN)))
    shading = Image.new("RGBA", canvas.size, HALO_COLOUR + (0,))
    shading.putalpha(halo)
    target.parent.mkdir(parents=True, exist_ok=True)
    Image.alpha_composite(shading, canvas).save(target, compression=None)


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
    export_town_group(ROOT / "tools/pin_source/town-group.png", ROOT / "media/TownGroup.tga")
    print("wrote media/TownGroup.tga")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Nearby.lua's stock panel, for a character with all service categories available."""

from PIL import Image
from wowmock import basic_panel, scene, ui_panel_button


def render(ui):
    canvas, x, y = basic_panel(ui, "Nearby services", 380, 400)
    for i, label in enumerate(
        (
            "Class trainer",
            "Trainers by specialty",
            "Repair",
            "Reagents",
            "Vendors by specialty",
            "Innkeeper",
            "Bank",
            "Auction house",
            "Flight master",
            "Stable master",
        )
    ):
        ui_panel_button(canvas, x + 20, y + 36 + i * 30, 320, 26, label)
    return scene(ui, [(canvas, 0, 0)])


def route_button(canvas, x, y, icon_path, active=True):
    """RouteButton.lua: the game's own minimap button plate, the addon's icon in it, gold while a route is on.

    The plate is the atlas the client's own addon compartment wears (20 by 18), drawn at its native size."""
    plate = canvas.ui.atlas("ui-hud-minimap-button")
    tint = (1, 0.82, 0, 1) if active else (1, 1, 1, 1)
    canvas.draw(plate, x - plate.width / 2, y - plate.height / 2, plate.width, plate.height, tint)
    icon_art = Image.open(icon_path).convert("RGBA")
    side = 14.4  # 24 * 0.6, the button's box for the addon's square icon
    canvas.draw(icon_art, x - side / 2, y - side / 2, side, side)

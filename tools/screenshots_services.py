"""Nearby services in the stock world-map tracking menu."""

from wowmock import MenuButton, MenuTitle, context_menu, map_art, scene, world_map_frame


def render(ui):
    # The stock world-map tracking dropdown gains one Nearby services submenu.
    canvas, _ = world_map_frame(ui, map_art(ui, 1439), ("World", "Kalimdor", "Darkshore"))
    menu, menu_rects = context_menu(
        ui,
        [
            MenuTitle("Map filters"),
            MenuButton("Show quests"),
            MenuButton("Show flight paths"),
            MenuButton("Nearby services", submenu=True, hover=True),
        ],
    )
    child, child_rects = context_menu(
        ui,
        [
            MenuTitle("Nearby services"),
            MenuButton("Class trainer"),
            MenuButton("Trainers by specialty", submenu=True, hover=True),
            MenuButton("Repair"),
            MenuButton("Reagents"),
            MenuButton("Vendors by specialty", submenu=True),
            MenuButton("Innkeeper"),
            MenuButton("Bank"),
            MenuButton("Auction house"),
            MenuButton("Flight master"),
            MenuButton("Stable master"),
        ],
    )
    specialty, _ = context_menu(
        ui, [MenuTitle("Trainers by specialty"), MenuButton("Alchemy Trainer"), MenuButton("Nearest")]
    )
    # Submenus open left when there is no room beyond the map's right edge.
    mx, my = canvas.width - menu.width - 28, 84
    cx = mx - child.width + 20
    cy = my + menu_rects["rows"][-1][1] - 20
    sx = cx - specialty.width + 20
    sy = cy + child_rects["rows"][2][1] - 20
    return scene(ui, [(canvas, 0, 0), (menu, mx, my), (child, cx, cy), (specialty, sx, sy)])

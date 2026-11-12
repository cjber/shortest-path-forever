"""The town services on the world map, in Stormwind City.

UI/NearbyGroups.lua and UI/TownServices.lua supply the icons and the grouping: every pin wears the client's minimap
tracking atlas for the service it stands for (the repairer's anvil, the banker's money bags, the baker's bread and
milk), never a town or city mark and never an item's icon. The pins that would overlap share one pin, which wears its
best-ranked service; the tooltip leads with the pinned service, lists the rest and the click journey hint. The NPCs
and where they stand are Stormwind's, from QuestieDB 1.0.13's Forever bake (X-BUILD-COMMIT
0f7d8adc92b28ac6594f4ad8745257f4d9784edf), Npc spawns in area 1519 as map percent. The first scene is the whole city
zoomed out, with the Dwarven District's group hovered; the second zooms into the Trade District the way the client's map
does, the terrain enlarged and the pins still 20 units, so the services separate into a pin each.
"""

from PIL import Image
from screenshots_maps import icon, map_base
from wowmock import TooltipLine, scene, tooltip

# The client's map canvas, which UI/Map.lua's OverlapGroups measures against.
TOWN_CANVAS = (1002, 668)
# The Nearby services list's groups, in its order: vendors first, then the trainers, then the services. Each entry is
# the section that ranks it and the client tracking atlas the map wears for it (UI/NearbyGroups.lua).
TOWN_GROUPS = {
    "Innkeeper": ("services", "Innkeeper"),
    "Flight master": ("services", "FlightMaster"),
    "Stable master": ("services", "StableMaster"),
    "Repair": ("services", "Repair"),
    "Bank": ("services", "Banker"),
    "Auction house": ("services", "Auctioneer"),
    "Class trainer": ("trainers", "Class"),
    "Engineering": ("trainers", "Profession"),
    "Food": ("vendors", "Food"),
    "Trade supplies": ("vendors", "Reagents"),
    "Weapons and armour": ("vendors", "Gear"),
}
TOWN_GROUP_RANK = {"services": 1, "trainers": 2, "vendors": 3}
# UI/Nearby.lua's group order: the vendor groups, the class trainer, the profession trainers, then the services.
TOWN_GROUP_ORDER = [
    "Food",
    "Trade supplies",
    "Weapons and armour",
    "Class trainer",
    "Engineering",
    "Innkeeper",
    "Flight master",
    "Stable master",
    "Repair",
    "Bank",
    "Auction house",
]
# (NPC, title, map percent x and y, the groups it is in). The order is the read's, which decides a tie.
TOWN_SERVICES = [
    ("Innkeeper Allison", "Innkeeper", 60.4, 75.3, ["Innkeeper", "Food"]),
    ("Thomas Miller", "Baker", 67.9, 72.1, ["Food"]),
    ("Edna Mullby", "Trade Supplier", 64.7, 71.3, ["Trade supplies", "Food"]),
    ("Marda Weller", "Weapons Merchant", 64.1, 68.4, ["Repair", "Weapons and armour"]),
    ("Einris Brightspear", "Hunter Trainer", 67.3, 36.2, ["Class trainer"]),
    ("Lilliam Sparkspindle", "Expert Engineer", 62.1, 30.3, ["Engineering"]),
    ("Dungar Longdrink", "Gryphon Master", 71.3, 72.2, ["Flight master"]),
    ("Jenova Stoneshield", "Stable Master", 67.2, 37.7, ["Stable master"]),
    ("Olivia Burnside", "Banker", 64.3, 80.8, ["Bank"]),
    ("Auctioneer Chilton", None, 60.9, 71.5, ["Auction house"]),
]


def town_entries():
    """The addon's entries: one per NPC, in the order its groups put them in, with the group its pin wears."""
    entries, by_name = [], {}
    for group in TOWN_GROUP_ORDER:
        for name, title, x, y, groups in TOWN_SERVICES:
            if group not in groups:
                continue
            entry = by_name.get(name)
            if entry is None:
                entry = {"name": name, "title": title, "x": x / 100, "y": y / 100, "groups": []}
                by_name[name] = entry
                entries.append(entry)
            entry["groups"].append(group)
    for entry in entries:
        entry["primary"] = min(entry["groups"], key=lambda group: TOWN_GROUP_RANK[TOWN_GROUPS[group][0]])
    return entries


def town_clusters(zoom):
    """UI/TownServices.lua's clusters at a zoom: overlapping pins share one, which wears its best-ranked service."""
    reach_x = 20 * 1.4 * (1 + 0.2 * zoom) * 0.8 / (0.5 + 1.5 * zoom) / TOWN_CANVAS[0]
    reach_y = 20 * 1.4 * (1 + 0.2 * zoom) * 0.8 / (0.5 + 1.5 * zoom) / TOWN_CANVAS[1]
    points = town_entries()
    roots = list(range(len(points)))

    def root(i):
        while roots[i] != i:
            i = roots[i]
        return i

    for i, a in enumerate(points):
        for j in range(i + 1, len(points)):
            b = points[j]
            if abs(a["x"] - b["x"]) < reach_x and abs(a["y"] - b["y"]) < reach_y:
                roots[root(j)] = root(i)
    groups = {}
    for i, point in enumerate(points):
        groups.setdefault(root(i), []).append(point)
    clusters = []
    for members in groups.values():
        primary = min(members, key=lambda point: TOWN_GROUP_RANK[TOWN_GROUPS[point["primary"]][0]])["primary"]
        labels = [label for label in TOWN_GROUP_ORDER if any(label in point["groups"] for point in members)]
        clusters.append(
            {
                "points": members,
                "x": sum(point["x"] for point in members) / len(members),
                "y": sum(point["y"] for point in members) / len(members),
                "primary": primary,
                "labels": [primary, *(label for label in labels if label != primary)],
            }
        )
    return clusters


def town_canvas(ui, zoom):
    """Stormwind City with its service pins at a zoom: the whole city, or the Trade District enlarged 2x."""
    base, rects = map_base(ui, 1453)
    canvas = ui.canvas(base.width, base.height)
    canvas.image = base.image.copy()
    mx, my, mw, mh = rects["map"]
    if zoom:
        # The Trade District: the bank, the inn, the auction house, the flight master and the weapons and food
        # sellers. The client zooms the terrain and keeps every pin its own size, so the crop is enlarged and the
        # pins stay 20 UI units.
        left, top, right, bottom = mx + 0.55 * mw, my + 0.62 * mh, mx + 0.76 * mw, my + 0.86 * mh
        area = canvas.image.crop(tuple(round(n * ui.scale) for n in (left, top, right, bottom)))
        frame = ui.canvas(area.width * 2, area.height * 2)
        frame.image = area.resize((area.width * 2, area.height * 2), Image.Resampling.LANCZOS)
        canvas = frame
        to_x = lambda x: (x * mw + mx - left) * 2  # noqa: E731 - the crop's own transform
        to_y = lambda y: (y * mh + my - top) * 2  # noqa: E731
    else:
        to_x = lambda x: x * mw + mx  # noqa: E731
        to_y = lambda y: y * mh + my  # noqa: E731
    hover = None
    for cluster in town_clusters(zoom):
        x, y = to_x(cluster["x"]), to_y(cluster["y"])
        icon(canvas, TOWN_GROUPS[cluster["primary"]][1], x, y, size=20)
        # The group furthest up the map, so its tooltip never covers another pin.
        if not zoom and len(cluster["points"]) > 1 and (hover is None or y < hover[1]):
            hover = (x, y, cluster)
    return canvas, hover


def render(ui):
    canvas, hover = town_canvas(ui, zoom=0)
    assert hover, "a group pin to hover"
    x, y, cluster = hover
    tip = tooltip(
        ui,
        [
            TooltipLine("Stormwind City"),
            *(TooltipLine(label) for label in cluster["labels"]),
            TooltipLine("Click to plan a journey here.", (0, 1, 0)),
        ],
    )
    # GameTooltip ANCHOR_RIGHT: the tooltip's bottom left just past the pin's top right.
    return scene(ui, [(canvas, 0, 0), (tip, x + 24, y - 30 - tip.height)])


def render_zoom(ui):
    canvas, _ = town_canvas(ui, zoom=1)
    return scene(ui, [(canvas, 0, 0)])

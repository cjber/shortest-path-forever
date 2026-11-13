"""The town services on the world map, in Stormwind City.

UI/NearbyGroups.lua and UI/TownServices.lua supply the icons and the grouping: a pin for one NPC, or for several NPCs
who all show the same service, wears the client's minimap tracking atlas for that service (the repairer's anvil, the
banker's money bags, the baker's bread and milk), never a town or city mark and never an item's icon. Only a pin that
stands for different services wears the addon's own market stall (media/TownGroup.tga). Pins of one service merge
first, at a wider reach; pins of different services merge only when their own pins truly overlap, and full zoom
spreads close NPCs around their shared centre so each keeps its own pin. A group's tooltip lists every shown service,
or every member of one service, and the click journey hint. The NPCs and where they stand are Stormwind's, from
QuestieDB 1.0.13's Forever bake (X-BUILD-COMMIT 0f7d8adc92b28ac6594f4ad8745257f4d9784edf), Npc spawns in area 1519
as map percent. The first scene is the whole city zoomed out, with the Dwarven District's mixed group hovered; the
second zooms into the Trade District the way the client's map does, the terrain enlarged and the pins still 20 units,
so the services separate into a pin each.
"""

import math
from functools import cache
from pathlib import Path

from PIL import Image
from screenshots_maps import icon, map_base
from wowmock import TooltipLine, scene, tooltip

ROOT = Path(__file__).resolve().parent.parent
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
    "Weapons and armour": ("vendors", "poi-transmogrifier"),
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


@cache
def town_group_art():
    """The addon's own market stall for a group pin, media/TownGroup.tga, square at 64 with its halo."""
    with Image.open(ROOT / "media" / "TownGroup.tga") as source:
        return source.convert("RGBA")


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


PIN_SIZE = 20
PIN_SCALE = 1.4
OVERLAP = 0.8


def town_overlap(points, size, zoom):
    """UI/Map.lua's OverlapGroups at a zoom, in the client's own canvas units."""
    reach_x = size * OVERLAP / (0.5 + 1.5 * zoom) / TOWN_CANVAS[0]
    reach_y = size * OVERLAP / (0.5 + 1.5 * zoom) / TOWN_CANVAS[1]
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
    return list(groups.values())


def town_cluster(members, x=None, y=None):
    """One pin's members, the service it wears, and every shown service its tooltip lists."""
    primary = min(members, key=lambda point: TOWN_GROUP_RANK[TOWN_GROUPS[point["primary"]][0]])["primary"]
    labels = []
    for point in members:
        labels.extend(group for group in point["groups"] if group not in labels)
    return {
        "points": members,
        "x": x if x is not None else sum(point["x"] for point in members) / len(members),
        "y": y if y is not None else sum(point["y"] for point in members) / len(members),
        "primary": primary,
        "labels": labels,
        "shared": primary if all(point["primary"] == primary for point in members) else None,
    }


def town_clusters(zoom):
    """UI/TownServices.lua's clusters at a zoom: same services merge first, different ones only when truly overlapping,
    and full zoom gives every NPC its own pin, close ones spread around their shared centre."""
    points = town_entries()
    plain = PIN_SIZE * PIN_SCALE
    if zoom >= 1:
        clusters = []
        size = plain / (0.5 + 1.5 * zoom)
        reach_x, reach_y = size / TOWN_CANVAS[0], size / TOWN_CANVAS[1]
        for members in town_overlap(points, plain, zoom):
            if len(members) == 1:
                clusters.append(town_cluster(members))
                continue
            centre_x = sum(point["x"] for point in members) / len(members)
            centre_y = sum(point["y"] for point in members) / len(members)
            radius = 0.5 / math.sin(math.pi / len(members))
            for index, point in enumerate(members):
                angle = 2 * math.pi * index / len(members)
                clusters.append(
                    town_cluster(
                        [point],
                        centre_x + math.cos(angle) * reach_x * radius,
                        centre_y + math.sin(angle) * reach_y * radius,
                    )
                )
        return clusters
    by_service = {}
    for point in points:
        by_service.setdefault(point["primary"], []).append(point)
    merged = []
    same_size = plain * 1.2 * (1 - zoom)
    for members in by_service.values():
        for group in town_overlap(members, same_size, zoom):
            merged.append(town_cluster(group))
    clusters = []
    for group in town_overlap(merged, plain * (1 - zoom), zoom):
        chosen = {id(point) for cluster in group for point in cluster["points"]}
        clusters.append(town_cluster([point for point in points if id(point) in chosen]))
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
        if cluster["shared"]:
            icon(canvas, TOWN_GROUPS[cluster["shared"]][1], x, y, size=20)
        else:
            # UI/TownServices.lua paints a pin of different services with the addon's stall, whole in the same 20
            # unit box.
            canvas.draw(town_group_art(), x - 10, y - 10, 20, 20, (1, 1, 1, 1))
        # The mixed group furthest up the map, so its tooltip never covers another pin.
        if not zoom and not cluster["shared"] and len(cluster["points"]) > 1 and (hover is None or y < hover[1]):
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

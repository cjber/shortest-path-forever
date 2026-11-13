"""The Nearby services tab in the world map's quest log side panel.

UI/ServicesPanel.lua supplies the geometry: the bank bags glyph, the title and the player's place over the Vendors,
Trainers and Services sections, with 44-unit rows 2 apart, 30-unit icons and the quest log's own side tabs. The
NPCs, their titles and the goods that group them are Auberdine's, from QuestieDB. A time is the straight line at
7 yards a second over Darkshore's 6,550 by 4,366 yards, or the boat to Darnassus where no local NPC serves. The
search scene types an item word into the same box and keeps the groups whose goods match it. The better scene is the
same hunter at level 25, offered better arrows farther away in a one-line row under Arrows. The roles scene shows
the class, portal and battlemaster rows on their own.
"""

import math

from PIL import Image, ImageChops, ImageDraw
from wowmock import (
    ARIALN,
    FONTS,
    FRIZQT,
    NORMAL,
    PORTRAIT_FRAME_LAYOUT,
    Font,
    camelot_layout,
    minimal_scrollbar,
    scene,
    search_box,
    tiled,
)

# The panel's fonts, as Blizzard's Fonts.xml defines them: SystemFont_Shadow_Med3, Game15Font_Shadow and
# SystemFont_Shadow_Large2.
FONTS.setdefault("GameFontNormalMed3", Font(FRIZQT, 14, NORMAL, (1, -1)))
FONTS.setdefault("Game15Font_Shadow", Font(FRIZQT, 15, NORMAL, (1, -1)))
FONTS.setdefault("GameFontNormalLarge2", Font(FRIZQT, 18, NORMAL, (1, -1)))
# ChatFontNormal, the EditBox text an InputBoxTemplate inherits: Arial Narrow 14, white with a shadow.
FONTS.setdefault("ChatFontNormal", Font(ARIALN, 14, (1.0, 1.0, 1.0), (1, -1)))

# The quest log panel, inside the world map frame; the frame's and the panel's chrome around it.
QUESTLOG_WIDTH, QUESTLOG_HEIGHT = 330, 506
FRAME_MARGIN = 16
PANEL_WIDTH = QUESTLOG_WIDTH - 22
TOP_BAR = 29
TITLE_HEIGHT = 34
SECTION_HEIGHT = 22
SECTION_GAP = 4
ROW_HEIGHT = 44
ROW_GAP = 2
ICON = 30
TAB_ICON = 32
# A better trip's row: one line, 16 in from its group's, a 22-unit item icon with the upgrade arrow at its top left.
BETTER_HEIGHT = 28
BETTER_ICON = 22
BETTER_INDENT = 16
BADGE_WIDTH, BADGE_HEIGHT = 11, 12
PAD = 6
LIST_TOP = 4 + TITLE_HEIGHT + 6

PLAYER = (36.3, 45.0)
W_YARDS, H_YARDS, SPEED = 6550, 4366, 7

# (label, icon, NPC, NPC title, x, y, time[, detail]): x and y are the NPC's Darkshore position in map percent, and a
# row with no local NPC carries the boat's time instead. The player is a level 15 hunter, so the tiered groups name
# and show the goods for that level in place of the title (UI/Nearby.lua's Goods, from QuestieDB's requiredLevel):
#   Dalmond (4182) sells Sharp Arrow 2515 and Heavy Shot 2519 (level 10), the best arrows and shot in Auberdine.
#   Kyndri (4190, 43 yd) sells Moist Cornbread 4542 and Melon Juice 1205 (level 15); Laird (4200, 44 yd) is the
#   other level 15 food seller, a yard farther.
VENDORS = [
    ("Arrows", ("item", 2515), "Dalmond", "General Goods", 37.5, 40.5, None, "Dalmond · Sharp Arrow"),
    ("Bullets", ("item", 2519), "Dalmond", "General Goods", 37.5, 40.5, None, "Dalmond · Heavy Shot"),
    ("Food", ("item", 4542), "Kyndri", "Baker", 36.9, 44.6, None, "Kyndri · Moist Cornbread"),
    ("Drink", ("item", 1205), "Kyndri", "Baker", 36.9, 44.6, None, "Kyndri · Melon Juice"),
    ("Bags", ("item", 4498), "Dalmond", "General Goods", 37.5, 40.5, None),
    ("Trade supplies", ("item", 2320), "Gorbold Steelhand", "General Trade Supplier", 38.1, 41.2, None),
    ("Reagents", ("item", 2928), "Gorbold Steelhand", "General Trade Supplier", 38.1, 41.2, None),
    ("Weapons and armour", ("item", 851), "Harlon Thornguard", "Armorer & Shieldsmith", 37.0, 41.3, None),
]
TRAINERS = [
    ("Class trainer", ("atlas", "Class"), "Jocaste", "Darnassus", None, None, "6:20"),
    ("Portal trainer", ("atlas", "TaxiNode_Continent_Neutral"), "Elissa Dumas", "Darnassus", None, None, "6:25"),
    ("Blacksmithing", ("atlas", "Profession"), "Delfrum Flintbeard", "Journeyman Blacksmith", 38.2, 40.9, None),
    ("Engineering", ("atlas", "Profession"), "Jenna Lemkenilli", "Journeyman Engineer", 38.3, 41.1, None),
    ("Mining", ("atlas", "Profession"), "Kurdram Stonehammer", "Mining Trainer", 38.2, 41.0, None),
    ("Tailoring", ("atlas", "Profession"), "Grondal Moonbreeze", "Journeyman Tailor", 38.2, 40.5, None),
]
SERVICES = [
    ("Innkeeper", ("atlas", "Innkeeper"), "Innkeeper Shaussiy", "Innkeeper", 37.0, 44.1, None),
    ("Flight master", ("atlas", "FlightMaster"), "Caylais Moonfeather", "Hippogryph Master", 36.3, 45.6, None),
    ("Stable master", ("atlas", "StableMaster"), "Jaelysia", "Stable Master", 37.4, 44.3, None),
    ("Repair", ("atlas", "Repair"), "Harlon Thornguard", "Armorer & Shieldsmith", 37.0, 41.3, None),
    ("Bank", ("atlas", "Banker"), "Idriana", "Darnassus", None, None, "6:05"),
    ("Auction house", ("atlas", "Auctioneer"), "Auctioneer Tolon", "Darnassus", None, None, "6:40"),
    ("Battlemaster", ("atlas", "BattleMaster"), "Aethalas", "Warsong Gulch Battlemaster", None, None, "6:35"),
]

# The search scene types "water", the first thing a player runs out of. UI/Nearby.lua's Matching keeps an NPC when
# the folded query is a substring of its group's label, its name or title, or the name of an item that puts it in the
# group; Detail then lists only the matching item names, and the row's icon is the first of them. QuestieDB 1.0.12,
# Forever baked build (X-BUILD-COMMIT 4d31c10394b11bd1), Npc-<id>-7 spawns and Item-<id>-14 vendors in
# QuestieDB_Forever.toc:
#   159 Refreshing Spring Water, in ns.Drink, sold in Darkshore by NPC 4190 Kyndri (36.9, 44.6), 4192 Taldan
#   (36.83, 43.91), 6737 Innkeeper Shaussiy (37.04, 44.13), 4191 Allyndia (37.12, 43.62), 4182 Dalmond and 4195
#   Tiyani; Kyndri is the nearest to the player at 36.3, 45.0.
#   4538 Snapvine Watermelon, in ns.Food, sold by NPC 4191 Allyndia and 4195 Tiyani (43.69, 76.63); Allyndia is
#   the nearer. No other group's label, NPC or goods contains "water", so the Vendors section keeps these two.
SEARCH_QUERY = "water"
SEARCH = [
    (
        "Vendors",
        [
            (
                "Food",
                ("item", 4538),
                "Allyndia",
                "Food & Drink Vendor",
                37.12,
                43.62,
                None,
                "Allyndia · Snapvine Watermelon",
            ),
            (
                "Drink",
                ("item", 159),
                "Kyndri",
                "Baker",
                36.9,
                44.6,
                None,
                "Kyndri · Refreshing Spring Water",
            ),
        ],
    ),
]
SECTIONS = (("Vendors", VENDORS), ("Trainers", TRAINERS), ("Services", SERVICES))

# The better scene: the same hunter at level 25, a bow in the ranged slot. QuestieDB as above, Item-<id>-10 the level
# each needs:
#   Auberdine's best arrow is still Dalmond's Sharp Arrow 2515 (10), and his Heavy Shot 2519 (10) the best shot.
#   Kyndri (4190, 43 yd) sells Mulgore Spice Bread 4544 and Sweet Nectar 1708 (25), the best food and drink for 25, so
#   neither gets a trip.
#   Razor Arrow 3030 (25) is sold by NPC 4173 Landria, 4170 Ellandrieth and 4241 Mydrannul in Darnassus, and 3962
#   Haljan Oakheart in Astranaar; the row says Darnassus, by the boat the other Darnassus rows take. A bow has no use
#   for shot, so Solid Shot 3033 gets no trip.
# A ("better", item, name, zone, time) entry is the trip's row (UI/ServicesPanel.lua's CreateBetterRow).
BETTER_VENDORS = [
    ("Arrows", ("item", 2515), "Dalmond", "General Goods", 37.5, 40.5, None, "Dalmond · Sharp Arrow"),
    ("better", 3030, "Razor Arrow", "Darnassus", "6:20"),
    ("Bullets", ("item", 2519), "Dalmond", "General Goods", 37.5, 40.5, None, "Dalmond · Heavy Shot"),
    ("Food", ("item", 4544), "Kyndri", "Baker", 36.9, 44.6, None, "Kyndri · Mulgore Spice Bread"),
    ("Drink", ("item", 1708), "Kyndri", "Baker", 36.9, 44.6, None, "Kyndri · Sweet Nectar"),
    *VENDORS[4:],
]
BETTER_SECTIONS = (("Vendors", BETTER_VENDORS), ("Trainers", TRAINERS), ("Services", SERVICES))

# The class, portal and battlemaster rows on their own, so the roles added beside the existing services are visible
# without scrolling past the vendors. Elissa Dumas is Darnassus's portal trainer and Aethalas its Warsong Gulch
# battlemaster; the times are the same Teldrassil boat the class trainer row takes.
ROLES = (
    ("Trainers", TRAINERS[:2]),
    ("Services", [SERVICES[-1]]),
)


def walk(x, y):
    """A straight line at 7 yards a second, as the preview's times were measured."""
    yards = math.hypot((x - PLAYER[0]) / 100 * W_YARDS, (y - PLAYER[1]) / 100 * H_YARDS)
    seconds = math.ceil(yards / SPEED)
    return f"{seconds // 60}:{seconds % 60:02d}"


def time_of(entry):
    return entry[6] if entry[4] is None else walk(entry[4], entry[5])


def icon(canvas, ref, x, y, size):
    """An item's square file whole but for its edge, or an atlas fitted at its native aspect into the box."""
    if ref[0] == "item":
        image = canvas.ui.texture(canvas.ui.item(ref[1]).icon)
        trim = round(image.width * 0.08)
        canvas.draw(image.crop((trim, trim, image.width - trim, image.height - trim)), x, y, size, size)
        return
    art = canvas.ui.atlas(ref[1])
    scale = min(size / art.width, size / art.height)
    width, height = art.width * scale, art.height * scale
    canvas.draw(art, x + (size - width) / 2, y + (size - height) / 2, width, height)


def title(canvas, x, y, width, header_icon):
    """BuildHeader: the header's icon at LEFT (2, 0), the title 1 below the header's top and the place 2 under it."""
    icon(canvas, header_icon, x + 2, y + (TITLE_HEIGHT - ICON) / 2, ICON)
    title_font = FONTS["GameFontNormalLarge2"]
    canvas.text(x, y - 1, "Nearby services", title_font, justify="CENTER", width=width)
    canvas.text(
        x,
        y - 1 + title_font.height + 2,
        "Auberdine, Darkshore",
        FONTS["GameFontHighlight"],
        justify="CENTER",
        width=width,
    )


def section_header(canvas, x, y, width, name, count):
    """CreateHeader: the stock list band, its name at LEFT 8, the count ending 28 in, and an open section's minus."""
    canvas.draw(canvas.ui.atlas("common-button-list-collapseExpand"), x, y, width, SECTION_HEIGHT)
    canvas.text(x + 8, y, name, FONTS["Game15Font_Shadow"], box_height=SECTION_HEIGHT)
    canvas.text(
        x,
        y,
        str(count),
        FONTS["Game15Font_Shadow"],
        justify="RIGHT",
        width=width - 28,
        box_height=SECTION_HEIGHT,
    )
    sign = canvas.ui.atlas("common-button-list-minus")
    canvas.draw(sign, x + width - 16 - sign.width / 2, y + (SECTION_HEIGHT - sign.height) / 2)


def row(canvas, x, y, width, entry):
    """CreateRow: the Who list's 44-high card, a 30-unit icon at LEFT 8, the label, its NPC and title, and the time."""
    label, ref, npc, place, _, _, _ = entry[:7]
    detail = entry[7] if len(entry) > 7 else f"{npc} · {place}"
    canvas.draw(canvas.ui.atlas("common-button-list-large"), x, y, width, ROW_HEIGHT)
    icon_top = y + (ROW_HEIGHT - ICON) / 2
    icon(canvas, ref, x + 8, icon_top, ICON)
    when = time_of(entry)
    time_font = FONTS["GameFontHighlight"]
    time_width = canvas.text_width(when, time_font)
    text_x = x + 8 + ICON + 8
    text_width = x + width - 8 - 6 - time_width - text_x
    label_top = icon_top + 4
    canvas.text(x, y + 8, when, time_font, justify="RIGHT", width=width - 8)
    canvas.text(text_x, label_top, label, FONTS["GameFontNormalMed3"], width=text_width)
    canvas.text(
        text_x,
        label_top + FONTS["GameFontNormalMed3"].height + 4,
        detail,
        FONTS["GameFontHighlightSmall"],
        width=text_width,
    )


def better_row(canvas, x, y, width, entry):
    """CreateBetterRow: the same card one line high, a 22-unit item icon at LEFT 6 wearing the upgrade arrow at its top
    left, the goods and their zone in GameFontHighlight, and the time at RIGHT -8."""
    _, item, name, zone, when = entry
    canvas.draw(canvas.ui.atlas("common-button-list-large"), x, y, width, BETTER_HEIGHT)
    icon_top = y + (BETTER_HEIGHT - BETTER_ICON) / 2
    icon(canvas, ("item", item), x + 6, icon_top, BETTER_ICON)
    badge = canvas.ui.atlas("bags-greenarrow")
    scale = min(BADGE_WIDTH / badge.width, BADGE_HEIGHT / badge.height)
    canvas.draw(badge, x + 6, icon_top, badge.width * scale, badge.height * scale)
    font = FONTS["GameFontHighlight"]
    time_width = canvas.text_width(when, font)
    text_x = x + 6 + BETTER_ICON + 8
    canvas.text(x, y, when, font, justify="RIGHT", width=width - 8, box_height=BETTER_HEIGHT)
    canvas.text(
        text_x, y, f"{name} · {zone}", font, width=x + width - 8 - 6 - time_width - text_x, box_height=BETTER_HEIGHT
    )


def sections(canvas, x, y, width, groups=SECTIONS):
    """Refresh: one header per section and its rows below, 44 high and 2 apart, a better trip's 28 high and indented
    under its group's; the count is the groups', and the list ends at the last row."""
    top = 0
    for name, entries in groups:
        count = sum(1 for entry in entries if entry[0] != "better")
        section_header(canvas, x, y + top, width, name, count)
        top += SECTION_HEIGHT + SECTION_GAP
        for entry in entries:
            if entry[0] == "better":
                better_row(canvas, x + BETTER_INDENT, y + top, width - BETTER_INDENT, entry)
                top += BETTER_HEIGHT + ROW_GAP
            else:
                row(canvas, x, y + top, width, entry)
                top += ROW_HEIGHT + ROW_GAP
    return top


def cover(canvas, atlas, x, y, width, height):
    """Art.Cover: the whole atlas at its own aspect with its overflow cropped evenly, never stretched."""
    image = atlas.image
    native, box = atlas.width / atlas.height, width / height
    if native > box:
        cut = round((1 - box / native) * image.width / 2)
        image = image.crop((cut, 0, image.width - cut, image.height))
    else:
        cut = round((1 - native / box) * image.height / 2)
        image = image.crop((0, cut, image.width, image.height - cut))
    canvas.draw(image, x, y, width, height)


def clipped(canvas, x, y, width, height, draw):
    """The scroll frame's viewport: content stops at the body's edge however far the list runs."""
    layer = canvas.ui.canvas(canvas.width, canvas.height)
    result = draw(layer)
    keep = Image.new("L", layer.image.size, 0)
    ImageDraw.Draw(keep).rectangle(
        (layer.px(x), layer.px(y), layer.px(x + width) - 1, layer.px(y + height) - 1), fill=255
    )
    layer.image.putalpha(ImageChops.multiply(layer.image.getchannel("A"), keep))
    canvas.paste(layer, 0, 0)
    return result


def side_tabs(canvas, x, y, selected_icon):
    """The quest log's LargeSideTabButtons: Quests, then the installed Nearby services tab, selected."""
    back = canvas.ui.atlas("common-sidetab")
    width, height = back.width, back.height - 5
    mask = canvas.ui.atlas("common-sidetab-mask")

    def tab(top, art, size, selected):
        cx, cy = x + width / 2, top + height / 2
        canvas.draw(back, cx - back.width / 2, cy - back.height / 2)
        layer = canvas.ui.canvas(canvas.width, canvas.height)
        atlas = canvas.ui.atlas(art)
        scale = min(size[0] / atlas.width, size[1] / atlas.height) if size else 1
        icon_width, icon_height = atlas.width * scale, atlas.height * scale
        layer.draw(atlas, cx - 3 - icon_width / 2, cy - icon_height / 2, icon_width, icon_height)
        layer.mask(mask.image, cx - mask.width / 2, cy - mask.height / 2, mask.width, mask.height)
        canvas.paste(layer, 0, 0)
        if selected:
            chosen = canvas.ui.atlas("common-sidetab-selected")
            canvas.draw(chosen, cx - chosen.width / 2, cy - chosen.height / 2)

    tab(y, "questlog-tab-icon-quest-inactive", None, False)
    # Adventure Guide is not installed in this scene, so the services tab stands directly under the quest one.
    tab(y + height + 3, selected_icon, (TAB_ICON, TAB_ICON), True)


def search_box_text(canvas, x, y, width, height, text):
    """SearchBoxTemplate holding text: the same border and magnifier, the query in ChatFontNormal and the clear
    button it shows while the box has text, its 10-unit icon at the stock 0.5 alpha 3 in from the button's top left."""
    ui = canvas.ui
    canvas.draw(ui.atlas("common-search-border-left"), x - 5, y, 8, height)
    canvas.draw(ui.atlas("common-search-border-middle"), x + 3, y, width - 8 - 3, height)
    canvas.draw(ui.atlas("common-search-border-right"), x + width - 8, y, 8, height)
    canvas.draw(ui.atlas("common-search-magnifyingglass"), x + 1, y + (height - 10) / 2 + 1, 10, 10)
    canvas.text(
        x + 16,
        y,
        text,
        FONTS["ChatFontNormal"],
        box_height=height,
        width=width - 16 - 20,
    )
    size = 17
    button_x, button_y = x + width - 3 - size, y + (height - size) / 2
    canvas.draw(ui.atlas("common-search-clearbutton"), button_x + 3, button_y + 3, 10, 10, (1, 1, 1, 0.5))


def panel(ui, query="", groups=SECTIONS):
    """The quest log's right-hand panel, cropped to the panel and its tabs as the preview is."""
    canvas = ui.canvas(QUESTLOG_WIDTH + 64 + 2 * FRAME_MARGIN, QUESTLOG_HEIGHT + 28 + 2 * FRAME_MARGIN)
    fx, fy = FRAME_MARGIN, FRAME_MARGIN
    rock = ui.texture("interface/framegeneral/ui-background-rock.blp")
    tiled(
        canvas,
        rock,
        fx,
        fy + 21,
        QUESTLOG_WIDTH + 3,
        QUESTLOG_HEIGHT + 28 - 23,
        rock.width / ui.scale,
        rock.height / ui.scale,
    )
    px, py = fx, fy + 25
    bx, by = px, py + TOP_BAR
    bw, bh = PANEL_WIDTH, QUESTLOG_HEIGHT - TOP_BAR
    # The quest list's own parchment, under the search row, covered to the body's box.
    cover(canvas, ui.atlas("QuestLog-main-background"), bx, by, bw, bh)
    header_x, header_width = bx + 8, bw - 16
    list_x, list_width = bx + 8, bw - 8

    def content(layer):
        title(layer, header_x, by + 4, header_width, ("atlas", "Banker"))
        top = sections(layer, list_x + 6, by + LIST_TOP, list_width - 12, groups)
        return LIST_TOP + top + PAD

    content_height = clipped(canvas, bx, by, bw, bh, content)
    # The stock quest log border and its filigree, then the scroll bar in the gap before the frame's right edge.
    canvas.draw(ui.atlas("questlog-frame"), bx - 3, by - 7, bw + 6, bh + 13)
    filigree = ui.atlas("questlog-frame-filigree")
    canvas.draw(filigree, bx + (bw - filigree.width) / 2, by - 8)
    minimal_scrollbar(canvas, bx + bw + 8, by + 2, bh - 6, min(1, bh / content_height), 0)
    if query:
        search_box_text(canvas, px + 6, py + 2, bw - 9, 20, query)
    else:
        search_box(canvas, px + 6, py + 2, bw - 9, 20, "Search services and goods")
    cog = ui.atlas("questlog-icon-setting")
    canvas.draw(cog, px + bw + 19 - 15 + (15 - cog.width) / 2, py + 4)
    # The world map frame's metal edge, its close buttons and the quest log's side tabs beyond it.
    canvas.nine_slice(
        camelot_layout(PORTRAIT_FRAME_LAYOUT), fx - 400, fy, QUESTLOG_WIDTH + 400 + 3, QUESTLOG_HEIGHT + 28
    )
    close_x = fx + QUESTLOG_WIDTH + 3 + 1 - 24
    canvas.draw(ui.atlas("RedButton-Exit"), close_x, fy, 24, 24)
    canvas.draw(ui.atlas("RedButton-Expand"), close_x - 1 - 24, fy, 24, 24)
    side_tabs(canvas, fx + QUESTLOG_WIDTH + 3, fy + 25 + 30, "Banker")
    return canvas


def render(ui):
    return scene(ui, [(panel(ui), 0, 0)])


def render_search(ui):
    return scene(ui, [(panel(ui, SEARCH_QUERY, SEARCH), 0, 0)])


def render_better(ui):
    return scene(ui, [(panel(ui, groups=BETTER_SECTIONS), 0, 0)])


def render_roles(ui):
    return scene(ui, [(panel(ui, groups=ROLES), 0, 0)])

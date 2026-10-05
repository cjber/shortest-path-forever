"""A quest's own area on the world map, as the client's blob widget draws it in the gold set QuestBlob.lua gives it.

The areas are the client's own data: every QuestPOIBlob of one quest objective on Westfall, with its QuestPOIPoint
corners. The border is the gold edge texture's own pixels; the set's fill texture is clear, so nothing is filled.
The widget's spline, its border's width and which side of the edge the border falls on are engine-side: see
docs/screenshots.md.
"""

from PIL import Image, ImageChops, ImageDraw
from wowmock import scene

MAP_ID = 1436
QUEST_ID, OBJECTIVE = "92744", "0"
# The area the player stands in, which the crop is taken around.
STANDING = "575423"
BORDER = "interface/minimap/ui-bonusobjectiveblob-outside.blp"
BORDER_ALPHA = 192 / 255
STEPS = 8


def areas(ui):
    """The quest objective's areas on the map as {blob ID: world points}, in the table's own order."""
    blobs = [
        row["ID"]
        for row in ui.wago.db2("QuestPOIBlob")
        if (row["QuestID"], row["ObjectiveIndex"], int(row["UiMapID"])) == (QUEST_ID, OBJECTIVE, MAP_ID)
    ]
    points = {blob: [] for blob in blobs}
    for row in sorted(ui.wago.db2("QuestPOIPoint"), key=lambda row: int(row["ID"])):
        if row["QuestPOIBlobID"] in points:
            points[row["QuestPOIBlobID"]].append({"map": 0, "x": float(row["X"]), "y": float(row["Y"])})
    return points


def spline(corners):
    """A closed Catmull-Rom curve through the corners."""
    curve = []
    for i, b in enumerate(corners):
        a, c, d = corners[i - 1], corners[(i + 1) % len(corners)], corners[(i + 2) % len(corners)]
        for step in range(STEPS):
            t = step / STEPS
            curve.append(
                tuple(
                    0.5
                    * (
                        2 * b[n]
                        + (c[n] - a[n]) * t
                        + (2 * a[n] - 5 * b[n] + 4 * c[n] - d[n]) * t * t
                        + (3 * b[n] - 3 * c[n] + d[n] - a[n]) * t**3
                    )
                    for n in (0, 1)
                )
            )
    return curve


def blob(canvas, outline, edge):
    """One area's border: the edge texture's rows laid inward from the outline, brightest at the outline."""
    k = canvas.ui.scale
    curve = [(x * k, y * k) for x, y in outline]
    rows = [edge.getpixel((edge.width // 2, row)) for row in range(edge.height)]
    if rows[0][3] < rows[-1][3]:
        rows.reverse()
    band = Image.new("RGBA", canvas.image.size)
    draw = ImageDraw.Draw(band)
    for row in range(len(rows) - 1, -1, -1):
        draw.line([*curve, curve[0], curve[1]], fill=rows[row], width=round(2 * (row + 1) * k), joint="curve")
    inside = Image.new("L", canvas.image.size)
    ImageDraw.Draw(inside).polygon(curve, fill=round(255 * BORDER_ALPHA))
    band.putalpha(ImageChops.multiply(band.getchannel("A"), inside))
    canvas.image.alpha_composite(band)


def render(ui, map_frame, project, landmarks, icon):
    """Westfall, standing inside a quest's area. Cropped to that area."""
    base, rects = map_frame(ui, MAP_ID)
    canvas = ui.canvas(base.width, base.height)
    canvas.image = base.image.copy()
    mx, my, mw, mh = rects["map"]
    edge = ui.texture(BORDER)
    standing = None
    for blob_id, corners in areas(ui).items():
        outline = spline([(mx + n[0] * mw, my + n[1] * mh) for n in (project(ui, p, MAP_ID) for p in corners)])
        blob(canvas, outline, edge)
        if blob_id == STANDING:
            standing = outline
    landmarks(canvas, MAP_ID, rects["map"])
    xs, ys = [x for x, _ in standing], [y for _, y in standing]
    icon(canvas, "UI-WorldMapArrow", sum(xs) / len(xs), sum(ys) / len(ys), 27)
    # The crop stays on the map: an area near its edge is not framed with the window's border.
    margin = 90
    left, top = max(mx, min(xs) - margin), max(my, min(ys) - margin)
    right, bottom = min(mx + mw, max(xs) + margin), min(my + mh, max(ys) + margin)
    crop = ui.canvas(right - left, bottom - top)
    crop.image = canvas.image.crop(
        (canvas.px(left), canvas.px(top), canvas.px(left) + crop.image.width, canvas.px(top) + crop.image.height)
    )
    return scene(ui, [(crop, 0, 0)])

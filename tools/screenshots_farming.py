"""Source-derived farming chooser proposals, separate from the public gallery."""

import hashlib
import io
import json

from PIL import Image


def farming_preview(ui, state, root, backdrop, fonts):
    """Illustrative UI/Farming.lua lockup, not a client capture or provider database copy."""
    from wowmock import (  # ty: ignore[import-not-found]
        INSET_FRAME_LAYOUT,
        draw_nine_slice,
        minimal_scrollbar,
        portrait_frame_art,
        three_slice_button,
        tiled,
        wrap_text,
    )

    # Runtime 480x520 host, with margin for the native portrait and metal corners.
    canvas = backdrop(ui, 544, 600)
    x, y, w, h = 32, 40, 480, 520
    controls = []

    def note(name, role, bx, by, bw, bh, enabled=True):
        rect = dict(name=name, role=role, x=bx, y=by, w=bw, h=bh, enabled=enabled)
        assert x <= bx and y <= by and bx + bw <= x + w and by + bh <= y + h, rect
        controls.append(rect)

    rock = ui.texture("interface/framegeneral/ui-background-rock.blp")
    tiled(canvas, rock, x + 2, y + 21, w - 4, h - 23, rock.width / ui.scale, rock.height / ui.scale)
    streaks = ui.atlas("_UI-Frame-TopTileStreaks")
    canvas.draw(streaks, x + 6, y + 21, w - 8, streaks.height)
    font = fonts["GameFontHighlight"]
    description = "Visit GatherMate2 recorded locations in your current zone. Nodes may be absent or unreachable."
    for i, line in enumerate(wrap_text(canvas, description, font, w - 72 - 16)):
        canvas.text(x + 72, y + 40 + i * 12, line, font)
    note("description", "text", x + 72, y + 40, w - 72 - 16, 36)
    active = state in ("running", "paused")
    for i, label in enumerate(("Herbs", "Mining", "All", "None")):
        enabled = not active and label != "Herbs"
        bx, by = x + 16 + i * 112, y + h - 406 - 26
        three_slice_button(canvas, bx, by, 104, 26, label, state="normal" if enabled else "disabled")
        note(label, "button", bx, by, 104, 26, enabled)
    ix, iy, iw, ih = x + 16, y + 120, 448, 270
    marble = ui.texture("interface/framegeneral/ui-background-marble.blp")
    tiled(canvas, marble, ix, iy, iw, ih, marble.width / ui.scale, marble.height / ui.scale)
    draw_nine_slice(canvas, INSET_FRAME_LAYOUT, ix, iy, iw, ih)
    note("inset", "container", ix, iy, iw, ih)
    sx, sy, sw, sh = ix + 6, iy + 6, iw - 34, ih - 12
    note("scroll viewport", "viewport", sx, sy, sw, sh)
    # Names are factual provider labels verified by the external released-data prototype.
    # No ARR coordinate records, provider source, icons or database fixtures are redistributed.
    names = () if state == "empty" else ("Earthroot", "Mageroyal", "Peacebloom", "Silverleaf")
    for i, label in enumerate(names):
        bx, by = sx + 4, sy + i * 28
        canvas.draw(ui.texture("interface/buttons/ui-checkbox-up.blp"), bx, by, 26, 26)
        # Core asset gate rejects the native DisabledCheckedTexture. Explicit preview approximation.
        canvas.draw(
            ui.texture("interface/buttons/ui-checkbox-check.blp"),
            bx,
            by,
            26,
            26,
            color=(0.5, 0.5, 0.5, 1) if active else (1, 1, 1, 1),
        )
        canvas.text(bx + 30, by, label, font, box_height=26)
        note(label, "checkbox", bx, by, 26, 26, not active)
        note(label + " label", "text", bx + 30, by, sw - 42, 26)
    # ScrollFrame_OnLoad: TOPLEFT at viewport TOPRIGHT (+6,+2), bottom (+6,+5).
    minimal_scrollbar(canvas, sx + sw + 6, sy - 2, sh - 3)
    note("scrollbar", "scrollbar", sx + sw + 3, sy - 2, 14, sh - 3)
    status = {
        "ready": "Ready to start.\nNext location: 1. Completed circuits: 0.",
        "empty": "No recorded locations for these choices in your current zone.",
        "running": "Farming tour running.\nNext location: 3. Completed circuits: 0.",
        "paused": "Farming tour paused.\nNext location: 3. Completed circuits: 0.",
    }[state]
    lines = []
    for paragraph in status.split("\n"):
        lines.extend(wrap_text(canvas, paragraph, font, 448))
    for i, line in enumerate(lines):
        canvas.text(x + 16, y + 400 + i * 12, line, font)
    note("status", "text", x + 16, y + 400, 448, len(lines) * 12)
    for i, label in enumerate(("Start", "Pause", "Resume", "Stop")):
        enabled = {"Start": state == "ready", "Pause": state == "running", "Resume": state == "paused", "Stop": active}[
            label
        ]
        bx, by = x + 16 + i * 112, y + h - 16 - 26
        three_slice_button(canvas, bx, by, 104, 26, label, state="normal" if enabled else "disabled")
        note(label, "button", bx, by, 104, 26, enabled)
    portrait_frame_art(canvas, x, y, w, h, Image.open(root / "media/Icon.tga"), "Farming tour")
    # Close belongs to the native host and extends one unit above its logical top.
    controls.append(dict(name="Portrait", role="host-art", x=x - 5, y=y - 7, w=62, h=62))
    controls.append(dict(name="Title", role="text", x=x + 58, y=y + 6, w=w - 82, h=12))
    controls.append(dict(name="Close", role="host-button", x=x + w - 26, y=y - 1, w=24, h=24, enabled=True))
    canvas.text(32, 8, "Illustrative mock - " + state, fonts["GameFontNormal"])
    canvas.text(32, 576, "Sample state, not a game capture", fonts["GameFontDisableSmall"])
    if active:
        canvas.text(32, 588, "Disabled check artwork approximated", fonts["GameFontDisableSmall"])
    buttons = [c for c in controls if c["role"] == "button"]
    for a, b in zip(buttons, buttons[1:], strict=False):
        if a["y"] == b["y"]:
            assert b["x"] - a["x"] - a["w"] == 8
    return canvas, dict(frame=[x, y, w, h], canvas=[544, 600], controls=controls)


def render_farming_previews(root, wowmock, art, backdrop, fonts):
    """Keep proposal outputs separate from the public screenshot gallery and its freshness gate."""
    out = root / "docs/previews/farming"
    out.mkdir(parents=True, exist_ok=True)
    sources = (
        "UI/Farming.lua",
        "UI/Art.lua",
        "Core/GatherMate.lua",
        "Journey/Farming.lua",
        "tools/screenshots.py",
        "tools/screenshots_farming.py",
        "tools/screenshots_art.py",
        "media/Icon.tga",
    )
    record = {
        "label": "Illustrative mocks, not client captures",
        "art_build": "1.60.1.70124",
        "sources": {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sources},
        "renderer_sha256": hashlib.sha256((wowmock / "wowmock.py").read_bytes()).hexdigest(),
        "pillow_version": Image.__version__,
        "scenes": {},
        "assets": {},
    }
    for state in ("ready", "empty", "running", "paused"):
        outputs = []
        for _ in range(2):
            ui = art(scale=2)
            canvas, layout = farming_preview(ui, state, root, backdrop, fonts)
            buffer = io.BytesIO()
            canvas.image.save(buffer, format="PNG", optimize=True)
            outputs.append(buffer.getvalue())
        assert outputs[0] == outputs[1], state + ": nondeterministic preview"
        for name in sorted(ui._atlas_cache):
            _, member, atlas, size = ui._atlas_member(name)
            record["assets"][name] = {
                "member": member["CommittedName"],
                "set": atlas["UiTextureAtlasSetID"],
                "file_data_id": atlas["FileDataID"],
                "size": size,
                "texcoords_pixels": [
                    member[k] for k in ("CommittedLeft", "CommittedTop", "CommittedRight", "CommittedBottom")
                ],
            }
        path = out / (state + ".png")
        path.write_bytes(outputs[0])
        record["scenes"][state] = dict(layout, sha256=hashlib.sha256(outputs[0]).hexdigest())
        print(path.relative_to(root), record["scenes"][state]["sha256"], flush=True)
    assets = json.dumps({"art_build": record["art_build"], "assets": record.pop("assets")}, indent=2) + "\n"
    (out / "assets.json").write_text(assets)
    record["assets"] = {"path": "assets.json", "sha256": hashlib.sha256(assets.encode()).hexdigest()}
    (out / "layout.json").write_text(json.dumps(record, indent=2) + "\n")

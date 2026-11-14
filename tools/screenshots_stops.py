"""Illustrative journey editor renders, driven by the real Lua UI/controller.

The native-frame stub supplies geometry and input only. Journey/API/StopOrder are
real; terrain and sample coordinates remain the journey_driver test fixture.
"""

import hashlib
import io
import json
import subprocess

from PIL import Image


def snapshots(root):
    """Reuse the UI spec's native stubs, then click the actual runtime controls."""
    source = (root / "tests/journey_stops_ui_spec.lua").read_text()
    marker = "ns.ShowJourneyStops()\nlocal window, scroll"
    assert source.count(marker) == 1, "UI harness changed: review snapshot adapter"
    program = (
        source.split(marker)[0]
        + r"""
local titles = { "Thelsamar", "Ironband's Excavation Site", "Farstrider Lodge" }
local nextTitle = 0
ns.JourneyTitle = function()
    nextTitle = nextTitle + 1
    return titles[nextTitle]
end
env.C_AddOns.GetAddOnMetadata = function()
    return "Interface\\Icons\\INV_Misc_Spyglass_03"
end
local function json(v)
    if type(v) == "string" then return string.format("%q", v):gsub("\\\n", "\\n") end
    if type(v) ~= "table" then return tostring(v) end
    local keys, parts = {}, {}
    for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do parts[#parts+1] = json(tostring(k)) .. ":" .. json(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local results = {}
local function capture(state)
    local controls, labels = {}, {}
    for _, f in ipairs(frames) do
        if f.template == "SharedButtonSmallTemplate" and f:IsShown() then
            controls[#controls+1] = {text=f.text, enabled=f.enabled, selected=f.highlighted or false,
                points=f.points, width=f.width, height=f.height}
        end
        if f.name == "ShortestPathForeverJourneyStops" then
            for _, t in ipairs(f.children) do labels[#labels+1] = {text=t.text, points=t.points} end
        end
    end
    -- Strip object references from anchors, preserving the native anchor's numeric offsets.
    for _, c in ipairs(controls) do
        local p = c.points[1]
        c.anchor = {p[1], p[2], p[3]}
        c.points = nil
    end
    results[state] = {controls=controls, labels=labels}
end
ns.ShowJourneyStops()
capture("empty")
-- Deliberately add farther first: submitted nearest-next order must differ from draft.
for _, x in ipairs({0.506, 0.502, 0.504}) do
    waypoint(x)
    find("Add map waypoint"):Click()
end
capture("draft")
find("Start"):Click()
for _=1,12 do flush() end
assert(ns.HasJourney(), "real route did not submit")
capture("running")
find("Pause"):Click()
assert(find("Resume").enabled, "real route did not pause")
capture("paused")
find("Stop"):Click()
find("Close"):Click()
for _=1,3 do flush() end
assert(#timers == 0, "snapshot adapter left timers")
print(json(results))
"""
    )
    result = subprocess.run(["luajit", "-"], input=program, text=True, cwd=root, capture_output=True, check=True)
    result = json.loads(result.stdout)
    draft = [c["text"] for c in values(result["draft"]["controls"]) if c["anchor"]["1"] == "TOPLEFT"]
    active = [c["text"] for c in values(result["running"]["controls"]) if c["anchor"]["1"] == "TOPLEFT"]
    assert draft != active, "fixture must demonstrate actual submitted order"
    assert active[0].startswith("1. Ironband"), active
    return result


def values(mapping):
    return [mapping[k] for k in sorted(mapping, key=int)]


def preview(ui, state, snapshot, backdrop, fonts):
    from wowmock import (  # ty: ignore[import-not-found]
        INSET_FRAME_LAYOUT,
        draw_nine_slice,
        minimal_scrollbar,
        portrait_frame_art,
        three_slice_button,
        tiled,
        wrap_text,
    )

    canvas = backdrop(ui, 624, 648)
    x, y, w, h = 32, 40, 560, 560
    rock = ui.texture("interface/framegeneral/ui-background-rock.blp")
    tiled(canvas, rock, x + 2, y + 21, w - 4, h - 23, rock.width / ui.scale, rock.height / ui.scale)
    streaks = ui.atlas("_UI-Frame-TopTileStreaks")
    canvas.draw(streaks, x + 6, y + 21, w - 8, streaks.height)
    ix, iy, iw, ih = x + 16, y + 124, 528, 300
    marble = ui.texture("interface/framegeneral/ui-background-marble.blp")
    tiled(canvas, marble, ix, iy, iw, ih, marble.width / ui.scale, marble.height / ui.scale)
    draw_nine_slice(canvas, INSET_FRAME_LAYOUT, ix, iy, iw, ih)
    sx, sy, sw, sh = ix + 6, iy + 6, iw - 34, ih - 12
    minimal_scrollbar(canvas, sx + sw + 6, sy - 2, sh - 3)
    controls = []
    for control in values(snapshot["controls"]):
        anchor = values(control["anchor"])
        row = anchor[0] == "TOPLEFT"
        bx, by = (sx, sy - anchor[2]) if row else (x + anchor[1], y + h - anchor[2] - 26)
        bw = sw if row else control["width"]
        enabled = control["enabled"]
        three_slice_button(canvas, bx, by, bw, 26, control["text"], state="normal" if enabled else "disabled")
        if control["selected"]:
            # LockHighlight remains visible on disabled rows too; native highlight is ADD.
            canvas.draw(ui.atlas("128-RedButton-Highlight"), bx, by, bw, 26, blend="ADD")
        assert canvas.text_width(control["text"], fonts["GameFontNormal"]) < bw - 8, control["text"]
        if row:
            assert sx <= bx and sy <= by and bx + bw <= sx + sw and by + 26 <= sy + sh
        controls.append(dict(control, rect=[bx, by, bw, 26]))
    labels = []
    for label in values(snapshot["labels"]):
        point = values(label["points"])[0]
        p = values(point)
        lx, ly, lw = x + p[1], y - p[2], w - p[1] - 16
        lines = []
        for paragraph in label["text"].split("\n"):
            lines.extend(wrap_text(canvas, paragraph, fonts["GameFontHighlight"], lw))
        for i, line in enumerate(lines):
            canvas.text(lx, ly + i * 12, line, fonts["GameFontHighlight"])
        labels.append(dict(text=label["text"], rect=[lx, ly, lw, len(lines) * 12]))
    rects = [c["rect"] for c in controls] + [label["rect"] for label in labels]
    for i, (ax, ay, aw, ah) in enumerate(rects):
        for bx, by, bw, bh in rects[i + 1 :]:
            assert ax + aw <= bx or bx + bw <= ax or ay + ah <= by or by + bh <= ay, "overlap"
    portrait_frame_art(canvas, x, y, w, h, "interface/icons/inv_misc_spyglass_03.blp", "Journey stops")
    canvas.text(32, 8, "Illustrative mock - " + state, fonts["GameFontNormal"])
    canvas.text(32, 616, "Real controller, sample locations and stubbed terrain", fonts["GameFontDisableSmall"])
    canvas.text(32, 630, "Not a client capture", fonts["GameFontDisableSmall"])
    return canvas, dict(frame=[x, y, w, h], viewport=[sx, sy, sw, sh], controls=controls, labels=labels)


def render_stops_previews(root, wowmock, art, backdrop, fonts):
    out = root / "docs/previews/journey-stops"
    out.mkdir(parents=True, exist_ok=True)
    states = snapshots(root)
    record = dict(
        label="Illustrative mocks, not client captures",
        art_build="1.60.1.70124",
        pillow_version=Image.__version__,
        scenes={},
        assets={},
    )
    for state in ("empty", "draft", "running", "paused"):
        encoded = []
        for _ in range(2):
            ui = art(scale=2)
            canvas, layout = preview(ui, state, states[state], backdrop, fonts)
            buffer = io.BytesIO()
            canvas.image.save(buffer, format="PNG", optimize=True)
            encoded.append(buffer.getvalue())
        assert encoded[0] == encoded[1], state
        for name in sorted(ui._atlas_cache):
            _, member, atlas, size = ui._atlas_member(name)
            record["assets"][name] = dict(
                member=member["CommittedName"],
                set=atlas["UiTextureAtlasSetID"],
                file_data_id=atlas["FileDataID"],
                size=size,
                texcoords_pixels=[
                    member[k] for k in ("CommittedLeft", "CommittedTop", "CommittedRight", "CommittedBottom")
                ],
            )
        (out / (state + ".png")).write_bytes(encoded[0])
        record["scenes"][state] = dict(layout, sha256=hashlib.sha256(encoded[0]).hexdigest())
        print(state, record["scenes"][state]["sha256"], flush=True)
    (out / "assets.json").write_text(json.dumps(record.pop("assets"), indent=2) + "\n")
    (out / "layout.json").write_text(json.dumps(record, separators=(",", ":")) + "\n")

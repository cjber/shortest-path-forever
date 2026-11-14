# Journey editor illustrative previews

These are labelled illustrative mocks of the current `UI/JourneyStops.lua`, not client captures. Render with `FOREVER_CORE=/path/to/forever-core uv run --project tools --frozen --group dev python tools/screenshots.py --stops-previews`. Each invocation renders each image twice and checks encoded PNG bytes.

The adapter reuses the native frame stubs from `tests/journey_stops_ui_spec.lua`. It clicks the real UI and loads the real controller, StopOrder, itinerary and public API through `tests/journey_driver.lua`. Captured runtime labels, row anchors, enabled states and locked highlights drive the images. Terrain, map projection and coordinates are synthetic fixture inputs. The three actual place names are illustrative labels, not verified coordinates for those places. No provider node artwork is drawn because the runtime draws none.

Empty and draft retain the runtime help and status text. Draft insertion order is Thelsamar, Ironband's Excavation Site, Farstrider Lodge. Real deferred nearest-next ordering submits Ironband's Excavation Site, Farstrider Lodge, Thelsamar. Running and paused display that submitted order through `activeStops`, with editing disabled. The first row is the current stop. Pause and Resume follow the real controller; there is no Edit remaining action.

| Source/template | Attachment | Art | Set/crop | Border owner/layer |
| --- | --- | --- | --- | --- |
| `PortraitFrameTemplate` | 560 by 560 host at 32,40 | `PORTRAIT_FRAME_TEMPLATE_LAYOUT`, metal frame and `RedButton-Exit` | resolved members in assets.json | host NineSlice above content |
| TOC `X-Forever-Icon` | portrait at -5,-7, 62 square | `INV_Misc_Spyglass_03` | whole icon, native portrait alpha mask | host frame, portrait below frame |
| host background | inset 2,21 | native rock and `_UI-Frame-TopTileStreaks` | native tiling | background |
| `InsetFrameTemplate` | top 16,-124; bottom -16,136 | marble and `INSET_FRAME_LAYOUT` | native tiling and NineSlice | inset above background |
| `ScrollFrameTemplate` | inset 6,-6 to -28,6 | minimal scrollbar | native track, no thumb at zero range | scroll host |
| `SharedButtonSmallTemplate` | exact runtime bottom anchors; rows every 28 units | `128-RedButton` normal/disabled, ADD locked highlight | set 1; highlight is approved set 0 | template background and highlight |
| shared fonts | native help/status and centred button text | Friz, GameFontHighlight/Normal/Disable | 12 units | artwork |

`assets.json` records resolved atlas member, set, file ID, dimensions and source crop. `layout.json` records all four preview hashes and control/text rectangles. There are deliberately no source freshness hashes: the parent records final freshness after the parallel runtime work settles.

All four 1248 by 1296 PNGs were inspected at full resolution. Host corners, portrait crop, title, inset edges, button text, current-row selection and status lines fit without overlap or clipping. Rectangle and button text-width assertions also run during rendering. The logical host stays 560 by 560 in every state. The scene uses the suite renderer's native portrait mask, Camelot corner offsets, rock/marble surfaces, button slices and scrollbar; no invented borders or node art.

Native source checked: the local Blizzard UI extract's `Blizzard_UIPanelTemplates/Mainline/UIPanelTemplates.xml`, `Blizzard_SharedXML/Shared/Button/ThreeSliceButtonTemplate.xml` and `.lua`, `SecureUIPanelTemplates.lua`, and `Shared/Scroll/ScrollBar.lua`. Art stays pinned to 1.60.1.70124, with Pillow 13.0.0. Composition follows Core's `docs/ui-composition.md` and `docs/asset-registry.md`.

Limits: no same-window client capture exists in this task. Engine text rasterization and locked-highlight/disabled-font interaction are represented by the shared renderer, not validated in a running client. The minimal scrollbar helper draws its native normal arrow artwork at zero range; native source names a different disabled bottom-arrow member. These renders establish source-derived illustrative layout and state evidence only.

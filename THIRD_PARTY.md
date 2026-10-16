# Third-party inputs

Everything Shortest Path Forever is built from that it did not write itself: where each comes from, where its pin
lives, its licence, and whether any of it reaches the zip players install. A pin is named by the constant that holds
it, so a data refresh that moves the pin never leaves this file behind. The addon itself is GPL-3.0-or-later
([LICENSE](LICENSE)).

## Ships in the zip

| Input | Used for | Pin | Licence |
|---|---|---|---|
| WoW: Forever client tables, via [wago.tools](https://wago.tools) | Taxi paths, transports, lifts, portals and teleports in `Data/*.lua` | `BUILD` in `tools/gen_routes.py` (`tools/gen_transit.py` imports it) | Blizzard Entertainment's game data |
| [CMaNGOS classic-db](https://github.com/cmangos/classic-db) | Portal and teleport destinations, transport spawns and periods in `Data/*.lua` | `DB_REV` in `tools/gen_transit.py` | GPL-3.0 |
| [CMaNGOS mangos-classic](https://github.com/cmangos/mangos-classic) | The transport timetable model and flight speed, reimplemented in `tools/gen_routes.py` and `tools/gen_transit.py` | Cited by source file in those scripts; no code copied | GPL-2.0-or-later |
| [InFlight](https://github.com/LudiusMaximus/InFlight) | Recorded flight durations in `Data/Taxi.lua` | `INFLIGHT_REV` in `tools/gen_transit.py` | MIT |
| Local client terrain, baked with TrinityCore's tools | The walkable cells in `Nav/*.lua` (`tools/baker/README.md`) | `TRINITY_REV` in `tools/baker/bake.sh` and the client build baked | Derived data, GPL-3.0-or-later; Blizzard's EULA applies to the client files |

No embedded libraries ship. `media/` is this addon's own: the icon is drawn in `media/icon.svg`, `zeppelin.tga` by
`tools/draw_zeppelin.py`, and `Dot.tga` is a plain white disc.

## Read in game, never bundled

| Input | Used for | Licence |
|---|---|---|
| QuestieDB, if installed | Quest givers and objectives as route goals | QuestieDB carries no licence; nothing is copied |
| TomTom and RestedXP Guides, if installed | Waypoints and guide steps, through their public APIs | Their own; nothing is copied |
| TomTom's API, while TomTom is not installed | `Core/TomTom.lua` answers guide addons' TomTom calls, and `/way` reads its arguments as TomTom does | Our own code; only TomTom's public call names and `/way` syntax are followed |
| Adventure Guide Forever and Tweaks Forever, if installed | The RestedXP hand-off, and class trainers for nearby services, through their public APIs | GPL-3.0-or-later |

## Build and test only

| Input | Used for | Pin | Licence |
|---|---|---|---|
| [TrinityCore](https://github.com/TrinityCore/TrinityCore) with its vendored CascLib (MIT) and Recast/Detour (zlib) | Terrain extraction for the navigation bake, fetched and patched in `tools/baker/` | `TRINITY_REV` in `tools/baker/bake.sh` | GPL-2.0-or-later |
| [WoWDBDefs](https://github.com/wowdev/WoWDBDefs) | Reference for the Forever table layouts the baker reads | The commit linked in `tools/baker/README.md` | CC BY-SA 4.0 |
| [Blizzard UI source](https://github.com/Gethe/wow-ui-source) | The map, tracker and spinner specs, fetched into `tools/.cache/` | `revision` in `tools/fetch_blizzard_ui.sh`; `REVISION` in `tools/fetch_tracker_ui.py` | Blizzard Entertainment's; fetched, never committed |
| [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api) | lua-language-server types in `tools/typecheck.sh` | `revision` in `tools/typecheck.sh` | MIT |
| [forever_tools](https://github.com/cjber/skills/tree/main/wow-forever-addon/tooling/forever_tools) | Shared lints, release checks and the generated-data gate, vendored in `tools/forever_tools/` | `revision` in `tools/forever_tools/MANIFEST.json` | MIT |
| [wow-mock-screenshots](https://github.com/cjber/skills/tree/main/wow-mock-screenshots) and the client art it fetches | `tools/screenshots.py` | `WOWMOCK` (a local checkout); the art at `BUILD` in `tools/gen_routes.py` | MIT; the art is Blizzard Entertainment's, fetched at build time and committed only as it appears in `docs/screenshots/` |
| sift gate | `.sift/gate.py` and `.sift/agents.py` in CI | Vendored by `sift setup` | MIT (`.sift/LICENSE`) |

CI tools (StyLua, ruff, luacheck, shellcheck, shfmt, lua-language-server, actionlint, zizmor, gitleaks, the BigWigs
packager) are pinned in `.github/workflows/` and `tools/typecheck.sh`, except luajit and luacheck, which come from the runner's apt; they build and check the addon and are never
part of it.

## Ideas and contributors

Credit for the ideas, translations and reports behind the addon.

| Who | What | Notes |
|---|---|---|
| [Polestar](https://github.com/fitzforge/polestar) by Fitz | The ideas for knowing the Hearthstone bind point at login (#147), keeping a journey after `/reload` (#148), an eased, movable fallback arrow (#149), flights in flight master tooltips (#150), routing instance goals to the entrance (#151), stopping idle minimap updates (#152), the arrival sound (#155), the time left under the compass (#156) and the goal on the minimap rim (#157); `/path report` the `Subscribe` API and `tests/README.md` (cjber/adventure-guide-forever#159, #164), and the shared tooling's zip check, `tools/doctor.py`, stale-screenshot check and `.editorconfig`, plus this file, the issue forms and the "For addon authors" changelog subsection (cjber/adventure-guide-forever#156-#158, #160-#163, #165) | GPL-3.0. Inspired only; no code was copied. Fitz is welcome to use our code. |
| Fitz | Found that drawn walks skipped the line test at their ends, with reproductions (#144); the fix is our own (#187) | |
| Zavian | Found Shift-click on map pins blocking chat links, with the fix (#134) | |
| Osipanda | Found routes ignoring Forever's new boats (#84) | |
| Nightwind416 | Asked for a movable tracker and compass (#76) | |
| wfournier | Asked for the tracker and compass to scale (#122) | |
| maggew, on CurseForge | Asked for finer compass positioning (#160) | |

Thanks also to everyone else who reported a bug, here or on CurseForge.

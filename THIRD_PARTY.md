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

No embedded libraries ship.

## Read in game, never bundled

| Input | Used for | Licence |
|---|---|---|
| QuestieDB, if installed | Quest givers and objectives as route goals | No licence; nothing is copied |
| TomTom and RestedXP Guides, if installed | Waypoints and guide steps, through their public APIs | Their own; nothing is copied |

## Build and test only

| Input | Used for | Pin | Licence |
|---|---|---|---|
| [TrinityCore](https://github.com/TrinityCore/TrinityCore) with its vendored CascLib (MIT) and Recast/Detour (zlib) | Terrain extraction for the navigation bake, fetched and patched in `tools/baker/` | `TRINITY_REV` in `tools/baker/bake.sh` | GPL-2.0-or-later |
| [WoWDBDefs](https://github.com/wowdev/WoWDBDefs) | Reference for the Forever table layouts the baker reads | The commit linked in `tools/baker/README.md` | CC BY-SA 4.0 |
| [Blizzard UI source](https://github.com/Gethe/wow-ui-source) | The map, tracker and spinner specs, fetched into `tools/.cache/` | `revision` in `tools/fetch_blizzard_ui.sh`; `REVISION` in `tools/fetch_tracker_ui.py` | Blizzard Entertainment's; fetched, never committed |
| [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api) | lua-language-server types in `tools/typecheck.sh` | `revision` in `tools/typecheck.sh` | MIT |
| [forever_tools](https://github.com/cjber/skills/tree/main/wow-forever-addon/tooling) | Shared lints, release checks and the generated-data gate, vendored in `tools/forever_tools/` | `revision` in `tools/forever_tools/MANIFEST.json` | MIT |
| [wow-mock-screenshots](https://github.com/cjber/skills/tree/main/wow-mock-screenshots) and the client art it fetches | `tools/screenshots.py` | `WOWMOCK`; art at `BUILD` | MIT; the art is Blizzard Entertainment's |
| sift gate | `.sift/gate.py` and `.sift/agents.py` in CI | Vendored by `sift setup` | MIT (`.sift/LICENSE`) |

CI tools (StyLua, ruff, luacheck, shellcheck, shfmt, lua-language-server, actionlint, zizmor, gitleaks, the BigWigs
packager) are pinned in `.github/workflows/` and `tools/typecheck.sh`; they build and check the addon and are never
part of it.

# Third-party inputs

Everything Shortest Path Forever is built from that it did not write itself: where each comes from, where its pin
lives, its licence, and whether any of it reaches the zip players install. A pin is named by the constant that holds
it, so a data refresh that moves the pin never leaves this file behind. The addon itself is GPL-3.0-or-later
([LICENSE](LICENSE)).

## Ships in the zip

| Input | Used for | Pin | Licence |
|---|---|---|---|
| WoW: Forever client tables, via [wago.tools](https://wago.tools) | Taxi paths, transports, lifts, portals, teleports, food and drink items, and profession spells in `Data/*.lua` | `BUILD` in `tools/gen_routes.py` (`tools/gen_transit.py` and `tools/gen_services.py` import it) | Blizzard Entertainment's game data |
| [CMaNGOS classic-db](https://github.com/cmangos/classic-db) | Portal and teleport destinations, transport spawns and periods, trainer NPCs and spells, and the heights of NPC and quest object spawns in `Data/*.lua` | `DB_REV` in `tools/gen_transit.py` (`tools/gen_services.py` and `tools/gen_heights.py` import it) | GPL-3.0 |
| [CMaNGOS mangos-classic](https://github.com/cmangos/mangos-classic) | The transport timetable model and flight speed, reimplemented in `tools/gen_routes.py` and `tools/gen_transit.py` | Cited by source file in those scripts; no code copied | GPL-2.0-or-later |
| [InFlight](https://github.com/LudiusMaximus/InFlight) | Recorded flight durations in `Data/Taxi.lua` | `INFLIGHT_REV` in `tools/gen_transit.py` | MIT |
| Local client terrain, baked with TrinityCore's tools | The walkable cells in `Nav/*.lua` (`tools/baker/README.md`) | `TRINITY_REV` in `tools/baker/bake.sh` and the client build baked | Derived data, GPL-3.0-or-later; Blizzard's EULA applies to the client files |

No embedded libraries ship. `media/` is this addon's own: the icon is drawn in `media/icon.svg`, the feathered
`Dot.tga` is the route-stroke brush, `Zeppelin.tga` is the zeppelin map marker, `Pin.tga` is the gold goal pin and
`PinInactive.tga` its bronze untracked twin, and `Numbers/1.tga` to `Numbers/25.tga` are the gold numbered markers,
all original assets made for this addon with AI assistance and no Blizzard art; the pins and the numbered markers are
generated from `tools/pin_source` and `tools/pin_source/numbers` by `tools/export_pin.py`. Boat markers use
Blizzard's `flightmasterferry` atlas, which has no zeppelin equivalent.
`Locales/*.lua` are machine translated, using the client's own GlobalStrings for the pinned build (via wago.tools)
as the glossary for game terms; eight frFR lines are Brainc3ll's.

## Read in game, never bundled

| Input | Used for | Licence |
|---|---|---|
| QuestieDB, if installed | Quest givers and objectives as route goals | QuestieDB carries no licence; nothing is copied |
| TomTom, RestedXP Guides and Guidelime, if installed | Waypoints and guide steps, through their public APIs | Their own; nothing is copied |
| TomTom's API, while TomTom is not installed | `Core/TomTom.lua` answers guide addons' TomTom calls, and `/way` reads its arguments as TomTom does | Our own code; only TomTom's public call names and `/way` syntax are followed |
| Adventure Guide Forever and Tweaks Forever, if installed | The RestedXP hand-off, and class trainers for nearby services, through their public APIs | GPL-3.0-or-later |

## Build and test only

| Input | Used for | Pin | Licence |
|---|---|---|---|
| [TrinityCore](https://github.com/TrinityCore/TrinityCore) with its vendored CascLib (MIT) and Recast/Detour (zlib) | Terrain extraction for the navigation bake, fetched and patched in `tools/baker/` | `TRINITY_REV` in `tools/baker/bake.sh` | GPL-2.0-or-later |
| [WoWDBDefs](https://github.com/wowdev/WoWDBDefs) | Reference for the Forever table layouts the baker reads | The commit linked in `tools/baker/README.md` | CC BY-SA 4.0 |
| [Blizzard UI source](https://github.com/Gethe/wow-ui-source) | The map and spinner specs, fetched into `tools/.cache/` | `revision` in `tools/fetch_blizzard_ui.sh`; the simulator pin in `tools/forever_sim/fetch.py` | Blizzard Entertainment's; fetched, never committed |
| [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api) | lua-language-server types in `tools/typecheck.sh` | `revision` in `tools/typecheck.sh` | MIT |
| [forever_tools](https://github.com/cjber/forever-core/tree/main/.agents/skills/wow-forever-addon/tooling/forever_tools) | Shared lints, release checks and the generated-data gate, vendored in `tools/forever_tools/` | `revision` in `tools/forever_tools/MANIFEST.json` | MIT |
| [forever-core/tools/wowmock](https://github.com/cjber/forever-core/tree/main/tools/wowmock) and the client art it fetches | `tools/screenshots.py` | `FOREVER_CORE` (a local forever-core checkout); UI art at `UI_ART_BUILD` in `tools/screenshots_art.py`, map content at `BUILD` in `tools/gen_routes.py` | MIT; the art is Blizzard Entertainment's, fetched at build time and committed only as it appears in `docs/screenshots/` |
| Ko-fi's Support me on Ko-fi button | The support button in the README (`ko-fi.com/img/githubbutton_sm.svg`) and its PNG render, `docs/kofi-button.png`, in the store description | None: the README links Ko-fi's live file; the PNG is rendered from it | Ko-fi's brand asset, used as Ko-fi provides it for linking to a Ko-fi page |
| `docs/github-sponsors-button.png` | The GitHub Sponsors button in the README and store description; drawn here to match the Ko-fi button, with the heart from GitHub's [Octicons](https://github.com/primer/octicons) and the Adwaita Sans font | None | Octicons: MIT; Adwaita Sans: SIL OFL 1.1 |
| `docs/discord-button.png` | The Discord button on the store page; drawn in forever-core with Discord's logo from [Simple Icons](https://simpleicons.org) and the Adwaita Sans font | None | Simple Icons: CC0; Adwaita Sans: SIL OFL 1.1; the logo is Discord's, used to link to a Discord server |

CI tools (StyLua, ruff, luacheck, shellcheck, shfmt, lua-language-server, actionlint, zizmor, gitleaks, the BigWigs
packager) are pinned in `.github/workflows/` and `tools/typecheck.sh`, except luajit and luacheck, which come from the runner's apt; they build and check the addon and are never
part of it.

## Players

Credit for the reports and requests behind the addon.

| Who | What | Notes |
|---|---|---|
| Fitz | Walks checked at both ends | GitHub; #144 |
| TRDeadbeat | Gamepad interface no longer freezes or blocks | CurseForge; #158 |
| tallsmartman | Gamepad interface no longer freezes or blocks | CurseForge; #158 |
| Sol\_Deus | Gamepad interface no longer freezes or blocks | CurseForge; #158 |
| Zavian | Shift-click map pins no longer block chat links | GitHub; #134 |
| Osipanda | Routes use Forever's new boats | GitHub; #84 |
| Nightwind416 | Movable tracker and compass | GitHub; #76 |
| wfournier | Tracker and compass scale | GitHub; #122 |
| The\_\_\_Fast | Fixed a phantom flight path | CurseForge |
| The\_\_\_Fast | A minimum Hearthstone saving | CurseForge |
| cidolfus27 | Journeys follow RestedXP guides | CurseForge |
| Alex21xx | Choice of yards or metres | CurseForge; 1.14.0 |
| Alex21xx | Resume guide returns to the current step | CurseForge; 1.14.0 |
| Alex21xx | Complete this step ticks a step off | CurseForge; 1.14.0 |
| Alex21xx | Minimap button opens the settings | CurseForge; 1.14.0 |
| Alex21xx | Right-click a flight master marks it known | CurseForge; 1.14.0 |
| Alex21xx | Connecting flights only through known points | CurseForge; 1.15.0 |
| o0saw0o | Hide journey steps and arrow, keep the map route | CurseForge |
| Merlinqt | Map icon sizes | CurseForge |
| Maggew | Fixed the division-by-zero route error | CurseForge; 1.15.0 |
| Maggew | Destination pin names the current step | CurseForge; 1.15.0 |
| Maggew | Optional background behind the compass | CurseForge; 1.15.0 |
| Maggew | Finer compass placement | CurseForge; #160 |
| Maggew | Arrow keys nudge the compass | CurseForge; 1.17.0 |
| team\_Brigade | Hide the empty tracker's title | CurseForge |
| phear | Hide the empty tracker's title | CurseForge |
| Testvonfarkle | Hide the empty tracker's title | CurseForge |
| rydoc | Fixed the Journey collapsing into the quest tracker | CurseForge |
| Joster91 | Fixed the Journey overlapping the quest tracker | CurseForge |
| Joster91 | No more waypoint spam at level-up | CurseForge; #245 |
| deathmvp1 | Guidelime guides can lead the journey | CurseForge; #506 |
| saikoso | Fixed the missing Dalaran–Stormwind portal route | CurseForge; #226 |
| Ragnarok11B | Quest tracker movable after hiding journey steps | CurseForge; #227 |
| GenericP | Plan to a spot under a Questie icon | CurseForge |
| GenericP | Journeys start from TomTom waypoints | CurseForge |
| [Brainc3ll](https://github.com/Brainc3ll) | Eight French translation lines | GitHub; cjber/legacy-forever#99 |
| [Mouchoir](https://github.com/Mouchoir) | Fixed the arrow hidden behind the game's marker (code) | GitHub; #224, PR #225 |
| [z1ck](https://github.com/z1ck) | Travel journal starts off | GitHub; #269, #270 |
| Oxds | Walking route line colour | CurseForge; #411 |
| sean16981 | Key bindings for journey actions | GitHub; #412 |
| Stiandresius | Zeppelin pin no longer vanishes when zoomed | CurseForge; #393 |
| Stiandresius | Zeppelins get their own dock icon | CurseForge; #394 |
| Stiandresius | Zeppelin pin drawn in the right zone | CurseForge; #414 |
| aryaxo | Hint when a flight would be quicker | GitHub; #539 |
| Exo\_NA | Unknown flight points no longer marked as known | CurseForge; #555 |
| legortiz | Unknown flight points no longer marked as known | CurseForge; #555 |
| JohnChrin | First journey after login no longer stalls | GitHub; #317 |
| wheelbarrel00 | Column stays clear of EQ Objective Tracker's list | GitHub; #395 |
| lkshrk | Tracker header no longer opens the map in combat (code) | GitHub; #444, PR #445 |
| HeartOfD2 | Waypoint UI bends land on the route | GitHub; #454 |
| rml9ty | Long journeys to another continent appear | GitHub; #516 |
| hwalflor | Lighter map redraw while zooming | GitHub; #529 |
| chris-chrysos | Flights only between known flight points | GitHub; #537 |
| Quantity-4 | Unknown flight points no longer marked as known | GitHub; #555 |
| Bolton\_wow | Unknown flight points no longer marked as known | CurseForge; 8673972 |
| Aldericdevir | Journeys to quests with only a start pin | GitHub; #629 |
| joaocjesus | Controller route waits for the map to close (code) | GitHub; #581, PR #580 |
| jakerist (Grayburn) | Destination pin points the right way | GitHub; #624 |
| MacieGx | Stop right-clicks work first time (code) | GitHub; #542, PR #533 |
| MacieGx | Walks start and end on your floor (code) | GitHub; PR #574, PR #696 |
| MacieGx | Nearby goods suit your level (code) | GitHub; PR #601 |
| MacieGx | Your own profession trainers come first (code) | GitHub; PR #704 |
| borick7318 | Metres match the game's distances | Discord; #668 |
| cotijelucie | Hide travel marks on the world map | Discord; #635 |
| cotijelucie | Town services drawn on the world map | Discord; #739 |
| sampconrad | Arrow becomes a pin on arrival | CurseForge; #627 |
| jixxor | Stormwind walks follow the streets | Discord; #602 |
| Gaafah | Option to hide the walking line | CurseForge; #576 |
| \_spada | Journey steps can leave the tracker | Discord; #563 |
| vladsnz | No second marker beside the character | CurseForge; #531 |
| macwire | Option to follow roads | CurseForge; #498 |
| scraak | Routes through a party mage's portals | CurseForge; #353 |
| overspark | In-world destination pin | CurseForge; #271 |
| TeeRKee | Route for the tracked quest on the minimap | GitHub; #466 |
| Speaker1264 | Combat Text taint fixed | GitHub; #457 |
| SuubzTV | Fixed the RestedXP guidance regression | CurseForge; #458 |
| Fel7 | Build a path returns to the quest menu | CurseForge; #459 |
| Kragmars | Objective lines under the arrow and pin | Discord; #660 |
| spidersylar | Known flight points kept per character | CurseForge; #685 |
| Acem | Known flight points kept per character | CurseForge; #685 |
| tgkGate | Fixed the path job yield error | CurseForge; #717 |
| IronmanBG | Plan journey back in Kaliel's Tracker | CurseForge; #718 |
| vladsnz | Quest list More options works with a controller | CurseForge; #788 |
| vcatalin | Forever Core bundled in the download again | GitHub; #731 |

## Inspired by

Credit for the addons and projects an idea came from.

| Who | What | Notes |
|---|---|---|
| [Polestar](https://github.com/fitzforge/polestar) by Fitz | Ideas for many features | Hearthstone learning, journeys after `/reload`, the fallback arrow, flight tooltips, instance routing, compass time, minimap rim, own map frames, and the shared report window and tooling. GPL-3.0. Inspired only; no code was copied. Fitz is welcome to use our code. |
| Ding! by Yendi | Walks that keep out of zones far above your level | Inspired only; no code was copied. |

Thanks also to everyone else who reported a bug or asked for a feature, here or on CurseForge.

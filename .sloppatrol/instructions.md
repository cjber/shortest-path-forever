# About the code

Shortest Path Forever is a World of Warcraft: Forever addon in Lua 5.1. The files `ShortestPathForever.toc` lists are
what the game loads; `tests/*_spec.lua` load them in that order inside a stubbed client.

- Keep every saved variable name and every global the TOC exposes unchanged.
- Generated data, `Libs/` and `tools/forever_tools/` are never edited by hand.
- Taint: never replace a Blizzard global or hook a secure function a spec does not already hook.
- Never use the network, and never start the game, Battle.net, Lutris or Wine. The headless client (forever-core's `wow-forever-addon/in-game.md`) tests the build linked into the game, not this checkout, so in-game checks belong to the agent that ships a change.

`python3 tools/repo_rules.py` holds the rules no linter covers; run it with the other checks.

## Live roots

Things reached indirectly: none of them is dead code, even when no file calls it by name.

- `ShortestPathForever.toc` file list: load order; every listed file runs at login.
- `UI/Map.xml` templates name the global mixins (`ShortestPathForever*PinMixin`); Blizzard's map canvas calls
  their `OnLoad`, `OnAcquired`, `OnReleased`, `OnMouseEnter`/`OnMouseLeave`, `OnClick`,
  `OnCanvasScaleChanged`, `OnCanvasSizeChanged` by name. Data-provider mixins' `RefreshAllData`,
  `RemoveAllData`, `OnAdded`, `OnRemoved`, `OnMapChanged` likewise.
- Tracker module methods (`UI/Tracker.lua`) are called by the addon-owned `ForeverTrackerHost` in
  `UI/TrackerHost.lua`; this host never registers the module with `ObjectiveTrackerManager`.
- `ns.X` / `function ns.X` exports are the cross-file API; a symbol defined in one file is used in another
  (and by specs via `loadfile(...)("ShortestPathForever", ns)`). Search every `.lua`, not just the file.
- `Nav/Nav.xml` loads compressed walking-map fields; `Routing/PathGrid.lua` decodes them on demand.
- SavedVariables `ShortestPathForeverDB` / `ShortestPathForeverCharDB`: keys (settings in Core/Core.lua
  `DEFAULTS`, `anchors` owned by Transport/Timetable.lua, debug trace) persist in players' saved files.
- Sync wire format (Transport/Sync.lua, prefix `ShortPath1`): other players run older versions; message fields are
  a compatibility contract.
- Slash commands `/path`, `/shortestpath` (`SLASH_SHORTESTPATHFOREVER*`, `SlashCmdList`) and `/spfnear`
  (`SLASH_SPFNEAR1`, `SlashCmdList.SPFNEAR`, UI/Nearby.lua).
- UI/Nearby.lua reads two optional globals other addons define: `LibQuestieDB` and `TweaksForever.API`.
- `tools/*.py` are run by hand (README), except those a workflow runs: `ci.yml` runs `check_generated.py`,
  `changelog.py --check`, `repo_rules.py`, `fetch_tracker_ui.py` and `typecheck.sh`; `release.yml` runs `release_check.py` and
  `changelog.py`; `shared-tracker.yml` runs `check_shared_tracker.py`.
  `tools/bake_walks.lua` writes `Data/Walks.lua`; `tools/baker/bake.sh` builds pinned TrinityCore tools
  and runs `trinity.py`, `gen_nav.py` and `pack_nav.py`.
- Test seams: `Path.after`, `Path.clock` and `Path.budget` are replaced by specs. Specs that load Journey without
  the walking search get `tests/path_fake.lua`, the whole `ns.Path` surface Journey calls; Journey has no
  branch for a missing or partial `ns.Path`. Planner.Plan's
  `exactMaps` option has no runtime caller; planner_spec and journey_optimal_spec use it for exact-cost
  plans, so it stays.
- The `taxiLog` / debug trace in SavedVariables is read by a human after `/path debug`; a bounded,
  debug-gated write there is a live output, not residue.
- `tests/journey_driver.lua` is a helper loaded by the journey specs; `journey_bench.lua` and
  `walk_sim.lua` are run by hand (README), `memory_bench.lua` and `nav_compare.lua` likewise
  (`tests/*_performance.md`). `journey_bench.lua` reads `job.frames` and `settleRound`, and specs replace
  `Path.clusters`, `Path.cacheKB` and `Path.graphKB`, so those stay.
- `tests/api_ui.lua` rebinds `ns.Routes`/`ns.Docks` after load, which keeps UI/Route.lua's geometry-cache
  identity reset and the `ns.JourneyStops` guard live. `Path.decodes` exists for `runtime_bench.lua`.
- `tools/pack_nav.py`'s chunk-table `pack()` converts older shipped maps; `tools/baker/README.md` documents it,
  so it is live even though current bakes never need it.
- `tools/.cache` from the primary checkout is not enough for `gen_transit.py --offline`: it looks for
  `InFlight-<rev>-Defaults.lua`/`-LICENSE` and the cache holds unversioned names. `gen_routes.py --offline` works.

## Settled

Shapes that look like defects here but are not. Add an entry when the same shape keeps being raised and
dismissed for the same reason.

- **walk progress per surface**: `UI/Arrow.lua` (`ns.RefreshGuideStops`), `UI/Tracker.lua` (`JourneyDistance`) and
  Journey's `OnWalk` each project the player onto a walk, but for different contracts (arrow stop advance, tracker
  yards, planner replanning); they are not one fact.
- **WalkPlaces provenance**: `ns.WalkPlaces` in the shipped `Data/Walks.lua` is read only by `planner_spec.lua`,
  which checks the baked walks were built from the current places; CI consumes it, so it is live.
- **Blizzard-called handlers**: `tools/fetch_blizzard_ui.sh` does not pin the ObjectiveTracker Block/Module
  files, so a handler such as `OnBlockHeaderClick` (called by `Blizzard_ObjectiveTrackerBlock.lua`) has no caller
  in the tree and is still live.
- **partial-load guard**: a nil check on `ns.db`, `ns.Teleports`, `ns.Landmasses` or `C_AddOns` that a spec or
  UI check needs because it loads the module without the rest of the addon (`Core/PlanContext.lua` under
  `tests/plan_context_spec.lua`, `/path perf` in `UI/Settings.lua` under `tests/activity_ui.lua`).
- **byte-shared tracker files**: `UI/TrackerHost.lua`, `tools/fetch_tracker_ui.py` and
  `tests/tracker_host_spec.lua` are held byte-identical across four addon repositories by
  `tools/check_shared_tracker.py`. An export, comment or override that nothing here uses can have a reader in a
  sibling repository, and a copy of this repository's own helper there cannot be folded in.
- **middle dot join**: `tests/locales_spec.lua` requires two joined phrases to go through `L["%s · %s"]`, so the
  middle dot in shown text is the project's join form.

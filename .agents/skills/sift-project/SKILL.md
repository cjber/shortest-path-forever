---
name: sift-project
description: "Project profile for sift in Shortest Path Forever: the exact quality-gate and evidence commands, live roots that must never be deleted as dead code, exclusions, conventions and risk order. Load before running sift or any code-quality, cleanup or dead-code work in this repository."
---

# sift project profile — Shortest Path Forever

<!-- Written by `sift setup`. Keep it factual: every command here has been run and works.
     Update it whenever an audit learns something (a live root, a false-positive source). -->

A World of Warcraft: Forever (Classic, `## Interface: 16001`) addon that plans journeys (walking, flights,
boats, lifts, tram, portals) and draws them on the map. Runtime is the WoW client's Lua 5.1 sandbox; files
load in `.toc` order and share one namespace table (`local addonName, ns = ...`). It ships through
BigWigs packager (`.pkgmeta`) to CurseForge/Wago/GitHub as one zip that also carries three load-on-demand
walking-map addons. The specs run headless under LuaJIT with stubbed WoW APIs. Python, shell scripts and
C# under `tools/` generate the data offline; `.pkgmeta` keeps `tools/` and `tests/` out of the zip.

## Gate

Run in order from the repository root. All must pass before and after any audit slice.

| Step | Command | Pass means |
|---|---|---|
| Format (Lua) | `stylua --check .` | exit 0 (StyLua 2.5.2) |
| Format (Python) | `ruff format --check .` | exit 0 (ruff 0.16.8, `ruff.toml`) |
| Format (shell) | `shfmt -d tools/baker/bake.sh tools/typecheck.sh` | no diff |
| Lint (Lua) | `luacheck .` | `0 warnings / 0 errors` |
| Lint (Python) | `ruff check .` | `All checks passed!` |
| Lint (shell) | `shellcheck tools/baker/bake.sh tools/typecheck.sh` | exit 0 |
| Types (Lua) | `tools/typecheck.sh` | zero diagnostics at Information level; multi-value lint and gate regression tests pass |
| Tests | `for s in tests/*_spec.lua; do luajit "$s" \|\| exit 1; done` | every spec prints `…: ok`; ~25 s total |
| Workflows | `actionlint && zizmor --offline .github` | exit 0 / "No findings" |
| Secrets | `gitleaks git --redact --no-banner .` | `no leaks found` |
| Project rules | `python3 .sift/gate.py --base origin/main && python3 .sift/agents.py check` | exit 0 |

When the two workflow linters are not on PATH, `go run github.com/rhysd/actionlint/cmd/actionlint@latest`
and `uvx zizmor --offline .github` run the same checks.

Not in the gate but worth running after touching the planner: `luajit -joff tests/journey_bench.lua`,
`luajit tests/walk_sim.lua` (README lists both). After touching Map, Route, Tracker, Settings or the
public API, run `tests/ui.sh`: the `tests/*_ui.lua` checks load `tests/ui_client.lua`, `tests/ui_map.lua` and Blizzard's UI source
(fetched pinned by `tools/fetch_blizzard_ui.sh`). CI runs it too.

## Evidence

On-demand tools for audits. Output is candidates, never verdicts.

| Concern | Command | Known false positives |
|---|---|---|
| Dead code (Lua) | `luacheck .` (unused locals/values; clean today) | none so far |
| Diagnostics (Lua) | `tools/typecheck.sh` (file:line diagnostics and counts; JSON in `.types/diagnostics.json`) | tests/tools are excluded from LuaLS; all TOC runtime files, including generated data, are checked |
| Dead code (Python) | `uvx vulture tools --min-confidence 60` | clean today |
| Types (Python) | `uvx --with pillow ty check --extra-search-path tools --python-version 3.10 tools` | 5 inference errors in `gen_nav.py` (tuple unpacking, `dict.get` keys) + Pillow `Image.LANCZOS` — not bugs |
| Large files | `python3 .sift/gate.py --rule file-size-no-growth --all` | lists files over 1000 lines; none remain, so any listed file is a regression |
| Duplication | `npx --yes jscpd@4 --silent --reporters json --output .sift/runs/jscpd --ignore '**/ShortestPathForever_Nav*/**,**/Data/**,**/.sift/**,**/media/**,LICENSE' .` | the test harness preambles (`walk_sim`, `journey_bench`, `journey_optimal_spec`) repeat stub setup; whole-file clones among `tests/*_ui.lua` are their long-string bodies |
| Unread `ns` members | the `ns-defined`/`ns-once` pipeline in the sift skill's `languages/lua.md` | its regex has no word boundary, so `options.revision` reads as `ns.revision` |
| Standards pack | `SIFT_STANDARDS_PATH=$HOME/skills python3 <sift>/scripts/agents.py standards` | `wow-forever-addon` lives in `~/skills`, which the default search path misses |
| Live roots (Lua) | `rg -n 'RegisterEvent\|SetScript\|hooksecurefunc\|SLASH_\|SlashCmdList\|LoadAddOn\|SendAddonMessage' -g '*.lua'` | — |

## Live roots

Things reached indirectly. The dead-code lens must treat these as referenced.

- `ShortestPathForever.toc` file list — load order; every listed file runs at login.
- `Map.xml` templates name the global mixins (`ShortestPathForever*PinMixin`); Blizzard's map canvas calls
  their `OnLoad`, `OnAcquired`, `OnReleased`, `OnMouseEnter`/`OnMouseLeave`, `OnClick`,
  `OnCanvasScaleChanged`, `OnCanvasSizeChanged` by name. Data-provider mixins' `RefreshAllData`,
  `RemoveAllData`, `OnAdded`, `OnRemoved`, `OnMapChanged` likewise.
- ObjectiveTracker module methods (Tracker.lua) are called by `ObjectiveTrackerManager`.
- `ns.X` / `function ns.X` exports are the cross-file API; a symbol defined in one file is used in another
  (and by specs via `loadfile(...)("ShortestPathForever", ns)`). Search every `.lua`, not just the file.
- `C_AddOns.LoadAddOn("ShortestPathForever_Nav" .. map)` (PathGrid.lua) loads the walking maps by built name.
- SavedVariables `ShortestPathForeverDB` / `ShortestPathForeverCharDB`: keys (settings in Core.lua
  `DEFAULTS`, `anchors`, debug trace) persist in players' saved files.
- Sync wire format (Sync.lua, prefix `ShortPath1`): other players run older versions; message fields are
  a compatibility contract.
- Slash commands `/path`, `/shortestpath` (`SLASH_SHORTESTPATHFOREVER*`, `SlashCmdList`).
- `tools/*.py` are run by hand (README) and `tools/changelog.py` by `.github/workflows/release.yml`;
  `tools/bake_walks.lua` writes `Data/Walks.lua`; `tools/baker/bake.sh` drives `gen_nav.py` and the C# baker.
- Test seams: `Path.after`, `Path.clock` and `Path.budget` are replaced by specs; Journey's `ns.Path == nil`
  branches serve specs that load Journey without Path. Guards around them are not dead. Planner.Plan's
  `exactMaps` option has no runtime caller; planner_spec and journey_optimal_spec use it for exact-cost
  plans, so it stays.
- The `taxiLog` / debug trace in SavedVariables is read by a human after `/path debug`; a bounded,
  debug-gated write there is a live output, not residue.
- `tests/journey_driver.lua` is a helper loaded by the journey specs; `journey_bench.lua` and
  `walk_sim.lua` are run by hand (README).
- `tests/api_ui.lua` rebinds `ns.Routes`/`ns.Docks` after load, which keeps Route.lua's geometry-cache
  identity reset and the `ns.JourneyStops` guard live. `Path.decodes` exists for `runtime_bench.lua`.
- `tools/pack_nav.py`'s chunk-table `pack()` converts older shipped maps; `tools/baker/README.md` documents it,
  so it is live even though current bakes never need it.
- `tools/.cache` from the primary checkout is not enough for `gen_transit.py --offline`: it looks for
  `InFlight-<rev>-Defaults.lua`/`-LICENSE` and the cache holds unversioned names. `gen_routes.py --offline` works.

## Zones

How each part of the tree is reviewed. Unlisted paths are `production`.

| Path | Zone | Reason |
|---|---|---|
| `Data/Routes.lua`, `Data/Taxi.lua`, `Data/Transports.lua`, `Data/Portals.lua` | generated | `tools/gen_*.py`, "do not edit" header |
| `Data/Walks.lua` | generated | `luajit tools/bake_walks.lua > Data/Walks.lua` |
| `ShortestPathForever_Nav*/` | generated | `tools/baker/gen_nav.py` + `bake.sh`; excluded from luacheck/stylua/gitleaks |
| `tools/` | script | offline data generators, never shipped |
| `tools/baker/mappster.patch` | vendor | patch against upstream Mappster |
| `tests/` | test | headless LuaJIT specs, harnesses and a bench |
| `tests/*_ui.lua`, `tests/activity_bench.lua`, `tests/runtime_bench.lua` | test | load `tests/ui_client.lua` and `tests/ui_map.lua`; the UI checks run in CI, the benches locally |
| `tests/*_performance.md`, `README.md`, `docs/*.md`, `types/README.md`, `tools/baker/README.md` | docs | `docs/curseforge.md` is store copy: proposals only |
| `types/` | config (types) | LuaLS declarations for Forever and addon contracts; never shipped |
| `CHANGELOG.md` | docs (history) | each entry is a release note; kept verbatim by policy |
| `.github/`, `.pkgmeta`, `.luacheckrc`, `.luarc.json`, `stylua.toml`, `ruff.toml`, `.gitleaks.toml` | config | |
| `media/` | asset | |

## Conventions

- Tabs, 120 columns (StyLua, luacheck, ruff). Double quotes.
- Each file receives TOC varargs; `---@class SPFNamespace` on `local ns = select(2, ...)` joins its API and publishes modules as `ns.Name`
  tables; locals cache `ns.Model` etc. at file top. Globals only where WoW requires them (mixins,
  SavedVariables, slash commands) — all listed in `.luacheckrc`.
- Modules start via `ns.Init(fn)` after `ADDON_LOADED`, each under `xpcall` so one failure does not stop
  the rest (Core.lua `Start`).
- Comments explain why, in full sentences, often citing the Blizzard source file and line a behaviour
  depends on; they are the project's documentation style, not narration.
- Specs are plain LuaJIT scripts with `assert`, stubbing WoW APIs and loading production files by
  `loadfile`; they end by printing `<name>: ok`.
- Generated files carry a `-- Generated by … — do not edit.` header naming their generator.
- Any string a generator emits (headers, fit tables, messages) is generated data: changing it is a data
  diff, so such findings are reported, not applied during an audit.
- The route and transit data regenerate byte-identically offline once `tools/.cache` is filled
  (`gen_routes.py --offline`, `gen_transit.py`), so a generator refactor is provable by an empty
  `git diff Data`. `gen_nav.py` needs the mmtiles and cannot be checked that way.
- Settings defaults live once, in Core.lua `DEFAULTS` (exported as `ns.Defaults`); the panel reads them.
- The BigWigs packager already drops dotfiles and git-ignored paths from the zip; `.pkgmeta` `ignore`
  only needs visible, tracked files (e.g. `ruff.toml`, `tools/`, `tests/`).

## Risk order

Audit slices from lowest to highest risk:

1. docs + config (`README.md`, `tools/baker/README.md`, `tests/journey_performance.md`, config files)
2. `tools/` — offline generators; output is checked in, so a change is visible as a data diff
3. `tests/`
4. UI leaves: `Alert.lua`, `Arrow.lua`, `Compass.lua`, `Settings.lua`, `Taxi.lua`, `Tracker.lua`, `MinimapPins.lua`
5. Map layers: `Map.lua`, `Map.xml`, `Route.lua`, `RouteTransports.lua`, `Looks.lua`
6. State and wire: `Model.lua`, `Core.lua`, `Observer.lua`, `Sync.lua`, `API.lua` (SavedVariables, wire format,
   public API)
7. Planning core: `Planner.lua`, `Path*.lua`, `Journey*.lua`, `Corpse.lua` (performance-tuned, 3 ms frame budget;
   Corpse.lua suspends and resumes the journey)

## Project rules and lenses

- Rules: `file-size-no-growth` (`.sift/scripts/`, from the sift catalog) fails a change that adds
  a file over 1000 lines or grows one. Generated `Data/*.lua` and `ShortestPathForever_Nav*/*.lua`
  are excluded.
- Lenses: none yet.

## Settled

Shapes that look like defects here but are not. Reviewers and verifiers read this before raising a
finding; audits add an entry when verifiers keep dismissing the same shape for the same reason.

- **walk progress per surface**: `Arrow.lua` (`ns.RefreshGuideStops`), `Tracker.lua` (`JourneyDistance`) and
  Journey's `OnWalk` each project the player onto a walk, but for different contracts (arrow stop advance, tracker
  yards, planner replanning); they are not one fact.
- **WalkPlaces provenance**: `ns.WalkPlaces` in the shipped `Data/Walks.lua` is read only by `planner_spec.lua`,
  which checks the baked walks were built from the current places; CI consumes it, so it is live.
- **Blizzard-called handlers**: `tools/fetch_blizzard_ui.sh` does not pin the ObjectiveTracker Block/Module
  files, so a handler such as `OnBlockHeaderClick` (called by `Blizzard_ObjectiveTrackerBlock.lua`) has no caller
  in the tree and is still live.

## Anti-patterns

Shapes this codebase keeps producing. Check new code against them.

- **orphaned comment**: a comment left behind when the code it explains moves (`comment-narration`): `Route.lua`
  GoalPin atlas note after #27; `gen_nav.py` naming the wrong setter for its globals; `.luacheckrc` group comments
  naming `Path.lua` after the `PathGrid.lua` split.
- **bare-string closed set**: a closed set passed around as bare strings with `string` types (`stringly-typed`):
  Path failure reasons (`Journey.lua` `WALK_FAILURE`), sighting `source` `"you"|"player"` (`Model.lua`), crossing
  modes in `Route.lua`.
- **second copy of a fact**: another module's fact restated (`parallel-implementations`): Compass's
  `transportIcons` beside `ns.SetTransportIcon`; `bakedBound` (`JourneyCosts.lua`) re-deriving Planner's
  Walks.lua keys; the TaxiPathNode stop flag as a literal in `gen_transit.py`.
- **stale spec stub**: spec, bench and UI-harness stubs outliving the production field they stood in for
  (`dead-code`): `owner.loading` in `memory_bench.lua`, a `NewTicker` stub in `sync_spec.lua`, client stubs in
  `tests/ui_client.lua` and `tests/ui_map.lua`.
- **dead lint config**: `.luacheckrc` ignores and globals no file needs any more; delete them when the code they
  covered goes.
- **docs missing a new file**: README, AGENTS.md and `docs/` lists that miss a generated table or check added later.
- **guard on a defined function**: `if ns.X then` around a function or table defined unconditionally earlier in the
  TOC (`Itinerary.lua`, `RouteTransports.lua`).

The type gate also runs `python3 -m tools.lint_taint` and `python3 tools/typecheck_coverage.py`: native-method hooks, shared UI-state writes and omitted runtime type coverage fail CI. TrackerHost owns addon sections and pools outside Blizzard's registry; first rendering follows both native load events, deferred one frame. CI runs the private host against pinned Forever module/block/animation source.

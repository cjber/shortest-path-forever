# Issue #504: minimap gold area around the blue quest blob

## What changed

The minimap's gold step area was produced by recolouring `Minimap`'s **quest blob ring** texture. That ring is the client's own edge ring, drawn around the whole minimap rather than around the quest area, so while the player stood in a held stop's area the map showed the client's blue area with a second, larger gold outline around it.

- `UI/QuestBlob.lua`
  - The area textures (`Inside`, `Outside`, and the `OutsideSelected` edge a super-tracked quest can wear, where the client exposes that setter) now carry the bonus objective gold. The edge ring is no longer touched, so no larger gold circle is drawn around the minimap.
  - The area textures are applied on every `SetAreaBlob(true)` call, not only on the first transition, because a quest update can rebuild the client's blob from the stock textures while the player stands still. The stock set is restored once on leaving.
  - A client without the selected-edge setter still gets the ordinary area recoloured.
- `UI/Route.lua`
  - The minimap layer now listens to `QUEST_LOG_UPDATE`, `QUEST_WATCH_LIST_CHANGED`, `QUEST_POI_UPDATE`, `SUPER_TRACKING_CHANGED` and `CVAR_UPDATE` (only `questPOI` matters), forcing a redraw so the gold area comes back after those events.
- `tests/ui_client.lua` records the selected-edge texture and the edge ring.
- `tests/route_ui.lua` checks the gold area's `Inside`, `Outside` and `OutsideSelected` textures, and checks that the edge ring is never recoloured.
- `tests/quest_blob_spec.lua` is the new focused spec, including a simulated client blob rebuild.
- `CHANGELOG.md` has an `[Unreleased]` bullet crediting the in-game report without naming the reporter.

## Old-code spec failure

The new spec fails against `HEAD:UI/QuestBlob.lua` at the point this work started:

```
luajit: tests/quest_blob_spec.lua:64: a super-tracked quest's selected edge wears the gold set:
expected Interface\Minimap\UI-BonusObjectiveBlob-OutsideSelected, got nil
```

The old code also sets `Minimap.questBlobRing` to the gold ring, which the updated `tests/route_ui.lua` rejects with `"the minimap's own edge ring is left alone, so no second outline is drawn"`, and it early-returns on a repeated inside call, so the simulated client rebuild stays blue.

With the new code:

```
quest_blob_spec: 18 checks: the minimap's gold area, not its edge ring, replaces the blue one
route_ui: shared stop button, pooled stroke pairs, minimap stop mark and hovered transport routes ok
```

## Golden changes

None. `python3 tools/check_screenshots.py` reports all 14 images still match what they are drawn from, so no screenshot was regenerated.

## Gate results

Run from the worktree unless noted.

- `python3 tools/gen_corpus.py`: not present in this repository (`tools/gen_corpus.py: No such file or directory`).
- `stylua --check .`: passed.
- `ruff format --check tools && ruff check tools`: passed, 82 files already formatted, all checks passed.
- `luacheck .`: passed, 0 warnings / 0 errors in 246 files.
- `PATH="$HOME/.cache/agent-scratch/luals-3.19.1/bin:$PATH" tools/typecheck.sh`: passed, LuaLS found no problems; the taint, art, secret, multi-value, editorconfig, locale and family lints passed.
- `for s in tests/*_spec.lua; do luajit "$s" || exit 1; done`: all passed, including the new `quest_blob_spec`.
- `tests/ui.sh`: passed, including `route_ui`, `noblob_ui` and `minimap_ui`.
- `luajit -joff tests/plan_bench.lua`: not present in this repository. Ran the repository's own `luajit -joff tests/journey_bench.lua` instead: passed, every journey settled. Its worst frame was 3.165 ms in the Crossroads to Thunder Bluff case, slightly over the 3 ms local guidance; the bench fails a journey that does not settle, not one over that guide.
- `python3 tools/changelog.py --check`: passed for every tag through `v1.22.55`, the newest as at its tag.
- `python3 tools/repo_rules.py`: passed.
- `python3 tools/check_screenshots.py`: passed, 14 images match.
- `python3 tools/check_generated.py --offline`: passed, generated data, walking costs, nav packing and phrases are current and reproducible.

## In-game check (`/reload`)

1. Follow an Adventure Guide journey into a held stop's quest area on the minimap.
2. The quest area itself turns the bonus objective's gold at the client's own shape and scale, and there is no second gold ring around the minimap. If this client also draws a selected edge for the quest and exposes the selected setter, that edge is gold too.
3. Stand still through a quest update (for example kill an objective mob): the area stays gold.
4. Leave the area: the stock blue area returns and the minimap's own edge ring is unchanged.

Note on the client build: the pinned 1.60.1 Lua API exposes `SetQuestBlobInsideTexture`, `SetQuestBlobOutsideTexture` and the ring setters, but not a selected-edge setter. The code uses `SetQuestBlobOutsideSelectedTexture` when a client exposes it and otherwise leaves the ordinary area recoloured. The live client's `Minimap` XML does define a selected outside texture, so the in-game check above is the confirmation that the ordinary area is the one the held stop draws.

## Workspace note

While this work was finishing, an external process committed the first snapshot as `6f87890` and merged `origin/main` as `93e33f5`; the later no-cache and quest-event changes were reapplied on top and are uncommitted. The task's no-commit instruction was followed for the work done here.

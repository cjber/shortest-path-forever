# SPF repository organisation @ 753c1467b214771226744978b16c8e6caeb9c0c0

Scope: runtime layout and all consumers of relocated source paths, plus independently verified lint configuration and project-profile findings. This is not a claim that every historical whole-repository candidate has been settled.

Moved 34 runtime Lua modules and Map.xml into Core, Routing, Journey, Transport and UI. Runtime bytes and manifest load order are unchanged. Tests, screenshot data loading, offline baking, documentation and strict type-check fixtures follow the new paths. Historical navigation comparisons still support flat baseline trees.

Removed one duplicate allowed global and two inherited LuaJIT lint declarations. Corrected the profile's tracker ownership, shell gate coverage and risk paths. Independent source verification supported these five findings; broader candidates without sufficient evidence remain unchanged. No speculative dead-code deletion was applied.

The type coverage gate now rejects orphaned Lua modules in all five runtime directories. A regression test checks each directory; no ignore, assertion, budget or preload limit was relaxed. The strict diagnostic mutation fixture copies real namespace exports from their new folders.

Verification: full Lua specs, native UI checks, unchanged journey benchmark, lint and formatting; LuaLS and strict checker regression tests. The first checker run failed because /tmp exhausted its disk quota, then passed with TMPDIR on the workspace disk. Screenshot runtime data loaded successfully. Independent Codex review found no path regressions; Pi's default-model review identified the strict-fixture dependency, covered by the fixture update and passing mutation tests.

Open work: no open GitHub PR at the initial check. Existing feature worktrees and client release packages were preserved. No live gameplay claim is made for a file-layout change.

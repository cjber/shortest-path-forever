# About the app

Shortest Path Forever is a World of Warcraft: Forever addon written in Lua 5.1. The game cannot run
here, so what is measured is the planner under its own headless benches, which stub the client API and
load the addon files the TOC lists, in order.

Two benchmarks, both `kind: command`:

- `planner.journey` runs `luajit -joff tests/journey_bench.lua`. The script plans four journeys and
  fails unless each settles into one committed route; it prints the worst frame but asserts no budget.
- `planner.hearth` runs `luajit -joff tests/hearth_savings_bench.lua`, the hearthstone savings
  comparison. Its strict 3 ms budget is a local machine budget (AGENTS.md says so), which is why this
  benchmark runs it without `SPF_BENCH_STRICT`.

Wall time here includes luajit's own startup, roughly 20 ms, so a change under about 10 percent of the
numbers will not be visible. Anything worth keeping also has to pass the repo's gate: `stylua --check .`,
`luacheck .`, `tools/typecheck.sh` and every spec, with lua-language-server 3.19.1 and stylua 2.5.2,
which are the CI pins rather than whatever this machine has installed.

A `custom` benchmark that printed the planner's own milliseconds as `{"metrics": {"plan_ms": ...}}`
would remove the startup noise. That is the improvement to make if these numbers prove too coarse.

## On pull requests

`.github/workflows/speedpatrol.yml` runs `speedpatrol compare` on every pull request: three A/B rounds
against the base branch, over `planner.journey` and `planner.hearth` only, failing the job on a regression. CI's `check` job
runs both benches as well.

## Never do these things

- Never start the game, Battle.net, Lutris or Wine. The headless client (forever-core's `wow-forever-addon/in-game.md`) tests the build linked into the game, not this checkout, so in-game checks belong to the agent that ships a change.
- Never commit a speed-up that only the benchmark likes: it has to pass the full gate.
- Never leave scratch files in the commit.

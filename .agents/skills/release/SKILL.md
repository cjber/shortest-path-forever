---
name: release
description: "Prepare, publish and verify a complete Shortest Path Forever release. Use for /release or cutting a release, including data, README and store copy, screenshots, both stores and client installation."
---

# Release Shortest Path Forever

Run from the repository root. Read `AGENTS.md`, then the installed
`wow-forever-addon` and `wow-addon-publish` skills. For images, also read
`wow-mock-screenshots`. These supply the shared standards and store procedures;
this checklist supplies the release completion criteria. Use the user's existing
authorization. A preparation-only request ends before tags or uploads.

## Prepare main

1. Fetch origin and tags. Inventory open PRs, local branches, worktrees and
   unpushed changes. Land only authorized, reviewed PRs with all checks green on
   their current heads. Preserve unfinished work and list anything excluded.
2. Inspect the latest data-refresh run, open data PRs and refresh-failure issues.
   Compare the selected client build and companion versions with current upstream
   sources. Refresh through the documented workflow/generators where needed;
   `python3 tools/check_generated.py` reproduces the selected pins but does not
   prove that those pins are newest. Inspect `python3 tools/data_report.py --base
   <last-release-tag>`. Keep generated data and its source pins together.
3. Prepare release changes on a branch from fresh main. Choose a new version from
   the changes since the last tag. Retain `[Unreleased]` and move shipped notes
   into `## [X.Y.Z] - YYYY-MM-DD` using the UTC release date. Keep the TOC version
   as `@project-version@`. Run `python3 tools/changelog.py --check X.Y.Z` and
   `python3 tools/changelog.py --check`; inspect the extracted version notes.

## Refresh every presentation surface

4. Compare `README.md`, `docs/curseforge.md`, linked documentation, defaults,
   commands and companion requirements with the behaviour being released. Remove
   stale claims and broken links. Run the shared `wow-forever-addon/check_copy.py`
   on both copy files. Keep README/store copy within the shared length limits.
5. Set `WOWMOCK` to the installed mock library and run `python3 tools/screenshots.py`
   twice, requiring identical output bytes. Inspect the actual images at readable
   size, including the changed features and empty/error states. Commit the current
   images and screenshot manifest where present; remove obsolete images and their
   references. Regenerate icon art if changed. Check README image links against
   the files that will exist on main.
6. Record the intended store summary, description, logo and gallery set with exact
   filenames, captions and order. Use current committed assets for GitHub,
   CurseForge and Wago. Gallery refresh includes replacing stale screenshots and
   duplicates, not merely appending the new set. Preserve any intentionally kept
   images; identify the exact stale images before deleting them. Use authorized
   browser/connector tooling for changes the packager does not perform.

## Verify and publish

7. Run the fast lint/type gate from `AGENTS.md`, focused checks for changed
   behaviour, generated-data verification and
   `python3 tools/forever_tools/sync.py check`. Full suites run in CI. Record
   user `/reload` checks and their results separately: agents do not drive the
   game, and headless checks do not establish client visual or combat correctness.
8. Commit the release preparation with a signed commit and ship its reviewed,
   green PR. Merge only within the user's authorization. Wait for the complete
   `ci.yml` **push run on main at the exact commit to be tagged**. PR checks and
   workflow-dispatch runs do not satisfy `tools/release_check.py`. Confirm the
   primary checkout is clean main at that commit before proceeding.
9. Inspect `.github/workflows/release.yml`, `.pkgmeta` and `ShortestPathForever.toc`.
   Confirm `X-Curse-Project-ID`, `X-Wago-ID`, interface and dependencies are right.
   Check secret names with `gh secret list`: `CF_API_KEY` and `WAGO_API_TOKEN`
   must both be present; never print their values. Create a new signed `vX.Y.Z`
   tag at the verified main commit and push that exact tag. Preserve existing tags.
10. Watch the tag's release workflow through completion. Inspect its log for both
    store IDs with `[token set]` and successful uploads to each provider. A green
    workflow can silently skip a provider with a missing token. Download and
    inspect the GitHub release zip: substituted version, TOC/XML load graph,
    runtime files, media, required bundled data and libraries must be present;
    development files and third-party companion databases must remain excluded.
11. Apply the prepared summary, description, logo and gallery to both stores.
    Save, reopen and verify each surface, including captions/order and removed
    duplicates. Check GitHub's rendered README, release notes and image links too.
    An upload does not update store descriptions or galleries automatically.
12. Verify the public CurseForge files page and Wago version page show this version
    for the intended client, with the correct notes and downloadable artifact.
    Report moderation or an unavailable surface as pending, with its URL; uploaded
    or workflow-green does not mean publicly live. Retry without creating another
    version or tag to mask a failed upload.
13. If installation was requested, update every authorized client copy/symlink to
    the released version or verified main commit, preserve saved variables and
    backups, include any `.pkgmeta` moved companion folders, and verify targets
    and the load graph. Retire named obsolete addon folders/links outside AddOns
    so old packaging cannot remain enabled. Tell the user to `/reload`.
    Report version/tag and commit, CI/release links, package verification, each
    store's public status, copy/gallery verification and any remaining client
    checks. The release is complete only when every requested surface is verified.

## Addon checks

- Include the generated compressed `Nav/` payload and its XML load graph. Check
  bake provenance and the shared-tracker workflow; a terrain or transit change
  needs its generated-data and native bake checks green.
- After planner changes, run the journey and strict hearth-savings benchmarks
  named in `AGENTS.md`. Render screenshots with `--verify`.
- User checks: outdoor walking, unreachable destinations, flight/transit routes,
  cancellation and movement during calculation; shift-click flight master and
  quest icons with small corner badges; route progress updating.
- The release zip must contain one ShortestPathForever addon, including terrain,
  with no separate walking-map addon folders or extra TOCs.

## Command discovery

`.agents/skills/release/SKILL.md` is the canonical file for Codex. Claude and
Pi load it through `.claude/skills/release` and `.pi/skills/release` symlinks.
Pi's `/release` prompt loads it; `/skill:release` also works. Reload agent
commands after adding it.

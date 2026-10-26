"""Check this addon's vendored files against cjber/forever-core main."""

import hashlib
import urllib.error
import urllib.request
from pathlib import Path

TRACKER_CONSUMERS = {
    "adventure-guide-forever",
    "legacy-forever",
    "shortest-path-forever",
    "skillup-forever",
}
COMMON = (
    "tools/deadcode.py",
    "tools/deadcode-allow.txt",
    "Core/SafeCall.lua",
    "UI/Report.lua",
    "tests/report_spec.lua",
    "UI/ForeverFamily.lua",
    "tests/forever_family_spec.lua",
)
TRACKER = (
    "UI/TrackerHost.lua",
    "UI/TrackerLock.lua",
    "UI/TrackerOrder.lua",
    "UI/TrackerQuestie.lua",
    "tests/tracker_host_spec.lua",
    "tests/tracker_host_harness.lua",
    "tests/tracker_questie_spec.lua",
    "tools/fetch_tracker_ui.py",
)


def main():
    repo = Path.cwd().name
    paths = COMMON + (TRACKER if repo in TRACKER_CONSUMERS else ())
    failures = []
    for path in paths:
        url = f"https://raw.githubusercontent.com/cjber/forever-core/main/{path}"
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                expected = response.read()
        except (OSError, urllib.error.URLError, TimeoutError) as error:
            failures.append(f"{path}: could not read core main: {error}")
            continue
        actual = (Path.cwd() / path).read_bytes()
        if actual != expected:
            failures.append(
                f"{path}: consumer {hashlib.sha256(actual).hexdigest()[:12]} "
                f"core {hashlib.sha256(expected).hexdigest()[:12]}"
            )
    if failures:
        raise SystemExit("Vendored files differ from forever-core main:\n  " + "\n  ".join(failures))
    print(f"{len(paths)} vendored files match forever-core main.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Move the generators' pins to the newest upstream data, without regenerating (stdlib and git only).

    python3 tools/refresh_pins.py    # then run the generators, as tools/check_generated.py does

BUILD follows the newest WoW: Forever client build on wago.tools. INFLIGHT_REV follows the InFlight addon's
head, and only when the two files read from it differ from the pinned ones, so an unrelated upstream commit
changes nothing. Under GitHub Actions the step outputs `changed` and `summary` say what moved.
"""

import json
import os
import re
import subprocess
import urllib.request
from pathlib import Path

import gen_routes
import gen_transit

TOOLS = Path(__file__).resolve().parent
INFLIGHT = "https://github.com/LudiusMaximus/InFlight"
INFLIGHT_FILES = ("Defaults.lua", "LICENSE")


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def latest_build(builds):
    """The newest Forever build; wow_classic_beta carries other Classic betas too, and Forever's are 1.6x."""
    forever = [build["version"] for build in builds["wow_classic_beta"] if build["version"].startswith("1.6")]
    if not forever:
        raise SystemExit("no Forever build listed on wago.tools")
    return max(forever, key=version_key)


def fetch_builds():
    request = urllib.request.Request("https://wago.tools/api/builds", headers={"User-Agent": "ShortestPathForever/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def inflight_file(revision, name):
    return gen_routes.download(
        f"https://raw.githubusercontent.com/LudiusMaximus/InFlight/{revision}/{name}", f"InFlight-{revision}-{name}"
    )


def inflight_revision(pinned):
    head = subprocess.check_output(["git", "ls-remote", INFLIGHT, "HEAD"], text=True, timeout=60).split()[0]
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise SystemExit(f"unexpected InFlight head: {head!r}")
    if head != pinned and any(inflight_file(head, name) != inflight_file(pinned, name) for name in INFLIGHT_FILES):
        return head
    return pinned


def pin(text, name, value):
    """`text` with its one `NAME = "..."` assignment set to `value`."""
    replaced, count = re.subn(rf'^{name} = "[^"\n]*"$', f'{name} = "{value}"', text, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"expected one {name} pin, found {count}")
    return replaced


def main():
    build = latest_build(fetch_builds())
    if version_key(build) < version_key(gen_routes.BUILD):
        build = gen_routes.BUILD
    pins = (
        ("gen_routes.py", "BUILD", gen_routes.BUILD, build),
        ("gen_transit.py", "INFLIGHT_REV", gen_transit.INFLIGHT_REV, inflight_revision(gen_transit.INFLIGHT_REV)),
    )
    moved = []
    for filename, name, old, new in pins:
        if new != old:
            path = TOOLS / filename
            path.write_text(pin(path.read_text(encoding="utf-8"), name, new), encoding="utf-8")
            moved.append(f"{name} {old} -> {new}")
    summary = ", ".join(moved)
    print(summary or f"already on {build}, InFlight {gen_transit.INFLIGHT_REV[:8]}")
    if "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"changed={'true' if moved else 'false'}\nsummary={summary}\n")


if __name__ == "__main__":
    main()

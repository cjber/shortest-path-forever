"""Verify an extractor's expected tile inventory before publishing a navigation map."""

import argparse
import json
import os
import re
from pathlib import Path


def complete(directory: Path, map_id: int) -> dict:
    manifest = json.loads((directory / "source.json").read_text())
    if manifest["schema"] != 1 or manifest["map"] != map_id or not manifest["build"] or not manifest["recipe"]:
        raise ValueError("Invalid extractor provenance")
    expected = set(manifest["tiles"])
    if not expected or len(expected) != len(manifest["tiles"]):
        raise ValueError("Invalid expected tile inventory")
    actual = {p.stem for p in directory.glob(f"{map_id:04d}_??_??.mmtile")}
    populated = set()
    for tile in sorted(expected):
        match = re.fullmatch(rf"{map_id:04d}_(\d{{2}})_(\d{{2}})", tile)
        if not match or max(map(int, match.groups())) > 63:
            raise ValueError(f"Invalid tile identifier: {tile}")
        path = directory / "status" / tile
        words = path.read_text().split() if path.is_file() else []
        status = words[0] if words else "missing"
        if status == "ok":
            populated.add(tile)
        elif status != "empty":
            raise ValueError(f"Unfinished extraction: {tile} is {status}")
    if actual != populated:
        raise ValueError(f"Tile files disagree with extraction statuses: {sorted(actual ^ populated)}")
    return manifest


def arguments(directory):
    parser = argparse.ArgumentParser(description="Bake a map's walking-route data as an addon Lua file.")
    parser.add_argument("out", nargs="?", help="output file (default Nav<map>.lua)")
    parser.add_argument("--map", type=int, required=True)
    parser.add_argument("--name")
    parser.add_argument("--rows", nargs=2, type=int)
    parser.add_argument("--cols", nargs=2, type=int)
    parser.add_argument("--jobs", type=int, default=int(os.environ.get("NAV_JOBS", "6")))
    parser.add_argument("--metrics", type=Path, help="write timing, hashes and resource metrics as JSON")
    parser.add_argument("--build", help="client build the input tiles were extracted from")
    parser.add_argument(
        "--require-complete", action="store_true", help="require a complete extractor manifest and tile statuses"
    )
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    provenance = (
        complete(directory, args.map) if args.require_complete or (directory / "source.json").is_file() else None
    )
    if provenance and args.build and args.build != provenance["build"]:
        parser.error("--build disagrees with extractor provenance")
    if provenance:
        args.build = provenance["build"]
    return args, provenance


def source_label(provenance: dict | None) -> str:
    """Prefer an explicit label, then verified native provenance, preserving unmanifested historical output."""
    if "NAV_SOURCE" in os.environ:
        return os.environ["NAV_SOURCE"]
    if provenance:
        rev = provenance.get("provenance", {}).get("code", {}).get("trinitycore")
        if rev:
            return (
                f"local {provenance['product']} {provenance['build']}, TrinityCore {rev}, recipe {provenance['recipe']}"
            )
    return "own bake of the World of Warcraft client (wow_classic_beta), Mappster/DotRecast"

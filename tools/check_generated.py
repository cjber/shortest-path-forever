"""Regenerate pinned data in a scratch tree and reject stale or unstable output."""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = (
    "Data/Routes.lua",
    "Data/Transports.lua",
    "Data/Taxi.lua",
    "Data/Portals.lua",
    "Data/Teleports.lua",
    "Data/Walks.lua",
    "Locales/phrases.txt",
)


def run(root, *command, output=None):
    if output is None:
        subprocess.run(command, cwd=root, check=True)
    else:
        with (root / output).open("wb") as stream:
            subprocess.run(command, cwd=root, stdout=stream, check=True)


def outputs(root):
    files = set(DATA)
    files.update(str(path.relative_to(root)) for path in (root / "Data").glob("*.lua"))
    files.update(str(path.relative_to(root)) for path in root.glob("ShortestPathForever_Nav*/*.lua"))
    files.update(str(path.relative_to(root)) for path in root.glob("**/*.toc"))
    return {name: (root / name).read_bytes() for name in sorted(files)}


def regenerate(root, offline):
    for name in DATA:
        (root / name).unlink()
    mode = ["--offline"] if offline else []
    run(root, sys.executable, "tools/gen_routes.py", *mode)
    run(root, sys.executable, "tools/gen_transit.py", *mode)
    run(root, "luajit", "tools/bake_walks.lua", output="Data/Walks.lua")
    run(root, sys.executable, "tools/pack_nav.py")
    run(root, sys.executable, "tools/phrases.py", output="Locales/phrases.txt")


def compare(expected, actual, label):
    changed = sorted(name for name in expected.keys() | actual.keys() if expected.get(name) != actual.get(name))
    if changed:
        raise SystemExit(f"{label}:\n" + "\n".join(changed))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="require existing tools/.cache inputs")
    args = parser.parse_args()
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    with tempfile.TemporaryDirectory(prefix="spf-regenerate-") as temporary:
        scratch = Path(temporary)
        for name in filter(None, tracked):
            source = ROOT / name
            if source.is_file():
                target = scratch / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
        cache = ROOT / "tools/.cache"
        if cache.exists():
            shutil.copytree(cache, scratch / "tools/.cache", dirs_exist_ok=True)
        expected = outputs(scratch)
        regenerate(scratch, args.offline)
        generated = outputs(scratch)
        compare(expected, generated, "Stale generated files; run the canonical generators")
        regenerate(scratch, True)
        compare(generated, outputs(scratch), "Regeneration is not byte-for-byte reproducible")
    print("Generated data, walking costs, nav packing and phrases are current and reproducible.")


if __name__ == "__main__":
    main()

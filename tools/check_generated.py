"""Regenerate pinned data in a scratch tree and reject stale or unstable output."""

import argparse
import subprocess
import sys
from pathlib import Path

try:
    from tools.forever_tools.generated import check_generated
except ModuleNotFoundError:
    from forever_tools.generated import check_generated

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
    files = {*DATA, ".pkgmeta"}
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="require existing tools/.cache inputs")
    args = parser.parse_args()
    check_generated(
        ROOT,
        outputs=outputs,
        regenerate=regenerate,
        offline=args.offline,
        success="Generated data, walking costs, nav packing and phrases are current and reproducible.",
        prefix="spf-regenerate-",
    )


if __name__ == "__main__":
    main()

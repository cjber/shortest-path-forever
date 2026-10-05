"""Bake walking maps with the pinned TrinityCore extractors, one fresh extraction per map.

Per map: mapextractor, vmap4extractor and vmap4assembler fill a new scratch directory, the expected tile list the
patched mapextractor wrote (maps/<map>.expected) becomes source.json, mmaps_generator builds the targets into a
durable per-map output, and only a complete output reaches gen_nav and pack_nav. pack_nav stages the whole bundle
of compressed walking maps, laid out as the main addon's Nav directory, before it replaces the one under the output.
The game install is read only.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from baker.inputs import complete  # noqa: E402
from forever_tools.fsio import atomic_write, publish  # noqa: E402

HERE = Path(__file__).resolve().parent
LOCALE = "enUS"
ADDON = "ShortestPathForever"
BUNDLED = re.compile(r"Nav\.xml|Nav\d+(?:_\d+)?\.lua")
TILE = re.compile(r"(\d{4})_(\d{2})_(\d{2})")


def active_build(wow: Path, product: str) -> str:
    """The Version of the product's one active row in .build.info."""
    lines = (wow / ".build.info").read_text().splitlines()
    if not lines:
        raise ValueError(f"{wow}/.build.info is empty")
    names = [field.split("!")[0] for field in lines[0].split("|")]
    for column in ("Product", "Active", "Version"):
        if column not in names:
            raise ValueError(f".build.info has no {column} column")
    rows = [dict(zip(names, line.split("|"), strict=False)) for line in lines[1:] if line.strip()]
    versions = [r["Version"] for r in rows if r["Product"] == product and r["Active"] == "1" and r["Version"]]
    if len(versions) != 1:
        raise ValueError(f"expected one active {product} Version in .build.info, found {sorted(versions) or 'none'}")
    return versions[0]


def expected_tiles(path: Path, map_id: int) -> list[tuple[int, int]]:
    """Tile (x, y) pairs from the mapextractor's inventory; an absent or empty list is an extraction failure."""
    if not path.is_file():
        raise ValueError(f"mapextractor wrote no tile inventory: {path}")
    names = path.read_text().split()
    tiles = []
    for name in names:
        match = TILE.fullmatch(name)
        if not match or int(match[1]) != map_id or max(int(match[2]), int(match[3])) > 63:
            raise ValueError(f"Invalid expected tile identifier: {name}")
        tiles.append((int(match[2]), int(match[3])))
    if not tiles or len(set(tiles)) != len(tiles):
        raise ValueError(f"Expected tile inventory is empty or repeats tiles: {path}")
    return sorted(tiles)


def inside(tile: tuple[int, int], rows, cols) -> bool:
    return (rows is None or rows[0] <= tile[0] <= rows[1]) and (cols is None or cols[0] <= tile[1] <= cols[1])


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage_commands(args, map_id: int) -> dict[str, list[str]]:
    """Every stage's argv with the machine-specific paths as tokens, so the recipe is stable across checkouts."""
    threads = "$THREADS"
    return {
        "mapextractor": [
            "mapextractor", "-i", "$WOW", "-o", "$RUN", "-p", args.product, "-l", LOCALE, "-e", "3", "-f", "0",
        ],
        "vmap4extractor": [
            "vmap4extractor", "-d", "$WOW", "-p", args.product, "-dl", LOCALE, "-l", "--threads", threads,
        ],
        "vmap4assembler": ["vmap4assembler", "--threads", threads, "$RUN/Buildings", "$RUN/vmaps"],
        "mmaps_generator": [
            "mmaps_generator", "--input", "$RUN", "--output", "$OUT", "--threads", threads,
            "--skipJunkMaps", "false", "--bigBaseUnit", "true", str(map_id),
        ],
    }  # fmt: skip


def expand(argv: list[str], wow: Path, run: Path, output: Path, bin_dir: Path, threads: int) -> list[str]:
    subs = {"$WOW": str(wow), "$RUN": str(run), "$OUT": str(output), "$THREADS": str(threads)}
    out = [subs.get(a, a.replace("$RUN", str(run))) for a in argv]
    out[0] = str(bin_dir / argv[0])
    return out


def recipe(args, build: str, commands: dict) -> tuple[str, dict]:
    """Hash the portable source recipe, retaining exact binaries separately for safe cache reuse."""
    body = {
        "product": args.product,
        "build": build,
        "code": {"trinitycore": args.rev, "patches": {p.name: sha256(p) for p in args.patch}},
        "commands": commands,
    }
    digest = hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()
    body["binaries"] = {name: sha256(args.bin / name) for name in commands}
    return digest, body


def measured(argv: list[str], cwd: Path, log: Path, env: dict | None = None) -> dict:
    """Run one fresh process, log its output and return wall and CPU seconds and peak RSS."""
    started = time.perf_counter()
    print(f"Running {Path(argv[0]).name}, log: {log}", flush=True)
    with log.open("ab") as sink:
        log_start = sink.tell()
        sink.write(("$ " + " ".join(argv) + "\n").encode())
        sink.flush()
        child = subprocess.Popen(
            argv,
            cwd=cwd,
            env={**os.environ, **(env or {})},
            stdin=subprocess.DEVNULL,
            stdout=sink,
            stderr=subprocess.STDOUT,
        )
        _, status, usage = os.wait4(child.pid, 0)
        child.returncode = os.waitstatus_to_exitcode(status)
    if child.returncode:
        raise RuntimeError(f"{Path(argv[0]).name} exited {child.returncode}; see {log}")
    with log.open("rb") as source:
        source.seek(log_start)
        skipped = re.findall(
            rb"SPF-DB2-SKIPPED-SECTION FileDataId: 1349477 key=([A-F0-9]+) records=(\d+)", source.read()
        )
    return {
        "wall_seconds": time.perf_counter() - started,
        "cpu_seconds": usage.ru_utime + usage.ru_stime,
        "max_rss_kib": usage.ru_maxrss,
        "skipped_map_sections": [{"key": key.decode(), "records": int(count)} for key, count in skipped],
    }


def prepare(output: Path, manifest: dict) -> None:
    """Write source.json before any tile is built; refuse preexisting tiles the manifest cannot vouch for."""
    mmaps = output / "mmaps"
    path = mmaps / "source.json"
    text = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    if path.is_file():
        if json.loads(path.read_text()) != manifest:
            raise ValueError(f"{path} differs from this run's build, recipe, crop or tiles; use a new --out")
        return
    leftovers = [p for p in (*mmaps.glob("*.mmtile"), *(mmaps / "status").glob("*")) if p.is_file()]
    if leftovers:
        raise ValueError(f"{mmaps} holds {len(leftovers)} tile files or statuses without source.json")
    atomic_write(path, text)


def pending(mmaps: Path, targets: list[tuple[int, int]], map_id: int) -> list[tuple[int, int]]:
    """Targets whose status is not yet ok or empty; an absent status is pending, never empty."""
    todo = []
    for x, y in targets:
        status = mmaps / "status" / f"{map_id:04d}_{x:02d}_{y:02d}"
        if not status.is_file() or status.read_text().split()[:1] not in (["ok"], ["empty"]):
            todo.append((x, y))
    return todo


def extract(args, map_id: int, commands: dict, run: Path, log: Path) -> dict:
    env = {"SPF_MAP": str(map_id)}
    if args.rows or args.cols:  # neighbours of the crop feed the edge tiles' collision and liquid
        if args.rows:
            env["SPF_ROWS"] = f"{max(args.rows[0] - 1, 0)},{min(args.rows[1] + 1, 63)}"
        if args.cols:
            env["SPF_COLS"] = f"{max(args.cols[0] - 1, 0)},{min(args.cols[1] + 1, 63)}"
    return {
        name: measured(expand(commands[name], args.wow, run, run, args.bin, args.threads), run, log, env)
        for name in ("mapextractor", "vmap4extractor", "vmap4assembler")
    }


def bundled(root: Path) -> list[Path]:
    """The walking-map files under an addon root's Nav directory; anything else there is refused."""
    nav = root / "Nav"
    files = sorted(nav.iterdir()) if nav.is_dir() else []
    for path in files:
        if not path.is_file() or not BUNDLED.fullmatch(path.name):
            raise ValueError(f"Unrecognised file in the walking-map bundle: {path}")
    return files


def stage_bundle(staged: Path, destination: Path) -> None:
    """Copy the maps the published Nav.xml lists, so pack_nav validates them and carries them into the new bundle."""
    index = destination / "Nav" / "Nav.xml"
    bundled(destination)
    (staged / "Nav").mkdir(parents=True)
    if index.is_file():
        for name in ("Nav.xml", *re.findall(r'<Script file="([^"]+)"/>', index.read_text())):
            if not BUNDLED.fullmatch(name):
                raise ValueError(f"Unrecognised file listed in {index}: {name}")
            shutil.copyfile(index.with_name(name), staged / "Nav" / name)


def publish_bundle(staged: Path, destination: Path) -> None:
    """Replace the published bundle with the complete staged one, then remove the files it leaves out."""
    old = bundled(destination)
    outputs = {destination / p.relative_to(staged): p.read_bytes() for p in bundled(staged)}
    if destination / "Nav" / "Nav.xml" not in outputs:
        raise ValueError(f"Staged walking-map bundle has no Nav.xml: {staged}")
    publish(outputs)
    for path in old:
        if path not in outputs:
            path.unlink()


def bake_map(args, map_id: int, build: str) -> None:
    root = args.out
    root.mkdir(parents=True, exist_ok=True)
    output = root / f"trinity{map_id}"
    mmaps = output / "mmaps"
    mmaps.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix=f"extract{map_id}-", dir=root))
    log = root / f"bake{map_id}.log"
    commands = stage_commands(args, map_id)
    digest, body = recipe(args, build, commands)
    metrics = {"map": map_id, "build": build, "scratch": str(run), "stages": extract(args, map_id, commands, run, log)}

    tiles = expected_tiles(run / "maps" / f"{map_id:04d}.expected", map_id)
    targets = [t for t in tiles if inside(t, args.rows, args.cols)]
    if not targets:
        raise ValueError(f"map {map_id}: no expected tile inside rows {args.rows} cols {args.cols}")
    prepare(
        output,
        {
            "schema": 1,
            "map": map_id,
            "build": build,
            "recipe": digest,
            "product": args.product,
            "provenance": body,
            "db2_sha256": {p.name: sha256(p) for p in sorted((run / "dbc" / LOCALE).glob("*.db2"))},
            "skipped_map_sections": metrics["stages"]["mapextractor"]["skipped_map_sections"],
            "rows": args.rows,
            "cols": args.cols,
            "tiles": [f"{map_id:04d}_{x:02d}_{y:02d}" for x, y in targets],
        },
    )

    todo = pending(mmaps, targets, map_id)
    base = expand(commands["mmaps_generator"], args.wow, run, output, args.bin, args.threads)
    if args.rows or args.cols:
        runs = [[*base, "--tile", f"{x},{y}"] for x, y in todo]
    else:
        runs = [base] if todo else []
    metrics["stages"]["mmaps_generator"] = [measured(argv, run, log) for argv in runs]
    complete(mmaps, map_id)

    name = args.names.get(map_id) or os.environ.get("MAP_NAME") or f"map {map_id}"
    lua = run / "raw" / f"Nav{map_id}.lua"
    lua.parent.mkdir()
    gen = [sys.executable, str(HERE / "gen_nav.py"), str(lua), "--map", str(map_id), "--name", name]
    gen += ["--require-complete", "--metrics", str(root / f"nav{map_id}.metrics.json")]
    for flag, bounds in (("--rows", args.rows), ("--cols", args.cols)):
        if bounds:
            gen += [flag, *map(str, bounds)]
    metrics["stages"]["gen_nav"] = measured(
        gen,
        HERE,
        log,
        {
            "NAV_MM": str(mmaps),
            "NAV_JOBS": str(args.jobs),
            "NAV_SOURCE": f"local {args.product} {build}, TrinityCore {args.rev}, recipe {digest}",
        },
    )
    staged, destination = run / "addons" / ADDON, root / "addons" / ADDON
    stage_bundle(staged, destination)
    pack = [sys.executable, str(HERE.parent / "pack_nav.py"), "--root", str(staged), str(lua)]
    metrics["stages"]["pack_nav"] = measured(pack, HERE, log)
    publish_bundle(staged, destination)
    atomic_write(root / f"trinity{map_id}.metrics.json", json.dumps(metrics, indent=2, sort_keys=True) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wow", type=Path, required=True)
    parser.add_argument("--product", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--bin", type=Path, required=True, help="directory holding the four TrinityCore tools")
    parser.add_argument("--maps", type=int, nargs="+", required=True)
    parser.add_argument("--threads", type=int, default=8)
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--rows", nargs=2, type=int)
    parser.add_argument("--cols", nargs=2, type=int)
    parser.add_argument("--rev", required=True, help="pinned TrinityCore commit the binaries were built from")
    parser.add_argument("--patch", type=Path, action="append", required=True, help="each patch applied to that commit")
    parser.add_argument("--name", action="append", default=[], metavar="MAP=TITLE", help="name of a map")
    args = parser.parse_args()
    if min(args.threads, args.jobs) < 1:
        parser.error("--threads and --jobs must be positive")
    for bounds in (args.rows, args.cols):
        if bounds and not 0 <= bounds[0] <= bounds[1] <= 63:
            parser.error("crop bounds must be ordered within 0..63")
    if len(set(args.maps)) != len(args.maps) or any(not 0 <= m <= 9999 for m in args.maps):
        parser.error("map IDs must be distinct and within 0..9999")
    args.names = {int(k): v for k, v in (n.split("=", 1) for n in args.name)}
    args.wow, args.out, args.bin = args.wow.resolve(), args.out.resolve(), args.bin.resolve()
    if args.out == args.wow or args.wow in args.out.parents:
        parser.error("--out must be outside the game installation")
    build = active_build(args.wow, args.product)
    for map_id in args.maps:
        bake_map(args, map_id, build)


if __name__ == "__main__":
    main()

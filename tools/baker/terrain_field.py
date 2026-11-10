#!/usr/bin/env python3
"""Add or refresh the terrain exceptions of an existing walking-map bundle from extracted .map tiles.

usage: terrain_field.py --maps-dir <extract>/maps --root <addon root> [--maps 0 1 2991]

Navigation is not re-baked: graph, grid, height and floor stay byte-identical, and only the ``terrain`` field is
computed and packed. A cell with no floor is left out, as is a cell whose ground layer is its base surface; the field
holds only the cells whose ground is a floor, and the cells with floors over no terrain. The extractor's map directory
is the one mapextractor wrote (``<OUT>/maps`` or ``<extract>/maps``). A map whose bundle has no terrain, or whose tile
has no .map file, keeps no terrain for that cluster.
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from baker.terrain import (  # noqa: E402
    decode_base,
    decode_sparse,
    encode_sparse,
    floor_heights,
    sample_cluster,
)
from pack_nav import read_packed, write_bundle  # noqa: E402

ZQ = 2  # the same step as BASE_Z (tools/baker/gen_nav.py)
LAYOUT = re.compile(r"^\t(nx|ny|cx0|cy0|cells) = (-?\d+),", re.MULTILINE)


def layout(source):
    values = {name: int(value) for name, value in LAYOUT.findall(source)}
    missing = {"nx", "ny", "cx0", "cy0", "cells"} - values.keys()
    if missing:
        raise ValueError(f"Bundle has no map layout: {sorted(missing)}")
    return values


def terrain(entry, maps_dir, map_id, cells, cx0, cy0, ny):
    """Every cluster the bundle draws terrain for, keyed as the packed fields are (cluster + 1), and its exceptions."""
    fields, exceptions = {}, 0
    for key in sorted(entry["grid"]):
        kx, ky = divmod(key - 1, ny)
        row, col = 31 - cx0 - kx, 31 - cy0 - ky
        if not (0 <= row < 64 and 0 <= col < 64):
            continue
        grid, height = entry["grid"][key], entry["height"].get(key, "")
        base = decode_base(grid, height, cells)
        floors = floor_heights(entry.get("floor", {}).get(key, ""))
        text = encode_sparse(sample_cluster(maps_dir, map_id, row, col, cells, ZQ), base, cells, floors)
        if text:
            fields[key] = text
            exceptions += len(decode_sparse(text, base, cells))
    return fields, exceptions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--maps-dir", type=Path, required=True, help="the extractor's maps directory")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="addon root holding Nav/")
    parser.add_argument("--maps", nargs="+", type=int, help="map IDs (default: every bundled map)")
    args = parser.parse_args()
    bundled = {
        int(match[1]): path
        for path in sorted((args.root / "Nav").glob("Nav*.lua"))
        if (match := re.fullmatch(r"Nav(\d+)\.lua", path.name))
    }
    maps = args.maps or sorted(bundled)
    sources, extra = [], {}
    for map_id in maps:
        path = bundled.get(map_id)
        if path is None:
            parser.error(f"map {map_id} is not in {args.root / 'Nav'}")
        source, fields, _, _ = read_packed(path, map_id)
        values = layout(source)
        fields["terrain"].clear()  # this run owns the field; a cluster that no longer needs exceptions loses them
        fields, exceptions = terrain(
            fields, args.maps_dir, map_id, values["cells"], values["cx0"], values["cy0"], values["ny"]
        )
        extra[map_id] = {"terrain": fields}
        sources.append(path)
        print(
            f"map {map_id}: {exceptions} terrain exceptions in {len(fields)} clusters",
            flush=True,
        )
    write_bundle(args.root, sources, extra=extra)


if __name__ == "__main__":
    main()

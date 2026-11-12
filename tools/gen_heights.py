#!/usr/bin/env python3
"""Generate Data/Heights.lua and Data/IdleSpawns.lua: the height of each NPC or quest object spawn that stands over or
under another walkable surface, so a journey to it ends on its floor (stdlib + luajit), and the height of every spawn
an NPC stands still at, so a walk from where the player stands starts on their floor (Routing/Band.lua).

classic-db's creature and gameobject spawns carry a height; QuestieDB's are zone fractions with none. Each spawn on
the walking maps goes through tools/bake_heights.lua, which gives it the surface its height lands on. Data/Heights.lua
keeps those with another surface more than the router's ZTOL away within a cell of them; Data/IdleSpawns.lua keeps
every creature that stands at its spawn (MovementType 0), wherever it is, keyed by creature ID: Routing/Band.lua knows
an NPC by the ID UnitGUID carries.
"""

import argparse
import csv
import gzip
import math
import re
import subprocess
from collections import defaultdict

from gen_routes import CACHE, ROOT
from gen_transit import DB_REV, DB_URL

try:
    from tools.forever_tools.fsio import publish
    from tools.forever_tools.wago import fetch
except ModuleNotFoundError:
    from forever_tools.fsio import publish
    from forever_tools.wago import fetch

MAPS = ("0", "1")
# gameobject_template.type: QUESTGIVER (2), CHEST (3: quest containers, loot, herbs and veins) and GOOBER (10: the
# objects a quest has you use). Doors, chairs, signs and traps are never a journey's goal.
OBJECT_TYPES = {2, 3, 10}
TUPLES = re.compile(r"\(((?:'(?:\\.|[^'\\])*'|[^()'])*)\)")
# Nav clusters are ADT tiles: Routing/PathGrid.lua's TILE.
TILE = 1600 / 3


def spawns(refresh=False, offline=False):
    """Creature spawns and the quest kinds of gameobject spawns on the walking maps, as
    (map, creature ID, x, y, z, idle) strings. MovementType 0 stands still at its spawn; every other creature wanders
    or patrols off it, and no quest object moves."""
    path = CACHE / f"classicdb-{DB_REV[:8]}.sql.gz"
    fetch(
        DB_URL,
        path,
        user_agent="ShortestPathForever/1.0",
        refresh=refresh,
        offline=offline,
        timeout=60,
        validate=gzip.decompress,
    )
    creatures, objects, types = [], [], {}
    # creature and gameobject rows hold numbers only; gameobject_template's names are quoted.
    with gzip.open(path, "rt", encoding="utf-8") as stream:
        for line in stream:
            if line.startswith("INSERT INTO `creature` VALUES "):
                for match in TUPLES.finditer(line):
                    row = match[1].split(",")
                    if row[2] in MAPS:
                        creatures.append((row[2], row[1], row[4], row[5], row[6], "1" if row[11] == "0" else "0"))
            elif line.startswith("INSERT INTO `gameobject` VALUES "):
                for match in TUPLES.finditer(line):
                    row = match[1].split(",")
                    if row[2] in MAPS:
                        objects.append((int(row[1]), (row[2], row[4], row[5], row[6])))
            elif line.startswith("INSERT INTO `gameobject_template` VALUES "):
                for match in TUPLES.finditer(line):
                    row = next(csv.reader([match[1]], quotechar="'", escapechar="\\"))
                    types[int(row[0])] = int(row[1])
    if not creatures or not objects or not types:
        raise ValueError("classic-db: missing creature, gameobject or gameobject_template rows")
    still = [spawn for entry, spawn in objects if types.get(entry) in OBJECT_TYPES]
    return creatures + [(map_id, "0", x, y, z, "0") for map_id, x, y, z in still]


def bake(rows):
    """tools/bake_heights.lua over rows: (map, x, y, z) integers for the spawns Data/Heights.lua keeps, and
    (map, creature ID, x, y, z) for the ones Data/IdleSpawns.lua keeps."""
    result = subprocess.run(
        ["luajit", "tools/bake_heights.lua"],
        cwd=ROOT,
        input="".join("\t".join(row) + "\n" for row in rows),
        capture_output=True,
        text=True,
        check=True,
    )
    kept, idle = [], []
    for line in result.stdout.splitlines():
        kind, rest = line.split("\t", 1)
        fields = tuple(map(int, rest.split("\t")))
        if kind == "H":
            kept.append(fields)
        else:
            idle.append(fields)
    return kept, idle


def cluster(x, y, nav):
    """Routing/PathGrid.lua's locate, down to the cluster, computed as it is: through the global cell, so a spawn on a
    tile's edge is filed under the cluster the addon looks it up in."""
    cx0, cy0, ny, cells = nav
    size = TILE / cells
    gx, gy = math.floor((x - cx0 * TILE) / size), math.floor((y - cy0 * TILE) / size)
    return (gx // cells) * ny + gy // cells


def nav_origin(map_id):
    """The walking map's first tile, tile row length and cells per tile side, from its Nav<map>.lua header."""
    text = (ROOT / "Nav" / f"Nav{map_id}.lua").read_text(encoding="utf-8")
    values = {key: int(re.search(rf"\b{key} = (-?\d+)", text)[1]) for key in ("cx0", "cy0", "ny", "cells")}
    return values["cx0"], values["cy0"], values["ny"], values["cells"]


def by_cluster(rows):
    """(map, x, y, z) rows as {map: {cluster: ["x y z", ...]}}, filed under the cluster the addon looks them up in."""
    by_map = defaultdict(lambda: defaultdict(list))
    origins = {}
    for map_id, x, y, z in sorted(rows):
        origins.setdefault(map_id, nav_origin(map_id))
        by_map[map_id][cluster(x, y, origins[map_id])].append(f"{x} {y} {z}")
    return by_map


def render(kept):
    by_map = by_cluster(kept)
    lines = [
        "-- Generated by tools/gen_heights.py - do not edit.",
        "-- Source: classic-db creature spawns and QUESTGIVER, CHEST and GOOBER gameobject spawns, matched to the",
        "-- walking maps' surfaces by tools/bake_heights.lua.",
        f"-- DB: https://github.com/cmangos/classic-db/tree/{DB_REV}",
        "-- SpawnHeights[map][k + 1]: the spawns in Nav cluster k standing within a cell of another surface more",
        "-- than ZTOL away, as space-separated world x, y and the height of the surface they stand on, in whole yards.",
        "local ns = select(2, ...)",
        "",
        "-- stylua: ignore",
        "ns.SpawnHeights = {",
    ]
    for map_id in sorted(by_map):
        lines.append(f"\t[{map_id}] = {{")
        for k in sorted(by_map[map_id]):
            lines.append(f'\t\t[{k + 1}] = "{" ".join(by_map[map_id][k])}",')
        lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def render_idle(idle):
    """IdleSpawns[map][creature ID] as the "x y z" triples of that creature's idle spawns on the map, looked up by the
    creature ID UnitGUID names. A creature with more than one is kept whole: Routing/Band.lua measures only one."""
    by_map = defaultdict(lambda: defaultdict(list))
    for map_id, npc, x, y, z in sorted(idle):
        by_map[map_id][npc].append(f"{x} {y} {z}")
    lines = [
        "-- Generated by tools/gen_heights.py - do not edit.",
        "-- Source: classic-db creature spawns that stand at their spawn (MovementType 0), matched to the walking",
        "-- maps' surfaces by tools/bake_heights.lua.",
        f"-- DB: https://github.com/cmangos/classic-db/tree/{DB_REV}",
        "-- IdleSpawns[map][creature ID]: the spawns in that map a creature of that ID stands still at, as",
        "-- space-separated world x, y and the height of the surface it stands on, in whole yards, one triple per",
        "-- spawn. Routing/Band.lua bounds the player's height from the client's range checks to a unit whose",
        "-- UnitGUID carries the ID, and only where the ID has one spawn on the map.",
        "local ns = select(2, ...)",
        "",
        "-- stylua: ignore",
        "ns.IdleSpawns = {",
    ]
    for map_id in sorted(by_map):
        lines.append(f"\t[{map_id}] = {{")
        for npc in sorted(by_map[map_id]):
            lines.append(f'\t\t[{npc}] = "{" ".join(by_map[map_id][npc])}",')
        lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="redownload pinned sources")
    mode.add_argument("--offline", action="store_true", help="use cached sources only")
    args = parser.parse_args()
    kept, idle = bake(spawns(args.refresh, args.offline))
    publish({ROOT / "Data" / "Heights.lua": render(kept), ROOT / "Data" / "IdleSpawns.lua": render_idle(idle)})


if __name__ == "__main__":
    main()

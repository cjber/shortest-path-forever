"""Sample solid surfaces from TrinityCore's ADT height field and assembled VMAP collision meshes."""

import math
import struct
from functools import lru_cache
from pathlib import Path

from .terrain import TILE, Terrain

VMAP_MAGIC = b"VMAP_4.E"
MOD_HAS_BOUND = 1
MOD_PATH_ONLY = 4


class Reader:
    def __init__(self, path):
        self.path = path
        self.data = path.read_bytes()
        self.position = 0

    def take(self, size):
        start = self.position
        self.position += size
        if self.position > len(self.data):
            raise ValueError(f"Truncated VMAP: {self.path}")
        return self.data[start : self.position]

    def expect(self, tag):
        if self.take(len(tag)) != tag:
            raise ValueError(f"Expected {tag!r} in VMAP: {self.path}")

    def read(self, fmt):
        fmt = "<" + fmt
        return struct.unpack(fmt, self.take(struct.calcsize(fmt)))

    def integer(self):
        return self.read("I")[0]

    def skip_bih(self):
        self.take(24)
        self.take(4 * self.integer())
        self.take(4 * self.integer())


@lru_cache(maxsize=32)
def read_model(path):
    reader = Reader(path)
    reader.expect(VMAP_MAGIC)
    reader.expect(b"WMOD")
    header_size, flags, _root = reader.read("III")
    if header_size != 8:
        raise ValueError(f"Unsupported VMAP model header: {path}")
    if reader.position == len(reader.data):
        return flags, []
    reader.expect(b"GMOD")
    groups = []
    for _ in range(reader.integer()):
        # Bounding box, WMO group flags and group ID precede collision geometry.
        reader.take(32)
        reader.expect(b"VERT")
        vertices_size, vertices_count = reader.read("II")
        if vertices_size != 4 + 12 * vertices_count:
            raise ValueError(f"Invalid VMAP vertex count: {path}")
        if not vertices_count:
            continue
        vertices = tuple(struct.iter_unpack("<fff", reader.take(12 * vertices_count)))
        reader.expect(b"TRIM")
        triangle_size, triangle_count = reader.read("II")
        if triangle_size != 4 + 12 * triangle_count:
            raise ValueError(f"Invalid VMAP triangle count: {path}")
        triangles = tuple(struct.iter_unpack("<III", reader.take(12 * triangle_count)))
        groups.append((vertices, triangles))
        reader.expect(b"MBIH")
        reader.skip_bih()
        reader.expect(b"LIQU")
        reader.take(reader.integer())
    reader.expect(b"GBIH")
    reader.skip_bih()
    return flags, groups


def transform(position, rotation, scale):
    """TerrainBuilder::transformVertices in world (X, Y, Z), using ModelInstance's ZYX Euler rotation."""
    px, py, pz = position
    pitch, yaw, roll = map(math.radians, rotation)
    cx, sx = math.cos(roll), math.sin(roll)
    cy, sy = math.cos(pitch), math.sin(pitch)
    cz, sz = math.cos(yaw), math.sin(yaw)

    def world(vertex):
        x, y, z = vertex
        y, z = cx * y - sx * z, sx * y + cx * z
        x, z = cy * x + sy * z, -sy * x + cy * z
        x, y = cz * x - sz * y, sz * x + cz * y
        return 32 * TILE - px - scale * x, 32 * TILE - py - scale * y, pz + scale * z

    return world


def model_triangles(vmaps, map_id, row, col):
    path = vmaps / f"{map_id:04d}" / f"{map_id:04d}_{row:02d}_{col:02d}.vmtile"
    if not path.is_file():
        return
    reader = Reader(path)
    reader.expect(VMAP_MAGIC)
    for _ in range(reader.integer()):
        flags, _adt, _spawn, px, py, pz, rx, ry, rz, scale = reader.read("2BI7f")
        if flags & MOD_HAS_BOUND:
            reader.take(24)
        name = reader.take(reader.integer()).decode()
        if flags & MOD_PATH_ONLY:
            continue
        model_flags, groups = read_model(vmaps / f"{name}.vmo")
        world = transform((px, py, pz), (rx, ry, rz), scale)
        for vertices, triangles in groups:
            vertices = [world(point) for point in vertices]
            for a, b, c in triangles:
                if model_flags & 1:  # WorldModel::IsM2; TerrainBuilder flips M2 winding.
                    a, c = c, a
                yield vertices[a], vertices[b], vertices[c]
    if reader.position != len(reader.data):
        raise ValueError(f"Trailing data in VMAP tile: {path}")


class ClusterSurfaces:
    """Index source collision triangles by cell, then sample at a baked layer's anchor."""

    def __init__(self, maps_dir, map_id, row, col, cells):
        maps_dir = Path(maps_dir)
        self.terrain = Terrain(maps_dir, map_id).tile(row, col)
        self.east = (32 - row) * TILE
        self.north = (32 - col) * TILE
        self.x0 = self.east - TILE
        self.y0 = self.north - TILE
        self.cells = cells
        self.bins = {}
        for triangle in model_triangles(maps_dir.parent / "vmaps", map_id, row, col):
            (ax, ay, az), (bx, by, bz), (cx, cy, cz) = triangle
            denominator = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
            if denominator == 0:
                continue  # A vertical triangle has no single height at an XY point.
            x0, y0 = self.cell(min(ax, bx, cx), min(ay, by, cy))
            x1, y1 = self.cell(max(ax, bx, cx), max(ay, by, cy))
            plane = (ax, ay, az, bx - ax, by - ay, bz - az, cx - ax, cy - ay, cz - az, denominator)
            for ix in range(max(0, x0), min(cells - 1, x1) + 1):
                for iy in range(max(0, y0), min(cells - 1, y1) + 1):
                    self.bins.setdefault((ix, iy), []).append(plane)

    def cell(self, x, y):
        return math.floor((x - self.x0) * self.cells / TILE), math.floor((y - self.y0) * self.cells / TILE)

    def terrain_at(self, x, y):
        return self.terrain.height((self.east - x) / TILE, (self.north - y) / TILE) if self.terrain else None

    def structure_at(self, x, y):
        """Projected triangle intersections at the anchor, with their orientation."""
        for ax, ay, az, bx, by, bz, cx, cy, cz, denominator in self.bins.get(self.cell(x, y), ()):
            dx, dy = x - ax, y - ay
            u = (dx * cy - dy * cx) / denominator
            v = (bx * dy - by * dx) / denominator
            if u >= 0 and v >= 0 and u + v <= 1:
                yield az + u * bz + v * cz, denominator > 0

    def above(self, x, y, floor_z, water=False):
        """Return the extracted height and kind of cover at a walkable layer's anchor."""
        terrain = self.terrain_at(x, y)
        structures = list(self.structure_at(x, y))
        if not water:
            # Recast approximates the original surface. Match the floor to the nearest upward source face
            # before testing what lies above it; otherwise even open ground can appear under itself.
            floors = [height for height, upward in structures if upward]
            if terrain is not None:
                floors.append(terrain)
            floor_z = min(floors, key=lambda height: abs(height - floor_z), default=floor_z)
        if terrain is not None and terrain > floor_z:
            # Cave WMOs can have a ceiling mesh under the ADT. The terrain is the surface
            # a cave runs below, even when the collision ceiling is nearer the path.
            return terrain, "terrain"
        ceiling = min((height for height, _ in structures if height > floor_z), default=None)
        return (ceiling, "structure") if ceiling is not None else None

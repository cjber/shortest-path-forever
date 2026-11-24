"""Read the pinned TrinityCore Detour tile format, also used by historical bakes."""

import struct
from collections import defaultdict
from pathlib import Path

# TileBuilder builds 25 Recast subtiles per 1600/3-yard ADT edge.
SUBTILES_PER_ADT = 25
SUBTILE_WIDTH = (1600 / 3) / SUBTILES_PER_ADT
PLAYER_STEP = 2.0
# Account for float32 rounding of the ADT origin and voxel offset across the full 64-tile map.
SEAM_ROUNDING = 2**-22 * (SUBTILE_WIDTH * SUBTILES_PER_ADT * 32)


def subtile_links(edges):
    """Recover portals between unmatched, oppositely wound edges on an internal Recast subtile seam.

    Recast simplifies each subtile's contour independently. The merge only links edges with two matching
    vertices. A shared 3D vertex identifies the same floor when the other endpoint differs.
    """
    seams = defaultdict(lambda: ([], []))
    for poly, start, end in edges:
        for axis in (0, 1):
            other = 1 - axis
            line = start[axis]
            if end[axis] != line or start[other] == end[other]:
                continue
            seam = round(line / SUBTILE_WIDTH)
            if seam % SUBTILES_PER_ADT == 0 or abs(line - seam * SUBTILE_WIDTH) > SEAM_ROUNDING:
                continue
            ascending = start[other] < end[other]
            a, b = (start, end) if ascending else (end, start)
            seams[axis, a, True][ascending].append((poly, b))
            seams[axis, b, False][ascending].append((poly, a))

    for (axis, shared, lower), (descending, ascending) in seams.items():
        other = 1 - axis
        for a, p in descending:
            for b, q in ascending:
                if a == b or p[:2] == q[:2]:
                    continue
                p_width, q_width = abs(p[other] - shared[other]), abs(q[other] - shared[other])
                width = min(p_width, q_width)
                # Edge endpoints lie on the voxel grid. Discard numerical slivers, which cannot span a voxel.
                slope_delta = abs((p[2] - shared[2]) / p_width - (q[2] - shared[2]) / q_width)
                if width <= SEAM_ROUNDING or width * slope_delta > PLAYER_STEP:
                    continue
                far = p if p_width <= q_width else q
                start, end = (far[:2], shared[:2]) if lower else (shared[:2], far[:2])
                yield a, b, start, end
                yield b, a, end, start


def load_tile(path):
    """Detour tile -> (vertices, [(vertex IDs, neighbours, flags, area, type)], off-mesh connections).

    Connections are the last block of the tile data, (pos(6) radius poly flags) each, in Detour's (west, up, north)
    frame; gen_nav reads the one-way ledge drops the local bake emitted from them.
    """
    data = Path(path).read_bytes()
    if len(data) < 120:
        raise ValueError(f"Truncated navigation tile: {path}")
    magic, detour, mmap, size = struct.unpack_from("<4I", data)
    if (magic, detour, mmap) != (0x4D4D4150, 7, 16) or size != len(data) - 20:
        raise ValueError(f"Unsupported or incomplete navigation tile: {path}")
    header = struct.unpack_from("<4s14i10f", data, 20)
    poly_count, vert_count, connections = header[6:8] + (header[13],)
    if header[:2] != (b"VAND", 7) or min(poly_count, vert_count, connections) < 0:
        raise ValueError(f"Invalid Detour header: {path}")
    offset = 120 + vert_count * 12
    if offset + poly_count * 32 > len(data):
        raise ValueError(f"Truncated Detour geometry: {path}")
    verts = struct.unpack_from(f"<{vert_count * 3}f", data, 120)
    polys = []
    for _ in range(poly_count):
        _, *rest = struct.unpack_from("<I6H6HHBB", data, offset)
        offset += 32
        pv, pn, flags, count, area_type = rest[:6], rest[6:12], rest[12], rest[13], rest[14]
        if not 1 <= count <= 6 or any(v >= vert_count for v in pv[:count]):
            raise ValueError(f"Invalid Detour polygon: {path}")
        polys.append((pv[:count], pn[:count], flags, area_type & 0x3F, area_type >> 6))
    connection = 36  # sizeof(dtOffMeshConnection) at the pinned Detour
    start = len(data) - connection * connections
    if start < offset:
        raise ValueError(f"Truncated off-mesh connections: {path}")
    drops = []
    for i in range(connections):
        fields = struct.unpack_from("<7fH4B", data, start + i * connection)
        drops.append((fields[:6], fields[6], fields[7], fields[8]))
    return verts, polys, drops

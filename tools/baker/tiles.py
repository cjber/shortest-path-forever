"""Read the pinned TrinityCore Detour tile format, also used by historical bakes."""

import struct
from pathlib import Path


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

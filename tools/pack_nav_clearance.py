"""Repack format 4's clearance tail while keeping the raw baker format reversible."""

from collections import Counter

ALPHABET = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
SYMBOLS = bytes.maketrans(ALPHABET, bytes(range(64)))
MOVES = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
MARKER = b"!"
LAYER_PLANES = b"~"


class Reader:
    def __init__(self, text):
        self.values = text.translate(SYMBOLS)
        self.pos = 0

    def take(self, width=1):
        value = 0
        for _ in range(width):
            value = value * 64 + self.values[self.pos]
            self.pos += 1
        return value

    def delta(self):
        value = self.take()
        return value if value < 63 else 63 + self.take(3)

    def restrictions(self):
        node = 0
        while self.pos < len(self.values):
            node += self.delta()
            yield node, self.take(), self.take()


def skip_masks(reader, count, value_width):
    cell = 0
    for _ in range(count):
        cell += reader.delta()
        reader.pos += value_width
        yield cell, reader.take(2)


def clearance_offset(reader, cells):
    floors = list(skip_masks(reader, reader.take(3), 3))
    bases = list(skip_masks(reader, reader.take(3), 0))
    overrides = reader.take(3)
    reader.pos += overrides
    layers = Counter(cell for cell, _ in floors)
    for count, masks in ((0, floors), (1, bases)):
        for cell, mask in masks:
            x, y = divmod(cell, cells)
            for d, (dx, dy) in enumerate(MOVES):
                if mask & (1 << d):
                    tx, ty = x + dx, y + dy
                    implicit = 0 <= tx < cells and 0 <= ty < cells and layers[tx * cells + ty] == count
                    if not implicit and reader.take() == 0:
                        landings = reader.take(2)
                        reader.pos += landings
    drops = reader.take(3)
    reader.pos += drops * 8
    return reader.pos, cells * cells + len(floors)


def write_records(records):
    output = bytearray()
    last = 0
    for node, direction, layer in records:
        delta = node - last
        if delta < 63:
            output.append(delta)
        else:
            delta -= 63
            output.extend((63, delta >> 12, (delta >> 6) & 63, delta & 63))
        output.extend((direction, layer))
        last = node
    return output.translate(bytes.maketrans(bytes(range(64)), ALPHABET))


def pack_clearance(raw, cells):
    """Yield equivalent packed layouts for the zlib producer to compare."""
    reader = Reader(raw)
    offset, nodes = clearance_offset(reader, cells)
    if offset == len(raw):
        yield raw
        return
    wet, narrow, upper = bytearray(nodes), bytearray(nodes), []
    for node, direction, layer in reader.restrictions():
        if layer:
            upper.append((node, direction, layer))
        elif direction >= 8:
            narrow[node] |= 1 << (direction - 8)
        else:
            wet[node] |= 1 << direction
    prefix = raw[:offset]
    yield prefix + MARKER + wet + narrow + write_records(upper)
    if upper:
        # Keep wet/narrow masks contiguous so the reader can address them by layer and node.
        layers = {0: wet + narrow}
        for node, direction, layer in upper:
            plane = layers.get(layer)
            if plane is None:
                plane = layers[layer] = bytearray(2 * nodes)
            slot = node + (nodes if direction >= 8 else 0)
            plane[slot] |= 1 << (direction % 8)
        yield prefix + LAYER_PLANES + b"".join(bytes([layer]) + plane for layer, plane in sorted(layers.items()))


def restore_clearance(raw, cells):
    # Search the ASCII baker prefix only. The masks themselves can contain either marker.
    offset = min((pos for marker in (MARKER, LAYER_PLANES) if (pos := raw.find(marker)) >= 0), default=len(raw))
    prefix, marker, suffix = raw[:offset], raw[offset : offset + 1], raw[offset + 1 :]
    if not marker:
        return raw
    nodes = cells * cells + Reader(prefix).take(3)
    if marker == LAYER_PLANES:
        stride = 1 + 2 * nodes
        layers = ((suffix[pos], suffix[pos + 1 : pos + stride]) for pos in range(0, len(suffix), stride))
        records = []
    else:
        layers = ((0, suffix[: 2 * nodes]),)
        records = list(Reader(suffix[2 * nodes :]).restrictions())
    for layer, masks in layers:
        for flag, plane in ((0, masks[:nodes]), (8, masks[nodes:])):
            for node, mask in enumerate(plane):
                if mask:
                    records.extend((node, direction + flag, layer) for direction in range(8) if mask & (1 << direction))
    return prefix + write_records(sorted(records))

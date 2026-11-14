"""Read TrinityCore's extracted terrain height field (``maps/<map>_<row>_<col>.map``).

A tile holds a header, area ids, a height section and optionally holes (map_extractor/System.cpp and the server's
GridMap loader). The height section is one flat height, or V9's 129 x 129 grid and V8's 128 x 128 grid as floats,
uint16 or uint8 scaled between gridHeight and gridMaxHeight. A point over an extracted hole, or outside every
extracted tile, has no terrain.

Only the standard library is used: samples are taken at the centre of a walking-map cell, with the same tile and
cell layout as gen_nav.py.
"""

import struct
from pathlib import Path

TILE = 1600.0 / 3.0
RESOLUTION = 128
CELLS_PER_GRID = 16
CELL_SIZE = 8
MAP_MAGIC = b"MAPS"
MAP_VERSION = 10
HEIGHT_MAGIC = b"MHGT"

NO_HEIGHT = 0x0001
HEIGHT_AS_INT16 = 0x0002
HEIGHT_AS_INT8 = 0x0004

B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


class Tile:
    """One ADT tile's terrain height, read from its extracted ``.map`` file."""

    def __init__(self, data, name="<map>"):
        self.name = name
        if len(data) < 44:
            raise ValueError(f"Truncated map tile: {name}")
        (
            magic,
            version,
            _build,
            _area_offset,
            _area_size,
            height_offset,
            _height_size,
            _liquid_offset,
            _liquid_size,
            holes_offset,
            holes_size,
        ) = struct.unpack_from("<4s10I", data, 0)
        if magic != MAP_MAGIC or version != MAP_VERSION:
            raise ValueError(f"Unsupported map tile {name}: {magic!r} v{version}")
        if not height_offset or height_offset + 16 > len(data):
            raise ValueError(f"Map tile {name} has no height section")
        height_magic, flags, self.grid_height, self.grid_max_height = struct.unpack_from("<4sIff", data, height_offset)
        if height_magic != HEIGHT_MAGIC:
            raise ValueError(f"Map tile {name} has no height header")
        self.v9 = None
        self.v8 = None
        self.step = 0  # 0 floats, else the integer extractor's 65535 or 255
        self.holes = None
        if not flags & NO_HEIGHT:
            position = height_offset + 16
            if flags & HEIGHT_AS_INT16:
                self.v9, position = self._integers(data, position, 129 * 129, "H", name)
                self.v8, position = self._integers(data, position, 128 * 128, "H", name)
                self.step = 65535
            elif flags & HEIGHT_AS_INT8:
                self.v9, position = self._integers(data, position, 129 * 129, "B", name)
                self.v8, position = self._integers(data, position, 128 * 128, "B", name)
                self.step = 255
            else:
                count = 129 * 129 + 128 * 128
                if position + count * 4 > len(data):
                    raise ValueError(f"Truncated height data: {name}")
                values = struct.unpack_from(f"<{count}f", data, position)
                self.v9 = values[: 129 * 129]
                self.v8 = values[129 * 129 :]
        if self.step:
            scale = (self.grid_max_height - self.grid_height) / self.step
            self.v9 = [value * scale + self.grid_height for value in self.v9]
            self.v8 = [value * scale + self.grid_height for value in self.v8]
            self.step = 0
        if holes_offset and holes_size >= CELLS_PER_GRID * CELLS_PER_GRID * CELL_SIZE:
            self.holes = data[holes_offset : holes_offset + CELLS_PER_GRID * CELLS_PER_GRID * CELL_SIZE]

    @staticmethod
    def _integers(data, position, count, code, name):
        end = position + count * struct.calcsize("<" + code)
        if end > len(data):
            raise ValueError(f"Truncated height data: {name}")
        return struct.unpack_from(f"<{count}{code}", data, position), end

    def is_hole(self, row, col):
        if not self.holes:
            return False
        cell_row, cell_col = row // CELL_SIZE, col // CELL_SIZE
        index = cell_row * CELLS_PER_GRID * CELL_SIZE + cell_col * CELL_SIZE + row % CELL_SIZE
        return bool(self.holes[index] & (1 << (col % CELL_SIZE)))

    def height(self, u, v):
        """The terrain height at fractional tile coordinates u, v (0 at the high world-x/y edge), or None."""
        x, y = RESOLUTION * u, RESOLUTION * v
        x_int, y_int = int(x), int(y)
        x, y = x - x_int, y - y_int
        x_int &= RESOLUTION - 1
        y_int &= RESOLUTION - 1
        if self.is_hole(x_int, y_int):
            return None
        if self.v9 is None or self.v8 is None:
            return self.grid_height
        v9, v8 = self.v9, self.v8
        h1 = v9[x_int * 129 + y_int]
        h5 = 2 * v8[x_int * 128 + y_int]
        if x + y < 1:
            if x > y:
                h2 = v9[(x_int + 1) * 129 + y_int]
                a, b, c = h2 - h1, h5 - h1 - h2, h1
            else:
                h3 = v9[x_int * 129 + y_int + 1]
                a, b, c = h5 - h1 - h3, h3 - h1, h1
        elif x > y:
            h2 = v9[(x_int + 1) * 129 + y_int]
            h4 = v9[(x_int + 1) * 129 + y_int + 1]
            a, b, c = h2 + h4 - h5, h4 - h2, h5 - h4
        else:
            h3 = v9[x_int * 129 + y_int + 1]
            h4 = v9[(x_int + 1) * 129 + y_int + 1]
            a, b, c = h4 - h3, h3 + h4 - h5, h5 - h4
        return a * x + b * y + c


class Terrain:
    """One map's terrain tiles, cached one tile at a time because a cluster lies inside one tile."""

    def __init__(self, directory, map_id):
        self.directory = Path(directory)
        self.map_id = int(map_id)
        self._key = None
        self._tile = None

    def tile(self, row, col):
        key = (row, col)
        if key != self._key:
            path = self.directory / f"{self.map_id:04d}_{row:02d}_{col:02d}.map"
            self._tile = Tile(path.read_bytes(), path.name) if path.is_file() else None
            self._key = key
        return self._tile

    def height(self, x, y):
        row, col = int(32 - x / TILE), int(32 - y / TILE)
        if not (0 <= row < 64 and 0 <= col < 64):
            return None
        tile = self.tile(row, col)
        if tile is None:
            return None
        return tile.height((32 - row) - x / TILE, (32 - col) - y / TILE)


def sample_cluster(directory, map_id, row, col, cells, quantize=2):
    """Terrain heights at a cluster's cell centres, quantized, in gen_nav's x-major order (None = no terrain)."""
    tile = Terrain(directory, map_id).tile(row, col)
    if tile is None:
        return [None] * (cells * cells)
    heights = []
    for i in range(cells):
        u = 1 - (i + 0.5) / cells
        for j in range(cells):
            value = tile.height(u, 1 - (j + 0.5) / cells)
            heights.append(None if value is None else int(round(value / quantize)))
    return heights


def _encode_number(value, width):
    assert 0 <= value < 64**width, (value, width)
    return "".join(B64[(value >> (6 * (width - 1 - i))) & 63] for i in range(width))


def _number(text, position, width):
    value = 0
    for i in range(width):
        value = value * 64 + B64.index(text[position + i])
    return value


def encode_sparse(heights, base, cells, floors, quantize=2):
    """A cell's ground layer, for the cells whose ground is not their base surface, in cell order.

    A cell with no floor never gets an exception: it has one place to stand, and the route walks the player onto it.
    A cell with floors (``{cell: [floor height, ...]}``, lowest first, in yards) takes the layer nearest the terrain
    height at its centre, ties to the base, and stores only a ground layer that is not the base. A cell with floors
    over no terrain (an ADT hole or no extracted tile) stores the no-ground marker instead. Each exception is its cell
    delta from the previous one (symbol 0-62 is 1-63, 63 is followed by delta - 64 in three symbols), then its ground
    layer (symbol 0-62 is layer 1-63, 63 is no ground). Heights are compared in yards; ``heights`` is quantized to
    ``quantize`` yards and ``base`` is in those units.
    """
    out, previous = [], -1
    for index in range(cells * cells):
        above = floors.get(index)
        if not above:
            continue
        height = heights[index]
        if height is None:
            layer = None
        else:
            terrain = height * quantize
            best = (abs(base[index] * quantize - terrain), 0) if base[index] is not None else None
            for i, floor_z in enumerate(above, 1):
                if best is None or abs(floor_z - terrain) < best[0]:
                    best = (abs(floor_z - terrain), i)
            layer = best[1] if best else None
        if layer == 0:
            continue
        delta = index - previous
        previous = index
        if delta <= 63:
            out.append(B64[delta - 1])
        else:
            out.append(B64[63] + _encode_number(delta - 64, 3))
        out.append(B64[63] if layer is None else B64[layer - 1])
    return "".join(out)


def decode_sparse(text, base, cells, step=2):
    """Inverse of encode_sparse for tests and diagnostics: {cell: ground layer}, None for no ground.

    A cell left out of the field has the base surface as its ground. ``base`` is accepted for callers' symmetry;
    the layers are already integers.
    """
    if not text:
        return {}
    values, cell, position = {}, -1, 0
    while position < len(text):
        symbol = B64.index(text[position])
        position += 1
        if symbol < 63:
            cell += symbol + 1
        else:
            cell += 64 + _number(text, position, 3)
            position += 3
        symbol = B64.index(text[position])
        position += 1
        values[cell] = None if symbol == 63 else symbol + 1
    return values


def floor_heights(text):
    """The local cells that hold a floor, and each one's floor heights lowest first, from gen_nav's floor field."""
    if not text:
        return {}
    cells, position = {}, 3
    for _ in range(_number(text, 0, 3)):
        cell, count = _number(text, position, 3), B64.index(text[position + 3])
        position += 4
        heights = []
        for _ in range(count):
            heights.append(_number(text, position + 1, 2) - 2048)
            position += 5
        cells[cell] = heights
    return cells


def decode_values(grid, cells):
    """gen_nav's grid cell values from its grid field (0 blocked, 1 ground, 2 water)."""
    values, value = [], 0
    for symbol in grid:
        index = B64.index(symbol)
        if index < 48:
            value = index // 16
            values.append(value)
        else:
            values.extend([value] * (index - 47))
    if len(values) > cells * cells:
        raise ValueError("Grid field holds more cells than the cluster")
    values.extend([0] * (cells * cells - len(values)))
    return values


def decode_base(grid, height, cells):
    """Base surface heights in zstep units from gen_nav's grid and height fields, None where there is no surface.

    The grid field is value * 16 + flags per cell, with a symbol >= 48 repeating the previous cell; the height
    field encodes only the cells whose value is not zero (gen_nav's encode_heights), as symbols 0-46 adding -23..23,
    47 followed by an absolute value + 2048 in two symbols, and a symbol >= 48 repeating the previous difference.
    """
    present = [value != 0 for value in decode_values(grid, cells)]
    heights = [None] * (cells * cells)
    if not height:
        return heights
    last = repeat = delta = position = 0
    for index in range(cells * cells):
        if not present[index]:
            continue
        if index % cells > 0 and heights[index - 1] is not None:
            predicted = heights[index - 1]
        elif index >= cells and heights[index - cells] is not None:
            predicted = heights[index - cells]
        else:
            predicted = last
        if repeat:
            repeat -= 1
            value = predicted + delta
        else:
            symbol = B64.index(height[position])
            if symbol == 47:
                value = _number(height, position + 1, 2) - 2048
                position += 3
            else:
                delta, position = symbol - 23, position + 1
                while position < len(height) and B64.index(height[position]) >= 48:
                    repeat += B64.index(height[position]) - 47
                    position += 1
                value = predicted + delta
        last, heights[index] = value, value
    return heights

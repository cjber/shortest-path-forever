-- Builders for small format 1 and format 2 walking maps, so a spec can test the decoder and the directed search
-- without a client bake. The encoding mirrors tools/baker/gen_nav.py and Routing/PathGrid.lua's decoders.
local F = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CELLS = 67

local function enc(value, width)
	local out = {}
	for i = width, 1, -1 do
		local digit = math.floor(value / 64 ^ (i - 1)) % 64
		out[#out + 1] = ALPHABET:sub(digit + 1, digit + 1)
	end
	return table.concat(out)
end

local function symbol(value)
	return ALPHABET:sub(value + 1, value + 1)
end

-- Run-length symbols >= 48 repeat the previous cell (symbol - 47) more times.
local function runs(values, to_symbol)
	local out = {}
	local i = 1
	while i <= #values do
		local j = i + 1
		while j <= #values and values[j] == values[i] do
			j = j + 1
		end
		out[#out + 1] = to_symbol(values[i])
		local repeat_ = j - i - 1
		while repeat_ > 0 do
			local n = math.min(repeat_, 16)
			out[#out + 1] = ALPHABET:sub(48 + n, 48 + n)
			repeat_ = repeat_ - n
		end
		i = j
	end
	return table.concat(out)
end

-- Base heights in cell order: a symbol 0-46 is a delta of -23..23 from the -y neighbour (else -x, else the previous
-- cell), 47 is followed by an absolute value + 2048, and >= 48 repeats the previous delta.
local function heights(z_of)
	local at, out, last = {}, {}, 0
	for i = 0, CELLS - 1 do
		for j = 0, CELLS - 1 do
			local z = z_of(i, j)
			if z then
				local v = math.floor(z / 2 + 0.5)
				local pred = at[i .. "," .. (j - 1)] or at[(i - 1) .. "," .. j] or last
				at[i .. "," .. j], last = v, v
				out[#out + 1] = math.abs(v - pred) <= 23 and { "d", v - pred } or { "a", v }
			end
		end
	end
	local syms, n = {}, 1
	while n <= #out do
		if out[n][1] == "a" then
			syms[#syms + 1] = ALPHABET:sub(48, 48) .. enc(out[n][2] + 2048, 2)
			n = n + 1
		else
			local j = n + 1
			while j <= #out and out[j][1] == "d" and out[j][2] == out[n][2] do
				j = j + 1
			end
			syms[#syms + 1] = symbol(out[n][2] + 23)
			local repeat_ = j - n - 1
			while repeat_ > 0 do
				local take = math.min(repeat_, 16)
				syms[#syms + 1] = ALPHABET:sub(48 + take, 48 + take)
				repeat_ = repeat_ - take
			end
			n = j
		end
	end
	return table.concat(syms)
end

local function cluster(gx, gy, ny)
	return math.floor(gx / CELLS) * ny + math.floor(gy / CELLS)
end

local function local_cell(gx, gy)
	return (gx % CELLS) * CELLS + gy % CELLS
end

-- A direction byte as gen_nav.py's DIRS numbers them, and the order records are written in.
local DIRECTIONS = {
	["1,0"] = 0,
	["-1,0"] = 1,
	["0,1"] = 2,
	["0,-1"] = 3,
	["1,1"] = 4,
	["1,-1"] = 5,
	["-1,1"] = 6,
	["-1,-1"] = 7,
}

local function gen_direction(dx, dy)
	return DIRECTIONS[dx .. "," .. dy]
end

local function record_order(a, b)
	for i = 1, math.max(#a, #b) do
		if a[i] ~= b[i] then
			return a[i] < b[i]
		end
	end
	return false
end

-- A cell or node delta as format 3 stores it: symbol 0-62 is the delta, 63 is followed by the delta - 63 in three
-- characters (tools/baker/gen_nav.py's emit_delta).
local function delta(value)
	if value < 63 then
		return symbol(value)
	end
	return symbol(63) .. enc(value - 63, 3)
end

--- Build a format 2 or format 3 map: the two differ only in the floor chunk, where format 3 names the layer each
-- step bit lands on and writes cells and record nodes as deltas.
local function build(spec, format)
	local ny, nx = spec.ny, spec.nx
	local map = { cx0 = 0, cy0 = 0, nx = nx, ny = ny, cells = CELLS, swim = 3, zstep = 2, format = format }
	map.grid, map.height, map.floor, map.graph = {}, {}, {}, {}
	for _, f in ipairs(spec.floor or {}) do
		if f[4] == 3 then
			map.steep = true
		end
	end
	local cell_of = function(gx, gy)
		return spec.cell[gx] and spec.cell[gx][gy]
	end
	-- entrances per cluster, in the order the graph file lists them, so an edge can name one by its index
	local clusters, index = {}, {}
	for _, node in ipairs(spec.node or {}) do
		local k = cluster(node[1], node[2], ny)
		clusters[k + 1] = clusters[k + 1] or {}
		local list = clusters[k + 1]
		list[#list + 1] = node
		index[node[1] * nx * CELLS + node[2]] = #list - 1
	end

	for k = 0, nx * ny - 1 do
		local kx, ky = math.floor(k / ny), k % ny
		local values, any = {}, false
		for i = 0, CELLS - 1 do
			for j = 0, CELLS - 1 do
				local c = cell_of(kx * CELLS + i, ky * CELLS + j)
				if c and c.steep then
					map.steep = true
				end
				local value = c
					and ((c.steep and 1 or (c.water and 2 or 1)) * 16 + (c.flags or 0) + (c.steep and 8 or 0))
				values[#values + 1] = value or 0
				any = any or c ~= nil
			end
		end
		if any then
			map.grid[k + 1] = runs(values, symbol)
			map.height[k + 1] = heights(function(i, j)
				local c = cell_of(kx * CELLS + i, ky * CELLS + j)
				return c and c.z or nil
			end)
		end

		local steps, drops = {}, {}
		for _, l in ipairs(spec.link or {}) do
			if cluster(l[1], l[2], ny) == k then
				if (l[5] or 0) > 0 then
					drops[#drops + 1] = { local_cell(l[1], l[2]), l[3] + 8, l[4] + 8, l[6] or 0, l[5] }
				else
					-- a step's direction, + 8 when only that way takes it
					local d = gen_direction(l[3], l[4])
					assert(d, "fixture link is not one cell step")
					steps[#steps + 1] = { local_cell(l[1], l[2]), d + (l[7] and 0 or 8), l[6] or 0 }
				end
			end
		end
		local floors, cells = {}, {}
		for _, f in ipairs(spec.floor or {}) do
			if cluster(f[1], f[2], ny) == k then
				local c = local_cell(f[1], f[2])
				if not floors[c] then
					floors[c], cells[#cells + 1] = {}, c
				end
				floors[c][#floors[c] + 1] = f
			end
		end
		if #cells > 0 or #steps > 0 or #drops > 0 then
			table.sort(cells)
			local out = {}
			if format >= 3 then
				local total = 0
				for _, c in ipairs(cells) do
					total = total + #floors[c]
				end
				out[1] = enc(total, 3)
				local at = 0
				for _, c in ipairs(cells) do
					local list = floors[c]
					table.sort(list, function(a, b)
						return a[3] < b[3]
					end)
					for _, f in ipairs(list) do
						local mask, land = 0, {}
						for d = 0, 7 do
							if (f[5] or {})[d] then
								mask = mask + 2 ^ d
								land[#land + 1] = enc(f[5][d], 1)
							end
						end
						out[#out + 1] = delta(c - at)
							.. enc(f[4] or 1, 1)
							.. enc(math.floor(f[3] + 0.5) + 2048, 2)
							.. enc(mask, 2)
							.. table.concat(land)
						at = c
					end
				end
			else
				out[1] = enc(#cells, 3)
				for _, c in ipairs(cells) do
					local list = floors[c]
					table.sort(list, function(a, b)
						return a[3] < b[3]
					end)
					out[#out + 1] = enc(c, 3) .. enc(#list, 1)
					for _, f in ipairs(list) do
						out[#out + 1] = enc(f[4] or 1, 1) .. enc(math.floor(f[3] + 0.5) + 2048, 2) .. enc(f[5] or 0, 2)
					end
				end
			end
			table.sort(steps, record_order)
			out[#out + 1] = enc(#steps, 3)
			local node = 0
			for _, s in ipairs(steps) do
				out[#out + 1] = (format >= 3 and delta(s[1] - node) or enc(s[1], 3)) .. enc(s[2], 1) .. enc(s[3], 1)
				node = s[1]
			end
			table.sort(drops, record_order)
			out[#out + 1] = enc(#drops, 3)
			for _, l in ipairs(drops) do
				out[#out + 1] = enc(l[1], 3) .. enc(l[2], 1) .. enc(l[3], 1) .. enc(l[4], 1) .. enc(l[5], 2)
			end
			map.floor[k + 1] = table.concat(out)
		end

		local nodes = clusters[k + 1]
		if #nodes > 0 then
			local chunks = { enc(#nodes, 2) }
			for _, node in ipairs(nodes) do
				chunks[#chunks + 1] = enc(local_cell(node[1], node[2]), 3)
					.. enc(0, 1)
					.. enc(node[3], 2)
					.. enc(#(node.out or {}), 1)
			end
			for _, node in ipairs(nodes) do
				for _, edge in ipairs(node.out or {}) do
					local km = cluster(edge[1], edge[2], ny)
					local dx, dy = math.floor(km / ny) - kx, km % ny - ky
					assert(
						math.abs(dx) <= 1 and math.abs(dy) <= 1,
						"fixture graph edge leaves the neighbouring cluster"
					)
					chunks[#chunks + 1] = enc((dx + 1) * 3 + dy + 1, 1)
						.. enc(index[edge[1] * nx * CELLS + edge[2]], 2)
						.. enc(edge[3], 2)
						.. enc(edge[4], 2)
				end
			end
			map.graph[k + 1] = table.concat(chunks)
		end
	end

	return map
end

--- Build a format 2 map: a step both ways take is a mask bit whose landing is the surface nearest its height.
-- spec = {
--   map = 42, nx = 2, ny = 1,
--   cell = { [gx] = { [gy] = { z = 20, water = false, steep = false, flags = 0 } } }, -- steep writes flag 8
--   floor = { { gx, gy, z, value, steps } },   -- a floor surface; value 3 is steep, steps is the 8-bit mask
--   link = { { gx, gy, dx, dy, cost, layer, both } },   -- one record: a step only that way (both = a step both
--                                                       -- ways, at least one of whose ends is a floor), or, with a
--                                                       -- cost, a drop
--   node = { { gx, gy, comp, out = { { gx, gy, c1, c2 } } } },
-- }
-- A step both ways take normally lives in a floor's step mask, so a plain link is a one-way step.
function F.format2(spec)
	return build(spec, 2)
end

--- Build a format 3 map: a floor's step bits name the layer each one lands on, so the decoder resolves the pair the
-- bake linked rather than a surface merely near its height.
-- spec = format 2's, with a floor's steps a table of direction -> landing layer (0 is the target cell's base
-- surface, i the cell's ith floor) and cells and record nodes written as deltas.
function F.format3(spec)
	return build(spec, 3)
end

--- A format 1 map of base surfaces and a symmetric graph.
-- spec = {
--   map = 45, nx = 1, ny = 1,
--   cell = { [gx] = { [gy] = { z = 20, water = false, flags = 0 } } },
--   node = { { gx, gy, comp, edges = { { gx, gy, c1, c2 } } } },
-- }
-- A format 1 map has no `format` field: its links are symmetric and its floors pick a surface by height.
function F.format1_cells(spec)
	local ny, nx = spec.ny, spec.nx
	local map = { cx0 = 0, cy0 = 0, nx = nx, ny = ny, cells = CELLS, swim = 3, zstep = 2 }
	map.grid, map.height, map.floor, map.graph = {}, {}, {}, {}
	local cell_of = function(gx, gy)
		return spec.cell[gx] and spec.cell[gx][gy]
	end
	local nodes = spec.node or {}
	local index = {}
	for i, node in ipairs(nodes) do
		index[node[1] * nx * CELLS + node[2]] = i - 1
	end
	for k = 0, nx * ny - 1 do
		local kx, ky = math.floor(k / ny), k % ny
		local values, any = {}, false
		for i = 0, CELLS - 1 do
			for j = 0, CELLS - 1 do
				local c = cell_of(kx * CELLS + i, ky * CELLS + j)
				values[#values + 1] = c and ((c.water and 2 or 1) * 16 + (c.flags or 0)) or 0
				any = any or c ~= nil
			end
		end
		if any then
			map.grid[k + 1] = runs(values, symbol)
			map.height[k + 1] = heights(function(i, j)
				local c = cell_of(kx * CELLS + i, ky * CELLS + j)
				return c and c.z or nil
			end)
		end
		local here = {}
		for _, node in ipairs(nodes) do
			if cluster(node[1], node[2], ny) == k then
				here[#here + 1] = node
			end
		end
		if #here > 0 then
			local chunks = { enc(#here, 2) }
			for _, node in ipairs(here) do
				chunks[#chunks + 1] = enc(local_cell(node[1], node[2]), 3)
					.. enc(0, 1)
					.. enc(node[3], 2)
					.. enc(#(node.edges or {}), 1)
			end
			for _, node in ipairs(here) do
				for _, edge in ipairs(node.edges or {}) do
					local km = cluster(edge[1], edge[2], ny)
					local dx, dy = math.floor(km / ny) - kx, km % ny - ky
					chunks[#chunks + 1] = enc((dx + 1) * 3 + dy + 1, 1)
						.. enc(index[edge[1] * nx * CELLS + edge[2]], 2)
						.. enc(edge[3], 2)
						.. enc(edge[4], 2)
				end
			end
			map.graph[k + 1] = table.concat(chunks)
		end
	end
	return map
end

--- A format 1 map: one cluster with a three-cell strip of ground, a floor above the middle cell with one step bit
-- and one explicit link, and a symmetric graph of two entrances.
function F.format1()
	local map = { cx0 = 0, cy0 = 0, nx = 1, ny = 1, cells = CELLS, swim = 3, zstep = 2 }
	local strip = function(i, j)
		return i == 5 and j >= 10 and j <= 12
	end
	local of = function(i, j)
		return strip(i, j) and { z = 20, flags = j == 10 and 1 or 0 } or nil
	end
	local values = {}
	for i = 0, CELLS - 1 do
		for j = 0, CELLS - 1 do
			local c = of(i, j)
			values[#values + 1] = c and (16 + c.flags) or 0
		end
	end
	map.grid = { [1] = runs(values, symbol) }
	map.height = {
		[1] = heights(function(i, j)
			local c = of(i, j)
			return c and c.z or nil
		end),
	}
	-- One floor at 23 yards on the strip's middle cell, value 1: its +y step bit, and one explicit link to the base
	-- surface in -y (direction 3), which the decoder must mirror as the reverse link on that cell.
	map.floor =
		{
			[1] = enc(1, 3) .. enc(local_cell(5, 11), 3) .. enc(1, 1) .. enc(1, 1) .. enc(23 + 2048, 2) .. enc(
				2 ^ 2,
				2
			) .. enc(1, 3) .. enc(CELLS * CELLS, 3) .. enc(3, 1) .. enc(0, 1),
		}
	-- Two entrances on the strip, each a symmetric edge to the other.
	map.graph =
		{
			[1] = enc(2, 2) .. enc(local_cell(5, 10), 3) .. enc(0, 1) .. enc(1, 2) .. enc(1, 1) .. enc(
				local_cell(5, 12),
				3
			) .. enc(0, 1) .. enc(1, 2) .. enc(1, 1) .. enc(4, 1) .. enc(1, 2) .. enc(16, 2) .. enc(16, 2) .. enc(
				4,
				1
			) .. enc(0, 2) .. enc(16, 2) .. enc(16, 2),
		}
	return map
end

--- Install a map as ShortestPathForeverPathData[id].
function F.install(id, map)
	_G.ShortestPathForeverPathData = _G.ShortestPathForeverPathData or {}
	_G.ShortestPathForeverPathData[id] = map
end

return F

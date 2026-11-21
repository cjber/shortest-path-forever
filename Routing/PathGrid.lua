---@class SPFNamespace
local ns = select(2, ...)

-- rule-ignore: file-size-no-growth - the decoded walking grid and its searches share one hot path

if ns.broken then
	return
end

-- Walking routes over a continent's collision map: HPA* between ADT-tile clusters, an 8 yd grid inside them,
-- then string-pulling so the drawn line is not jagged. FindMany resolves costs in one abstract Dijkstra.
-- Costs use the graph and local grid weights; smoothing changes only the drawing.
-- Coordinates are UnitPosition's frame (x north, y west).
-- A cell holds its base surface and, where surfaces overlap (a tunnel under a mountain, a city under ruins, both
-- ends of a lift), floors above or below it. A node is a local cell (the base surface) or C * C + a floor's index.
-- Format 3 maps carry directed links, so a ledge can be dropped off but not climbed, steep ground walked down but
-- not up. A step both ways take is one bit, and its floor node's landings name the layer it lands on, so the decoder
-- resolves the pair the bake linked; in a `steep` map a ground cell's flag 8 and a floor value of 3 mark steep
-- ground, and the decoder compares the two stored heights so only the downhill direction passes. Only a step one way
-- takes or a cost of its own is a record, and the decoder mirrors each link into the reverse lists a reverse search
-- walks rather than storing them.
-- Format 2 maps keep symmetric links but resolve a floor step bit by height; format 1 maps (every map shipped before
-- format 2) keep symmetric links and pick a floor step's surface by height too.
-- This file holds the decoded maps, their memory ceilings, frame slicing and string-pulling; Path.lua searches them
-- and PathJobs.lua schedules the searches.
---@class SPFPath
local Path = {}
ns.Path = Path

-- Milliseconds of path work a frame. A slice overruns it by about half a millisecond, inside the 3 ms frame
-- rule (#1080).
Path.budget = 2.5
Path.clusters = 64 -- secondary count ceiling per map (at least 4)
-- Decoded entrances/edges across all maps. A reverse search across a continent keeps a ring of clusters in use, each
-- with its inbound lists; 4 MB held about 55 of them, and a search over most of Kalimdor rebuilt each cluster's lists
-- about five times (#1074).
Path.graphKB = 8192
Path.cacheKB = 24576 -- decoded grids across all maps; active corridors may exceed it
Path.clock = debugprofilestop or function()
	return os.clock() * 1000
end
-- With Follow roads on, a yard off the road counts as 1.5 while a walk is chosen: a road is taken when it adds less
-- than half again to the walk.
local OFFROAD = 1.5

local TILE = 1600 / 3
local SNAP = 6 -- cells searched around an off-grid endpoint
local ZTOL = 10 -- an endpoint stands on a surface within this height (yd)
local CHECK = 64 -- expansions between clock reads

local byte, floor, sqrt, huge, max, min, abs =
	string.byte, math.floor, math.sqrt, math.huge, math.max, math.min, math.abs
local yield = coroutine.yield

local B64 = {}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, 64 do
		B64[byte(alphabet, i)] = i - 1
	end
end

local function num(s, i, width)
	local a, b, c = byte(s, i, i + width - 1)
	if width == 1 then
		return B64[a]
	end
	local value = B64[a] * 64 + B64[b]
	return width == 2 and value or value * 64 + B64[c]
end

-- Slicing yields at the shared deadline; pump swaps each coroutine's private search scratch before resuming it.
local deadline, ops, expansions = huge, 0, 0
-- Set while this module answers a question asked from outside a job's own search (Quiet).
local quiet = false
local clock = function()
	return Path.clock()
end

local function slice()
	if not quiet and deadline < huge and clock() > deadline then
		yield()
	end
end

-- Slicing is for a path job's own search, and for a checkpoint a caller inside one asks for (Path.Checkpoint). Work a
-- job's callback asks for must not slice: the client can reach a callback from C (a secure hook, another addon's
-- estimate), and no yield may cross that (#717).
Path.Checkpoint = slice

-- A question this module answers for a caller outside a job's own search — a stop's ground, the node an endpoint
-- snaps to for a batch that may be reused — is asked from a path job's callback, where the client may be inside a C
-- call it cannot yield across: the journey's route setter is a hooksecurefunc trampoline (Transport/Taxi.lua), and the
-- map it refreshes asks each stop for its ground. Quiet decodes what such a question reads whole, in the asking frame,
-- so no grid read taken to answer a question pauses the work that asked it (#803). Slicing comes back with the next
-- Deadline, which pump arms before every resume, so a query that raises cannot leave it off.
---@param fn fun(...): any
---@return any ...
local function Quiet(fn, ...)
	local was = quiet
	quiet = true
	local a, b, c = fn(...)
	quiet = was
	-- the queries this serves answer with at most three values
	return a, b, c
end

local function tick()
	expansions = expansions + 1
	ops = ops + 1
	if ops >= CHECK then
		ops = 0
		slice()
	end
end

-- Pump and the synchronous searches arm the deadline; math.huge never yields.
local function Deadline(limit)
	deadline, ops, quiet = limit, 0, false
end

-- The running expansion count, replaced when count is given.
local function Expansions(count)
	expansions = count or expansions
	return expansions
end

-- Compressed terrain is bundled with the main addon; decoded clusters stay lazy.
local function Data(map)
	return ShortestPathForeverPathData and ShortestPathForeverPathData[map]
end

local states = {}
-- Each map's endpoint connections, kept when a journey ends and its states go (Reset): a flight master's or dock's
-- entrance costs are the same for every journey, and connecting one is a search over its whole cluster (#1080).
local keptEnds = {}

local function unpackField(data, field, key)
	if data[field][key] or not data.packed then
		return data[field][key]
	end
	local blocks = data.packed[field][key]
	if not blocks then
		return nil
	end
	local chunks = {}
	for i, block in ipairs(blocks) do
		slice()
		local compressed = C_EncodingUtil.DecodeBase64(block)
		local raw = compressed and C_EncodingUtil.DecompressString(compressed, Enum.CompressionMethod.Zlib)
		if not raw then
			return nil
		end
		chunks[i] = raw
	end
	local raw = table.concat(chunks)
	data[field][key] = raw
	return raw
end

-- The client walks a slope up to 50 degrees; the bake marks the faces from 50 to 61.6 degrees as steep, and those
-- may only go downhill.
local function steepGround(valA, zA, from, valB, zB, to)
	if valA[from + 1] ~= 3 and valB[to + 1] ~= 3 then
		return true
	end
	return zB[to + 1] <= zA[from + 1]
end

-- A format 2 map's links are symmetric, so nothing in it says a step is one-way but the steep flag, and its stored
-- heights also refuse a climb past 50 degrees (#897). A format 3 map's links are directed: the bake links two cells
-- only the ways the navmesh walks between them, and that navmesh holds the player's slope and 2.0 yd step, so it
-- already refuses a climb the client refuses and joins real stairs steeper than 50 degrees. There the stored heights
-- judge steep ground alone; the climb test refused stairs and ramps the navmesh joins, and one stored height off its
-- ground turned the Dun Algaz pass one-way (#1011).
local TAN50 = math.tan(50 * math.pi / 180)
local function climbStep(valA, zA, from, valB, zB, to, distance)
	if distance and zB[to + 1] - zA[from + 1] > TAN50 * distance then
		return false
	end
	return steepGround(valA, zA, from, valB, zB, to)
end

-- May a base step feed a diagonal detour? A steep step only does when its stored heights match: a step that only
-- goes downhill is one direction, and a detour through it would turn that into a climb.
local function bitStep(val, z, a, b)
	return (val[a] ~= 3 and val[b] ~= 3) or z[a] == z[b]
end

local function State(map)
	local st = states[map]
	if st == nil then
		local D = Data(map)
		if states[map] then
			return states[map]
		end
		if not D then
			return nil
		end
		local C = D.cells
		st = {
			D = D,
			map = map,
			C = C,
			fmt = D.format or 1,
			-- Format 1 carries no steep ground, so it takes the plain step and never reads a height.
			steep = (D.format or 1) >= 3 and steepGround or (D.format == 2 and climbStep) or nil,
			ny = D.ny,
			GX = D.nx * C,
			GY = D.ny * C,
			x0 = D.cx0 * TILE,
			y0 = D.cy0 * TILE,
			cs = TILE / C,
			swim = D.swim,
			zstep = D.zstep,
			sizes = {},
			used = {}, -- [k] = last use, for eviction
			decoded = 0,
			val = {}, -- [k] = node values (node + 1), false when the cluster has no data
			moves = {}, -- [k][lc + 1] = open moves inside the cluster + 16 * the data file's step flags
			z = {}, -- [k][node + 1] = height of a walkable node
			terrain = {}, -- [k][cell + 1] = the cell's ground layer, or false when it has floors over no terrain
			at = {}, -- [k][node + 1] = a floor's local cell; [k][-(lc + 1)] = the cell's first floor node
			links = {}, -- [k][node + 1] = { link, ... } steps besides the base grid's
			linksIn = {}, -- [k][node + 1] = the links into a node, mirrored from the links out of it (format 2)
			graphUsed = {},
			graphSize = {},
			nodes = {}, -- [k] = entrance ids (k * 4096 + i)
			ncell = {}, -- [id] = local cell
			nlayer = {}, -- [id] = 0 for the base surface, i for the cell's ith floor
			ncomp = {},
			nadj = {}, -- [id] = { target, cost swimming, cost walking on water, ... }
			nadjIn = {}, -- [id] = the same for the edges that reach it, built when a reverse search needs them
			baseBuilt = {},
			inBuilt = {}, -- [k] = true once cluster k's inbound lists are built
			outDeg = {},
			baseDeg = {},
			baseAdj = {},
			baseIn = {},
			ends = {}, -- bounded local connections, shared by successive endpoint batches and journeys
			endCount = 0,
			road = {}, -- [k] = road cells (local cell -> coverage), false when the cluster has none
			roadEdges = {}, -- [k] = baked entrance edge ratios (RoadEdges.lua)
			roadIn = {}, -- [k] = the same for the edges that reach a node, aligned with preceding()
			nodeZ = {}, -- [id] = an entrance's stored height, kept after its cluster is released
			nodeSteep = {}, -- [id] = whether its surface is steep ground
		}
		local kept = keptEnds[map]
		if kept then
			st.ends, st.endCount = kept.ends, kept.count
		end
		states[map] = st
	end
	return st
end

-- Directions of floor links: +x, -x, +y, -y, +x+y, +x-y, -x+y, -x-y.
-- A decoded link entry at or above FREE is a step the bake's navmesh walk decided, taken as written: the steep test
-- never judges it by stored height (#1101). It sits above every cost a record can hold (two symbols, below 4096), so
-- the cost reads floor(entry / 16384) % 8192.
local FREE = 2 ^ 27
local DX = { [0] = 1, -1, 0, 0, 1, 1, -1, -1 }
local DY = { [0] = 0, 0, 1, -1, 1, -1, 1, -1 }
local OPPOSITE = { [0] = 1, 0, 3, 2, 7, 6, 5, 4 }
local DIRECTION = {} -- [(dx + 1) * 3 + dy + 1] = direction
for d = 0, 7 do
	DIRECTION[(DX[d] + 1) * 3 + DY[d] + 1] = d
end

-- The node on local cell lc for a link layer (0 the base surface, i the ith floor up, -1 the surface nearest
-- height h), with its height gap for -1. The cluster must be decoded.
local function surface(st, k, lc, layer, h, values, heights, floors)
	local val, z, at = values or st.val[k], heights or st.z[k], floors or st.at[k]
	local first = at[-(lc + 1)]
	if layer == 0 then
		return val[lc + 1] ~= 0 and lc or nil
	elseif layer > 0 then
		local node = first and first + layer - 1
		return node and at[node + 1] == lc and node or nil
	end
	local best, gap
	if val[lc + 1] ~= 0 then
		best, gap = lc, abs(z[lc + 1] - h)
	end
	local node = first
	while node and at[node + 1] == lc do
		if not gap or abs(z[node + 1] - h) < gap then
			best, gap = node, abs(z[node + 1] - h)
		end
		node = node + 1
	end
	return best, gap
end

-- Floor step masks recur thousands of times. Share the common immutable link sets;
-- the few nodes with additional explicit links copy on write.
local linkSets, directionBits = {}, {}
for _, layer in ipairs({ -1, 1 }) do
	linkSets[layer] = setmetatable({}, {
		__index = function(set, mask)
			if mask == 0 then
				return nil
			end
			local links, bits = { shared = layer, mask = mask }, mask
			for d = 0, 7 do
				if bits % 2 == 1 then
					links[#links + 1] = d + 8 * (layer + 1)
				end
				bits = floor(bits / 2)
			end
			set[mask] = links
			return links
		end,
	})
end
for d = 0, 7 do
	directionBits[d] = 2 ^ d
end
local stepLinks = linkSets[-1]

local function addLink(links, node, d, layer)
	local l = links[node + 1]
	local set = linkSets[layer]
	if set and (not l or l.shared == layer) then
		local mask, bit = l and l.mask or 0, directionBits[d]
		if floor(mask / bit) % 2 == 0 then
			mask = mask + bit
		end
		links[node + 1] = set[mask]
		return
	end
	if not l then
		l = {}
		links[node + 1] = l
	elseif l.shared then
		local copy = {}
		for i = 1, #l do
			copy[i] = l[i]
		end
		l, links[node + 1] = copy, copy
	end
	l[#l + 1] = d + 8 * (layer + 1)
end

local function decodeHeights(st, val, z, s)
	local C, step = st.C, st.zstep
	local pos, rep, delta, last = 1, 0, 0, 0
	for i = 1, C * C do
		if i % 256 == 0 then
			slice()
		end
		if val[i] ~= 0 then
			local a = i - 1
			local pred = (a % C > 0 and z[i - 1] and z[i - 1] / step)
				or (a >= C and z[i - C] and z[i - C] / step)
				or last
			local v
			if rep > 0 then
				rep, v = rep - 1, pred + delta
			else
				local sym = B64[byte(s, pos)]
				if sym == 47 then
					v, pos = num(s, pos + 1, 2) - 2048, pos + 3
				else
					delta, pos = sym - 23, pos + 1
					while pos <= #s and B64[byte(s, pos)] >= 48 do
						rep, pos = rep + B64[byte(s, pos)] - 47, pos + 1
					end
					v = pred + delta
				end
			end
			last, z[i] = v, v * step
		end
	end
end

-- A cluster's terrain exceptions (tools/baker/terrain.py): only the cells whose ground is one of their floors, plus
-- cells with floors over no terrain. Each exception is its cell delta from the previous one (symbol 0-62 is 1-63, 63
-- is followed by the delta - 64 in three symbols), then its ground layer (symbol 0-62 is layer 1-63, 63 is no
-- ground). A cell with no floor is left out: it has one place to stand, and the route walks the player onto it.
-- Decoded on the first ground() call, so route decoding never reads it.
local function decodeTerrain(s)
	local out = {}
	if not s or s == "" then
		return out
	end
	local cell, pos = -1, 1
	while pos <= #s do
		if pos % 512 == 1 then
			slice()
		end
		local sym = B64[byte(s, pos)]
		pos = pos + 1
		if sym < 63 then
			cell = cell + sym + 1
		else
			cell = cell + 64 + num(s, pos, 3)
			pos = pos + 3
		end
		sym = B64[byte(s, pos)]
		pos = pos + 1
		out[cell + 1] = sym == 63 and false or sym + 1
	end
	return out
end

-- Format 2 links: a step both ways take is a bit in a node's step mask, resolved to the surface in that direction
-- nearest the node's height, exactly as format 1 writes it; every other link is one record per direction, either a
-- step [node(3) direction(1) layer(1)], the direction + 8 when only that way takes it, or a drop
-- [node(3) 16(1) x(1) y(1) layer(1) cost(2)], the cell offset it falls and its cost in whole yards. Layer 0 is the
-- base surface, i the cell's ith floor. A record packs as dx + 8 + 16 * (dy + 8) + 256 * (layer + 1) + 16384 * cost,
-- where a layer byte of 0 (a step bit) means the surface nearest the node's height. Nothing stores a link's reverse:
-- the decoder mirrors each link on the surface it lands on, which is a reverse search's edge and, for a step both
-- ways take, that surface's own outbound link too.
-- Format 3 names each bit's landing layer, one layer per set direction in ascending order at the node's landing run
-- (lpos), and a record's node is a delta from the record before it, so both read the pair the bake linked.
-- A step record's direction + 16 is taken as written: the bake's navmesh walk decided it where the steep test's
-- stored heights would misread it (#1101), so the search skips that test for it. The link entry carries FREE.
local function decodeLinks(st, k, val, z, at, links, s, pos, masks, last, lpos)
	local C, N = st.C, st.C * st.C
	local back, fmt = {}, st.fmt
	local function add(into, node, entry)
		local list = into[node + 1]
		if list then
			list[#list + 1] = entry
		else
			into[node + 1] = { entry }
		end
	end
	local function link(node, dx, dy, layer, cost, both, free)
		local flag = free and FREE or 0
		local entry = dx + 8 + 16 * (dy + 8) + 256 * (layer + 1) + 16384 * cost + flag
		add(links, node, entry)
		local cell = node < N and node or at[node + 1]
		local tx, ty = floor(cell / C) + dx, cell % C + dy
		if tx < 0 or ty < 0 or tx >= C or ty >= C then
			return
		end
		local target = surface(st, k, tx * C + ty, layer, z[node + 1], val, z, at)
		if not target then
			return
		end
		local source = node < N and 1 or node - at[-(cell + 1)] + 2
		local mirror = -dx + 8 + 16 * (-dy + 8) + 256 * source + 16384 * cost + flag
		add(back, target, mirror)
		if both then
			add(links, target, mirror)
			add(back, node, entry)
		end
	end
	for index = N + 1, last do
		if index % 64 == 0 then
			slice()
		end
		local bits = masks[index]
		if bits then
			local p = lpos and lpos[index]
			for d = 0, 7 do
				if bits % 2 == 1 then
					local layer = -1
					if p then
						layer, p = B64[byte(s, p)], p + 1
					end
					link(index - 1, DX[d], DY[d], layer, 0, true)
				end
				bits = floor(bits / 2)
			end
		end
	end
	local steps, at_step = num(s, pos, 3), pos + 3
	local record = 0
	for i = 1, steps do
		if i % 64 == 0 then
			slice()
		end
		if fmt >= 3 then
			-- a record's node is the delta from the record before it: symbol 0-62 is the delta, 63 is followed by
			-- the delta - 63 in three symbols
			local sym = B64[byte(s, at_step)]
			at_step = at_step + 1
			if sym < 63 then
				record = record + sym
			else
				record, at_step = record + 63 + num(s, at_step, 3), at_step + 3
			end
			local kind = B64[byte(s, at_step)]
			link(record, DX[kind % 8], DY[kind % 8], B64[byte(s, at_step + 1)], 0, kind % 16 < 8, kind >= 16)
			at_step = at_step + 2
		else
			record = num(s, at_step, 3)
			local kind = B64[byte(s, at_step + 3)]
			link(record, DX[kind % 8], DY[kind % 8], B64[byte(s, at_step + 4)], 0, kind % 16 < 8, kind >= 16)
			at_step = at_step + 5
		end
	end
	local drops, at_drop = num(s, at_step, 3), at_step + 3
	for i = 1, drops do
		if i % 64 == 0 then
			slice()
		end
		local node = num(s, at_drop, 3)
		link(
			node,
			B64[byte(s, at_drop + 3)] - 8,
			B64[byte(s, at_drop + 4)] - 8,
			B64[byte(s, at_drop + 5)],
			num(s, at_drop + 6, 2),
			false
		)
		at_drop = at_drop + 8
	end
	return back
end

-- A format 3 floor node stores one landing layer per set direction of its step mask.
local function landingCount(mask)
	local n = 0
	for _ = 1, 8 do
		n = n + mask % 2
		mask = floor(mask / 2)
	end
	return n
end

local function decodeFloors(st, k, val, z, chunks)
	local at, links = {}, {}
	if not chunks then
		return at, links, nil
	end
	local s, C = chunks, st.C
	local node, pos = C * C, 4
	if st.fmt >= 3 then
		-- Format 3: a floor node per record, its cell a delta from the node before it, then value, stored height,
		-- step mask, and one landing layer per set direction.
		local masks, lpos, lc = {}, {}, 0
		for _ = 1, num(s, 1, 3) do
			if node % 64 == 0 then
				slice()
			end
			local sym = B64[byte(s, pos)]
			pos = pos + 1
			if sym < 63 then
				lc = lc + sym
			else
				lc, pos = lc + 63 + num(s, pos, 3), pos + 3
			end
			val[node + 1], z[node + 1], at[node + 1] = B64[byte(s, pos)], num(s, pos + 1, 2) - 2048, lc
			if at[-(lc + 1)] == nil then
				at[-(lc + 1)] = node
			end
			local mask = num(s, pos + 3, 2)
			masks[node + 1], lpos[node + 1] = mask, pos + 5
			pos = pos + 5 + landingCount(mask)
			node = node + 1
		end
		return at, links, decodeLinks(st, k, val, z, at, links, s, pos, masks, node, lpos)
	end
	local masks = st.fmt >= 2 and {} or nil
	for _ = 1, num(s, 1, 3) do
		local lc, count = num(s, pos, 3), B64[byte(s, pos + 3)]
		pos = pos + 4
		at[-(lc + 1)] = node
		for _ = 1, count do
			if node % 64 == 0 then
				slice()
			end
			val[node + 1], z[node + 1], at[node + 1] = B64[byte(s, pos)], num(s, pos + 1, 2) - 2048, lc
			if st.fmt < 2 then
				links[node + 1] = stepLinks[num(s, pos + 3, 2)]
			else
				masks[node + 1] = num(s, pos + 3, 2)
			end
			pos, node = pos + 5, node + 1
		end
	end
	if st.fmt >= 2 then
		return at, links, decodeLinks(st, k, val, z, at, links, s, pos, masks, node)
	end
	local last = node
	for i = 1, num(s, pos, 3) do
		if i % 64 == 0 then
			slice()
		end
		addLink(links, num(s, pos + 3, 3), B64[byte(s, pos + 6)], B64[byte(s, pos + 7)])
		pos = pos + 5
	end
	-- A base cell's links to floors inside the cluster are the reverse of the floors' own.
	for f = C * C, last - 1 do
		if f % 64 == 0 then
			slice()
		end
		local l, lc = links[f + 1], at[f + 1]
		local layer = f - at[-(lc + 1)] + 1
		for e = 1, l and #l or 0 do
			local d = l[e] % 8
			local tx, ty = floor(lc / C) + DX[d], lc % C + DY[d]
			if tx >= 0 and ty >= 0 and tx < C and ty < C then
				local t = surface(st, k, tx * C + ty, floor(l[e] / 8) - 1, z[f + 1], val, z, at)
				if t and t < C * C then
					addLink(links, t, OPPOSITE[d], layer)
				end
			end
		end
	end
	return at, links, nil
end

local function decodeGrid(st, k)
	Path.decodes = (Path.decodes or 0) + 1
	local chunks = unpackField(st.D, "grid", k + 1)
	if not chunks then
		st.val[k] = false
		return false
	end
	local s, C = chunks, st.C
	local height = unpackField(st.D, "height", k + 1)
	if not height then
		st.val[k] = false
		return false
	end
	local floors = unpackField(st.D, "floor", k + 1)
	if st.D.packed and st.D.packed.floor[k + 1] and not floors then
		st.val[k] = false
		return false
	end
	local val, m = {}, {}
	local n, valueCode, moveCode = 0, 0, 0
	for i = 1, #s do
		if i % 256 == 0 then
			slice()
		end
		local sym = B64[byte(s, i)]
		if sym < 48 then
			valueCode, moveCode = floor(sym / 16), (sym % 16) * 16
			-- A steep map spends a ground cell's flag 8 on steep ground, not on its -x-y diagonal (that is a record).
			if st.D.steep and valueCode == 1 and moveCode >= 128 then
				valueCode, moveCode = 3, moveCode - 128
			end
			n = n + 1
			val[n], m[n] = valueCode, moveCode
		else
			for _ = 48, sym do
				n = n + 1
				val[n], m[n] = valueCode, moveCode
			end
		end
	end
	local z = {}
	decodeHeights(st, val, z, height)
	-- m[i] packs the open moves (1 = +x, 2 = +y, 4 = +x+y, 8 = +x-y) over the data flags * 16.
	local N = C * C
	-- Descending cells let diagonals reuse their forward neighbours' decoded moves in the same pass. A steep step
	-- with unequal stored heights is a one-way step, so it must not feed a diagonal detour.
	for a = N - 1, 0, -1 do
		if a % 256 == 0 then
			slice()
		end
		local i, ly = a + 1, a % C
		local f = m[i] / 16
		if val[i] ~= 0 then
			if a + C < N and val[i + C] ~= 0 and f % 2 == 0 then
				m[i] = m[i] + 1
			end
			if ly < C - 1 and val[i + 1] ~= 0 and f % 4 < 2 then
				m[i] = m[i] + 2
			end
		end
		-- Diagonals: either L-shaped detour open, or an explicit link.
		if a + C < N and val[i] ~= 0 then
			if
				ly < C - 1
				and val[i + C + 1] ~= 0
				and (
					(
						m[i] % 2 == 1
						and bitStep(val, z, i, i + C)
						and m[i + C] % 4 >= 2
						and bitStep(val, z, i + C, i + C + 1)
					)
					or (m[i] % 4 >= 2 and bitStep(val, z, i, i + 1) and m[i + 1] % 2 == 1 and bitStep(
						val,
						z,
						i + 1,
						i + C + 1
					))
					or f % 8 >= 4
				)
			then
				m[i] = m[i] + 4
			end
			if
				ly > 0
				and val[i + C - 1] ~= 0
				and (
					(
						m[i] % 2 == 1
						and bitStep(val, z, i, i + C)
						and m[i + C - 1] % 4 >= 2
						and bitStep(val, z, i + C - 1, i + C)
					)
					or (val[i - 1] ~= 0 and m[i - 1] % 64 < 32 and m[i - 1] % 32 < 16 and bitStep(val, z, i, i - 1) and bitStep(
						val,
						z,
						i - 1,
						i + C - 1
					))
					or f >= 8
				)
			then
				m[i] = m[i] + 8
			end
		end
	end
	local at, links, back = decodeFloors(st, k, val, z, floors)
	return val, m, z, at, links, back
end

-- Lua 5.1 array slots occupy 16 bytes and grow by powers of two. Charge sparse floor/link hashes
-- conservatively too; this is a memory ceiling across continents, not a cluster count estimate.
local useClock, decodedKB, decodedCount = 0, 0, 0
local function gridSize(val, at, links, back)
	local capacity = 1
	while capacity < #val do
		capacity = capacity * 2
	end
	local bytes = capacity * 16 * 3 + 5 * 64
	for _ in pairs(at) do
		bytes = bytes + 64
	end
	for _, link in pairs(links) do
		bytes = bytes + 128 + #link * 32
	end
	for _, link in pairs(back or {}) do
		bytes = bytes + 128 + #link * 32
	end
	return bytes / 1024
end

local function evict(st, oldest)
	decodedKB, decodedCount = decodedKB - st.sizes[oldest], decodedCount - 1
	st.sizes[oldest], st.used[oldest] = nil, nil
	st.val[oldest], st.moves[oldest], st.z[oldest], st.at[oldest], st.links[oldest] = nil, nil, nil, nil, nil
	st.terrain[oldest] = nil
	st.linksIn[oldest], st.road[oldest], st.roadEdges[oldest], st.roadIn[oldest] = nil, nil, nil, nil
	st.decoded = st.decoded - 1
end

-- Each search owns its corridor until its scheduler releases it, including abandoned coroutines.
local holds = {}

local function Hold(job, st, k)
	local held = holds[job]
	if not held then
		held = { state = st, clusters = {} }
		holds[job] = held
	end
	held.clusters[k] = true
end

local function Release(job)
	holds[job] = nil
end

local function held(st, k)
	for _, corridor in pairs(holds) do
		if corridor.state == st and corridor.clusters[k] then
			return true
		end
	end
	return false
end

-- The job its scheduler is resuming. A cluster it decodes is held with its corridor: line pulling reads clusters
-- beside the corridor, and once the held corridor fills the cache those would evict each other within one search,
-- so the same walk searched again would decode them again.
local running

---@param job table?
local function Running(job)
	running = job
end

local function trim(st, size)
	while (decodedKB + size > Path.cacheKB and decodedCount >= 4) or st.decoded >= max(Path.clusters, 4) do
		local owner, oldest, age = nil, nil, huge
		for _, candidate in pairs(states) do
			if st.decoded < max(Path.clusters, 4) or candidate == st then
				-- Never the grid touched last: a step reads the cluster it stands in while it decodes the next one.
				for k, used in pairs(candidate.used) do
					if used < age and used < useClock and not held(candidate, k) then
						owner, oldest, age = candidate, k, used
					end
				end
			end
		end
		if not owner or not oldest then
			break
		end
		evict(owner, oldest)
	end
end

local function grid(st, k)
	local val = st.val[k]
	if val == nil then
		local m, z, at, links, back
		val, m, z, at, links, back = decodeGrid(st, k)
		-- Decoding may yield; only complete grids are published to concurrent searches.
		if st.val[k] ~= nil then
			return grid(st, k)
		end
		if not val then
			return false
		end
		local size = gridSize(val, at, links, back)
		trim(st, size)
		st.val[k], st.moves[k], st.z[k], st.at[k], st.links[k] = val, m, z, at, links
		st.linksIn[k] = back
		st.sizes[k], st.decoded, decodedKB = size, st.decoded + 1, decodedKB + size
		decodedCount = decodedCount + 1
		if running then
			Hold(running, st, k)
		end
		if st.D.packed then
			st.D.grid[k + 1], st.D.height[k + 1], st.D.floor[k + 1] = nil, nil, nil
		end
	end
	if val then
		useClock = useClock + 1
		st.used[k] = useClock
	end
	return val
end

-- A node's local cell.
local function cellOf(st, k, node)
	if node < st.C * st.C then
		return node
	end
	grid(st, k)
	return st.at[k][node + 1]
end

local graphKB, graphClock = 0, 0
local function trimGraphs()
	while graphKB > Path.graphKB do
		local owner, oldest, age = nil, nil, huge
		for _, st in pairs(states) do
			for k, used in pairs(st.graphUsed) do
				if used < age then
					owner, oldest, age = st, k, used
				end
			end
		end
		if not owner or not oldest then
			break
		end
		for _, id in ipairs(owner.nodes[oldest]) do
			owner.ncell[id], owner.nlayer[id], owner.ncomp[id], owner.nadj[id] = nil, nil, nil, nil
			owner.nadjIn[id], owner.baseAdj[id], owner.baseIn[id], owner.baseDeg[id] = nil, nil, nil, nil
		end
		owner.outDeg[oldest], owner.inBuilt[oldest], owner.baseBuilt[oldest] = nil, nil, nil
		if owner.D.packed then
			owner.D.graph[oldest + 1] = nil
		end
		graphKB = graphKB - owner.graphSize[oldest]
		owner.nodes[oldest], owner.graphUsed[oldest], owner.graphSize[oldest] = nil, nil, nil
	end
end

local function decodeGraph(st, k)
	slice()
	if st.nodes[k] then
		return st.nodes[k]
	end
	trimGraphs()
	local chunks = unpackField(st.D, "graph", k + 1)
	if st.nodes[k] then
		return st.nodes[k]
	end
	local ids = {}
	if not chunks then
		st.nodes[k] = ids
		return ids
	end
	-- Built aside and published whole: the loops pause at the frame budget, and another job running meanwhile must
	-- never find the cluster half decoded.
	local s = chunks
	local n, pos = num(s, 1, 2), 3
	local degree = {}
	local width, step = st.D.degreeWidth or 1, 6 + (st.D.degreeWidth or 1) + (st.D.baseDegreeWidth or 0)
	for i = 0, n - 1 do
		if i % 512 == 511 then
			slice()
		end
		ids[i + 1] = k * 4096 + i
		degree[i + 1] = num(s, pos + 6, width)
		pos = pos + step
	end
	local adj = {}
	for i = 1, n do
		if i % 512 == 0 then
			slice()
		end
		adj[i] = pos
		pos = pos + degree[i] * 7
	end
	if st.nodes[k] then
		return st.nodes[k]
	end
	for i = 1, n do
		st.nadj[ids[i]] = adj[i]
	end
	st.nodes[k], st.outDeg[k] = ids, degree
	st.graphSize[k] = (n * 288 + 128 + (st.D.packed and #s or 0)) / 1024
	graphKB = graphKB + st.graphSize[k]
	return ids
end

local function nodesOf(st, k)
	local nodes = st.nodes[k] or decodeGraph(st, k)
	if st.graphSize[k] then
		graphClock = graphClock + 1
		st.graphUsed[k] = graphClock
	end
	return nodes
end

local function metadata(st, id)
	if st.ncell[id] == nil then
		-- A packed map keeps its graph compressed until asked for: read the field, never the raw table (#897).
		local field, pos =
			unpackField(st.D, "graph", floor(id / 4096) + 1),
			3 + (id % 4096) * (6 + (st.D.degreeWidth or 1) + (st.D.baseDegreeWidth or 0))
		if not field then
			return nil
		end
		st.ncell[id], st.nlayer[id], st.ncomp[id] =
			num(field, pos, 3), B64[byte(field, pos + 3)], num(field, pos + 4, 2)
	end
	return st.ncell[id], st.nlayer[id], st.ncomp[id]
end

-- Most entrances in a visited cluster are never expanded. Decode their edges only when needed.
-- Search passes false for the plain-pruned prefix; road baking omits the flag to read the entire graph.
local noEdges = {}

local function edgesAt(st, id, roads)
	if roads == false and st.baseAdj[id] then
		return st.baseAdj[id]
	end
	local adj = st.nadj[id]
	if adj == nil then
		-- The records live in the node's own cluster, so decode it here: a caller holding an id from a neighbour's
		-- edges must not need to have visited that neighbour first.
		local k = floor(id / 4096)
		if not st.nodes[k] then
			nodesOf(st, k)
		end
		adj = st.nadj[id]
		if adj == nil then
			return noEdges
		end
	end
	if roads == false and st.D.baseDegreeWidth and st.baseDeg[id] == nil then
		local width = st.D.degreeWidth or 1
		local pos = 3 + (id % 4096) * (6 + width + st.D.baseDegreeWidth) + 6 + width
		st.baseDeg[id] = num(st.D.graph[floor(id / 4096) + 1], pos, st.D.baseDegreeWidth)
	end
	if type(adj) == "number" then
		local k, pos = floor(id / 4096), adj
		local s = st.D.graph[k + 1]
		local degree = st.outDeg[k]
		adj = {}
		local count = roads == false and st.baseDeg[id] or degree[id % 4096 + 1]
		for e = 1, count do
			local offset = B64[byte(s, pos)]
			local target = k + (floor(offset / 3) - 1) * st.ny + offset % 3 - 1
			adj[e * 3 - 2] = target * 4096 + num(s, pos + 1, 2)
			adj[e * 3 - 1] = num(s, pos + 3, 2)
			adj[e * 3] = num(s, pos + 5, 2)
			pos = pos + 7
		end
		if roads == false and st.baseDeg[id] and count < degree[id % 4096 + 1] then
			st.baseAdj[id] = adj
		else
			st.nadj[id] = adj
		end
		local capacity = 1
		while capacity < #adj do
			capacity = capacity * 2
		end
		local size = (64 + capacity * 16) / 1024
		st.graphSize[k], graphKB = st.graphSize[k] + size, graphKB + size
	end
	return adj
end

-- The links into every node of cluster k, from the outbound records of the cluster and its neighbours. The file
-- stores each edge once, from the node that leaves it, so a reverse search is handed the same edges the other way:
-- a link costs the same walked backwards, and all it wants is the node that reaches it. A node's inbound list is
-- the chart's outbound triples, so it reads exactly like adjacent.
local function buildInbound(st, k, roads)
	local ny = st.ny
	local kx, ky = floor(k / ny), k % ny
	local into = {}
	for dx = -1, 1 do
		for dy = -1, 1 do
			local nx, nyc = kx + dx, ky + dy
			local s = nx >= 0
				and nyc >= 0
				and nx < st.D.nx
				and nyc < ny
				and unpackField(st.D, "graph", nx * ny + nyc + 1)
			if s then
				local n, pos = num(s, 1, 2), 3
				local degrees, bases, left = {}, {}, 256
				for i = 0, n - 1 do
					degrees[i] = num(s, pos + 6, st.D.degreeWidth or 1)
					bases[i] = st.D.baseDegreeWidth and num(s, pos + 6 + (st.D.degreeWidth or 1), st.D.baseDegreeWidth)
						or degrees[i]
					pos = pos + 6 + (st.D.degreeWidth or 1) + (st.D.baseDegreeWidth or 0)
				end
				for i = 0, n - 1 do
					local source = (nx * ny + nyc) * 4096 + i
					local count = roads == false and bases[i] or degrees[i]
					for _ = 1, count do
						local offset = B64[byte(s, pos)]
						if floor(offset / 3) - 1 == -dx and offset % 3 - 1 == -dy then
							local target = k * 4096 + num(s, pos + 1, 2)
							local list = into[target]
							if list then
								list[#list + 1] = source
								list[#list + 1] = num(s, pos + 3, 2)
								list[#list + 1] = num(s, pos + 5, 2)
							else
								into[target] = { source, num(s, pos + 3, 2), num(s, pos + 5, 2) }
							end
						end
						pos = pos + 7
						left = left - 1
						if left == 0 then
							left = 256
							slice()
						end
					end
					pos = pos + (degrees[i] - count) * 7
				end
			end
		end
	end
	local bytes = 0
	for id, list in pairs(into) do
		if roads == false then
			st.baseIn[id] = list
		else
			st.nadjIn[id] = list
		end
		bytes = bytes + 64 + #list * 16
	end
	local size = bytes / 1024
	st.graphSize[k] = (st.graphSize[k] or 0) + size
	graphKB = graphKB + size
	if roads == false then
		st.baseBuilt[k] = true
	else
		st.inBuilt[k] = true
	end
end

-- The edges out of an entrance, then the edges into it: a reverse search walks the latter, never an edge backwards.
-- Format 1's graph is symmetric, so both are the same list.
local function adjacent(st, id, roads)
	local adj = edgesAt(st, id, roads)
	local base = st.baseDeg[id]
	if roads ~= false or not base or base * 3 == #adj then
		return adj
	end
	if not st.baseAdj[id] then
		local list = {}
		for i = 1, base * 3 do
			list[i] = adj[i]
		end
		st.baseAdj[id] = list
		local k = floor(id / 4096)
		local capacity = 1
		while capacity < #list do
			capacity = capacity * 2
		end
		local size = (64 + capacity * 16) / 1024
		st.graphSize[k], graphKB = st.graphSize[k] + size, graphKB + size
	end
	return st.baseAdj[id]
end

local function preceding(st, id, roads)
	if st.fmt < 2 then
		return adjacent(st, id, roads)
	end
	local k = floor(id / 4096)
	local built = roads == false and st.baseBuilt or st.inBuilt
	if not built[k] then
		-- counting the cluster as used keeps its records reclaimable once the lists are built
		nodesOf(st, k)
		buildInbound(st, k, roads)
	end
	local lists = roads == false and st.baseIn or st.nadjIn
	return lists[id] or noEdges
end

-- Road cells of cluster k (RoadCells.lua), decoded once: a set of local cell -> coverage, or false when it has none.
-- Only read while Follow roads is on.
local function decodeRoads(st, k)
	local list = ns.RoadCells and ns.RoadCells[st.map]
	local s = list and list[k + 1]
	if not s then
		return false
	end
	local set, lc, pos = {}, 0, 1
	while pos <= #s do
		local run = num(s, pos, 2)
		local coverage = B64[byte(s, pos + 2)] / 63
		pos = pos + 3
		if run > 0 then
			if coverage > 0 then
				for cell = lc, lc + run - 1 do
					set[cell] = coverage
				end
			end
			lc = lc + run
		end
	end
	return set
end

local function roads(st, k)
	local set = st.road[k]
	if set == nil then
		set = decodeRoads(st, k) or false
		st.road[k] = set
	end
	return set or nil
end

-- Painted road coverage of this node's base cell, zero without paint.
local function roadNode(st, k, node)
	local set = roads(st, k)
	if not set then
		return 0
	end
	local cell = cellOf(st, k, node)
	return cell ~= nil and set[cell] or 0
end

-- Length in cell widths, and how much of it crosses unpainted cells. Road coverage is attached to the
-- horizontal cell, so floors on the same cell share the same road classification.
local function roadDistance(st, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local length = sqrt(dx * dx + dy * dy)
	local x, y = floor(ax), floor(ay)
	local sx, sy = dx > 0 and 1 or -1, dy > 0 and 1 or -1
	local stepX, stepY = dx ~= 0 and 1 / abs(dx) or huge, dy ~= 0 and 1 / abs(dy) or huge
	local nextX = dx ~= 0 and (sx > 0 and x + 1 - ax or ax - x) * stepX or huge
	local nextY = dy ~= 0 and (sy > 0 and y + 1 - ay or ay - y) * stepY or huge
	local C = st.C
	local at, off = 0, 0
	while at < 1 do
		tick()
		local nextAt = min(nextX, nextY, 1)
		local set = x >= 0 and x < st.GX and y >= 0 and y < st.GY and roads(st, floor(x / C) * st.ny + floor(y / C))
		if not set or not set[(x % C) * C + y % C] then
			off = off + nextAt - at
		end
		if nextX == nextAt then
			x, nextX = x + sx, nextX + stepX
		end
		if nextY == nextAt then
			y, nextY = y + sy, nextY + stepY
		end
		at = nextAt
	end
	return length, length * off
end

-- Both the replaced span and the full walk keep their painted share. The full walk's limit is
-- additive across shortcuts, so shortening a painted span cannot dilute the final line's share.
local function roadClear(st, ax, ay, bx, by, length, off, routeFieldShare)
	if length <= 0 or (off >= length and routeFieldShare >= 1) then
		return true
	end
	local span, field = roadDistance(st, ax, ay, bx, by)
	return field <= span * (off / length) + 1e-9 and field <= off + (span - length) * routeFieldShare + 1e-9
end

-- RoadEdges.lua's edge ratios for cluster k: a default run is "=" and its length in two base64 symbols, any other
-- edge is four symbols (preference and real ratio for walking, then for water walking). A ratio q is
-- 1 + q / 63 * (OFFROAD - 1); a default edge is OFFROAD and 1 in both modes.
local function decodeRoadEdges(st, k)
	local list = ns.RoadEdges and ns.RoadEdges[st.map]
	local s = list and list[k + 1]
	local ratios, e = {}, 0
	if not s then
		return ratios
	end
	local pos = 1
	while pos <= #s do
		if byte(s, pos) == 61 then -- "="
			local n = num(s, pos + 1, 2)
			pos = pos + 3
			for _ = 1, n do
				e = e + 1
				ratios[e * 4 - 3], ratios[e * 4 - 2] = OFFROAD, 1
				ratios[e * 4 - 1], ratios[e * 4] = OFFROAD, 1
			end
		else
			local a, b, c, d = B64[byte(s, pos)], B64[byte(s, pos + 1)], B64[byte(s, pos + 2)], B64[byte(s, pos + 3)]
			pos = pos + 4
			e = e + 1
			ratios[e * 4 - 3] = 1 + a / 63 * (OFFROAD - 1)
			ratios[e * 4 - 2] = 1 + b / 63 * (OFFROAD - 1)
			ratios[e * 4 - 1] = 1 + c / 63 * (OFFROAD - 1)
			ratios[e * 4] = 1 + d / 63 * (OFFROAD - 1)
		end
	end
	return ratios
end

-- An entrance's edge ratios, aligned with adjacent(st, id): for edge e, the preference and real ratio with normal
-- swimming, then with water walking. Missing data is the default: OFFROAD and 1.
local function roadEdges(st, id)
	local k = floor(id / 4096)
	local data = st.roadEdges[k]
	if not data then
		data = { ratios = decodeRoadEdges(st, k), at = {}, byId = {} }
		local offset = 0
		for _, node in ipairs(nodesOf(st, k)) do
			data.at[node] = offset
			offset = offset + #adjacent(st, node) / 3
		end
		st.roadEdges[k] = data
	end
	local cached = data.byId[id]
	if cached then
		return cached
	end
	local adj = adjacent(st, id)
	local base = data.at[id] or 0
	local r = {}
	for e = 1, #adj / 3 do
		local j = (base + e) * 4
		r[e * 4 - 3] = data.ratios[j - 3] or OFFROAD
		r[e * 4 - 2] = data.ratios[j - 2] or 1
		r[e * 4 - 1] = data.ratios[j - 1] or OFFROAD
		r[e * 4] = data.ratios[j] or 1
	end
	data.byId[id] = r
	return r
end

-- An entrance's edge ratios aligned with preceding(st, id): the edges that reach it carry the ratio of their source's
-- outbound edge into it, which is the only one the bake stores. A reverse search must not read the outbound list's
-- ratios, whose length and order are its own.
local function roadEdgesIn(st, id)
	local k = floor(id / 4096)
	local data = st.roadIn[k]
	if not data then
		data = { byId = {} }
		st.roadIn[k] = data
	end
	local cached = data.byId[id]
	if cached then
		return cached
	end
	local into = preceding(st, id)
	local r = {}
	for e = 1, #into / 3 do
		local v = into[e * 3 - 2]
		local out = adjacent(st, v)
		local index
		for i = 1, #out / 3 do
			if out[i * 3 - 2] == id then
				index = i
				break
			end
		end
		local ratios = index and roadEdges(st, v)
		local j = index and index * 4 or 0
		r[e * 4 - 3] = ratios and ratios[j - 3] or OFFROAD
		r[e * 4 - 2] = ratios and ratios[j - 2] or 1
		r[e * 4 - 1] = ratios and ratios[j - 1] or OFFROAD
		r[e * 4] = ratios and ratios[j] or 1
	end
	data.byId[id] = r
	return r
end

-- An entrance's node in its cluster.
local function entrance(st, id)
	local k = floor(id / 4096)
	if not st.nodes[k] then
		nodesOf(st, k)
	end
	local cell, layer = metadata(st, id)
	grid(st, k)
	return surface(st, k, cell, layer)
end

-- Cluster k and local cell of a world point, or nil outside the data.
local function locate(st, x, y)
	local gx, gy = floor((x - st.x0) / st.cs), floor((y - st.y0) / st.cs)
	if gx < 0 or gy < 0 or gx >= st.GX or gy >= st.GY then
		return nil
	end
	local C = st.C
	return floor(gx / C) * st.ny + floor(gy / C), (gx % C) * C + gy % C
end

-- The walkable node of local cell lc a point at height h stands on (the base surface when h is unknown), and the
-- height gap to it.
local function standing(st, k, lc, h)
	local val = grid(st, k)
	if not val then
		return nil
	end
	if h == nil then
		return val[lc + 1] ~= 0 and lc or nil, 0
	end
	return surface(st, k, lc, -1, h)
end

-- How a point at height z stands against its cell's ground: "up" above it, "down" below it, nil on it. The point
-- snaps to the nearest surface of its cell as a walk. A cell with no floor has one place to stand and says nothing.
-- Otherwise the ground is the cell's stored ground layer, or its base when the cell is left out; a cell with floors
-- over no terrain stores the no-ground marker and says nothing. An undecoded cell says nothing too: the map's own
-- asynchronous decoding fills it, so a caller on hover never forces a grid decode. The exceptions themselves are
-- decoded here, on first use, without slicing: ground is asked for from a path job's callback.
local function terrain(st, k)
	local exceptions = st.terrain[k]
	if exceptions == nil then
		local s = Quiet(unpackField, st.D, "terrain", k + 1)
		exceptions = s and Quiet(decodeTerrain, s) or {}
		st.terrain[k] = exceptions
	end
	return exceptions
end
---@param map number
---@param x number
---@param y number
---@param z number?
---@return "up"|"down"|nil
local function ground(map, x, y, z)
	if type(z) ~= "number" then
		return nil
	end
	local st = states[map] or State(map)
	if not st then
		return nil
	end
	local k, lc = locate(st, x, y)
	local val = k and st.val[k]
	if not val then
		return nil
	end
	local at = st.at[k]
	if not at or not at[-(lc + 1)] then
		return nil
	end
	local layer = terrain(st, k)[lc + 1]
	if layer == false then
		return nil
	end
	local node = surface(st, k, lc, -1, z)
	local groundNode = surface(st, k, lc, layer or 0)
	if not node or not groundNode then
		return nil
	end
	local gap = st.z[k][node + 1] - st.z[k][groundNode + 1]
	if gap > 0 then
		return "up"
	elseif gap < 0 then
		return "down"
	end
	return nil
end

-- The node an endpoint stands on: within SNAP cells, the surface with the least distance plus twice the height gap,
-- preferring those within ZTOL of its height; a point off every surface (in a lift shaft, mid-jump, deep under water)
-- takes the least of the same cost among all surfaces.
local function snap(st, k, lc, x, y, h)
	local C, cs = st.C, st.cs
	local lx, ly = floor(lc / C), lc % C
	local cx, cy = st.x0 + (floor(k / st.ny) * C + lx + 0.5) * cs, st.y0 + ((k % st.ny) * C + ly + 0.5) * cs
	local best, bestCost, any, anyCost
	for r = 0, SNAP do
		if best and (r - 1) * cs > bestCost then
			break
		end
		for dx = -r, r do
			for dy = -r, r do
				local nx, ny = lx + dx, ly + dy
				if (dx == r or dx == -r or dy == r or dy == -r) and nx >= 0 and ny >= 0 and nx < C and ny < C then
					local n, gap = standing(st, k, nx * C + ny, h)
					if n then
						local d = r == 0 and 0 or sqrt((cx + dx * cs - x) ^ 2 + (cy + dy * cs - y) ^ 2)
						local cost = d + 2 * gap
						if gap <= ZTOL and (not bestCost or cost < bestCost) then
							best, bestCost = n, cost
						end
						if not anyCost or cost < anyCost then
							any, anyCost = n, cost
						end
					end
				end
			end
		end
	end
	return best or any
end

-- Global grid helpers for smoothing across clusters.
local function value(st, gx, gy)
	if gx < 0 or gy < 0 or gx >= st.GX or gy >= st.GY then
		return 0
	end
	local C = st.C
	local val = grid(st, floor(gx / C) * st.ny + floor(gy / C))
	return val and val[(gx % C) * C + gy % C + 1] or 0
end

-- Is the base surface's step from (gx, gy) to (gx + dx, gy + dy) open, for an orthogonal unit step?
local function stepOpen(st, gx, gy, dx, dy, water)
	local ax, ay = gx, gy
	if dx < 0 or dy < 0 then
		ax, ay = gx + dx, gy + dy
	end
	local C = st.C
	local a = value(st, ax, ay)
	-- Read before b's cluster decodes: that decode can yield, and a cluster nothing holds may be evicted meanwhile.
	local moves = st.moves[floor(ax / C) * st.ny + floor(ay / C)]
	local b = value(st, ax + (dx ~= 0 and 1 or 0), ay + (dy ~= 0 and 1 or 0))
	if a == 0 or b == 0 or (not water and (a == 2 or b == 2)) then
		return false
	end
	local f = floor(moves[(ax % C) * C + ay % C + 1] / 16)
	if dx ~= 0 then
		return f % 2 == 0
	end
	return f % 4 < 2
end

-- Is the bake's explicit diagonal step from (gx, gy) by (sx, sy) open in the grid? The bit sits on the lower-x
-- cell: `4` doubles as a ground cell's steep flag in a `steep` map, so only water keeps it there.
local function diagonalBit(st, gx, gy, sx, sy, water)
	local ax, ay, up = gx, gy, sy > 0
	if sx < 0 then
		ax, ay, up = gx + sx, gy + sy, sy < 0
	end
	local a = value(st, ax, ay)
	if a == 0 or (not water and a == 2) then
		return false
	end
	local C = st.C
	local f = floor(st.moves[floor(ax / C) * st.ny + floor(ay / C)][(ax % C) * C + ay % C + 1] / 16)
	if up then
		return f % 8 >= 4
	end
	return f >= 8
end

-- The base surface's node in its own cluster, with the cluster's values and heights. A caller keeps these tables,
-- never st's slots: decoding another cluster can yield, and a paused search resumes after Idle evicted this one.
-- Every cluster a step reads was decoded by the step's open check, so its grid is never false.
local function baseAt(st, gx, gy)
	local C = st.C
	local k = floor(gx / C) * st.ny + floor(gy / C)
	local val = grid(st, k) --[[@as integer[] ]]
	return (gx % C) * C + gy % C, val, st.z[k]
end

-- An L-shaped detour leg: the step is open, and a steep leg feeds a detour only when its two stored heights match,
-- the rule decodeGrid applies to a detour inside one cluster. The base grid's own bits let a steep step be walked
-- downhill, and no detour may turn that into a climb.
local function detourStep(st, gx, gy, dx, dy, water)
	if not stepOpen(st, gx, gy, dx, dy, water) then
		return false
	end
	local steep = st.steep
	if not steep then
		return true
	end
	local an, av, az = baseAt(st, gx, gy)
	local bn, bv, bz = baseAt(st, gx + dx, gy + dy)
	if av[an + 1] ~= 3 and bv[bn + 1] ~= 3 then
		-- A detour's leg is an ordinary step too, judged by the map's own rule (climbStep in format 2, #897).
		return steep(av, az, an, bv, bz, bn, st.cs)
	end
	return az[an + 1] == bz[bn + 1]
end

-- Is the base surface's diagonal step from (gx, gy) by (dx, dy) walkable in that direction? Either L-shaped detour,
-- both legs walked by an ordinary step's rule, or the bake's explicit diagonal, which the decoder allows downhill
-- only by the stored heights. Checking only the two ends would let a detour climb through its corner cell.
local function diagonalStep(st, gx, gy, dx, dy, water)
	local tx, ty = gx + dx, gy + dy
	local b = value(st, tx, ty)
	if b == 0 or (not water and b == 2) then
		return false
	end
	if
		(detourStep(st, gx, gy, dx, 0, water) and detourStep(st, gx + dx, gy, 0, dy, water))
		or (detourStep(st, gx, gy, 0, dy, water) and detourStep(st, gx, gy + dy, dx, 0, water))
	then
		return true
	end
	if not diagonalBit(st, gx, gy, dx, dy, water) then
		return false
	end
	local steep = st.steep
	if not steep then
		return true
	end
	local an, av, az = baseAt(st, gx, gy)
	local bn, bv, bz = baseAt(st, tx, ty)
	return steep(av, az, an, bv, bz, bn, st.cs * math.sqrt(2))
end

-- Every node one step (dx, dy) on from node of cluster k at global cell (gx, gy) lands on, as search() expands it:
-- the base surface's own step, then each of the node's floor links with that offset. They go into outK and outN from
-- index 1, and the count is returned. One step can land on several surfaces (a stair beside the drop off its side),
-- and a caller following a walk keeps them all: the first alone can be another floor than the walk's (#1015). With
-- outC, each landing's cost goes there too: 0 for a walked step, a drop's whole yards otherwise.
local function neighbours(st, k, node, gx, gy, dx, dy, water, outK, outN, outC)
	local tx, ty = gx + dx, gy + dy
	if tx < 0 or ty < 0 or tx >= st.GX or ty >= st.GY then
		return 0
	end
	local count = 0
	local C = st.C
	local tk, tlc = floor(tx / C) * st.ny + floor(ty / C), (tx % C) * C + ty % C
	-- A zero-offset move can only be an explicit drop between layers, never an ordinary base step.
	if node < C * C and (dx ~= 0 or dy ~= 0) then
		local open
		local val = tk == k and grid(st, k)
		-- Most string-pulling steps stay on one base grid. Its decoded moves already check the
		-- same detours; only a dry diagonal beside water needs the stricter surface checks below.
		if
			val
			and (
				water
				or (
					val[node + 1] ~= 2
					and val[tlc + 1] ~= 2
					and (dx == 0 or dy == 0 or (val[node + dx * C + 1] ~= 2 and val[node + dy + 1] ~= 2))
				)
			)
		then
			local m = st.moves[k]
			if dy == 0 then
				open = m[(dx > 0 and node or tlc) + 1] % 2 == 1
			elseif dx == 0 then
				open = m[(dy > 0 and node or tlc) + 1] % 4 >= 2
			elseif dx == dy then
				open = m[(dx > 0 and node or tlc) + 1] % 8 >= 4
			else
				open = m[(dx > 0 and node or tlc) + 1] % 16 >= 8
			end
		elseif dx == 0 or dy == 0 then
			open = stepOpen(st, gx, gy, dx, dy, water)
		else
			open = diagonalStep(st, gx, gy, dx, dy, water)
		end
		if open then
			-- The step's checks may have decoded, yielded and seen k evicted: keep k's tables, then tk's, last.
			local vk = grid(st, k) --[[@as integer[] ]]
			local zk = st.z[k]
			local vt = grid(st, tk) --[[@as integer[] ]]
			local steep = st.steep
			local distance = math.sqrt(dx * dx + dy * dy) * st.cs
			if not steep or steep(vk, zk, node, vt, st.z[tk], tlc, distance) then
				count = 1
				outK[1], outN[1] = tk, tlc
				if outC then
					outC[1] = 0
				end
			end
		end
	end
	local vk = grid(st, k) --[[@as integer[] ]]
	local zk, l = st.z[k], st.links[k][node + 1]
	if not l then
		return count
	end
	local here, h = vk[node + 1], zk[node + 1]
	local steep = st.steep
	for e = 1, #l do
		if st.fmt >= 2 then
			-- a format 2 link carries the cell offset it steps to, so a drop of more than a cell matches as well
			local entry = l[e]
			if entry % 16 - 8 == dx and floor(entry / 16) % 16 - 8 == dy then
				local vt = grid(st, tk) --[[@as integer[] ]]
				local v = surface(st, tk, tlc, floor(entry / 256) % 64 - 1, h)
				if v and (water or (here ~= 2 and vt[v + 1] ~= 2)) then
					local distance = math.sqrt((entry % 16 - 8) ^ 2 + (floor(entry / 16) % 16 - 8) ^ 2) * st.cs
					if not steep or entry >= FREE or steep(vk, zk, node, vt, st.z[tk], v, distance) then
						count = count + 1
						outK[count], outN[count] = tk, v
						if outC then
							outC[count] = floor(entry / 16384) % 8192
						end
					end
				end
			end
		else
			local d = DIRECTION[(dx + 1) * 3 + dy + 1]
			if l[e] % 8 == d then
				local vt = grid(st, tk) --[[@as integer[] ]]
				local v = surface(st, tk, tlc, floor(l[e] / 8) - 1, h)
				if v and (water or (here ~= 2 and vt[v + 1] ~= 2)) then
					local distance = math.sqrt(DX[d] ^ 2 + DY[d] ^ 2) * st.cs
					if not steep or steep(vk, zk, node, vt, st.z[tk], v, distance) then
						count = count + 1
						outK[count], outN[count] = tk, v
						if outC then
							outC[count] = 0
						end
					end
				end
			end
		end
	end
	return count
end

-- Scratch for following every surface a walk can be on: the current set, the next one, and a step's landings.
-- Kept per path, as a sliced job yields inside sight and toward and another job's path may run in between.
local frontiers = setmetatable({}, { __mode = "k" })
local function frontier(P)
	local f = frontiers[P]
	if not f then
		f = { {}, {}, {}, {}, {}, {}, {}, {} }
		frontiers[P] = f
	end
	return f
end

-- Add node n of cluster k at spent s to the first count entries of a set, keeping the least spent; returns the count.
local function admit(setK, setN, setS, count, k, n, s)
	for i = 1, count do
		if setN[i] == n and setK[i] == k then
			if s < setS[i] then
				setS[i] = s
			end
			return count
		end
	end
	count = count + 1
	setK[count], setN[count], setS[count] = k, n, s
	return count
end

-- A path entry list built by Path.lua's refinement and drawn here. factor is a hazard profile's cost at an entry,
-- kept per profile by Path.lua so the drawn line weighs the same cells the search chose between; nil without one.
---@class SPFPathPoints
---@field x number[] -- global cell x of each entry
---@field y number[] -- global cell y of each entry
---@field z number[] -- surface height captured during refinement
---@field w number[] -- water entries up to each entry
---@field t number[] -- walking time up to each entry, in running yards
---@field k number[] -- cluster of each entry
---@field n number[] -- node in that cluster
---@field r number[]? -- off-road entries up to each entry, with Follow roads
---@field distance number[]? -- path length in cell widths, with Follow roads
---@field field number[]? -- path length in unpainted cells, with Follow roads
---@field fieldShare number? -- share of the whole route in unpainted cells
---@field roadFactor? number -- an off-road yard's cost while choosing a walk
---@field swim number? -- a water yard's cost in running yards, as the search charged it
---@field factor? fun(k: number, node: number): number -- a hazard profile's factor at an entry

-- A drawn step's time: its length on land at run speed, or at the map's swim in water, charged for the cell it enters
-- as the walk itself is charged. Past the time of the walk it replaces, nil: string-pulling and the end chord turn a
-- swim the route walked around away by this one rule (#742).
---@param swim number
---@param spent number
---@param yards number
---@param water boolean
---@param budget number?
---@return number|nil
local function pace(swim, spent, yards, water, budget, ratio)
	local time = spent + (water and yards * swim or yards) * (ratio or 1)
	return (not budget or time <= budget) and time or nil
end

-- Line of sight between two path entries, walking every cell the segment between their cell centres crosses and
-- following the surface from node to node, so it cannot jump between floors. With a limit, no crossed cell may be
-- charged more than the walk the segment replaces; with a budget, neither may the segment's own time.
---@param P SPFPathPoints
---@param a number
---@param b number
---@param water boolean
---@param road boolean?
---@param limit number?
---@param budget number?
---@return boolean
local function sight(st, P, a, b, water, road, limit, budget, roadFactor)
	local factor = limit and P.factor
	local swim = P.swim or st.swim
	local ax, ay, bx, by = P.x[a], P.y[a], P.x[b], P.y[b]
	local dx, dy = bx - ax, by - ay
	local sx, sy = dx > 0 and 1 or -1, dy > 0 and 1 or -1
	local nx, ny = dx * sx, dy * sy
	-- The segment's own length in yards, the fraction of it one cell boundary crosses, and how far along it the last
	-- crossing stood.
	local span = sqrt(dx * dx + dy * dy) * st.cs
	local invX, invY = nx > 0 and 1 / nx or 0, ny > 0 and 1 / ny or 0
	local at = 0.0
	local x, y, ix, iy = ax, ay, 0, 0
	local f = frontier(P)
	local fk, fn, fs, gk, gn, gs, bk, bn = f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8]
	fk[1], fn[1], fs[1] = P.k[a], P.n[a], 0.0
	local count = 1
	while ix < nx or iy < ny do
		tick()
		-- Compare the next x and y boundary crossings: (0.5 + ix) / nx against (0.5 + iy) / ny.
		local d = (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		local mx, my = 0, 0
		local next2
		if d == 0 then -- through a corner
			mx, my, next2 = sx, sy, (0.5 + ix) * invX
		elseif d < 0 then
			mx, next2 = sx, (0.5 + ix) * invX
		else
			my, next2 = sy, (0.5 + iy) * invY
		end
		local reached = 0
		for i = 1, count do
			for j = 1, neighbours(st, fk[i], fn[i], x, y, mx, my, water, bk, bn) do
				local nk, nn = bk[j], bn[j]
				if not (road and roadNode(st, nk, nn) == 0) and not (factor and factor(nk, nn) > limit) then
					local spent = fs[i]
					if budget then
						-- A pulled segment that leaves the road is charged the off-road preference too: a straight cut
						-- across a field must not beat the road bend the walk took just because its own time is shorter
						-- (#891).
						local ratio = roadFactor and (1 + (roadFactor - 1) * (1 - roadNode(st, nk, nn))) or 1
						spent = pace(swim, spent, (next2 - at) * span, grid(st, nk)[nn + 1] == 2, budget, ratio)
					end
					if spent then
						reached = admit(gk, gn, gs, reached, nk, nn, spent)
					end
				end
			end
		end
		if reached == 0 then
			return false
		end
		fk, fn, fs, gk, gn, gs, count = gk, gn, gs, fk, fn, fs, reached
		at = next2
		x, y = x + mx, y + my
		ix, iy = ix + mx * sx, iy + my * sy
	end
	for i = 1, count do
		if fk[i] == P.k[b] and fn[i] == P.n[b] then
			if not budget then
				return true
			end
			-- the rest of the segment, inside the far entry's own cell
			local k, node = fk[i], fn[i]
			local ratio = roadFactor and (1 + (roadFactor - 1) * (1 - roadNode(st, k, node))) or 1
			return pace(swim, fs[i], (1 - at) * span, grid(st, k)[node + 1] == 2, budget, ratio) ~= nil
		end
	end
	return false
end

-- No surface of any height on global cell (gx, gy): no base surface and no floor. Off the map counts as none.
local function bare(st, gx, gy)
	if value(st, gx, gy) ~= 0 then
		return false
	end
	if gx < 0 or gy < 0 or gx >= st.GX or gy >= st.GY then
		return true
	end
	local C = st.C
	local k = floor(gx / C) * st.ny + floor(gy / C)
	local at = st.at[k]
	return not at or at[-((gx % C) * C + gy % C + 1)] == nil
end

-- A drawn line's end segments run off cell centres: from an endpoint itself, or to one. Walk the cells such a
-- segment really crosses, from node of cluster k at the fractional global cell position (fx, fy) to (tx, ty),
-- following the surface as sight does and, with a limit, refusing a cell a hazard profile charges more than the walk
-- the segment replaces. With a budget, its own time is charged the way sight charges a pulled segment and the segment
-- is refused once it would take longer than the walk it replaces. Every surface a step lands on is followed, as
-- search() would. Returns the cluster and node it reaches in the end's cell: (wk, wn) when that one is reached, else
-- the one reached soonest. When every step is closed: nil and whether every cell from the closed one to the end has no
-- surface at all (the line only runs on into a point the grid has no surface for). The third result measures the
-- complete connector with the same destination-surface intervals, including the terminal tail; real suppresses road
-- preference.
---@param P SPFPathPoints
---@param limit number?
---@param budget number?
---@param real boolean? -- measure real travel time without road preference
---@param wk number? -- the cluster and node wanted in the end's cell
---@param wn number?
---@return number|nil, number|boolean, number? -- reached surface or bare status, and complete connector time
local function toward(st, P, k, node, fx, fy, tx, ty, water, limit, budget, real, wk, wn)
	local factor = limit and P.factor
	local roadFactor = not real and budget and P.roadFactor
	local swim = P.swim or st.swim
	local x, y, ex, ey = floor(fx), floor(fy), floor(tx), floor(ty)
	local dx, dy = tx - fx, ty - fy
	local sx, sy = dx > 0 and 1 or -1, dy > 0 and 1 or -1
	-- Distance along the segment, in segment lengths, to the next x and y cell boundary and between boundaries.
	local stepX, stepY = dx ~= 0 and 1 / abs(dx) or huge, dy ~= 0 and 1 / abs(dy) or huge
	local nextX = (sx > 0 and x + 1 - fx or fx - x) * stepX
	local nextY = (sy > 0 and y + 1 - fy or fy - y) * stepY
	-- The whole segment's length in yards, and how far along it the walked boundary crossings have taken us.
	local span, at = sqrt(dx * dx + dy * dy) * st.cs, 0.0
	local f = frontier(P)
	local fk, fn, fs, gk, gn, gs, bk, bn = f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8]
	fk[1], fn[1], fs[1] = k, node, 0.0
	local count = 1
	-- Once every surface's step is closed, the time of the line running on over cells with none.
	local closed
	for _ = 1, 2 * (abs(ex - x) + abs(ey - y)) + 2 do
		if x == ex and y == ey then
			break
		end
		tick()
		local mx, my = 0, 0
		local reached = nextX < nextY and nextX or nextY -- equal through a corner
		if abs(nextX - nextY) < 1e-9 then -- through a corner
			mx, my, nextX, nextY = sx, sy, nextX + stepX, nextY + stepY
		elseif nextX < nextY then
			mx, nextX = sx, nextX + stepX
		else
			my, nextY = sy, nextY + stepY
		end
		-- Rounding can only overshoot along an axis already level with the end; never step past it.
		if x == ex then
			mx = 0
		end
		if y == ey then
			my = 0
		end
		if mx ~= 0 or my ~= 0 then
			if reached > 1 then
				reached = 1
			end
			local landed, kept = false, 0
			if not closed then
				for i = 1, count do
					for j = 1, neighbours(st, fk[i], fn[i], x, y, mx, my, water, bk, bn) do
						landed = true
						local nk, nn = bk[j], bn[j]
						if not factor or factor(nk, nn) <= limit then
							local ratio = roadFactor and (1 + (roadFactor - 1) * (1 - roadNode(st, nk, nn))) or 1
							local wet = grid(st, nk)[nn + 1] == 2
							local paced = pace(swim, fs[i], (reached - at) * span, wet, budget, ratio)
							if paced then
								kept = admit(gk, gn, gs, kept, nk, nn, paced)
							end
						end
					end
				end
				if landed and kept == 0 then
					return nil, false
				end
				if landed then
					fk, fn, fs, gk, gn, gs, count = gk, gn, gs, fk, fn, fs, kept
				else
					closed = fs[1]
					for i = 2, count do
						closed = min(closed, fs[i])
					end
				end
			end
			x, y = x + mx, y + my
			if not landed then
				local paced = pace(swim, closed, (reached - at) * span, value(st, x, y) == 2, budget, roadFactor or 1)
				if not paced then
					return nil, false
				end
				closed = paced
				if not bare(st, x, y) then
					return nil, false
				end
			end
			at = reached
		end
	end
	if x ~= ex or y ~= ey then
		return nil, false
	end
	if closed then
		if at < 1 then -- the rest of the segment, inside the end's own cell
			closed = pace(swim, closed, (1 - at) * span, false, budget, roadFactor or 1)
			if not closed then
				return nil, false
			end
		end
		return nil, true, closed
	end
	-- The surface wanted when the walk reaches it, else the one reached soonest.
	local best, bestTime
	for i = 1, count do
		local time = fs[i]
		if at < 1 then -- the rest of the segment, inside the end's own cell
			local ratio = roadFactor and (1 + (roadFactor - 1) * (1 - roadNode(st, fk[i], fn[i]))) or 1
			time = pace(swim, time, (1 - at) * span, grid(st, fk[i])[fn[i] + 1] == 2, budget, ratio)
		end
		if time then
			if fk[i] == wk and fn[i] == wn then
				return fk[i], fn[i], time
			end
			if not bestTime or time < bestTime then
				best, bestTime = i, time
			end
		end
	end
	if not best then
		return nil, false
	end
	return fk[best], fn[best], bestTime
end

-- The largest factor a hazard profile charges over path entries first..last, keeping the highest limit already seen:
-- a pulled segment may cross no cell charged more than the walk it replaces. Maxima only ever grow as an anchor's
-- candidates advance, so a running one replaces a prefix sum, which cannot answer a range's maximum.
---@param P SPFPathPoints
---@param factor fun(k: number, node: number): number
---@param first number
---@param last number
---@param limit number
---@return number
local function peak(P, factor, first, last, limit)
	for e = first, last do
		local f = factor(P.k[e], P.n[e])
		if f > limit then
			limit = f
		end
	end
	return limit
end

-- Collapse a node path to its turns, then pull the string: the shortest line through the turns in which each pulled
-- segment is in sight (#1024). Joining the furthest point in sight from each anchor is not the shortest line.
-- Water may only be crossed where the path itself swam, and neither a hazard profile's cost nor a pulled segment's own
-- time may be higher along the pulled segment than along the entries it replaces, so a walk drawn round a town stays
-- round it and a walk round a bay is not drawn across the water (#742).
---@param P SPFPathPoints
---@param ends table? how the line is drawn from the start and to the goal (Path.lua): sx, sy and gx, gy, the points in
--- cells; start(j) and goal(j), whether the segment between that point and entry j is clear; chord(), the one segment
--- between the two. Without start (or goal) the line is drawn through the first (or last) entry's centre.
---@return number[] keep -- the entries kept
---@return boolean startVia -- the line runs from the start through its end entry's centre, not straight from the point
---@return boolean goalVia -- the same at the goal
local function smooth(st, P, ends)
	local PX, PY, PW, PR, PT = P.x, P.y, P.w, P.r, P.t
	local factor = P.factor
	local n = #PX
	local keep = { 1 }
	for i = 2, n - 1 do
		if
			PX[i + 1] - PX[i] ~= PX[i] - PX[i - 1]
			or PY[i + 1] - PY[i] ~= PY[i] - PY[i - 1]
			or PW[i + 1] ~= PW[i]
			or (PR and PR[i + 1] - PR[i] ~= PR[i] - PR[i - 1])
		then
			keep[#keep + 1] = i
		end
	end
	if n > 1 then
		keep[#keep + 1] = n
	end
	-- The line runs through nodes: the start and goal points when it is drawn from them (Path.lua), and the kept
	-- entries between. best[b]: the shortest line to node b, in cells; from[b]: the node before it. Neighbouring nodes
	-- are joined as the walk goes, so a start or goal segment that is not clear detours through its end entry's centre.
	local m = #keep
	local E = ends or {}
	local start, goal = E.start, E.goal
	local X, Y, at = {}, {}, {}
	if start then
		X[1], Y[1] = E.sx, E.sy
	end
	for i = 1, m do
		local j = #X + 1
		X[j], Y[j], at[j] = PX[keep[i]] + 0.5, PY[keep[i]] + 0.5, keep[i]
	end
	local N = #X
	if goal then
		N = N + 1
		X[N], Y[N] = E.gx, E.gy
	end
	local function clear(a, b)
		slice() -- a long walk measures many segments; each is one sight, and a sight may already slice to decode
		local p, q = at[a] or 1, at[b] or n
		-- A segment from or to an end point is the one drawn from the point itself, so the end's own check is the whole
		-- check; between entries the line runs centre to centre.
		if not at[a] and not at[b] then
			return E.chord()
		elseif not at[a] then
			return start(q)
		elseif not at[b] then
			return goal(p)
		end
		if
			P.distance
			and P.field
			and not roadClear(
				st,
				X[a],
				Y[a],
				X[b],
				Y[b],
				P.distance[q] - P.distance[p],
				P.field[q] - P.field[p],
				P.fieldShare or 0
			)
		then
			return false
		end
		return sight(
			st,
			P,
			p,
			q,
			PW[q] - PW[p] > 0,
			PR and PR[q] - PR[p] == 0,
			factor and peak(P, factor, p, q, 1),
			PT[q] - PT[p],
			P.roadFactor
		)
	end
	-- Nodes are reached in order, so best[b] already holds the shortest line from every earlier node: a segment that
	-- cannot shorten it needs no check, and an equal line from an earlier node (fewer points) is never replaced. From
	-- each entry the line reaches forward until the first entry it checks out of sight, as the walk pulls the string;
	-- the start and goal points are each one segment checked on its own, so every one they clear counts.
	local best, from = { 0 }, { 0 }
	for b = 2, N do
		best[b] = huge
	end
	for a = 1, N - 1 do
		for b = a + 1, N do
			local d = best[a] + sqrt((X[a] - X[b]) ^ 2 + (Y[a] - Y[b]) ^ 2)
			if d < best[b] - 1e-9 then
				if b == a + 1 or clear(a, b) then
					best[b], from[b] = d, a
				elseif at[a] and at[b] then
					break
				end
			end
		end
	end
	-- The first and last entries stand for the start and goal (Path.lua draws them from the points), so they are
	-- always kept; any other entry kept is a corner of the line.
	local corners, b = {}, N
	local startVia, goalVia = not start, not goal
	while b > 0 do
		local j = at[b]
		if j and j ~= 1 and j ~= n then
			corners[#corners + 1] = j
		elseif j and b > 1 and b < N then
			startVia, goalVia = startVia or j == 1, goalVia or j == n
		end
		b = from[b]
	end
	local out = { 1 }
	for i = #corners, 1, -1 do
		out[#out + 1] = corners[i]
	end
	if n > 1 then
		out[#out + 1] = n
	end
	return out, startVia, goalVia
end

-- The clusters around the player that Floor.lua follows the player's floor on, by map. Idle keeps them decoded; the
-- memory ceilings may still evict one, and Floor.lua then asks for it again.
local pinned = {}

---@param map number?
---@param clusters table<number, true>?
---@return boolean released whether a cluster pinned before is pinned no longer
local function Pin(map, clusters)
	if not map and next(pinned) == nil then
		return false -- Floor.lua forgets on every tick it follows nothing (a taxi, a lift): nothing pinned, no table to make
	end
	local released = false
	for m, keep in pairs(pinned) do
		for k in pairs(keep) do
			if m ~= map or not (clusters and clusters[k]) then
				released = true
			end
		end
	end
	pinned = {}
	if map and clusters then
		pinned[map] = clusters
	end
	return released
end

-- Whether cluster k is decoded, or holds no walking data, so reading it never decodes.
local function Ready(st, k)
	if st.val[k] ~= nil then
		return true
	end
	local D = st.D
	return D.grid[k + 1] == nil and not (D.packed and D.packed.grid[k + 1])
end

-- With no search queued, drop decoded grids and local trees; exact endpoint costs stay.
local function Idle()
	holds = {}
	for map, st in pairs(states) do
		for _, entry in ipairs(st.endTrees or {}) do
			entry.tree = nil
		end
		st.endTrees = nil
		local keep = pinned[map]
		for k in pairs(st.used) do
			if not (keep and keep[k]) then
				evict(st, k)
			end
		end
		if st.D.packed then
			st.D.grid, st.D.height, st.D.floor = {}, {}, {}
		end
	end
	trimGraphs()
end

local function Reset()
	holds = {}
	for map, st in pairs(states) do
		-- The costs stay; the local search trees behind them are only for drawing a walk, and go with the grids.
		for _, entry in pairs(st.ends) do
			entry.tree = nil
		end
		keptEnds[map] = { ends = st.ends, count = st.endCount }
		if st.D.packed then
			st.D.graph, st.D.grid, st.D.height, st.D.floor = {}, {}, {}, {}
		end
	end
	states = {}
	decodedKB, decodedCount, graphKB = 0, 0, 0
end

-- The stored heights of a cluster's entrances, decoded without the grid's moves and links: a few graph nodes
-- stand in a cluster the abstract search never walks, so decoding its whole grid for them is far too much work.
-- Returns the walkable values and heights, plus each floor node's height and value, then forgets the arrays once
-- the cluster's entrances have their two facts (#897).
---@param st table
---@param k number
local function cacheEntranceHeights(st, k)
	local gridData, heightData = unpackField(st.D, "grid", k + 1), unpackField(st.D, "height", k + 1)
	if not gridData or not heightData then
		for _, id in ipairs(nodesOf(st, k)) do
			st.nodeZ[id], st.nodeSteep[id] = false, false
		end
		return
	end
	local C = st.C
	local val, n, valueCode = {}, 0, 0
	for i = 1, #gridData do
		local sym = B64[byte(gridData, i)]
		if sym < 48 then
			valueCode = floor(sym / 16)
			n = n + 1
			val[n] = valueCode
		else
			for _ = 48, sym do
				n = n + 1
				val[n] = valueCode
			end
		end
	end
	local z = {}
	decodeHeights(st, val, z, heightData)
	local first, floorZ, floorVal = {}, {}, {}
	local floors = unpackField(st.D, "floor", k + 1)
	if floors then
		local s, node, pos = floors, C * C, 4
		if st.fmt >= 3 then
			local lc = 0
			for _ = 1, num(s, 1, 3) do
				local sym = B64[byte(s, pos)]
				pos = pos + 1
				if sym < 63 then
					lc = lc + sym
				else
					lc, pos = lc + 63 + num(s, pos, 3), pos + 3
				end
				local mask = num(s, pos + 3, 2)
				first[lc] = first[lc] or node
				floorVal[node], floorZ[node] = B64[byte(s, pos)], num(s, pos + 1, 2) - 2048
				pos, node = pos + 5 + landingCount(mask), node + 1
			end
		else
			for _ = 1, num(s, 1, 3) do
				local lc, count = num(s, pos, 3), B64[byte(s, pos + 3)]
				pos = pos + 4
				first[lc] = first[lc] or node
				for _ = 1, count do
					floorVal[node], floorZ[node] = B64[byte(s, pos)], num(s, pos + 1, 2) - 2048
					pos, node = pos + 5, node + 1
				end
			end
		end
	end
	for _, id in ipairs(nodesOf(st, k)) do
		local cell, layer = metadata(st, id)
		local height, steep
		if layer == 0 then
			height, steep = z[cell + 1], val[cell + 1] == 3
		else
			local node = first[cell] and first[cell] + layer - 1
			height, steep = node and floorZ[node], node and floorVal[node] == 3
		end
		st.nodeZ[id], st.nodeSteep[id] = height or false, steep or false
	end
end

-- An entrance's stored height and whether it stands on steep ground. Kept per entrance, not per decoded grid:
-- the abstract search visits far more clusters than the grid cache holds, and re-decoding one cluster's grid for
-- every edge out of it made the search crawl. A released cluster keeps these two small facts (#897).
---@param st table
---@param id number
---@return number|false? height, boolean?
local function entranceHeight(st, id)
	local height = st.nodeZ[id]
	if height ~= nil then
		return height or nil, st.nodeSteep[id]
	end
	cacheEntranceHeights(st, floor(id / 4096))
	height = st.nodeZ[id]
	return height or nil, st.nodeSteep[id]
end

-- Whether an abstract graph edge u -> v climbs more than the client allows. Graph edges join border entrances one
-- cell apart; the same stored-height rule the grid applies therefore refuses a baked edge too: steep ground goes
-- downhill only, and a format 2 map also refuses a climb past 50 degrees (#897; see climbStep).
---@param st table
---@param a number
---@param b number
---@return boolean
local function climbNodes(st, a, b)
	if st.D.climbChecked or not st.steep or a < 0 or b < 0 then
		return true
	end
	local ak, bk = floor(a / 4096), floor(b / 4096)
	if ak == bk then
		-- An edge between two entrances of one cluster stands for a walk through its grid, which the local search
		-- charges step by step; its ends' heights say nothing about the climb between them.
		return true
	end
	local ac = metadata(st, a)
	local bc = metadata(st, b)
	if not ac or not bc then
		return true -- a node the map cannot place says nothing about the climb
	end
	local C = st.C
	local ax = floor(ak / st.ny) * C + floor(ac / C)
	local ay = (ak % st.ny) * C + ac % C
	local bx = floor(bk / st.ny) * C + floor(bc / C)
	local by = (bk % st.ny) * C + bc % C
	local distance = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) * st.cs
	local za, steepA = entranceHeight(st, a)
	local zb, steepB = entranceHeight(st, b)
	if not za or not zb then
		return true
	end
	local rise = zb - za
	if st.fmt < 3 and rise > TAN50 * distance then
		return false
	end
	return not (steepA or steepB) or rise <= 0
end

---@param map number
---@return boolean
function Path.HasData(map)
	return Data(map) ~= nil
end

---@param map number
---@return boolean
function Path.IsLoaded(map)
	local data = Data(map)
	local state = states[map]
	return (state ~= nil and (state.decoded > 0 or next(state.graphUsed) ~= nil))
		or (data ~= nil and data.packed == nil)
end

---@class SPFPathGrid
ns.PathGrid = {
	clock = clock,
	tick = tick,
	Deadline = Deadline,
	Expansions = Expansions,
	State = State,
	surface = surface,
	grid = grid,
	cellOf = cellOf,
	nodesOf = nodesOf,
	metadata = metadata,
	adjacent = adjacent,
	preceding = preceding,
	entrance = entrance,
	locate = locate,
	standing = standing,
	ground = ground,
	snap = snap,
	roads = roads,
	roadDistance = roadDistance,
	roadClear = roadClear,
	roadEdges = roadEdges,
	roadEdgesIn = roadEdgesIn,
	smooth = smooth,
	climbNodes = climbNodes,
	peak = peak,
	toward = toward,
	bare = bare,
	neighbours = neighbours,
	Hold = Hold,
	Running = Running,
	Release = Release,
	Pin = Pin,
	Ready = Ready,
	Quiet = Quiet,
	Idle = Idle,
	Reset = Reset,
	TILE = TILE,
	SNAP = SNAP,
	ZTOL = ZTOL,
	OFFROAD = OFFROAD,
	FREE = FREE,
	DX = DX,
	DY = DY,
}

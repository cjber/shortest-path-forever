-- The spawns that stand under or over another walkable surface, with the height of the one they stand on. Reads
-- "map x y z" lines (classic-db spawns, world yards) on stdin and writes "map x y z" for each spawn kept, z being the
-- walking map's surface it matched. Run by tools/gen_heights.py, from the repo root:
-- luajit tools/bake_heights.lua < spawns.tsv
local ns = {}
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local MAPS = { 0, 1 }
for _, map in ipairs(MAPS) do
	assert(loadfile("tools/load_nav.lua"))(map)
end
local Path, Grid = ns.Path, ns.PathGrid
Path.cacheKB = math.huge -- the bake reads every cluster once; nothing needs evicting
local floor, abs = math.floor, math.abs

-- A spawn's z lands on a surface within MATCH yards. The baker keeps floors at least 3 yd apart, and the server's
-- heights sit within 5 yd of the client's surface for nine spawns in ten.
local MATCH = 5
-- Another surface this far from the matched one is another floor for the router (Path.lua's ZTOL): without a height
-- a journey could end on it instead.
local APART = Grid.ZTOL

-- Every surface of global cell (gx, gy): the base surface, then its floors.
local function Surfaces(st, gx, gy, out)
	if gx < 0 or gy < 0 or gx >= st.GX or gy >= st.GY then
		return
	end
	local C = st.C
	local k, lc = floor(gx / C) * st.ny + floor(gy / C), (gx % C) * C + gy % C
	local val = Grid.grid(st, k)
	if not val then
		return
	end
	local z, at = st.z[k], st.at[k]
	if val[lc + 1] ~= 0 then
		out[#out + 1] = z[lc + 1]
	end
	local node = at[-(lc + 1)]
	while node and at[node + 1] == lc do
		out[#out + 1] = z[node + 1]
		node = node + 1
	end
end

-- The surface nearest h among heights, within MATCH.
local function Match(heights, h)
	local best, gap
	for _, s in ipairs(heights) do
		if abs(s - h) <= MATCH and (not gap or abs(s - h) < gap) then
			best, gap = s, abs(s - h)
		end
	end
	return best
end

-- [map x y] = the height kept there, or false when spawns on different floors round to the same spot (the ruins over
-- the Undercity): there a height would guess, so the spot keeps the cheapest surface.
local kept, order = {}, {}
for line in io.lines() do
	local map, x, y, h = line:match("^(%d+)\t(%S+)\t(%S+)\t(%S+)$")
	map, x, y, h = tonumber(map), tonumber(x), tonumber(y), tonumber(h)
	local st = map and Path.HasData(map) and Grid.State(map)
	if st then
		local gx, gy = floor((x - st.x0) / st.cs), floor((y - st.y0) / st.cs)
		local own, near = {}, {}
		Surfaces(st, gx, gy, own)
		-- connectPoint takes a heightless goal on any surface within a cell of it, so the 3x3 around the spawn is what
		-- the journey could end on; its own cell is matched first, the neighbours at a cell's edge.
		for dx = -1, 1 do
			for dy = -1, 1 do
				Surfaces(st, gx + dx, gy + dy, near)
			end
		end
		local z = Match(own, h) or Match(near, h)
		local other = false
		for _, s in ipairs(z and near or {}) do
			other = other or abs(s - z) > APART
		end
		if other then
			-- Rounded to the yard: floors are at least 3 yd apart, and snap takes the surface nearest the height.
			local spot = string.format("%d\t%d\t%d", map, floor(x + 0.5), floor(y + 0.5))
			z = floor(z + 0.5)
			if kept[spot] == nil then
				kept[spot] = z
				order[#order + 1] = spot
			elseif kept[spot] and abs(kept[spot] - z) > APART then
				kept[spot] = false
			end
		end
	end
end
for _, spot in ipairs(order) do
	if kept[spot] then
		io.write(spot, "\t", kept[spot], "\n")
	end
end

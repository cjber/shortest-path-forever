-- Follow a drawn walk cell by cell on the baked walking map, the way the router's search expands it: every link entry
-- of a move, not only the first. A walk passes when each drawn point stands on a surface the walk can be on there and
-- each step between them is one the search could take. Used by tests/caves_cities_spec.lua.
local floor, abs, sqrt = math.floor, math.abs, math.sqrt

local F = {}

function F.new(ns)
	local Grid = ns.PathGrid
	local ZTOL, SNAP = Grid.ZTOL, Grid.SNAP
	local M = {}

	-- Every surface of global cell (gx, gy): the base node and each floor, as { k, node, z }.
	local function surfaces(st, gx, gy)
		local C, out = st.C, {}
		if gx < 0 or gy < 0 or gx >= st.GX or gy >= st.GY then
			return out
		end
		local k, lc = floor(gx / C) * st.ny + floor(gy / C), (gx % C) * C + gy % C
		local val = Grid.grid(st, k)
		if not val then
			return out
		end
		local z, at = st.z[k], st.at[k]
		if val[lc + 1] ~= 0 then
			out[#out + 1] = { k = k, node = lc, z = z[lc + 1] }
		end
		local node = at[-(lc + 1)]
		while node and at[node + 1] == lc do
			out[#out + 1] = { k = k, node = node, z = z[node + 1] }
			node = node + 1
		end
		return out
	end

	-- A link's landing node, read as search() reads it: layer 0 the base, n the nth floor, -1 the surface nearest h.
	local function land(st, tk, tlc, layer, h)
		local val, z, at = st.val[tk], st.z[tk], st.at[tk]
		local first = at[-(tlc + 1)]
		if layer == 0 then
			return val[tlc + 1] ~= 0 and tlc or nil
		end
		if layer > 0 then
			local node = first and first + layer - 1
			return node and at[node + 1] == tlc and node or nil
		end
		local best, gap
		if val[tlc + 1] ~= 0 then
			best, gap = tlc, abs(z[tlc + 1] - h)
		end
		local node = first
		while node and at[node + 1] == tlc do
			if not gap or abs(z[node + 1] - h) < gap then
				best, gap = node, abs(z[node + 1] - h)
			end
			node = node + 1
		end
		return best
	end

	-- Every node one move (dx, dy) reaches from node at global cell (x, y): the ordinary step and every link entry
	-- with that offset.
	local function targets(st, k, node, x, y, dx, dy, add)
		local tk, tn = Grid.neighbour(st, k, node, x, y, dx, dy, true)
		if tk and tn then
			add(tk, tn)
		end
		Grid.grid(st, k)
		local l = st.links[k][node + 1]
		local tx, ty = x + dx, y + dy
		if not l or tx < 0 or ty < 0 or tx >= st.GX or ty >= st.GY then
			return
		end
		local C = st.C
		local k2, tlc = floor(tx / C) * st.ny + floor(ty / C), (tx % C) * C + ty % C
		for e = 1, #l do
			local v = l[e]
			if v % 16 - 8 == dx and floor(v / 16) % 16 - 8 == dy then
				Grid.grid(st, k2)
				local n2 = land(st, k2, tlc, floor(v / 256) % 64 - 1, st.z[k][node + 1])
				if n2 then
					add(k2, n2)
				end
			end
		end
	end

	local function collector()
		local found, seen = {}, {}
		return found,
			function(st, k, n)
				local id = k * 1048576 + n
				if not seen[id] then
					seen[id] = true
					Grid.grid(st, k)
					found[#found + 1] = { k = k, node = n, z = st.z[k][n + 1] }
				end
			end
	end

	-- The surfaces one move (mx, my) reaches from nodes at (x, y), a change of layer within the cell allowed first.
	local function move(st, nodes, x, y, mx, my)
		local mid, addMid = collector()
		local found, add = collector()
		for _, s in ipairs(nodes) do
			addMid(st, s.k, s.node)
			targets(st, s.k, s.node, x, y, 0, 0, function(k, n)
				addMid(st, k, n)
			end)
		end
		for _, s in ipairs(mid) do
			targets(st, s.k, s.node, x, y, mx, my, function(k, n)
				add(st, k, n)
			end)
		end
		return found
	end

	local function heights(list)
		local t = {}
		for _, s in ipairs(list) do
			t[#t + 1] = floor(s.z)
		end
		return table.concat(t, "/")
	end
	local function near(list, z, tol)
		local out = {}
		for _, s in ipairs(list) do
			if abs(s.z - z) <= tol then
				out[#out + 1] = s
			end
		end
		return out
	end

	-- The cells segment a -> b crosses (fractional cell coordinates) in sight()'s order, from the set cur at (cx, cy).
	local function segment(st, cur, cx, cy, ax, ay, bx, by)
		local dx, dy = bx - ax, by - ay
		local sx, sy = dx > 0 and 1 or -1, dy > 0 and 1 or -1
		local tx, ty = floor(bx), floor(by)
		local ndx = dx ~= 0 and ((sx > 0 and (cx + 1 - ax) or (ax - cx)) / abs(dx)) or math.huge
		local ndy = dy ~= 0 and ((sy > 0 and (cy + 1 - ay) or (ay - cy)) / abs(dy)) or math.huge
		local ix, iy = dx ~= 0 and 1 / abs(dx) or math.huge, dy ~= 0 and 1 / abs(dy) or math.huge
		while cx ~= tx or cy ~= ty do
			local mx, my = 0, 0
			if abs(ndx - ndy) < 1e-9 then
				mx, my = sx, sy
				ndx, ndy = ndx + ix, ndy + iy
			elseif ndx < ndy then
				mx = sx
				ndx = ndx + ix
			else
				my = sy
				ndy = ndy + iy
			end
			local nxt = move(st, cur, cx, cy, mx, my)
			if #nxt == 0 then
				local here = surfaces(st, cx + mx, cy + my)
				return nil,
					cx + mx,
					cy + my,
					{
						kind = #here == 0 and "off-surface" or "level-break",
						from = heights(cur),
						to = heights(here),
					}
			end
			cur, cx, cy = nxt, cx + mx, cy + my
		end
		return cur, cx, cy
	end

	-- Does a point stand on the walking map by the router's own snap rule: a surface within ZTOL of its height in a
	-- cell within SNAP cells?
	function M.stands(map, x, y, z)
		local st = Grid.State(map)
		local gx, gy = floor((x - st.x0) / st.cs), floor((y - st.y0) / st.cs)
		for dx = -SNAP, SNAP do
			for dy = -SNAP, SNAP do
				if #near(surfaces(st, gx + dx, gy + dy), z, ZTOL) > 0 then
					return true
				end
			end
		end
		return false
	end

	-- points: the drawn walk (interior points carry their surface's height); z0, z1: the ends' true heights. Returns
	-- nil when the walk can be followed, else { kind, x, y, ... } at the first place it cannot.
	function M.check(map, points, z0, z1)
		local st = Grid.State(map)
		local n = #points
		if n < 2 then
			return nil
		end
		local P = {}
		for i, p in ipairs(points) do
			P[i] = { (p.x - st.x0) / st.cs, (p.y - st.y0) / st.cs, p.z }
		end
		-- An end's surfaces: its own cell's within ZTOL, else the first cell along its segment with one (the router
		-- snaps an end standing off the grid onto the nearest).
		local function endpoint(i0, i1, z)
			local ax, ay, bx, by = P[i0][1], P[i0][2], P[i1][1], P[i1][2]
			local steps = math.max(1, floor(sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) * 8))
			for j = 0, steps do
				local t = j / steps
				local gx, gy = floor(ax + t * (bx - ax)), floor(ay + t * (by - ay))
				local m = near(surfaces(st, gx, gy), z, ZTOL)
				if #m > 0 then
					return m, gx, gy
				end
			end
		end
		local function at(f, ex, ey, i)
			f.x, f.y, f.seg = st.x0 + (ex + 0.5) * st.cs, st.y0 + (ey + 0.5) * st.cs, i
			return f
		end
		local cur, cx, cy = endpoint(1, 2, z0 or P[2][3])
		if not cur then
			return { kind = "start-off-surface", x = points[1].x, y = points[1].y }
		end
		for i = 2, n - 1 do
			local ax, ay = P[i - 1][1], P[i - 1][2]
			if floor(ax) ~= cx or floor(ay) ~= cy then
				ax, ay = cx + 0.5, cy + 0.5
			end
			local nxt, ex, ey, f = segment(st, cur, cx, cy, ax, ay, P[i][1], P[i][2])
			if not nxt then
				return at(f, ex, ey, i)
			end
			cur, cx, cy = nxt, ex, ey
			if P[i][3] then
				local m = near(cur, P[i][3], 1)
				if #m == 0 then -- a drop or a link to another surface of the same cell
					local more, add = collector()
					for _, s in ipairs(cur) do
						targets(st, s.k, s.node, ex, ey, 0, 0, function(k, nd)
							add(st, k, nd)
						end)
					end
					m = near(more, P[i][3], 1)
				end
				if #m == 0 then
					return { kind = "vertex-level", seg = i, x = points[i].x, y = points[i].y, have = heights(cur) }
				end
				cur = m
			end
		end
		-- The last segment ends where the goal snaps.
		local zEnd = z1 or P[n - 1][3]
		local back, gx, gy = endpoint(n, n - 1, zEnd)
		if not back then
			return { kind = "goal-off-surface", x = points[n].x, y = points[n].y }
		end
		if gx == cx and gy == cy and #near(cur, zEnd, ZTOL) > 0 then
			return nil
		end
		local ax, ay = P[n - 1][1], P[n - 1][2]
		if floor(ax) ~= cx or floor(ay) ~= cy then
			ax, ay = cx + 0.5, cy + 0.5
		end
		local nxt, ex, ey, f = segment(st, cur, cx, cy, ax, ay, gx + 0.5, gy + 0.5)
		if not nxt then
			return at(f, ex, ey, n)
		end
		if #near(nxt, zEnd, ZTOL) == 0 then
			return { kind = "goal-level", x = points[n].x, y = points[n].y, have = heights(nxt) }
		end
		return nil
	end

	return M
end

return F

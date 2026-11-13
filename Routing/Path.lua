---@class SPFNamespace
local ns = select(2, ...)

-- rule-ignore: file-size-no-growth - the walking search and its refinement share one hot path

if ns.broken then
	return
end

-- Walking searches over PathGrid.lua's decoded maps: HPA* between ADT-tile clusters, an 8 yd grid inside them, and
-- FindMany's abstract Dijkstra. PathJobs.lua slices them over frames.
---@class SPFPath
local Path = ns.Path
local Grid = ns.PathGrid
local tick, Deadline, Expansions, State, surface, grid =
	Grid.tick, Grid.Deadline, Grid.Expansions, Grid.State, Grid.surface, Grid.grid
local cellOf, nodesOf, metadata = Grid.cellOf, Grid.nodesOf, Grid.metadata
local adjacent, preceding = Grid.adjacent, Grid.preceding
local entrance, locate, standing, snap, smooth = Grid.entrance, Grid.locate, Grid.standing, Grid.snap, Grid.smooth
local toward, peak = Grid.toward, Grid.peak

local TILE, SNAP, ZTOL, DX, DY = Grid.TILE, Grid.SNAP, Grid.ZTOL, Grid.DX, Grid.DY
local OFFROAD = Grid.OFFROAD
local RETRIES = 8 -- other cells tried for an endpoint stuck in a pocket
-- How far below its surface a stuck endpoint may move. Format 1 keeps the bake it shipped with; format 2 knows the
-- player's falling limit, and past 14.57 yards the drop hurts.
local DROP, DROP_LEGACY = 14.57, 30
local SQRT2 = math.sqrt(2)
local START, GOAL = -1, -2
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local floor, sqrt, huge, max, abs = math.floor, math.sqrt, math.huge, math.max, math.abs
local yield = coroutine.yield

-- Binary min-heap on parallel arrays, reset per search.
local hk, hv, hn = {}, {}, 0

local function push(k, v)
	hn = hn + 1
	local i = hn
	while i > 1 do
		local p = floor(i / 2)
		if hk[p] <= k then
			break
		end
		hk[i], hv[i] = hk[p], hv[p]
		i = p
	end
	hk[i], hv[i] = k, v
end

local function pop()
	local top = hv[1]
	local k, v = hk[hn], hv[hn]
	hn = hn - 1
	local i = 1
	while true do
		local c = i * 2
		if c > hn then
			break
		end
		if c < hn and hk[c + 1] < hk[c] then
			c = c + 1
		end
		if hk[c] >= k then
			break
		end
		hk[i], hv[i] = hk[c], hv[c]
		i = c
	end
	hk[i], hv[i] = k, v
	return top
end

-- A hazard profile (Journey/Hazards.lua) keeps its costs per map: entrance factors, near-town clusters and local cell
-- factors. A new profile starts when the costs it charges change.
local function memoOf(st, hz)
	local memo = st.hazards
	if not memo or memo.key ~= hz.key then
		memo = { key = hz.key, at = {}, near = {}, cell = {} }
		st.hazards = memo
	end
	return memo
end

-- What a hazard profile charges at a local cell, read at its centre: a cell search meets a hazard on the same terms
-- the entrance graph does.
local function cellFactor(st, hz, k, cell)
	local C = st.C
	local x = st.x0 + (floor(k / st.ny) * C + floor(cell / C) + 0.5) * st.cs
	local y = st.y0 + (k % st.ny * C + cell % C + 0.5) * st.cs
	return hz.Point(st.map, x, y)
end

-- The factors the profile charges across cluster k's cells, kept per profile and read at each cell the first time a
-- search reaches it; nil when nothing in the cluster is charged, so its search keeps its plain costs.
local function cellFactors(st, hz, k)
	local memo = memoOf(st, hz)
	local cells = memo.cell[k]
	if cells == nil then
		local C, cs = st.C, st.cs
		local x, y = st.x0 + floor(k / st.ny) * C * cs, st.y0 + (k % st.ny) * C * cs
		if not hz.Charged(st.map, x, y, x + C * cs, y + C * cs) then
			cells = false
		else
			cells = {}
		end
		memo.cell[k] = cells
	end
	return cells or nil
end

-- The factor the profile charges at a path entry, for the string-pulling in PathGrid.lua: the same per-profile memo
-- the cluster searches fill, so the drawn line and the chosen one weigh the same cells. A floor node maps to its base
-- cell the way the search does.
---@param hz SPFHazards
---@return fun(k: number, node: number): number
local function factorOf(st, hz)
	local C = st.C
	return function(k, node)
		local cells = cellFactors(st, hz, k)
		if not cells then
			return 1
		end
		local base = node < C * C and node or cellOf(st, k, node)
		local f = cells[base]
		if not f then
			f = cellFactor(st, hz, k, base)
			cells[base] = f
		end
		return f
	end
end

-- Grid search inside one cluster, entering water costing swim times its length. tree holds g/parent keyed by
-- node + 1. With goal set it is A*, otherwise Dijkstra that stops once every node in targets (a set of nodes) is
-- settled.
local function Tree()
	return { g = {}, r = {}, par = {}, stamp = {}, closed = {}, gen = 0 }
end
-- One grid search loop; splitting moves its retained arrays to upvalues on the hot path. g is the preference
-- cost it orders by, weighted by the hazard profile where one is given, and r the real cost it reports. reverse
-- follows the links that reach a node instead of the ones it leaves, so the tree's cost is a walk into the source and a
-- one-way drop is never climbed.
local function search(st, k, swim, source, tree, goal, targets, left, roads, hz, reverse)
	local val = grid(st, k)
	-- Search only enters populated grids, through snapped endpoints or decoded entrances.
	---@cast val number[]
	-- A paused search retains these arrays even if another job evicts its cluster.
	local m, z, at, links = st.moves[k], st.z[k], st.at[k], st.links[k]
	local fmt, back = st.fmt, reverse and st.linksIn[k]
	local steep = st.steep
	local C, cs = st.C, st.cs
	local N = C * C
	local g, r, par, stamp, closed = tree.g, tree.r, tree.par, tree.stamp, tree.closed
	local factor = hz and cellFactors(st, hz, k) or nil
	tree.gen = tree.gen + 1
	local gen = tree.gen
	tree.k = k
	local gx, gy = 0, 0
	if goal then
		local goalCell = goal < N and goal or at[goal + 1]
		gx, gy = floor(goalCell / C), goalCell % C
	end
	hn = 0
	g[source + 1], r[source + 1], par[source + 1], stamp[source + 1] = 0, 0, -1, gen
	push(0, source)

	---@type number, number, number, number, number
	local u, ux, uy, gu, ru
	local function relax(v, length, override)
		-- Forward walks u -> v; a reverse tree walks the stored edge the other way, v -> u, into the source.
		if reverse then
			if steep and not steep(val, z, v, val, z, u) then
				return
			end
		elseif steep and not steep(val, z, u, val, z, v) then
			return
		end
		local i = v + 1
		-- A step is charged for the cell it enters, whichever way the tree walks it: water, Follow roads and a
		-- hazard profile's weight are all properties of that cell.
		local entered = reverse and u or v
		local step = override or length * cs * (val[entered + 1] == 2 and swim or 1)
		local base = entered < N and entered or at[entered + 1]
		local choice = roads and not roads[base] and step * OFFROAD or step
		if factor then
			local f = factor[base]
			if not f then
				f = cellFactor(st, hz, k, base)
				factor[base] = f
			end
			choice = choice * f
		end
		local gv = gu + choice
		if stamp[i] ~= gen or gv < g[i] then
			g[i], r[i], par[i], stamp[i] = gv, ru + step, u, gen
			local h = 0
			if goal then
				local cell = v < N and v or at[i]
				local ax, ay = floor(cell / C) - gx, cell % C - gy
				if ax < 0 then
					ax = -ax
				end
				if ay < 0 then
					ay = -ay
				end
				h = (ax > ay and ax + (SQRT2 - 1) * ay or ay + (SQRT2 - 1) * ax) * cs
			end
			push(gv + h, v)
		end
	end

	while hn > 0 do
		u = pop()
		local i = u + 1
		if closed[i] ~= gen then
			closed[i] = gen
			tick()
			if u == goal then
				return true
			end
			if targets and targets[u] then
				left = left - 1
				if left <= 0 then
					return true
				end
			end
			local cell = u < N and u or at[i]
			gu, ru, ux, uy = g[i], r[i], floor(cell / C), cell % C
			if u < N then
				local mi = m[i] % 16
				local px, mx = mi % 2 == 1, ux > 0 and m[i - C] % 2 == 1
				local py, my = mi % 4 >= 2, uy > 0 and m[i - 1] % 4 >= 2
				if px then
					relax(u + C, 1)
				end
				if mx then
					relax(u - C, 1)
				end
				if py then
					relax(u + 1, 1)
				end
				if my then
					relax(u - 1, 1)
				end
				if mi % 8 >= 4 then
					relax(u + C + 1, SQRT2)
				end
				if mi >= 8 then
					relax(u + C - 1, SQRT2)
				end
				if ux > 0 and uy > 0 and m[i - C - 1] % 8 >= 4 then
					relax(u - C - 1, SQRT2)
				end
				if ux > 0 and uy < C - 1 and m[i - C + 1] % 16 >= 8 then
					relax(u - C + 1, SQRT2)
				end
			end
			local l
			if reverse and fmt >= 2 then
				l = back and back[i]
			else
				l = links[i]
			end
			if l then
				for e = 1, #l do
					if fmt >= 2 then
						-- the cell offset, the landing layer and the cost in whole yards (0 for an ordinary step)
						local entry = l[e]
						local tx, ty = ux + entry % 16 - 8, uy + floor(entry / 16) % 16 - 8
						if tx >= 0 and ty >= 0 and tx < C and ty < C then
							local v = surface(st, k, tx * C + ty, floor(entry / 256) % 64 - 1, z[i], val, z, at)
							if v then
								local cost = floor(entry / 16384)
								if cost > 0 then
									relax(v, nil, cost)
								else
									relax(v, (tx ~= ux and ty ~= uy) and SQRT2 or 1)
								end
							end
						end
					else
						local d = l[e] % 8
						local tx, ty = ux + DX[d], uy + DY[d]
						if tx >= 0 and ty >= 0 and tx < C and ty < C then
							local v = surface(st, k, tx * C + ty, floor(l[e] / 8) - 1, z[i], val, z, at)
							if v then
								relax(v, d >= 4 and SQRT2 or 1)
							end
						end
					end
				end
			end
		end
	end
	return goal == nil
end

local function reached(tree, node)
	return tree.stamp[node + 1] == tree.gen and tree.closed[node + 1] == tree.gen
end

-- Node path in a tree from node back to its source (node first).
local function trace(tree, node, out)
	local par = tree.par
	while node >= 0 do
		out[#out + 1] = node
		node = par[node + 1]
	end
	return out
end

local trees = { S = Tree(), G = Tree(), R = Tree() }

-- The bake runs a whole map's searches back to back; two trees keep their grown arrays instead of rebuilding four
-- tables for every search. The gen stamp makes each search start clean.
local bakeTrees = { Tree(), Tree() }

-- An entrance's world position: the centre of its cell.
local function nodeXY(st, id)
	local k, C = floor(id / 4096), st.C
	nodesOf(st, k)
	local lc = metadata(st, id)
	return st.x0 + (floor(k / st.ny) * C + floor(lc / C) + 0.5) * st.cs,
		st.y0 + ((k % st.ny) * C + lc % C + 0.5) * st.cs
end

-- What a hazard profile (Journey/Hazards.lua) multiplies an entrance graph edge by: the mean of its ends' factors, or
-- a town's when the edge crosses one. Ends are kept per profile; the town test runs only in clusters a town is near.
local function hazard(st, hz, u, v)
	local memo = memoOf(st, hz)
	local at, ux, uy, vx, vy = memo.at, nil, nil, nil, nil
	local fu, fv = at[u], at[v]
	if not fu then
		ux, uy = nodeXY(st, u)
		fu = hz.Point(st.map, ux, uy)
		at[u] = fu
	end
	if not fv then
		vx, vy = nodeXY(st, v)
		fv = hz.Point(st.map, vx, vy)
		at[v] = fv
	end
	local f, k = (fu + fv) / 2, floor(u / 4096)
	local near = memo.near[k]
	if near == nil then
		-- An edge stays within its cluster's neighbours, so a town matters if it is within a cluster of this one.
		local x, y = st.x0 + (floor(k / st.ny) - 1) * TILE, st.y0 + (k % st.ny - 1) * TILE
		near = hz.Near(st.map, x, y, x + 3 * TILE, y + 3 * TILE)
		memo.near[k] = near
	end
	if near then
		if not ux then
			ux, uy = nodeXY(st, u)
		end
		if not vx then
			vx, vy = nodeXY(st, v)
		end
		local town = hz.Chord(st.map, ux, uy, vx, vy)
		if town > f then
			f = town
		end
	end
	return f
end

-- Abstract A* state.
local ag, areal, apar, astamp, aclosed, agen = {}, {}, {}, {}, {}, 0

-- Endpoint searches: grid Dijkstra to the cluster's entrances, or from them when reverse.
local function endpoint(st, swim, tree, k, node, roadsOn, hz, reverse)
	local targets, left = {}, 0
	for _, id in ipairs(nodesOf(st, k)) do
		local e = entrance(st, id)
		if e and not targets[e] then
			targets[e], left = true, left + 1
		end
	end
	search(st, k, swim, node, tree, nil, targets, left, roadsOn and Grid.roads(st, k), hz, reverse)
end
-- An endpoint on a rooftop or ledge the grid cannot leave moves to the nearest node that reaches an entrance, down
-- a ledge but never up one, onto another level, or over a fall that hurts. A goal is judged by the walks into it, so
-- its search runs in reverse: a ledge a drop lands on is connected already and stays where it is.
local function settle(st, swim, tree, k, node, roadsOn, hz, reverse)
	local C = st.C
	endpoint(st, swim, tree, k, node, roadsOn, hz, reverse)
	local function connected()
		for _, id in ipairs(nodesOf(st, k)) do
			local e = entrance(st, id)
			if e and reached(tree, e) then
				return true
			end
		end
		return false
	end
	if connected() then
		return node
	end
	local tries = 0
	local reach = st.fmt >= 2 and DROP or DROP_LEGACY
	grid(st, k)
	local h = st.z[k][node + 1]
	local cell = cellOf(st, k, node)
	local lx, ly = floor(cell / C), cell % C
	for r = 1, SNAP do
		for dx = -r, r do
			for dy = -r, r do
				if tries >= RETRIES then
					return node
				end
				local x, y = lx + dx, ly + dy
				local ring = dx == r or dx == -r or dy == r or dy == -r
				if ring and x >= 0 and y >= 0 and x < C and y < C then
					local near = standing(st, k, x * C + y, h)
					local rise = near and st.z[k][near + 1] - h
					if near and rise <= ZTOL and rise >= -reach and not reached(tree, near) then
						tries, node = tries + 1, near
						endpoint(st, swim, tree, k, node, roadsOn, hz, reverse)
						if connected() then
							return node
						end
					end
				end
			end
		end
	end
	return node
end

-- Both APIs connect endpoints with the same local search: outbound from a start, and into a goal so a drop is not
-- climbed. The same-cluster direct edge retains the grid's entering-water direction.
local function connections(st, tree, k)
	local edges, reals = {}, {}
	for _, id in ipairs(nodesOf(st, k)) do
		local e = entrance(st, id)
		if e and reached(tree, e) then
			edges[id], reals[id] = tree.g[e + 1], tree.r[e + 1]
		end
	end
	return edges, reals
end

local function pointNode(st, point)
	local k, node = locate(st, point.x, point.y)
	if not k then
		return nil, nil, "outside"
	end
	node = snap(st, k, node, point.x, point.y, point.z)
	return k, node, not node and "offmesh" or nil
end

-- Fixed places recur in both batches and in later journeys. Keep their small entrance-cost vectors and only the
-- last eight grid trees; cap the cache so moving start positions cannot grow it for the entire play session.
-- reverse gives the cost into the node, which is what a goal needs; format 1's links are symmetric, so it reuses the
-- outbound search.
local function connect(st, swim, k, node, roadsOn, hz, reverse)
	nodesOf(st, k)
	if reverse and st.fmt < 2 then
		reverse = nil -- format 1's links are symmetric, so its outbound search already answers
	end
	local key = k
		.. ":"
		.. node
		.. ":"
		.. swim
		.. (roadsOn and ":r" or "")
		.. (hz and ":" .. hz.key or "")
		.. (reverse and ":i" or "")
	local entry = st.ends[key]
	if not entry then
		local tree = Tree()
		local settled = settle(st, swim, tree, k, node, roadsOn, hz, reverse)
		local edges, reals = connections(st, tree, k)
		entry = { node = settled, edges = edges, reals = reals, tree = tree }
		-- A handful of local trees removes repeated endpoint searches without retaining a continent's grids.
		st.endTrees = st.endTrees or {}
		st.endTrees[#st.endTrees + 1] = entry
		if #st.endTrees > 8 then
			table.remove(st.endTrees, 1).tree = nil
		end
		if st.endCount >= 256 then
			st.ends, st.endCount = {}, 0
		end
		st.ends[key], st.endCount = entry, st.endCount + 1
	end
	return entry.node, entry.edges, entry.reals, entry.tree
end

-- A point without a height (the player, whose UnitPosition height is a placeholder 0, or a map click) could stand on
-- any surface at its spot, so it starts from each one within a cell of it at a distinct height and the search keeps
-- the cheapest: a street beside or over a canal is not walked from the canal bed. Returns each surface's connection,
-- the entrance costs merged by minimum and, per entrance, the surface it came from. inbound returns the costs into the
-- point instead, which is what a goal needs, in the fifth to seventh places, and leaves the outbound ones empty: each
-- caller walks a point one way, and on format 2 the other way is a second grid search. The surfaces themselves are
-- returned too: a walk drawn or searched to a point ends on them, never on wherever the outbound rescue moved it.
local function connectPoint(st, swim, k, node, h, roadsOn, hz, inbound)
	local nodes = { node }
	if not h then
		local values = grid(st, k)
		assert(values)
		local C, val, z, at = st.C, values, st.z[k], st.at[k]
		local cell = cellOf(st, k, node)
		local lx, ly = floor(cell / C), cell % C
		local function consider(n, r)
			-- A neighbour's water is where the point is not: it would be standing in it.
			if r > 0 and val[n + 1] == 2 then
				return
			end
			for _, m in ipairs(nodes) do
				if abs(z[n + 1] - z[m + 1]) <= ZTOL then
					return
				end
			end
			nodes[#nodes + 1] = n
		end
		for r = 0, 1 do
			for dx = -r, r do
				for dy = -r, r do
					local x, y = lx + dx, ly + dy
					if (dx == r or dx == -r or dy == r or dy == -r) and x >= 0 and y >= 0 and x < C and y < C then
						local c = x * C + y
						if val[c + 1] ~= 0 then
							consider(c, r)
						end
						local n = at[-(c + 1)]
						while n and at[n + 1] == c do
							consider(n, r)
							n = n + 1
						end
					end
				end
			end
		end
	end
	local ends, merged, mergedReal, via = {}, {}, {}, {}
	for _, start in ipairs(nodes) do
		local n, edges, reals, tree = connect(st, swim, k, start, roadsOn, hz, inbound)
		local entry = { node = n, tree = tree, own = start }
		ends[#ends + 1] = entry
		for id, cost in pairs(edges) do
			if not merged[id] or cost < merged[id] then
				merged[id], mergedReal[id], via[id] = cost, reals[id], entry
			end
		end
	end
	if inbound then
		return ends, {}, {}, {}, merged, mergedReal, via, nodes
	end
	return ends, merged, mergedReal, via, {}, {}, {}, nodes
end
-- A point's position in global cells, and the node it stands on in its own cell: within ZTOL of its height, or the
-- base surface when it has none.
local function own(st, point)
	local fx, fy = (point.x - st.x0) / st.cs, (point.y - st.y0) / st.cs
	local k, lc = locate(st, point.x, point.y)
	local node, gap = standing(st, k, lc, point.z)
	return fx, fy, k, (node and gap <= ZTOL) and node or nil
end

-- The string is pulled between node centres, but the line is drawn from the endpoints themselves. Whether the drawn
-- segment between point and path entry j's cell centre stays on the walkable surface, walked in the direction it is
-- travelled (outbound from the start, inbound to the goal), and crosses no cell a hazard profile charges more than
-- the path entries it replaces. A point standing on a surface must be reached on it, or
-- leave from it; one with no surface in its cell (inside rock or a building the grid has none for) passes when the
-- segment runs on into it only across cells with no surface at all.
local function clearEnd(st, P, j, point, outbound, water, limit)
	local fx, fy, k, node = own(st, point)
	local cx, cy = P.x[j] + 0.5, P.y[j] + 0.5
	if outbound and node then
		local tk, tn = toward(st, P, k, node, fx, fy, cx, cy, water, limit)
		return tk == P.k[j] and tn == P.n[j]
	end
	local tk, tn = toward(st, P, P.k[j], P.n[j], cx, cy, fx, fy, water, limit)
	if not tk then
		return tn == true
	end
	return not node or (tk == k and tn == node)
end

-- With no pulled vertex between them, the line is the one chord between the two points: walked whole from a start
-- that stands on a surface to the goal's cell, on the goal's own surface when it has one, against the same hazard
-- limit the path's own entries allow and no slower than the route's own time (#742).
local function clearChord(st, P, from, to, water, limit, budget)
	local fx, fy, k, node = own(st, from)
	if not node then
		return false
	end
	local tx, ty, gk, goal = own(st, to)
	local tk, tn = toward(st, P, k, node, fx, fy, tx, ty, water, limit, budget)
	return tk ~= nil and (not goal or (tk == gk and tn == goal))
end

-- The largest factor a hazard profile charges over path entries first..last, or nil without a profile: a drawn segment
-- may cross no cell charged more than the walk it replaces.
local function limitOver(P, first, last)
	return P.factor and peak(P, P.factor, first, last, 1)
end

-- Sliced A* and refinement share scratch trees; splitting adds hot-path calls and upvalues
local function run(map, from, to, waterWalking, costOnly, hz)
	if hz and hz.ConnectorWalk and hz.ConnectorWalk(from, to) then
		hz = nil
	end
	local st = State(map)
	if not st then
		return nil, "nodata"
	end
	-- Walking on water is running, so the search weights water by 1 and reads each edge's second cost.
	local swim, cost2 = st.swim, 1
	if waterWalking then
		swim, cost2 = 1, 2
	end
	local sk, sc = locate(st, from.x, from.y)
	local gk, gc = locate(st, to.x, to.y)
	if not sk or not gk then
		return nil, "outside"
	end
	sc, gc = snap(st, sk, sc, from.x, from.y, from.z), snap(st, gk, gc, to.x, to.y, to.z)
	if not sc or not gc then
		return nil, "offmesh"
	end
	local C = st.C
	local roadsOn = hz and hz.roads

	local S, G = trees.S, trees.G
	local starts, source, sourceReal, sourceVia = connectPoint(st, swim, sk, sc, from.z, roadsOn, hz)
	-- The goal's costs are the walks into it, so a ledge drop is not climbed to reach it. A local walk to it ends on
	-- the surfaces it stands on, not on wherever the outbound rescue moved it.
	local _, _, _, _, target, targetReal, targetVia, goalOwn = connectPoint(st, swim, gk, gc, to.z, roadsOn, hz, true)
	local key = table.concat({ sk, sc, gk, gc, swim, from.z and 1 or 0, to.z and 1 or 0, hz and hz.key or "" }, ":")
	st.paths = st.paths or {}
	local cached = st.paths[key]
	local hops, cost, directFrom, directTo
	local x0, y0, cs = st.x0, st.y0, st.cs
	if cached then
		hops, cost, directFrom, directTo = cached.hops, cached.cost, cached.directFrom, cached.directTo
	else
		local direct, directReal
		if sk == gk then
			local roadSet = roadsOn and Grid.roads(st, sk)
			for _, a in ipairs(starts) do
				for _, b in ipairs(goalOwn) do
					if search(st, sk, swim, a.node, S, b, nil, nil, roadSet, hz) then
						local gv, rv = S.g[b + 1], S.r[b + 1]
						if not direct or gv < direct then
							direct, directReal, directFrom, directTo = gv, rv, a.node, b
						end
					end
				end
			end
		end

		local comps, shared = {}, false
		for id in pairs(source) do
			nodesOf(st, floor(id / 4096))
			local _, _, component = metadata(st, id)
			comps[component] = true
		end
		for id in pairs(target) do
			nodesOf(st, floor(id / 4096))
			local _, _, component = metadata(st, id)
			shared = shared or comps[component]
		end
		if not direct and not shared then
			return nil, "unreachable"
		end

		-- Abstract A* from START to GOAL through the entrance graph.
		-- Rounded graph edges and snapping must not let the heuristic overstate the remaining cost: a point can
		-- snap to a surface up to SNAP cells from the cell centre the heuristic measures to, and a drop shortens a
		-- fall to less than the cell-centre distance it replaces. Subtract that reach before scaling.
		local goalCell = cellOf(st, gk, gc)
		local goalX = x0 + (floor(gk / st.ny) * C + floor(goalCell / C) + 0.5) * cs
		local goalY = y0 + (gk % st.ny * C + goalCell % C + 0.5) * cs
		local lower = max(0, 1 - 0.5 / cs)
		local margin = SNAP * SQRT2 * cs
		local function h(id)
			local x, y = nodeXY(st, id)
			local dx, dy = abs(x - goalX), abs(y - goalY)
			local gap = dx > dy and dx + (SQRT2 - 1) * dy or dy + (SQRT2 - 1) * dx
			return max(0, gap - margin) * lower
		end
		agen = agen + 1
		local gen = agen
		hn = 0
		local function relax(v, gv, rv, parent)
			if astamp[v] ~= gen or gv < ag[v] then
				ag[v], areal[v], apar[v], astamp[v] = gv, rv, parent, gen
				push(gv + (v == GOAL and 0 or h(v)), v)
			end
		end
		for id, distance in pairs(source) do
			relax(id, distance, sourceReal[id], START)
		end
		if direct then
			relax(GOAL, direct, directReal, START)
		end
		local found = false
		while hn > 0 do
			local u = pop()
			if aclosed[u] ~= gen then
				aclosed[u] = gen
				tick()
				if u == GOAL then
					found = true
					break
				end
				local gu = ag[u]
				local ru = areal[u]
				if target[u] then
					relax(GOAL, gu + target[u], ru + targetReal[u], u)
				end
				nodesOf(st, floor(u / 4096))
				local adj = adjacent(st, u)
				local ratios = roadsOn and Grid.roadEdges(st, u) or nil
				for e = 1, #adj, 3 do
					local v = adj[e]
					if aclosed[v] ~= gen then
						nodesOf(st, floor(v / 4096))
						local yards = adj[e + cost2]
						local factor = hz and hazard(st, hz, u, v) or 1
						if ratios then
							local ei, m = (e + 2) / 3, cost2 == 2 and 2 or 0
							relax(
								v,
								gu + yards * ratios[ei * 4 - 3 + m] * factor,
								ru + yards * ratios[ei * 4 - 2 + m],
								u
							)
						else
							relax(v, gu + yards * factor, ru + yards, u)
						end
					end
				end
			end
		end
		if not found then
			return nil, "unreachable"
		end
		cost = areal[GOAL]
		hops = { GOAL }
		while hops[#hops] ~= START do
			hops[#hops + 1] = apar[hops[#hops]]
		end

		if (st.pathCount or 0) >= 16 then
			st.paths, st.pathCount = {}, 0
		end
		st.paths[key] = { hops = hops, cost = cost, directFrom = directFrom, directTo = directTo }
		st.pathCount = (st.pathCount or 0) + 1
	end
	if costOnly then
		return cost
	end

	-- Refine each hop into nodes with their global cells and a running count of water nodes. The pruned entrance
	-- graph may route through an entrance a little off the way, which refines to a spur walked out and back: a node
	-- reached again cuts the loop since its first visit, so the drawn walk never doubles back.
	---@type SPFPathPoints
	local P = { x = {}, y = {}, w = {}, t = {}, k = {}, n = {}, swim = swim }
	if hz then
		P.factor = factorOf(st, hz)
	end
	if roadsOn then
		P.roads, P.r = true, {}
	end
	local seen = {}
	local function add(k, node)
		local id = k * 1048576 + node
		local at = seen[id]
		if at then
			for j = #P.x, at + 1, -1 do
				seen[P.k[j] * 1048576 + P.n[j]] = nil
				P.x[j], P.y[j], P.w[j], P.t[j], P.k[j], P.n[j] = nil, nil, nil, nil, nil, nil
				if P.r then
					P.r[j] = nil
				end
			end
			return
		end
		local n = #P.x
		local cell = node < C * C and node or cellOf(st, k, node)
		P.x[n + 1], P.y[n + 1] = floor(k / st.ny) * C + floor(cell / C), (k % st.ny) * C + cell % C
		P.k[n + 1], P.n[n + 1] = k, node
		local wet = ((st.val[k] or grid(st, k))[node + 1] == 2)
		P.w[n + 1] = (P.w[n] or 0) + (wet and 1 or 0)
		-- The walk's own time to this entry, charged as the search charges a step: the cell it enters, land at run
		-- speed and water at the map's swim.
		local time = P.t[n] or 0
		if n > 0 then
			local dx, dy = P.x[n + 1] - P.x[n], P.y[n + 1] - P.y[n]
			time = time + sqrt(dx * dx + dy * dy) * st.cs * (wet and swim or 1)
		end
		P.t[n + 1] = time
		if P.r then
			local roadSet = Grid.roads(st, k)
			P.r[n + 1] = (P.r[n] or 0) + ((not roadSet or not roadSet[cell]) and 1 or 0)
		end
		seen[id] = n + 1
	end
	local function addAll(k, nodes, first, last, step)
		for i = first, last, step do
			add(k, nodes[i])
		end
	end
	local R = trees.R
	for i = #hops, 2, -1 do
		local a, b = hops[i], hops[i - 1]
		if a == START and b == GOAL then
			search(st, sk, swim, directFrom, S, directTo, nil, nil, roadsOn and Grid.roads(st, sk), hz)
			local nodes = trace(S, directTo, {})
			addAll(sk, nodes, #nodes, 1, -1)
		elseif a == START then
			local start = sourceVia[b]
			local tree = start.tree
			if not tree or not reached(tree, entrance(st, b)) then
				search(st, sk, swim, start.node, S, entrance(st, b), nil, nil, roadsOn and Grid.roads(st, sk), hz)
				tree = S
			end
			local nodes = trace(tree, entrance(st, b), {})
			addAll(sk, nodes, #nodes, 1, -1)
		elseif b == GOAL then
			local goal = targetVia[a]
			local tree = goal.tree
			if not tree or not reached(tree, entrance(st, a)) then
				search(st, gk, swim, goal.node, G, entrance(st, a), nil, nil, roadsOn and Grid.roads(st, gk), hz, true)
				tree = G
			end
			local nodes = trace(tree, entrance(st, a), {})
			addAll(gk, nodes, 1, #nodes, 1)
		else
			-- A mid-route cluster's walk is refined with the hazard profile: the entrance edge the search chose was
			-- charged for the ground it crosses, and the drawn line must keep out of the same ground rather than
			-- cut across it. The reported cost stays the search's real cost.
			local ka, kb = floor(a / 4096), floor(b / 4096)
			local ea, eb = entrance(st, a), entrance(st, b)
			if ka == kb and search(st, ka, swim, ea, R, eb, nil, nil, roadsOn and Grid.roads(st, ka), hz) then
				local nodes = trace(R, eb, {})
				addAll(ka, nodes, #nodes, 1, -1)
			else -- neighbouring entrances across a cluster border
				add(ka, ea)
				add(kb, eb)
			end
		end
	end

	-- Points carry the height of the surface they stand on; the returned cost uses real walking/swimming time, with
	-- hazards affecting only the route chosen. points.wet is the yards over water, which call for Water Walking.
	local keep = smooth(st, P)
	if #keep == 1 then -- both ends on one node
		keep[2] = keep[1]
	end
	local n = #P.x
	-- An end segment that fails is drawn through its end node's centre first: the string was pulled from there, so the
	-- rest of the line holds as it did. A chord that fails tries each end that way.
	local startVia, goalVia = #keep > 2 and keep[2] or n, #keep > 2 and keep[#keep - 1] or 1
	local startDetour, goalDetour = false, false
	if #keep > 2 or not clearChord(st, P, from, to, P.w[n] > 0, limitOver(P, 1, n), cost) then
		startDetour = not clearEnd(st, P, startVia, from, true, P.w[startVia] > 0, limitOver(P, 1, startVia))
		-- A chord whose start detoured now reaches the goal from the start node's centre.
		if startDetour and #keep <= 2 then
			goalVia = 1
		end
		goalDetour =
			not clearEnd(st, P, goalVia, to, false, P.w[n] - (P.w[goalVia - 1] or 0) > 0, limitOver(P, goalVia, n))
	end
	local drawn = { 1 }
	if startDetour then
		drawn[#drawn + 1] = 1
	end
	for i = 2, #keep - 1 do
		drawn[#drawn + 1] = keep[i]
	end
	-- Both ends on one node already pass through its centre once the start has detoured.
	if goalDetour and not (startDetour and n == 1) then
		drawn[#drawn + 1] = n
	end
	drawn[#drawn + 1] = n
	local points = { { map = map, x = from.x, y = from.y, z = from.z } }
	for i = 2, #drawn - 1 do
		local j = drawn[i]
		grid(st, P.k[j])
		points[#points + 1] = {
			map = map,
			x = x0 + (P.x[j] + 0.5) * cs,
			y = y0 + (P.y[j] + 0.5) * cs,
			z = st.z[P.k[j]][P.n[j] + 1],
		}
	end
	points[#points + 1] = { map = map, x = to.x, y = to.y, z = to.z }
	local wetYards = 0
	for i = 2, #points do
		local p, q = drawn[i - 1], drawn[i]
		-- A segment to or from an end node's own centre is as wet as that node.
		local wet = q > p and (P.w[q] - P.w[p]) / (q - p) or P.w[q] - (P.w[q - 1] or 0)
		local length = sqrt((points[i].x - points[i - 1].x) ^ 2 + (points[i].y - points[i - 1].y) ^ 2)
		wetYards = wetYards + length * wet
	end
	points.wet = wetYards
	-- Smoothing only changes drawing: planning and FindMany use the same hazard-selected graph route and real cost.
	return points, cost
end

-- Lazy terminal-node connections let nearby targets settle without first searching every faraway endpoint.
-- One sliced Dijkstra owns the heap swap and frontier locals across endpoint searches
local function runMany(map, from, targets, waterWalking, reverse, job, hz)
	local costs = job and job.costs or {}
	local function failed(reason)
		for i = 1, #targets do
			costs[i] = false
		end
		return costs, reason
	end
	local st = State(map)
	if not st then
		return failed("nodata")
	end
	local sk, sc, reason = pointNode(st, from)
	if not sc then
		return failed(reason)
	end
	if job then
		job.valid, job.sourceCluster, job.sourceNode = true, sk, sc
		for i, point in ipairs(targets) do
			if point.x == from.x and point.y == from.y then
				local k, node = pointNode(st, point)
				if k == sk and node == sc then
					costs[i] = 0
					job.revision = job.revision + 1
				end
			end
		end
		-- Publish endpoint validity before doing local Dijkstra work. Invalid goals and co-located
		-- transfers can then settle without launching speculative walks across the continent.
		if job.progress then
			yield()
		end
	end
	-- Resolve a short dock/flight-master connector on its own. FindMany shares one frontier among its targets, so a
	-- single target cannot remove hazard weights from the rest of that frontier.
	if hz and hz.ConnectorWalk then
		for i, point in ipairs(targets) do
			if costs[i] == nil and hz.ConnectorWalk(from, point) then
				-- a reverse batch costs the walk from the target, which on directed maps is not the walk back
				local cost = run(map, reverse and point or from, reverse and from or point, waterWalking, true, nil)
				if cost then
					costs[i] = cost
					if job then
						job.revision = job.revision + 1
					end
				end
			end
		end
	end
	local swim, cost2 = waterWalking and 1 or st.swim, waterWalking and 2 or 1
	local roadsOn = hz and hz.roads
	local starts, source, sourceReal, _, sourceIn, sourceInReal =
		connectPoint(st, swim, sk, sc, from.z, roadsOn, hz, reverse)
	local clusters, links, dist, real, closed, left = {}, {}, {}, {}, {}, #targets
	for i, point in ipairs(targets) do
		local k = locate(st, point.x, point.y)
		if costs[i] ~= nil then
			left = left - 1
		elseif k then
			clusters[k] = clusters[k] or {}
			clusters[k][#clusters[k] + 1] = i
		else
			costs[i], left = false, left - 1
		end
	end
	hn = 0
	local function relax(id, cost, realCost)
		if not dist[id] or cost < dist[id] then
			dist[id], real[id] = cost, realCost
			push(cost, id)
		end
	end
	local function prepare(k)
		local list = clusters[k]
		if not list then
			return
		end
		clusters[k] = nil
		-- Local searches need their own heap, including across a yield midway through a connection.
		local keys, values, size = hk, hv, hn
		hk, hv, hn = {}, {}, 0
		local direct, directReal, ends, realEnds = {}, {}, {}, {}
		for _, i in ipairs(list) do
			local _, node = pointNode(st, targets[i])
			if node then
				local goals
				-- A forward batch costs a walk into each target, so a drop is not climbed to reach it; a reverse batch
				-- costs a walk out of it, and its meeting point is whatever reaches `from`.
				local into, intoReal
				goals, ends[i], realEnds[i], _, into, intoReal =
					connectPoint(st, swim, k, node, targets[i].z, roadsOn, hz, not reverse)
				if not reverse then
					ends[i], realEnds[i] = into, intoReal
				end
				for _, a in ipairs(k == sk and starts or {}) do
					for _, b in ipairs(goals) do
						-- Both trees search outward from their endpoint; a reverse batch walks to the source. A local
						-- walk ends on the surface the point stands on, never on where the outbound rescue moved it.
						local first, last, tree = a.node, b.own, a.tree
						if reverse then
							first, last, tree = b.node, a.own, b.tree
						end
						local cost, realCost
						if first == last then
							cost, realCost = 0, 0
						elseif tree and reached(tree, last) then
							cost, realCost = tree.g[last + 1], tree.r[last + 1]
						elseif
							search(st, k, swim, first, trees.R, last, nil, nil, roadsOn and Grid.roads(st, k), hz)
						then
							cost, realCost = trees.R.g[last + 1], trees.R.r[last + 1]
						end
						if cost and (not direct[i] or cost < direct[i]) then
							direct[i], directReal[i] = cost, realCost
						end
					end
				end
			else
				costs[i], left = false, left - 1
				if job then
					job.revision = job.revision + 1
				end
			end
		end
		hk, hv, hn = keys, values, size
		for i, cost in pairs(direct) do
			relax(-i, cost, directReal[i])
		end
		for i, edges in pairs(ends) do
			local reals = realEnds[i]
			for id, cost in pairs(edges) do
				links[id] = links[id] or {}
				local joined = links[id]
				joined[#joined + 1], joined[#joined + 2], joined[#joined + 3] = -i, cost, reals[id]
			end
		end
	end
	prepare(sk)
	-- A reverse batch costs a walk into `from`, so it starts from the entrances that reach it and follows the edges
	-- that lead there.
	local seed, seedReal = (reverse and sourceIn) or source, (reverse and sourceInReal) or sourceReal
	for id, cost in pairs(seed) do
		relax(id, cost, seedReal[id])
	end
	while hn > 0 and left > 0 do
		-- Until the popped node's outgoing edges are relaxed, its key still bounds the frontier.
		if job then
			job.radius = hk[1]
		end
		local u = pop()
		if not closed[u] then
			closed[u] = true
			if u < 0 then
				costs[-u], left = real[u], left - 1
				if job then
					job.revision = job.revision + 1
				end
			else
				local k = floor(u / 4096)
				prepare(k)
				local ends = links[u]
				for i = 1, ends and #ends or 0, 3 do
					relax(ends[i], dist[u] + ends[i + 1], real[u] + ends[i + 2])
				end
				nodesOf(st, k)
				local adj = reverse and preceding(st, u) or adjacent(st, u)
				-- a reverse search over format 2 walks the edges into u, whose ratios are their sources' outbound ones;
				-- format 1's symmetric graph keeps the outbound list as it shipped
				local ratios = roadsOn
						and (reverse and st.fmt >= 2 and Grid.roadEdgesIn(st, u) or Grid.roadEdges(st, u))
					or nil
				for e = 1, #adj, 3 do
					local v = adj[e]
					if not closed[v] then
						local yards = adj[e + cost2]
						local factor = hz and hazard(st, hz, u, v) or 1
						if ratios then
							local ei, m = (e + 2) / 3, cost2 == 2 and 2 or 0
							relax(
								v,
								dist[u] + yards * ratios[ei * 4 - 3 + m] * factor,
								real[u] + yards * ratios[ei * 4 - 2 + m]
							)
						else
							relax(v, dist[u] + yards * factor, real[u] + yards)
						end
					end
				end
			end
		end
		if job then
			job.radius = hn > 0 and hk[1] or huge
		end
		tick()
	end
	for i = 1, #targets do
		if costs[i] == nil then
			costs[i] = false
		end
	end
	return costs
end

-- Does this cluster's grid contain water? Walking with water walking and swimming costs the same over a grid with
-- none, so the bake can answer both modes from one search.
local function wetCluster(st, k)
	local val = grid(st, k)
	if not val then
		return true
	end
	for i = 1, st.C * st.C do
		if val[i] == 2 then
			return true
		end
	end
	return false
end

-- The bake relaxes hundreds of thousands of edges against one cluster's roads. Its sparse set (only road cells) reads
-- as a hash lookup there, so expand it to a dense array once per cluster.
local function denseRoads(st, road)
	local set = {}
	for cell = 0, st.C * st.C - 1 do
		set[cell] = road[cell] == true
	end
	return set
end

-- Bake RoadEdges.lua: each entrance graph edge's road ratios, four base64 symbols per non-default edge, or a
-- default run as "=" and its length in two symbols. Only the bake tool calls this.
---@param map number
---@return table<number, string>
function Path.BakeRoadEdges(map)
	Deadline(huge)
	local st = State(map)
	local out = {}
	if not st then
		return out
	end
	local function ratioQ(value)
		local q = floor((value - 1) / (OFFROAD - 1) * 63 + 0.5)
		if q < 0 then
			return 0
		elseif q > 63 then
			return 63
		end
		return q
	end
	local function ratio(value)
		if value < 1 then
			return 1
		elseif value > OFFROAD then
			return OFFROAD
		end
		return value
	end
	for k = 0, st.D.nx * st.ny - 1 do
		local nodes = nodesOf(st, k)
		if #nodes > 0 then
			local road = Grid.roads(st, k)
			local wet, roadDense
			local parts, defaults, any = {}, 0, false
			local function flush()
				while defaults > 0 do
					local n = defaults > 4095 and 4095 or defaults
					parts[#parts + 1] = "="
						.. ALPHABET:sub(floor(n / 64) + 1, floor(n / 64) + 1)
						.. ALPHABET:sub(n % 64 + 1, n % 64 + 1)
					defaults = defaults - n
				end
			end
			for _, u in ipairs(nodes) do
				local adj = adjacent(st, u)
				local degree = #adj / 3
				local uNode = entrance(st, u)
				local targets, left = {}, 0
				if road and uNode then
					for e = 1, degree do
						local v = adj[e * 3 - 2]
						if floor(v / 4096) == k then
							local target = entrance(st, v)
							if target and not targets[target] then
								targets[target], left = true, left + 1
							end
						end
					end
				end
				local searches
				if left > 0 then
					if wet == nil then
						wet = st.swim ~= 1 and wetCluster(st, k)
					end
					roadDense = roadDense or denseRoads(st, road)
					searches = {}
					local tree = bakeTrees[1]
					search(st, k, st.swim, uNode, tree, nil, targets, left, roadDense)
					searches[1] = tree
					if wet then
						tree = bakeTrees[2]
						search(st, k, 1, uNode, tree, nil, targets, left, roadDense)
					end
					searches[2] = tree
				end
				for e = 1, degree do
					local v = adj[e * 3 - 2]
					local c1, c2 = adj[e * 3 - 1], adj[e * 3]
					local target = entrance(st, v)
					local q1, q2, q3, q4
					if floor(v / 4096) == k then
						if searches and target then
							local tree = searches[1]
							if c1 == 0 or not reached(tree, target) then
								q1, q2 = 63, 0
							else
								q1, q2 = ratioQ(ratio(tree.g[target + 1] / c1)), ratioQ(ratio(tree.r[target + 1] / c1))
							end
							tree = searches[2]
							if c2 == 0 or not reached(tree, target) then
								q3, q4 = 63, 0
							else
								q3, q4 = ratioQ(ratio(tree.g[target + 1] / c2)), ratioQ(ratio(tree.r[target + 1] / c2))
							end
						else
							q1, q2, q3, q4 = 63, 0, 63, 0
						end
					else
						local on = false
						if target then
							local other = Grid.roads(st, floor(v / 4096))
							local cell = metadata(st, v)
							on = other and cell and other[cell] or false
						end
						if c1 == 0 then
							q1, q2 = 63, 0
						else
							q1, q2 = on and 0 or 63, 0
						end
						if c2 == 0 then
							q3, q4 = 63, 0
						else
							q3, q4 = on and 0 or 63, 0
						end
					end
					if q1 == 63 and q2 == 0 and q3 == 63 and q4 == 0 then
						defaults = defaults + 1
					else
						flush()
						any = true
						parts[#parts + 1] = ALPHABET:sub(q1 + 1, q1 + 1)
							.. ALPHABET:sub(q2 + 1, q2 + 1)
							.. ALPHABET:sub(q3 + 1, q3 + 1)
							.. ALPHABET:sub(q4 + 1, q4 + 1)
					end
				end
			end
			flush()
			if any then
				out[k] = table.concat(parts)
			end
		end
	end
	return out
end

-- Eight-direction grid distance is a lower bound even across clusters. Costs omit snapping and height
-- and round each abstract edge to yards. Each endpoint can snap
-- SNAP cells and then move SNAP more off a ledge; each nonzero grid step is at least cs before rounding.
-- This bound is in running yards for both water modes, before the planner divides by walkSpeed.
---@param map number
---@param from SPFPoint
---@param to SPFPoint
---@return number
function Path.LowerBound(map, from, to)
	---@type SPFNavData?
	local D = ShortestPathForeverPathData and ShortestPathForeverPathData[map]
	-- Unloaded maps need no synchronous addon load just to publish an admissible preview.
	if not D then
		return 0
	end
	local cs = TILE / D.cells
	local dx, dy = abs(from.x - to.x), abs(from.y - to.y)
	local gap = dx > dy and dx + (SQRT2 - 1) * dy or dy + (SQRT2 - 1) * dx
	return max(0, gap - (4 * SNAP + 1) * SQRT2 * cs) * max(0, 1 - 0.5 / cs)
end

---@param job SPFPathJob?
---@param point SPFPoint
---@return boolean
function Path.ReuseMany(job, point)
	if not job or job.map ~= point.map or not job.sourceNode then
		return false
	end
	local from = job.from
	if (from.x - point.x) ^ 2 + (from.y - point.y) ^ 2 > 9 or (from.z and point.z and abs(from.z - point.z) > ZTOL) then
		return false
	end
	local st = State(job.map)
	if not st then
		return false
	end
	-- Asked from a batch's callback, where the client may be inside a C call no yield crosses: the endpoint's cluster
	-- is decoded whole to answer, never sliced (#803).
	local k, node = Grid.Quiet(pointNode, st, point)
	return k == job.sourceCluster and node == job.sourceNode
end

local function start(job)
	if job.notify then
		local owner = job.owner
		if not owner.cancelled then
			job.notify(job.points, job.cost, owner)
		end
		return
	end
	Expansions(0)
	if job.targets then
		return runMany(job.map, job.from, job.targets, job.waterWalking, job.reverse, job, job.hazards)
	end
	return run(job.map, job.from, job.to, job.waterWalking, job.costOnly, job.hazards)
end

local spare
local function scratch(saved)
	local previous = { hk, hv, hn, trees, ag, areal, apar, astamp, aclosed, agen }
	if not saved and spare then
		saved, spare = spare, nil
		saved[3] = 0
	end
	if saved then
		hk, hv, hn, trees = saved[1], saved[2], saved[3], saved[4]
		ag, areal, apar, astamp, aclosed, agen = saved[5], saved[6], saved[7], saved[8], saved[9], saved[10]
	else
		hk, hv, hn = {}, {}, 0
		trees = { S = Tree(), G = Tree(), R = Tree() }
		ag, areal, apar, astamp, aclosed, agen = {}, {}, {}, {}, {}, 0
	end
	return previous
end

-- Synchronous search, for tests and tools. Returns points, cost (or nil, reason) and the expansion count.
---@param map number
---@param from SPFPoint
---@param to SPFPoint
---@param waterWalking? boolean
---@param hazards? SPFHazards
function Path.FindSync(map, from, to, waterWalking, hazards)
	Deadline(huge)
	local job = { map = map, from = from, to = to, waterWalking = waterWalking, hazards = hazards }
	local co = coroutine.create(start)
	local saved = scratch()
	local ok, points, cost = coroutine.resume(co, job)
	scratch(saved)
	if not ok then
		error(points)
	end
	return points, cost, Expansions()
end

-- Costs indexed like targets, false for unreachable/off-mesh points; no geometry is built. reverse returns
-- target -> from costs, including the directed same-cluster water step: format 2's abstract edges are directed.
---@param map number
---@param from SPFPoint
---@param targets SPFPoint[]
---@param waterWalking? boolean
---@param reverse? boolean
---@param hazards? SPFHazards
function Path.FindManySync(map, from, targets, waterWalking, reverse, hazards)
	Deadline(huge)
	Expansions(0)
	local saved = scratch()
	local costs, reason = runMany(map, from, targets, waterWalking, reverse, nil, hazards)
	scratch(saved)
	return costs, reason, Expansions()
end

-- PathJobs.lua resumes start in a coroutine between scratch swaps; a finished search's scratch is kept as spare.
---@class SPFPathSearch
ns.PathSearch = {
	start = start,
	scratch = scratch,
	Spare = function(saved)
		spare = saved
	end,
}

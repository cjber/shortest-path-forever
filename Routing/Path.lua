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
local toward, peak, climbNodes = Grid.toward, Grid.peak, Grid.climbNodes

local TILE, SNAP, ZTOL, DX, DY = Grid.TILE, Grid.SNAP, Grid.ZTOL, Grid.DX, Grid.DY
local OFFROAD, FREE = Grid.OFFROAD, Grid.FREE

-- Baked ratios contain both the 1.5-weighted cost and the real cost of the baked road walk.
-- Their difference is the off-road part times 0.5. Reweight that part only; ETA keeps the real ratio.
local function roadChoice(choice, real, factor)
	if factor == OFFROAD then
		return choice -- keep the existing default's arithmetic exactly
	end
	return real + (choice - real) * (factor - 1) / (OFFROAD - 1)
end
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
	local offroad = hz and hz.roadFactor or OFFROAD
	-- No road record means unpainted ground; it does not switch the preference off.
	local roadsOn = hz and hz.roads and offroad ~= 1
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
	local function relax(v, length, override, free)
		-- Forward walks u -> v; a reverse tree walks the stored edge the other way, v -> u, into the source. A step
		-- the bake's walk decided is taken as written.
		if steep and not free then
			local distance = (length or 1) * cs
			if reverse then
				if not steep(val, z, v, val, z, u, distance) then
					return
				end
			elseif not steep(val, z, u, val, z, v, distance) then
				return
			end
		end
		local i = v + 1
		-- A step is charged for the cell it enters, whichever way the tree walks it: water, Follow roads and a
		-- hazard profile's weight are all properties of that cell.
		local entered = reverse and u or v
		local step = override or length * cs * (val[entered + 1] == 2 and swim or 1)
		local base = entered < N and entered or at[entered + 1]
		local choice = roadsOn and step * (1 + (offroad - 1) * (1 - (roads and roads[base] or 0))) or step
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
								local cost, free = floor(entry / 16384) % 8192, entry >= FREE
								if cost > 0 then
									relax(v, nil, cost, free)
								else
									relax(v, (tx ~= ux and ty ~= uy) and SQRT2 or 1, nil, free)
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
	if reverse and st.fmt < 2 and not (roadsOn and hz and hz.roadFactor and hz.roadFactor ~= OFFROAD) then
		reverse = nil -- preserve the legacy/default cache; custom road costs depend on the entered cell
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

-- A baked shortcut chose its interior walk at OFFROAD. A different preference
-- needs new entrance costs before the abstract search chooses its next cluster.
-- Reuse endpoint vectors, including their profile and direction cache keys.
local function customRoadEdges(st, swim, u, hz, reverse)
	local keys, values, size = hk, hv, hn
	hk, hv, hn = {}, {}, 0
	local k = floor(u / 4096)
	local node = entrance(st, u)
	local edges, reals = {}, {}
	if node then
		local _
		_, edges, reals = connect(st, swim, k, node, true, hz, reverse)
	end
	hk, hv, hn = keys, values, size
	return edges, reals
end

-- The surfaces a point stands on: its snapped node, or for a point without a height every distinct surface within
-- a cell of it, dry before water, narrowed by the player's height band.
local function surfaces(st, k, node, point)
	local nodes = { node }
	if not point.z then
		local values = grid(st, k)
		assert(values)
		local C, val, z, at = st.C, values, st.z[k], st.at[k]
		local cell = cellOf(st, k, node)
		local lx, ly = floor(cell / C), cell % C
		-- A pier's planks stand over the water: the base surface at the point's spot is the water, and the planks
		-- are a floor six to eight yards above it. Take every surface within a cell, then choose the dry ones first:
		-- a dry surface within ZTOL replaces an already-taken water node at the same spot, so a walk from a pier
		-- starts on its planks rather than in the water below (#889).
		local candidates = {}
		for r = 0, 1 do
			for dx = -r, r do
				for dy = -r, r do
					local x, y = lx + dx, ly + dy
					if (dx == r or dx == -r or dy == r or dy == -r) and x >= 0 and y >= 0 and x < C and y < C then
						local c = x * C + y
						if val[c + 1] ~= 0 then
							candidates[#candidates + 1] = { n = c, r = r, wet = val[c + 1] == 2 }
						end
						local n = at[-(c + 1)]
						while n and at[n + 1] == c do
							candidates[#candidates + 1] = { n = n, r = r, wet = val[n + 1] == 2 }
							n = n + 1
						end
					end
				end
			end
		end
		local taken = {}
		local function take(candidate)
			local n, r = candidate.n, candidate.r
			-- A neighbour's water is where the point is not: it would be standing in it.
			if r > 0 and candidate.wet then
				return
			end
			for index, m in ipairs(taken) do
				if abs(z[n + 1] - z[m + 1]) <= ZTOL then
					if not candidate.wet and val[m + 1] == 2 then
						taken[index] = n
					end
					return
				end
			end
			taken[#taken + 1] = n
		end
		-- Two passes rather than a sort: every dry surface is considered before any water at the same spot, so the
		-- planks on a pier win over the water under them without reordering the handful of candidates.
		for _, candidate in ipairs(candidates) do
			if not candidate.wet then
				take(candidate)
			end
		end
		for _, candidate in ipairs(candidates) do
			if candidate.wet then
				take(candidate)
			end
		end
		nodes = taken
		local band = point.band
		if band and ns.Band then
			local inside = {}
			for _, n in ipairs(nodes) do
				if ns.Band.Holds(band, z[n + 1]) then
					inside[#inside + 1] = n
				end
			end
			if #inside > 0 then
				nodes = inside
			end
		end
	end
	return nodes
end

-- A point without a height (the player, whose UnitPosition height is a placeholder 0, or a map click) could stand on
-- any surface at its spot, so it starts from each one within a cell of it at a distinct height and the search keeps
-- the cheapest: a street beside or over a canal is not walked from the canal bed. The player's measured height band
-- (Band.lua) narrows those surfaces to the ones they can be standing on; a band that fits none of them is no
-- measurement and every surface stays, exactly as a point with no band. Returns each surface's connection, the
-- entrance costs merged by minimum and, per entrance, the surface it came from. inbound returns the costs into the
-- point instead, which is what a goal needs, in the fifth to seventh places, and leaves the outbound ones empty: each
-- caller walks a point one way, and on format 2 the other way is a second grid search. The surfaces themselves are
-- returned too: a walk drawn or searched to a point ends on them, never on wherever the outbound rescue moved it.
local function connectPoint(st, swim, k, node, point, roadsOn, hz, inbound)
	local nodes = surfaces(st, k, node, point)
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
local function clearEnd(st, P, j, point, outbound, water, limit, budget, real)
	local fx, fy, k, node = own(st, point)
	local cx, cy = P.x[j] + 0.5, P.y[j] + 0.5
	if outbound and node then
		local tk, tn, time = toward(st, P, k, node, fx, fy, cx, cy, water, limit, budget, real, P.k[j], P.n[j])
		return tk == P.k[j] and tn == P.n[j], time
	end
	-- With no start surface this reverse legality check cannot establish a directed outbound reference.
	-- Keep the assembled fallback, but do not authorize an optional shortcut from an unmeasured connector.
	if outbound and real then
		return false
	end
	local tk, tn, time = toward(st, P, P.k[j], P.n[j], cx, cy, fx, fy, water, limit, budget, real, k, node)
	if not tk then
		return tn == true, time
	end
	return not node or (tk == k and tn == node), time
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
	local tk, tn = toward(st, P, k, node, fx, fy, tx, ty, water, limit, budget, nil, gk, goal)
	if not tk then -- a goal with no surface in its cell, reached across cells with none, as clearEnd allows
		return tn == true
	end
	return not goal or (tk == gk and tn == goal)
end

-- The largest factor a hazard profile charges over path entries first..last, or nil without a profile: a drawn segment
-- may cross no cell charged more than the walk it replaces.
local function limitOver(P, first, last)
	return P.factor and peak(P, P.factor, first, last, 1)
end

-- Sliced A* and refinement share scratch trees; splitting adds hot-path calls and upvalues
local function run(map, from, to, waterWalking, costOnly, hz, job)
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
	if not costOnly then
		Grid.Hold(job, st, sk)
		Grid.Hold(job, st, gk)
	end
	sc, gc = snap(st, sk, sc, from.x, from.y, from.z), snap(st, gk, gc, to.x, to.y, to.z)
	if not sc or not gc then
		return nil, "offmesh"
	end
	-- A start at a known height on a surface the goal can stand on walks nowhere: a map click on a flight master is
	-- probed from that flight master. The search below answers 0 for it too, after connecting both ends to their
	-- cluster, which is most of a probe's time (#1080).
	if costOnly and from.z and sk == gk then
		for _, n in ipairs(surfaces(st, gk, gc, to)) do
			if n == sc then
				return 0
			end
		end
	end
	local C = st.C
	local roadsOn = hz and hz.roads and hz.roadFactor ~= 1
	local offroad = hz and hz.roadFactor or OFFROAD

	local S, G = trees.S, trees.G
	local starts, source, sourceReal, sourceVia = connectPoint(st, swim, sk, sc, from, roadsOn, hz)
	-- The goal's costs are the walks into it, so a ledge drop is not climbed to reach it. A local walk to it ends on
	-- the surfaces it stands on, not on wherever the outbound rescue moved it.
	local _, _, _, _, target, targetReal, targetVia, goalOwn = connectPoint(st, swim, gk, gc, to, roadsOn, hz, true)
	local key = table.concat({
		sk,
		sc,
		gk,
		gc,
		swim,
		from.z and 1 or 0,
		to.z and 1 or 0,
		hz and hz.key or "",
		from.band and string.format("%.1f:%.1f", from.band.lo, from.band.hi) or "",
		to.band and string.format("%.1f:%.1f", to.band.lo, to.band.hi) or "",
	}, ":")
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
			if component then
				comps[component] = true
			end
		end
		for id in pairs(target) do
			nodesOf(st, floor(id / 4096))
			local _, _, component = metadata(st, id)
			shared = shared or (component ~= nil and comps[component])
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
				local adj = adjacent(st, u, roadsOn == true)
				local ratios = roadsOn and Grid.roadEdges(st, u) or nil
				local custom, customReal
				if roadsOn and offroad ~= OFFROAD then
					custom, customReal = customRoadEdges(st, swim, u, hz)
				end
				for e = 1, #adj, 3 do
					local v = adj[e]
					if aclosed[v] ~= gen and climbNodes(st, u, v) then
						nodesOf(st, floor(v / 4096))
						local yards = adj[e + cost2]
						local factor = hz and hazard(st, hz, u, v) or 1
						if custom and floor(v / 4096) == floor(u / 4096) then
							if custom[v] then
								relax(v, gu + custom[v], ru + customReal[v], u)
							end
						elseif ratios then
							local ei, m = (e + 2) / 3, cost2 == 2 and 2 or 0
							relax(
								v,
								gu
									+ yards
										* roadChoice(ratios[ei * 4 - 3 + m], ratios[ei * 4 - 2 + m], offroad)
										* factor,
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

	for _, hop in ipairs(hops) do
		if hop ~= START and hop ~= GOAL then
			Grid.Hold(job, st, floor(hop / 4096))
		end
	end

	-- Refine each hop into nodes with their global cells and a running count of water nodes. The pruned entrance
	-- graph may route through an entrance a little off the way, which refines to a spur walked out and back: a node
	-- reached again cuts the loop since its first visit, so the drawn walk never doubles back.
	---@type SPFPathPoints
	local P = { x = {}, y = {}, z = {}, w = {}, t = {}, k = {}, n = {}, swim = swim }
	if hz then
		P.factor = factorOf(st, hz)
	end
	if roadsOn then
		P.roads, P.r, P.roadFactor = true, {}, offroad
	end
	local seen = {}
	local function add(k, node)
		local id = k * 1048576 + node
		local at = seen[id]
		if at then
			for j = #P.x, at + 1, -1 do
				seen[P.k[j] * 1048576 + P.n[j]] = nil
				P.x[j], P.y[j], P.z[j], P.w[j], P.t[j], P.k[j], P.n[j] = nil, nil, nil, nil, nil, nil, nil
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
		P.z[n + 1] = st.z[k][node + 1]
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
	local n = #P.x
	local startOK, startTime = clearEnd(st, P, 1, from, true, P.w[1] > 0, limitOver(P, 1, 1), nil, true)
	local goalOK, goalTime =
		clearEnd(st, P, n, to, false, P.w[n] - (P.w[n - 1] or 0) > 0, limitOver(P, n, n), nil, true)
	-- P.t is the refined walk's real running-yard prefix, independent of reported/cached search cost.
	local chordBudget = startOK and goalOK and startTime + P.t[n] - P.t[1] + goalTime
	-- The end segments the line is drawn with, for the pull to measure and check as drawn.
	local function startClear(j)
		return clearEnd(st, P, j, from, true, P.w[j] > 0, limitOver(P, 1, j), startTime + P.t[j] - P.t[1])
	end
	local function goalClear(j)
		return clearEnd(
			st,
			P,
			j,
			to,
			false,
			P.w[n] - (P.w[j - 1] or 0) > 0,
			limitOver(P, j, n),
			P.t[n] - P.t[j] + goalTime
		)
	end
	local keep, startDetour, goalDetour = smooth(st, P, {
		sx = (from.x - x0) / cs,
		sy = (from.y - y0) / cs,
		gx = (to.x - x0) / cs,
		gy = (to.y - y0) / cs,
		start = startOK and startClear,
		goal = goalOK and goalClear,
		chord = function()
			return chordBudget and clearChord(st, P, from, to, P.w[n] > 0, limitOver(P, 1, n), chordBudget)
		end,
	})
	-- The pull chose whether each end is drawn through its end entry's centre: a start or goal segment that is not
	-- clear detours that way, so the rest of the line holds as it was pulled.
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
		points[#points + 1] = {
			map = map,
			x = x0 + (P.x[j] + 0.5) * cs,
			y = y0 + (P.y[j] + 0.5) * cs,
			z = P.z[j],
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

-- A goal no walk reaches from any place on its landmass moves to the nearest node those places do reach. In game such
-- a spot is a plateau ringed by faces past the player's slope and step limits, which nobody can walk onto (#1113): the
-- closest a player can stand is the honest end of the route. reach holds the entrances the places walk to; clusters
-- are tried nearest first until one starts farther away than the best node found.
local function nearestGround(st, swim, gk, gnode, reach)
	-- its own tree: a search can yield, and another job's search would overwrite a shared one meanwhile
	local tree = Tree()
	local C, cs, ny = st.C, st.cs, st.ny
	local nx, N = st.GX / C, C * C
	grid(st, gk)
	local cell = cellOf(st, gk, gnode)
	local cx, cy = floor(gk / ny), gk % ny
	local gx, gy, h = cx * C + floor(cell / C), cy * C + cell % C, st.z[gk][gnode + 1]
	-- the best node found, in grid cells and yards: a yield may evict its cluster before the search ends
	local best, bx, by, bz = huge, nil, nil, nil
	for r = 0, max(nx, ny) do
		-- every cluster on ring r starts at least r - 1 whole clusters away
		if r > 1 and ((r - 1) * C * cs) ^ 2 >= best then
			break
		end
		-- only ring r itself: its top and bottom rows, then the sides between them
		for side = 1, r == 0 and 1 or 4 do
			local n = side <= 2 and 2 * r + 1 or max(0, 2 * r - 1)
			for i = 0, n - 1 do
				local dx, dy
				if side == 1 then
					dx, dy = i - r, -r
				elseif side == 2 then
					dx, dy = i - r, r
				elseif side == 3 then
					dx, dy = -r, i - r + 1
				else
					dx, dy = r, i - r + 1
				end
				local kx, ky = cx + dx, cy + dy
				-- the cluster's nearest cell, in cells along each axis: no node in it is closer
				local ox = max(0, kx * C - gx, gx - kx * C - C + 1)
				local oy = max(0, ky * C - gy, gy - ky * C - C + 1)
				if kx >= 0 and ky >= 0 and kx < nx and ky < ny and (ox * cs) ^ 2 + (oy * cs) ^ 2 < best then
					local k = kx * ny + ky
					local val = grid(st, k)
					local seen = {}
					for _, id in ipairs(val and nodesOf(st, k) or {}) do
						local e = reach[id] and entrance(st, id)
						if e and not seen[e] then
							search(st, k, swim, e, tree, nil, nil, nil, nil, nil, false)
							-- the search may have yielded: read the cluster's heights and cells after it
							grid(st, k)
							local z, at = st.z[k], st.at[k]
							for v = 0, #val - 1 do
								if not seen[v] and reached(tree, v) then
									seen[v] = true
									local c = v < N and v or at[v + 1]
									local x, y = kx * C + floor(c / C), ky * C + c % C
									local d = ((x - gx) * cs) ^ 2 + ((y - gy) * cs) ^ 2 + (z[v + 1] - h) ^ 2
									if d < best then
										best, bx, by, bz = d, x, y, z[v + 1]
									end
								end
							end
						end
					end
				end
				tick()
			end
		end
	end
	return bx and { map = st.map, x = st.x0 + (bx + 0.5) * cs, y = st.y0 + (by + 0.5) * cs, z = bz }
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
	local swim, cost2 = waterWalking and 1 or st.swim, waterWalking and 2 or 1
	local roadsOn = hz and hz.roads and hz.roadFactor ~= 1
	local offroad = hz and hz.roadFactor or OFFROAD
	local starts, source, sourceReal, _, sourceIn, sourceInReal =
		connectPoint(st, swim, sk, sc, from, roadsOn, hz, reverse)
	-- A target's connection to its own cluster, made once: false when it stands on no node.
	local linked = {}
	local function link(i, k)
		if linked[i] == nil then
			local _, node = pointNode(st, targets[i])
			if node then
				-- A forward batch costs a walk into each target, so a drop is not climbed to reach it; a reverse batch
				-- costs a walk out of it, and its meeting point is whatever reaches `from`.
				local goals, ends, realEnds, _, into, intoReal =
					connectPoint(st, swim, k, node, targets[i], roadsOn, hz, not reverse)
				if not reverse then
					ends, realEnds = into, intoReal
				end
				linked[i] = { goals = goals, ends = ends, realEnds = realEnds }
			else
				linked[i] = false
			end
		end
		return linked[i]
	end
	-- A target on the source's own node is a transfer. Settle its zero before any other search, so a batch paused early
	-- still tells a transfer from a walk: once job.snapped is set, every unsettled target is a real walk away.
	-- connectPoint reuses the shared heap, which still holds the source connection's frontier.
	local heldKeys, heldValues, heldSize = hk, hv, hn
	hk, hv, hn = {}, {}, 0
	for i, point in ipairs(targets) do
		if costs[i] == nil and locate(st, point.x, point.y) == sk then
			local target = link(i, sk)
			for _, a in ipairs(target and starts or {}) do
				for _, b in ipairs(target and target.goals or {}) do
					if costs[i] == nil and (reverse and b.node or a.node) == (reverse and a.own or b.own) then
						costs[i] = 0
						if job then
							job.revision = job.revision + 1
						end
					end
				end
			end
		end
	end
	-- Both ends rescued onto one entrance at no cost are a transfer too, even from different clusters. Only a source
	-- with such an entrance needs the check, and only targets in that entrance's own cluster can share it: a point
	-- connects to its own cluster's entrances, and an entrance id names its cluster. The rest stay unlinked until the
	-- search reaches them.
	local zeros, zeroClusters = {}, {}
	for id, cost in pairs((reverse and sourceIn) or source) do
		if cost == 0 then
			zeros[id], zeroClusters[floor(id / 4096)] = true, true
		end
	end
	if next(zeros) then
		for i, point in ipairs(targets) do
			local k = costs[i] == nil and locate(st, point.x, point.y)
			local target = k and zeroClusters[k] and link(i, k)
			for id, cost in pairs(target and target.ends or {}) do
				if costs[i] == nil and cost == 0 and zeros[id] then
					costs[i] = 0
					if job then
						job.revision = job.revision + 1
					end
				end
			end
		end
	end
	hk, hv, hn = heldKeys, heldValues, heldSize
	if job then
		job.snapped = true
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
		local direct, directReal, ends, realEnds, goalsOf = {}, {}, {}, {}, {}
		for _, i in ipairs(list) do
			local target = link(i, k)
			if target then
				goalsOf[i], ends[i], realEnds[i] = target.goals, target.ends, target.realEnds
			else
				costs[i], left = false, left - 1
				if job then
					job.revision = job.revision + 1
				end
			end
		end
		for _, i in ipairs(list) do
			local goals = goalsOf[i]
			if goals then
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
				local adj = reverse and preceding(st, u, roadsOn == true) or adjacent(st, u, roadsOn == true)
				-- a reverse search over format 2 walks the edges into u, whose ratios are their sources' outbound ones;
				-- format 1's symmetric graph keeps the outbound list as it shipped
				local ratios = roadsOn
						and (reverse and st.fmt >= 2 and Grid.roadEdgesIn(st, u) or Grid.roadEdges(st, u))
					or nil
				local custom, customReal
				if roadsOn and offroad ~= OFFROAD then
					custom, customReal = customRoadEdges(st, swim, u, hz, reverse)
				end
				for e = 1, #adj, 3 do
					local v = adj[e]
					if not closed[v] and climbNodes(st, reverse and v or u, reverse and u or v) then
						local yards = adj[e + cost2]
						local factor = hz and hazard(st, hz, u, v) or 1
						if custom and floor(v / 4096) == k then
							if custom[v] then
								relax(v, dist[u] + custom[v], real[u] + customReal[v])
							end
						elseif ratios then
							local ei, m = (e + 2) / 3, cost2 == 2 and 2 or 0
							relax(
								v,
								dist[u]
									+ yards
										* roadChoice(ratios[ei * 4 - 3 + m], ratios[ei * 4 - 2 + m], offroad)
										* factor,
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
	local any = false
	for i = 1, #targets do
		if costs[i] == nil then
			costs[i] = false
		end
		any = any or costs[i] ~= false
	end
	local moved
	if reverse and not any then
		-- no target is settled yet, and the move below may take several frames: the batch is still running
		if job then
			job.radius = huge
		end
		-- Every entrance the targets walk to. Entrance-graph components join ground that is only walked downhill, so
		-- sharing one proves nothing: the walk is followed edge by edge, as the forward search would.
		-- The flood takes a cluster's entrances together, so each cluster's graph is decoded about once.
		local reach, pending, clusterQueue = {}, {}, {}
		local function add(id)
			if not reach[id] then
				reach[id] = true
				local k = floor(id / 4096)
				if not pending[k] then
					pending[k], clusterQueue[#clusterQueue + 1] = {}, k
				end
				pending[k][#pending[k] + 1] = id
			end
		end
		local head = 1
		local function drain()
			while clusterQueue[head] do
				local k = clusterQueue[head]
				head = head + 1
				local list = pending[k]
				pending[k] = nil
				nodesOf(st, k)
				local i = 1
				while list[i] do
					local u = list[i]
					i = i + 1
					local adj = adjacent(st, u, true)
					for e = 1, #adj, 3 do
						local v = adj[e]
						if not reach[v] and climbNodes(st, u, v) then
							if floor(v / 4096) == k then
								reach[v], list[#list + 1] = true, v
							else
								add(v)
							end
						end
					end
					tick()
				end
			end
		end
		local keys, values, size = hk, hv, hn
		hk, hv, hn = {}, {}, 0
		for _, point in ipairs(targets) do
			-- A target walks only to its own cluster's entrances: once the flood holds them all, it adds nothing. The walk
			-- is measured without the batch's hazards, which weigh a walk but never stop one.
			local k, node = pointNode(st, point)
			local covered = true
			for _, id in ipairs(node and nodesOf(st, k) or {}) do
				covered = covered and reach[id]
			end
			if node and not covered then
				local _, ends = connectPoint(st, swim, k, node, point, false, nil, false)
				for id in pairs(ends) do
					add(id)
				end
				drain()
			end
		end
		moved = head > 1 and nearestGround(st, swim, sk, sc, reach) or nil
		hk, hv, hn = keys, values, size
		if job then
			job.moved = moved
		end
	end
	return costs, nil, moved
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

-- A bake search walks one cluster's grid from each of its entrances in turn, so the work search() repeats for every
-- expansion (the move masks, the heights a step may not climb, the water each cell enters, whether the landing cell is
-- road) is resolved once per cluster instead: flat arrays hold, per exit, the node it reaches, its cost swimming and
-- water walking, and the preference multiplier a road cell changes. The order is search()'s: the base grid's eight
-- directions, then the cluster's explicit links, so equal costs settle in the same order and every ratio is unchanged.
---@return table<number, number>? flat, table<number, number>?
local function bakeEdges(st, k, road)
	local val = grid(st, k)
	if not val then
		return nil
	end
	local m, z, at, links = st.moves[k], st.z[k], st.at[k], st.links[k]
	local steep, fmt, C, cs, swim = st.steep, st.fmt, st.C, st.cs, st.swim
	local N = C * C
	-- Floor nodes follow the base cells; the highest one bounds the head table.
	local top = N
	for node in pairs(at) do
		if node > top then
			top = node
		end
	end
	local flat, head, size = {}, {}, 0
	local function add(from, v, length, override, free)
		if steep and not free and not steep(val, z, from, val, z, v, (length or 1) * cs) then
			return
		end
		local i = v + 1
		local step, wet
		if override then
			step, wet = override, override
		else
			local bare = length * cs
			step, wet = bare * (val[i] == 2 and swim or 1), bare
		end
		local base = v < N and v or at[i]
		size = size + 4
		flat[size - 3], flat[size - 2], flat[size - 1], flat[size] =
			v, step, wet, 1 + (OFFROAD - 1) * (1 - (road[base] or 0))
	end
	for node = 0, top - 1 do
		head[node + 1] = size + 1
		local i = node + 1
		if node < N then
			local mi = m[i] % 16
			local ux, uy = floor(node / C), node % C
			if val[i] ~= 0 then
				local px, mx = mi % 2 == 1, ux > 0 and m[i - C] % 2 == 1
				local py, my = mi % 4 >= 2, uy > 0 and m[i - 1] % 4 >= 2
				if px then
					add(node, node + C, 1)
				end
				if mx then
					add(node, node - C, 1)
				end
				if py then
					add(node, node + 1, 1)
				end
				if my then
					add(node, node - 1, 1)
				end
				if mi % 8 >= 4 then
					add(node, node + C + 1, SQRT2)
				end
				if mi >= 8 then
					add(node, node + C - 1, SQRT2)
				end
				if ux > 0 and uy > 0 and m[i - C - 1] % 8 >= 4 then
					add(node, node - C - 1, SQRT2)
				end
				if ux > 0 and uy < C - 1 and m[i - C + 1] % 16 >= 8 then
					add(node, node - C + 1, SQRT2)
				end
			end
		end
		local list = links[i]
		if list then
			local cell = node < N and node or at[i]
			local ux, uy = floor(cell / C), cell % C
			for e = 1, #list do
				local v, length, override, free
				local entry = list[e]
				if fmt >= 2 then
					-- the cell offset, the landing layer and the cost in whole yards (0 for an ordinary step)
					local tx, ty = ux + entry % 16 - 8, uy + floor(entry / 16) % 16 - 8
					if tx >= 0 and ty >= 0 and tx < C and ty < C then
						v = surface(st, k, tx * C + ty, floor(entry / 256) % 64 - 1, z[i], val, z, at)
						if v then
							local cost = floor(entry / 16384) % 8192
							free = entry >= FREE
							if cost > 0 then
								override = cost
							else
								length = (tx ~= ux and ty ~= uy) and SQRT2 or 1
							end
						end
					end
				else
					local d = entry % 8
					local tx, ty = ux + DX[d], uy + DY[d]
					if tx >= 0 and ty >= 0 and tx < C and ty < C then
						v = surface(st, k, tx * C + ty, floor(entry / 8) - 1, z[i], val, z, at)
						length = d >= 4 and SQRT2 or 1
					end
				end
				if v then
					add(node, v, length, override, free)
				end
			end
		end
	end
	head[top + 1] = size + 1
	return flat, head
end

-- One cluster's Dijkstra from a bake source, over bakeEdges' arrays, settling every target. It is search() with the
-- bake's fixed arguments (no goal, hazards or reverse) and its exits already resolved, on one of the bake's trees.
local function bakeSearch(tree, source, targets, left, flat, head, waterWalking)
	local g, r, stamp, closed = tree.g, tree.r, tree.stamp, tree.closed
	tree.gen = tree.gen + 1
	local gen = tree.gen
	hn = 0
	local i = source + 1
	g[i], r[i], stamp[i] = 0, 0, gen
	push(0, source)
	while hn > 0 do
		local u = pop()
		local ui = u + 1
		if closed[ui] ~= gen then
			closed[ui] = gen
			tick()
			if targets[u] then
				left = left - 1
				if left <= 0 then
					return
				end
			end
			local gu, ru = g[ui], r[ui]
			-- A node whose exits bakeEdges skipped has none.
			local stop = head[u + 2]
			if stop then
				local column = waterWalking and 2 or 1
				for e = head[u + 1], stop - 1, 4 do
					local v, vi = flat[e], flat[e] + 1
					local step = flat[e + column]
					local gv = gu + step * flat[e + 3]
					if stamp[vi] ~= gen or gv < g[vi] then
						g[vi], r[vi], stamp[vi] = gv, ru + step, gen
						push(gv, v)
					end
				end
			end
		end
	end
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
	-- Every edge asks for the node at one of its ends, and each cross-cluster edge asks after a neighbour's cluster:
	-- answer each id once so a bake decodes a cluster's grid once, however many edges point into it.
	local seen = {}
	local function nodeAt(id)
		local node = seen[id]
		if node == nil then
			node = entrance(st, id) or false
			seen[id] = node
		end
		return node or nil
	end
	for k = 0, st.D.nx * st.ny - 1 do
		local nodes = nodesOf(st, k)
		if #nodes > 0 then
			local road = Grid.roads(st, k)
			local flat, head, wet
			if road then
				flat, head = bakeEdges(st, k, road)
			end
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
				local uNode = nodeAt(u)
				local targets, left = {}, 0
				if road and uNode then
					for e = 1, degree do
						local v = adj[e * 3 - 2]
						if floor(v / 4096) == k then
							local target = nodeAt(v)
							if target and not targets[target] then
								targets[target], left = true, left + 1
							end
						end
					end
				end
				local dry, wetTree
				if left > 0 and flat then
					if wet == nil then
						wet = st.swim ~= 1 and wetCluster(st, k)
					end
					dry = bakeTrees[1]
					bakeSearch(dry, uNode, targets, left, flat, head)
					-- A grid with no water enters every cell at the same cost either way, so one tree answers both.
					wetTree = wet and bakeTrees[2] or dry
					if wet then
						bakeSearch(wetTree, uNode, targets, left, flat, head, true)
					end
				end
				for e = 1, degree do
					local v = adj[e * 3 - 2]
					local c1, c2 = adj[e * 3 - 1], adj[e * 3]
					local q1, q2, q3, q4
					if floor(v / 4096) == k then
						local target = nodeAt(v)
						if dry and target then
							if c1 == 0 or not reached(dry, target) then
								q1, q2 = 63, 0
							else
								q1, q2 = ratioQ(ratio(dry.g[target + 1] / c1)), ratioQ(ratio(dry.r[target + 1] / c1))
							end
							if c2 == 0 or not reached(wetTree, target) then
								q3, q4 = 63, 0
							else
								q3, q4 =
									ratioQ(ratio(wetTree.g[target + 1] / c2)), ratioQ(ratio(wetTree.r[target + 1] / c2))
							end
						else
							q1, q2, q3, q4 = 63, 0, 63, 0
						end
					else
						-- A cluster with no road cells answers false however its neighbour decodes, so the grid of a
						-- cross-cluster edge's far end is only read when that cluster paints roads.
						local coverage = 0
						local other = Grid.roads(st, floor(v / 4096))
						if other then
							-- A landing that the neighbour's grid cannot place is no road, as before.
							local cell = metadata(st, v)
							coverage = cell ~= nil and nodeAt(v) ~= nil and other[cell] or 0
						end
						if c1 == 0 then
							q1, q2 = 63, 0
						else
							q1, q2 = ratioQ(1 + (OFFROAD - 1) * (1 - coverage)), 0
						end
						if c2 == 0 then
							q3, q4 = 63, 0
						else
							q3, q4 = ratioQ(1 + (OFFROAD - 1) * (1 - coverage)), 0
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
---@param sliced? boolean asked from inside a path job, which may pause to decode the point's cluster
---@return boolean
function Path.ReuseMany(job, point, sliced)
	if not job or job.map ~= point.map or not job.sourceNode then
		return false
	end
	local from = job.from
	if (from.x - point.x) ^ 2 + (from.y - point.y) ^ 2 > 9 or (from.z and point.z and abs(from.z - point.z) > ZTOL) then
		return false
	end
	-- A start inside a different height band may have been settled on another surface.
	local one, other = from.band, point.band
	if (one or other) and not (one and other and one.lo == other.lo and one.hi == other.hi) then
		return false
	end
	local st = State(job.map)
	if not st then
		return false
	end
	if Grid.locate(st, point.x, point.y) ~= job.sourceCluster then
		return false
	end
	if sliced then
		local k, node = pointNode(st, point)
		return k == job.sourceCluster and node == job.sourceNode
	end
	-- Asked in the caller's frame, where the client may be inside a C call no yield crosses (#803): only a decoded
	-- cluster answers, since decoding one whole is a frame spike. The player's own cluster is normally decoded (Floor
	-- pins it); otherwise the batch is searched again, sliced.
	if not Grid.Ready(st, job.sourceCluster) then
		return false
	end
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
	return run(job.map, job.from, job.to, job.waterWalking, job.costOnly, job.hazards, job)
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
	Grid.Release(job)
	scratch(saved)
	if not ok then
		error(points)
	end
	return points, cost, Expansions()
end

-- Costs indexed like targets, false for unreachable/off-mesh points; no geometry is built. reverse returns
-- target -> from costs, including the directed same-cluster water step: format 2's abstract edges are directed. A
-- reverse batch none of whose targets reaches from also returns the nearest point they do reach, when there is one.
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
	local costs, reason, moved = runMany(map, from, targets, waterWalking, reverse, nil, hazards)
	scratch(saved)
	return costs, reason, Expansions(), moved
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

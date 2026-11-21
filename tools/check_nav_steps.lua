-- Every shipped walking map: a step the bake joined both ways on ordinary ground must be walkable both ways at
-- runtime. The bake links two neighbouring surfaces only the ways the navmesh walks between them, and that navmesh
-- holds the player's slope and step limits, so a two-way link the runtime refuses one way is a wrong stored value
-- or a runtime rule judging what the bake already judged (#1011: a tunnel floor stored a poly centroid's height, and
-- the 50 degree height test turned the Dun Algaz pass one-way). Steep ground is exempt: it is walked down only.
-- Usage: luajit tools/check_nav_steps.lua [map ...]   (default: every map Nav/Nav.xml lists)
-- SPF_STEPS_ALL=1 lists every failure rather than the first 20.

local maps = {}
for i = 1, #arg do
	maps[#maps + 1] = tonumber(arg[i])
end
if #maps == 0 then
	for line in io.lines("Nav/Nav.xml") do
		local m = line:match('file="Nav(%d+)%.lua"')
		if m then
			maps[#maps + 1] = tonumber(m)
		end
	end
end

-- PathGrid keeps its decoder local; expose the pieces this check walks with, without changing the shipped file.
local source = assert(io.open("Routing/PathGrid.lua")):read("*a")
source = source
	.. "\nlocal function neighbour(st, k, node, gx, gy, dx, dy, water)"
	.. "\n\tlocal ks, ns2 = {}, {}"
	.. "\n\tif neighbours(st, k, node, gx, gy, dx, dy, water, ks, ns2) > 0 then return ks[1], ns2[1] end"
	.. "\nend"
	.. "\nns.StepCheck = { State = State, grid = grid, neighbour = neighbour, cellOf = cellOf, states = states }\n"

local failures = 0
for _, map in ipairs(maps) do
	local ns = {}
	assert(loadfile("tools/load_nav.lua"))(map)
	assert(loadstring(source, "@Routing/PathGrid.lua"))("ShortestPathForever", ns)
	local P = ns.StepCheck
	ns.Path.cacheKB = 1e9 -- clusters are walked in order and released below, not evicted mid-walk
	local st = P.State(map)
	local C, steep = st.C, st.steep
	local clusters = st.GX / C * st.ny
	local checked, bad = 0, {}

	-- Raw: the bake's own link, before any height test.
	local function raw(k, node, gx, gy, dx, dy)
		st.steep = nil
		local tk, tn = P.neighbour(st, k, node, gx, gy, dx, dy, false)
		st.steep = steep
		return tk, tn
	end

	-- A diagonal walks through one of its corner cells; steep ground there refuses it uphill by design.
	local function steepCorner(gx, gy, dx, dy)
		if dx == 0 or dy == 0 then
			return false
		end
		for _, c in ipairs({ { gx + dx, gy }, { gx, gy + dy } }) do
			local ck = math.floor(c[1] / C) * st.ny + math.floor(c[2] / C)
			local v = P.grid(st, ck)
			if v and v[(c[1] % C) * C + c[2] % C + 1] == 3 then
				return true
			end
		end
		return false
	end

	for k = 0, clusters - 1 do
		local val = P.grid(st, k)
		if val then
			local kx, ky = math.floor(k / st.ny) * C, (k % st.ny) * C
			for node = 0, #val - 1 do
				local v = val[node + 1]
				if v == 1 then
					local lc = P.cellOf(st, k, node)
					local gx, gy = kx + math.floor(lc / C), ky + lc % C
					for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }) do
						local dx, dy = d[1], d[2]
						local tk, tn = raw(k, node, gx, gy, dx, dy)
						if tk and P.grid(st, tk) and st.val[tk][tn + 1] == 1 then
							local bk, bn = raw(tk, tn, gx + dx, gy + dy, -dx, -dy)
							if bk == k and bn == node then
								checked = checked + 1
								local fk, fn = P.neighbour(st, k, node, gx, gy, dx, dy, false)
								local rk, rn = P.neighbour(st, tk, tn, gx + dx, gy + dy, -dx, -dy, false)
								if
									(fk ~= tk or fn ~= tn or rk ~= k or rn ~= node) and not steepCorner(gx, gy, dx, dy)
								then
									bad[#bad + 1] = string.format(
										"(%.1f, %.1f) z%d <-> (%.1f, %.1f) z%d",
										st.x0 + (gx + 0.5) * st.cs,
										st.y0 + (gy + 0.5) * st.cs,
										st.z[k][node + 1],
										st.x0 + (gx + dx + 0.5) * st.cs,
										st.y0 + (gy + dy + 0.5) * st.cs,
										st.z[tk][tn + 1]
									)
								end
							end
						end
					end
				end
			end
		end
		-- Release decoded clusters so the walk over a continent stays within memory.
		if k % 64 == 63 then
			for c in pairs(st.val) do
				st.val[c], st.moves[c], st.z[c], st.at[c], st.links[c], st.linksIn[c] = nil, nil, nil, nil, nil, nil
			end
		end
	end
	print(
		string.format("map %d: %d two-way steps on ordinary ground, %d refused one way at runtime", map, checked, #bad)
	)
	for i = 1, os.getenv("SPF_STEPS_ALL") and #bad or math.min(#bad, 20) do
		print("  " .. bad[i])
	end
	failures = failures + #bad
end
if failures > 0 then
	io.stderr:write(string.format("%d two-way steps are refused one way at runtime\n", failures))
	os.exit(1)
end

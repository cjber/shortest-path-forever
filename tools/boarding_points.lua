-- Offline boarding endpoints from the bundled walking map, separate from transport stop positions.
local ns = {}
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
local G, loaded = ns.PathGrid, {}
local index = 0
for line in io.lines() do
	index = index + 1
	local m, x, y, z = line:match("^(%S+) (%S+) (%S+) (%S+)$")
	m, x, y, z = tonumber(m), tonumber(x), tonumber(y), tonumber(z)
	if not loaded[m] then
		assert(loadfile("tools/load_nav.lua"))(m)
		loaded[m] = true
	end
	local st = G.State(m)
	local best, distance
	if st then
		local gx, gy = math.floor((x - st.x0) / st.cs), math.floor((y - st.y0) / st.cs)
		local radius = math.ceil(64 / st.cs)
		for dx = -radius, radius do
			for dy = -radius, radius do
				local px, py = st.x0 + (gx + dx + 0.5) * st.cs, st.y0 + (gy + dy + 0.5) * st.cs
				local k, c = G.locate(st, px, py)
				if k and G.grid(st, k) then
					local function consider(n)
						local height = st.z[k][n + 1]
						local d = (px - x) ^ 2 + (py - y) ^ 2
						if
							st.val[k][n + 1] == 1
							and math.abs(height - z) <= G.ZTOL
							and d <= 64 ^ 2
							and (not distance or d < distance)
						then
							best, distance = { px, py, height }, d
						end
					end
					consider(c)
					local n = st.at[k][-(c + 1)]
					while n and st.at[k][n + 1] == c do
						consider(n)
						n = n + 1
					end
				end
			end
		end
	end
	if best then
		print(string.format("%d { map = %d, x = %.1f, y = %.1f, z = %.1f }", index, m, best[1], best[2], best[3]))
	else
		print(index .. " nil")
	end
end

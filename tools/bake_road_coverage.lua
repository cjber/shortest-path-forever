-- Match recorded trail heights to the same Nav surfaces the runtime walks.
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local digits = {}
for i = 1, #alphabet do
	digits[alphabet:byte(i)] = i - 1
end

local function num(s, i)
	local a, b, c = s:byte(i, i + 2)
	return digits[a] * 4096 + digits[b] * 64 + digits[c]
end

local function digit(n)
	return alphabet:sub(n + 1, n + 1)
end

return function(Grid, map, trails)
	local st, coverage = Grid.State(map), {}
	for cluster, trail in pairs(trails) do
		local k = cluster - 1
		if Grid.grid(st, k) then
			local paint, at = Grid.roads(st, k) or {}, st.at[k]
			local nodes = {}
			for i = 1, #trail, 6 do
				local cell, level = num(trail, i), num(trail, i + 3)
				local height = (math.floor(level / 4) - 32768) / 4
				local node, gap = Grid.surface(st, k, cell, -1, height)
				-- Same-layer limit (CLIMB in gen_nav.py).
				if node and gap < 3 then
					local painted = math.floor((paint[cell] or 0) * 63 + 0.5)
					if node == cell then
						-- A base trail must not leak to any sibling that would otherwise inherit its coverage.
						local sibling = at[-(cell + 1)]
						while sibling and at[sibling + 1] == cell do
							nodes[sibling] = nodes[sibling] or painted
							sibling = sibling + 1
						end
					end
					nodes[node] = math.max(nodes[node] or painted, level % 4 * 21)
				end
			end
			local keys, records = {}, {}
			for node in pairs(nodes) do
				keys[#keys + 1] = node
			end
			table.sort(keys)
			for i, node in ipairs(keys) do
				records[i] = digit(math.floor(node / 4096))
					.. digit(math.floor(node / 64) % 64)
					.. digit(node % 64)
					.. digit(nodes[node])
			end
			if #records > 0 then
				coverage[cluster] = table.concat(records)
			end
			-- BakeRoadEdges must use the runtime decoder with the completed coverage.
			st.road[k] = nil
		end
	end
	return coverage
end

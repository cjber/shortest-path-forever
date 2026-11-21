-- Synthetic coordinates only. World projection deliberately has unequal axes.
local ns = {
	PlayerPosition = function()
		return 23, 42, 80, 1
	end,
}
local env = setmetatable({
	C_Map = {
		GetBestMapForUnit = function()
			return nil
		end,
	},
}, { __index = _G })
setfenv(assert(loadfile("Journey/FarmingOrder.lua")), env)("test", ns)
ns.FarmingOrder.World = function(map, x, y)
	return { map = map, x = 100 * x, y = 10 * y }
end
local checks = 0
local function check(ok)
	assert(ok)
	checks = checks + 1
end
-- Ordering uses the journey's world position even when the client's map position is unavailable.
local sampled = ns.FarmingOrder.Player()
check(sampled.map == 1 and sampled.x == 23 and sampled.y == 42 and sampled.z == nil)
ns.PlayerPosition = function()
	return 23, 42
end
check(ns.FarmingOrder.Player() == nil)
local function node(id, x, y)
	return { uiMapID = 1, kind = "Mining", coord = id, nodeID = id, x = x, y = y, title = "synthetic" }
end
local player = { map = 1, x = 0, y = 0 }
local function finish(nodes, origin)
	local job = ns.FarmingOrder.Begin(nodes, origin or player)
	local steps = 0
	while job.status == "working" do
		local status, result = job:Step()
		if status == "working" then
			check(result == nil)
		end
		steps = steps + 1
		assert(steps < 10000)
	end
	return job.nodes, job.status, steps
end
local function distance(a, b)
	local dx, dy = 100 * (a.x - b.x), 10 * (a.y - b.y)
	return math.sqrt(dx * dx + dy * dy)
end
local function length(t)
	local total = 0
	for i = 1, #t do
		total = total + distance(t[i], t[i % #t + 1])
	end
	return total
end
-- Exhaust every nonempty subset of six points and every permutation of each
-- subset for the exact optimum. The closed shortcut tour must satisfy 2 * OPT.
local grid = { node(1, 0, 0), node(2, 0.1, 0), node(3, 0, 1), node(4, 0.1, 1), node(5, 0.03, 0.4), node(6, 0.08, 0.7) }
for mask = 1, 63 do
	local input = {}
	for i = 1, 6 do
		if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then
			input[#input + 1] = grid[i]
		end
	end
	local optimum = math.huge
	local function permute(i)
		if i > #input then
			optimum = math.min(optimum, length(input))
			return
		end
		for j = i, #input do
			input[i], input[j] = input[j], input[i]
			permute(i + 1)
			input[i], input[j] = input[j], input[i]
		end
	end
	permute(1)
	local output, status = finish(input)
	check(status == "ready" and #output == #input)
	check(length(output) <= 2 * optimum + 1e-9)
	local seen = {}
	for _, n in ipairs(output) do
		check(not seen[n.coord])
		seen[n.coord] = true
	end
	local reverse = {}
	for i = #input, 1, -1 do
		reverse[#reverse + 1] = input[i]
	end
	local again = finish(reverse)
	for i = 1, #output do
		check(output[i].coord == again[i].coord)
	end
end
-- Exhaust all spanning trees on each subset of four points. Confirm the
-- produced preorder belongs to an exact minimum tree, independently of Prim.
for mask = 1, 15 do
	local input = {}
	for i = 1, 4 do
		if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then
			input[#input + 1] = grid[i]
		end
	end
	local tour = finish(input)
	local edges = {}
	for i = 1, #input do
		for j = i + 1, #input do
			edges[#edges + 1] = { i, j }
		end
	end
	local minimum, matching = math.huge, math.huge
	for bits = 0, 2 ^ #edges - 1 do
		local adj, count, weight = {}, 0, 0
		for i = 1, #input do
			adj[i] = {}
		end
		for k, e in ipairs(edges) do
			if math.floor(bits / 2 ^ (k - 1)) % 2 == 1 then
				count = count + 1
				adj[e[1]][#adj[e[1]] + 1] = e[2]
				adj[e[2]][#adj[e[2]] + 1] = e[1]
				weight = weight + distance(input[e[1]], input[e[2]])
			end
		end
		if count == #input - 1 then
			local root = 1
			for i = 2, #input do
				local a, b = distance(input[i], { x = 0, y = 0 }), distance(input[root], { x = 0, y = 0 })
				if a < b or (a == b and input[i].coord < input[root].coord) then
					root = i
				end
			end
			local seen, ordered = {}, {}
			local function visit(i)
				if seen[i] then
					return
				end
				seen[i] = true
				ordered[#ordered + 1] = input[i].coord
				table.sort(adj[i], function(a, b)
					return input[a].coord < input[b].coord
				end)
				for _, j in ipairs(adj[i]) do
					visit(j)
				end
			end
			visit(root)
			if #ordered == #input then
				minimum = math.min(minimum, weight)
				local same = true
				for i = 1, #tour do
					if tour[i].coord ~= ordered[i] then
						same = false
					end
				end
				if same then
					matching = math.min(matching, weight)
				end
			end
		end
	end
	check(math.abs(minimum - matching) < 1e-9)
end
-- Known unique MST: root -> 2 -> 3, root -> 4. Preorder is 1,2,3,4.
local known = finish({ node(4, 0, 1), node(3, 0.02, 0), node(2, 0.01, 0), node(1, 0, 0) })
for i = 1, 4 do
	check(known[i].coord == i)
end
-- World metric chooses 2, while raw fractions would choose 1.
local anisotropic = finish({ node(1, 0.1, 0), node(2, 0, 0.2) })
check(anisotropic[1].coord == 2)
local large = {}
for i = 1, 300 do
	large[i] = node(i, (i % 17) / 20, (i % 13) / 20)
end
local job = ns.FarmingOrder.Begin(large, player)
-- Snapshot and player ownership, including original array length.
large[300].title = "changed"
large[301] = node(301, 0, 0)
player.map = 9
check(job:Step() == "working" and job.nodes == nil)
while job.status == "working" do
	job:Step()
end
check(job.status == "ready" and #job.nodes == 300)
local seen = {}
for _, n in ipairs(job.nodes) do
	seen[n.coord] = true
	check(n.title == "synthetic")
end
for i = 1, 300 do
	check(seen[i])
end
player.map = 1
local duplicates = finish({ node(3, 0.5, 0.5), node(2, 0.5, 0.5), node(1, 0.5, 0.5) })
for i = 1, 3 do
	check(duplicates[i].coord == i)
end
local cancelled = ns.FarmingOrder.Begin(large, player)
cancelled:Step()
cancelled:Cancel()
for _ = 1, 3 do
	local status, result = cancelled:Step()
	check(status == "cancelled" and result == nil)
end
local empty, emptyStatus = finish({})
check(emptyStatus == "ready" and #empty == 0)
local bad = { node(1, 0, 0), node(2, 0 / 0, 0) }
local result, status = finish(bad)
check(result == nil and status == "invalid-input")
ns.FarmingOrder.World = function()
	return nil
end
result, status = finish({ node(1, 0, 0) })
check(result == nil and status == "invalid-world")
ns.FarmingOrder.World = function()
	return { map = 2, x = 0, y = 0 }
end
result, status = finish({ node(1, 0, 0) })
check(result == nil and status == "invalid-world")
ns.FarmingOrder.World = function()
	return { map = 1, x = math.huge, y = 0 }
end
result, status = finish({ node(1, 0, 0) })
check(result == nil and status == "invalid-world")
print("farming_order_spec: " .. checks .. " checks passed")

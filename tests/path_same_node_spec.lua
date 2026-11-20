-- A cost probe from a known height to a goal that can stand on the start's own surface answers 0 without connecting
-- either end to its cluster: a map click on a flight master is probed from that flight master (#1080). The full
-- search agrees on every flight point, so the shortcut is exact.
local ns = {}
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
assert(loadfile("Data/Taxi.lua"))("ShortestPathForever", ns)
for _, map in ipairs({ 0, 1 }) do
	assert(loadfile("tools/load_nav.lua"))(map)
end
local Path = ns.Path

local frame
Path.after = function(fn)
	frame = fn
end
Path.budget = 3
local function pump()
	while frame do
		local fn = frame
		frame = nil
		fn()
	end
end
local function probe(map, from, to)
	local answer
	local job = Path.FindCost(map, from, to, function(c)
		answer = c
	end)
	pump()
	return answer, job.expansions
end

local probed, quick = 0, 0
for id, node in pairs(ns.TaxiNodes) do
	if (node.map == 0 or node.map == 1) and node.z then
		for _, to in ipairs({
			{ x = node.x, y = node.y, z = node.z },
			{ x = node.x, y = node.y },
			{ x = node.x + 3, y = node.y - 2 },
		}) do
			-- The probe goes first: the full search caches both ends' cluster connections.
			local cost, expanded = probe(node.map, node, to)
			local _, full = Path.FindSync(node.map, node, to)
			assert(
				cost == full,
				string.format("flight point %d: probe %s, full search %s", id, tostring(cost), tostring(full))
			)
			if cost == 0 then
				assert(
					expanded == 0,
					string.format("flight point %d: a probe that walks nowhere expanded %d nodes", id, expanded)
				)
				quick = quick + 1
			end
			probed = probed + 1
		end
	end
end
assert(quick > 100, "only " .. quick .. " probes walked nowhere")
print(string.format("path_same_node_spec: %d probes, %d answered at once", probed, quick))

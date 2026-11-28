---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- The planner's remaining-time bound: the least time from each node to the goal, ignoring arrival modes, revisits and
-- flight knowledge, with every unanchored route waiting half its period. It is admissible, and keeps the labels the
-- search needs for correctness from exploring unrelated routes before reaching the destination.
local PlanBounds = {}
ns.PlanBounds = PlanBounds

local NO_EDGES = {}

---@param topology table the cached topology: its first counts[node] edges per node are its own, the rest this plan's
---@param edges table[] each node's outgoing edges
---@param goal number
---@param options table the plan's options (routes, anchors)
---@param check function the slice budget, called as the walk goes
---@return table<number, number> lower each reachable node's bound in milliseconds
function PlanBounds.Lower(topology, edges, goal, options, check)
	local lower, done = { [goal] = 0 }, {}
	local anchors = options.anchors
	-- Each node's incoming edges: the topology's own fixed edges once per topology, this plan's walks from where you
	-- stand and to where you are going afresh. Durations are read when relaxed, so a speed change needs no rebuild.
	local backward = topology.backward
	if not backward then
		backward = {}
		for from, adjacent in ipairs(edges) do
			check()
			for i = 1, topology.counts[from] do
				local edge = adjacent[i]
				local list = backward[edge.to] or {}
				backward[edge.to] = list
				list[#list + 1], list[#list + 2] = from, edge
			end
		end
		topology.backward = backward
	end
	local added = {}
	for from, adjacent in ipairs(edges) do
		for i = topology.counts[from] + 1, #adjacent do
			local edge = adjacent[i]
			local list = added[edge.to] or {}
			added[edge.to] = list
			list[#list + 1], list[#list + 2] = from, edge
		end
	end
	-- Dijkstra on a binary heap of nodes keyed by their bound, each node in it once (`seat` is where): a bound that
	-- drops moves its node up in place. Scanning every bound for the next node made this quadratic in places.
	local nearest, seat = { goal }, { [goal] = 1 }
	while #nearest > 0 do
		check()
		local current = nearest[1]
		local best = lower[current]
		local n = #nearest
		local last = nearest[n]
		nearest[n], seat[current] = nil, nil
		n = n - 1
		if n > 0 then
			local i, key = 1, lower[last]
			while i * 2 <= n do
				local child = i * 2
				if child < n and lower[nearest[child + 1]] < lower[nearest[child]] then
					child = child + 1
				end
				if key <= lower[nearest[child]] then
					break
				end
				nearest[i] = nearest[child]
				seat[nearest[i]], i = i, child
			end
			nearest[i], seat[last] = last, i
		end
		done[current] = true
		for list = 1, 2 do
			local adjacent = (list == 1 and backward or added)[current] or NO_EDGES
			for i = 1, #adjacent, 2 do
				local node, edge = adjacent[i], adjacent[i + 1]
				local cost = best + edge.duration
				if edge.route and not edge.aboard and not (anchors and anchors[edge.route]) then
					cost = cost + options.routes[edge.route].period / 2
				end
				if not done[node] and (not lower[node] or cost < lower[node]) then
					lower[node] = cost
					local j = seat[node] or #nearest + 1
					while j > 1 do
						local parent = math.floor(j / 2)
						if lower[nearest[parent]] <= cost then
							break
						end
						nearest[j] = nearest[parent]
						seat[nearest[j]], j = j, parent
					end
					nearest[j], seat[node] = node, j
				end
			end
		end
	end
	return lower
end

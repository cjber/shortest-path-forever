---@class SPFNamespace
local ns = select(2, ...)
if ns.broken then
	return
end

local Order = {}
local function Finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end
local function Point(p)
	return type(p) == "table" and Finite(p.map) and Finite(p.x) and Finite(p.y)
end
-- The continent's world plane is the frame the order measures in.
---@param uiMapID number
---@param x number
---@param y number
---@return SPFPoint?
function Order.World(uiMapID, x, y)
	local continent, world = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(x, y))
	if continent and world then
		local worldX, worldY = world:GetXY()
		return { map = continent, x = worldX, y = worldY }
	end
end

-- Use the same readable world position as guidance, dropping height for the geometric order.
---@return SPFPoint?
function Order.Player()
	local x, y, _, map = ns.PlayerPosition()
	if x and y and map then
		return { map = map, x = x, y = y }
	end
end

local function Identity(a, b)
	for _, key in ipairs({ "uiMapID", "kind", "coord", "nodeID" }) do
		if a[key] ~= b[key] then
			return a[key] < b[key]
		end
	end
	return false
end
local function Distance(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

-- Exact Euclidean MST, then deterministic preorder shortcut of its doubled walk.
-- The closed cycle is a 2-approximation ONLY for this geometric surrogate metric,
-- not terrain distance, reachability or travel time. The cursor closes last to first.
-- Step performs at most 128 work units; the caller must defer each next Step to a
-- later client frame. No timer, OnUpdate or partial result is published here.
---@param nodes SPFGatherMateNode[]
---@param player SPFPoint
---@return SPFFarmingOrderJob
function Order.Begin(nodes, player)
	local job = { status = "working" }
	local copy = {}
	local count = type(nodes) == "table" and #nodes or 0
	if type(nodes) ~= "table" or not Point(player) then
		job.status = "invalid-input"
	else
		-- Own the snapshot before returning control. Only the small scalar records
		-- are copied here; projection and quadratic work are frame sliced below.
		for k, node in pairs(nodes) do
			if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > #nodes or type(node) ~= "table" then
				job.status = "invalid-input"
				break
			end
			local n = {}
			for key, value in pairs(node) do
				if type(value) ~= "number" and type(value) ~= "string" and type(value) ~= "boolean" then
					job.status = "invalid-input"
				end
				n[key] = value
			end
			copy[k] = n
		end
	end
	for i = 1, count do
		if not copy[i] then
			job.status = "invalid-input"
		end
	end
	local origin = Point(player) and { map = player.map, x = player.x, y = player.y } or nil
	---@type thread?
	local co = coroutine.create(function()
		if not origin then
			return "invalid-input"
		end
		local points, best, parent, used = {}, {}, {}, {}
		local root, rootDistance
		for i = 1, count do
			local n = copy[i]
			if
				not n
				or not Finite(n.uiMapID)
				or n.uiMapID <= 0
				or n.uiMapID % 1 ~= 0
				or type(n.kind) ~= "string"
				or not Finite(n.coord)
				or not Finite(n.nodeID)
				or not Finite(n.x)
				or not Finite(n.y)
				or n.x < 0
				or n.x > 1
				or n.y < 0
				or n.y > 1
			then
				return "invalid-input"
			end
			local p = Order.World(n.uiMapID, n.x, n.y)
			if not p or not Point(p) or p.map ~= origin.map then
				return "invalid-world"
			end
			points[i] = { map = p.map, x = p.x, y = p.y }
			local d = Distance(p, origin)
			if not Finite(d) then
				return "invalid-world"
			end
			if not root or d < rootDistance or (d == rootDistance and Identity(n, copy[root])) then
				root, rootDistance = i, d
			end
			best[i] = math.huge
			coroutine.yield()
		end
		if not root then
			return "ready", {}
		end
		best[root] = 0
		for _ = 1, #copy do
			local nextNode
			for i = 1, #copy do
				if
					not used[i]
					and (
						not nextNode
						or best[i] < best[nextNode]
						or (best[i] == best[nextNode] and Identity(copy[i], copy[nextNode]))
					)
				then
					nextNode = i
				end
				coroutine.yield()
			end
			used[nextNode] = true
			for i = 1, #copy do
				if not used[i] then
					local d = Distance(points[nextNode], points[i])
					if not Finite(d) then
						return "invalid-world"
					end
					if
						d < best[i] or (d == best[i] and (not parent[i] or Identity(copy[nextNode], copy[parent[i]])))
					then
						best[i], parent[i] = d, nextNode
					end
				end
				coroutine.yield()
			end
		end
		local result, stack, visited = {}, { root }, {}
		while #stack > 0 do
			local current = stack[#stack]
			if not visited[current] then
				visited[current] = true
				result[#result + 1] = copy[current]
			end
			local child
			for i = 1, #copy do
				if parent[i] == current and not visited[i] and (not child or Identity(copy[i], copy[child])) then
					child = i
				end
				coroutine.yield()
			end
			if child then
				stack[#stack + 1] = child
			else
				stack[#stack] = nil
			end
		end
		return "ready", result
	end)
	function job:Step()
		if self.status ~= "working" then
			return self.status, self.nodes
		end
		for _ = 1, 128 do
			if not co then
				self.status = "cancelled"
				break
			end
			local ok, status, result = coroutine.resume(co)
			if not ok then
				self.status = "invalid-world"
				break
			end
			if coroutine.status(co) == "dead" then
				self.status, self.nodes = status, result
				break
			end
		end
		return self.status, self.nodes
	end
	function job:Cancel()
		self.status, self.nodes = "cancelled", nil
		co = nil
	end
	return job
end
ns.FarmingOrder = Order

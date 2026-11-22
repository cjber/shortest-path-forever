---@class SPFNamespace
local ns = select(2, ...)
if ns.broken then
	return
end

local Order = {}
local EXACT_LIMIT = 8

local function Number(value)
	return canaccessvalue(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function Table(value)
	return canaccessvalue(value) and type(value) == "table" and getmetatable(value) == nil
end
local function ID(value)
	return Number(value) and value > 0 and value % 1 == 0
end
local function Place(point)
	return Table(point)
		and ID(point.map)
		and Number(point.x)
		and Number(point.y)
		and point.x >= 0
		and point.x <= 1
		and point.y >= 0
		and point.y <= 1
		and ns.WorldPoint(point.map, point.x, point.y) ~= nil
end
local function Count(list, limit)
	if not Table(list) then
		return nil
	end
	local count = #list
	if count < 1 or (limit and count > limit) then
		return nil
	end
	for key in pairs(list) do
		if not ID(key) or key > count then
			return nil
		end
	end
	for index = 1, count do
		if rawget(list, index) == nil then
			return nil
		end
	end
	return count
end
local function Stop(point)
	if not Place(point) then
		return nil
	end
	local copy = { map = point.map, x = point.x, y = point.y }
	for _, key in ipairs({ "title", "tooltip", "kind", "hold", "radius", "z", "questID", "npc" }) do
		local value = point[key]
		if not canaccessvalue(value) then
			return nil
		end
		if value ~= nil then
			if key == "title" or key == "tooltip" or key == "kind" then
				if type(value) ~= "string" then
					return nil
				end
			elseif key == "hold" then
				if type(value) ~= "boolean" then
					return nil
				end
			elseif
				not Number(value)
				or (key == "radius" and value < 0)
				or ((key == "questID" or key == "npc") and not ID(value))
			then
				return nil
			end
			copy[key] = value
		end
	end
	for _, key in ipairs({ "questIDs", "handins", "shapes" }) do
		local values = point[key]
		if not canaccessvalue(values) then
			return nil
		end
		if values ~= nil then
			local count = Count(values)
			if not count then
				return nil
			end
			local entries = {}
			for index = 1, count do
				local value = values[index]
				if key == "shapes" then
					if not Place(value) or not Number(value.radius) or value.radius < 0 then
						return nil
					end
					entries[index] = { map = value.map, x = value.x, y = value.y, radius = value.radius }
				elseif ID(value) then
					entries[index] = value
				else
					return nil
				end
			end
			copy[key] = entries
		end
	end
	return copy
end

---@alias SPFStopOrderCost fun(from: integer, to: integer): number?
---@param cost SPFStopOrderCost
---@param count integer
---@return integer[]?
local function Nearest(cost, count)
	local order, seen, from = {}, {}, 0
	for index = 1, count do
		local best, seconds = nil, math.huge
		for to = 1, count do
			local time = not seen[to] and cost(from, to)
			-- Strict comparison keeps the original input index on equal estimates.
			if time and time < seconds then
				best, seconds = to, time
			end
		end
		if not best then
			return nil
		end
		order[index], seen[best], from = best, true, best
	end
	return order
end

-- Add the legs in the same order as the exact solver's remaining-cost sums.
---@param cost SPFStopOrderCost
---@param order integer[]
local function Total(cost, order)
	local seconds = 0
	for i = #order, 1, -1 do
		seconds = (cost(order[i - 1] or 0, order[i]) or math.huge) + seconds
	end
	return seconds
end

-- Held-Karp for an open route. Each state is the cheapest suffix from `from`
-- through a bit mask of remaining stops. Row 0 is the fixed starting point.
---@param cost SPFStopOrderCost
---@param count integer
---@param nearest integer[]?
---@return integer[]?
local function Exact(cost, count, nearest)
	local bits, memo = {}, {}
	for i = 1, count do
		bits[i] = 2 ^ (i - 1)
	end
	local function Solve(from, remaining)
		if remaining == 0 then
			return 0
		end
		local states = memo[remaining]
		if not states then
			states = {}
			memo[remaining] = states
		end
		if states[from] then
			return states[from].seconds
		end
		local best, nextStop = math.huge, nil
		for to, mask in ipairs(bits) do
			local leg = bit.band(remaining, mask) ~= 0 and cost(from, to)
			if leg then
				local seconds = leg + Solve(to, remaining - mask)
				if seconds < best then
					best, nextStop = seconds, to
				end
			end
		end
		states[from] = { seconds = best, nextStop = nextStop }
		return best
	end
	local remaining, from = 2 ^ count - 1, 0
	local best = Solve(from, remaining)
	if best == math.huge or (nearest and Total(cost, nearest) <= best) then
		return nearest
	end
	local order = {}
	for index = 1, count do
		local to = memo[remaining][from].nextStop --[[@as integer]]
		order[index], remaining, from = to, remaining - bits[to], to
	end
	return order
end

-- Depth-first search for any complete order, cheapest leg first, for when nearest-next strands a stop.
-- Finding one is the Hamiltonian path problem, exponential in the worst case, so the search gives up as
-- unreachable after count^2 dead ends; by then it has asked for at most every directed estimate once.
---@param cost SPFStopOrderCost
---@param count integer
---@return integer[]?
local function Any(cost, count)
	local order, seen, budget = {}, {}, count * count
	local function Visit(from, depth)
		if depth > count then
			return true
		end
		local options = {}
		for to = 1, count do
			local time = not seen[to] and cost(from, to)
			if time then
				options[#options + 1] = { to = to, time = time }
			end
		end
		table.sort(options, function(a, b)
			return a.time < b.time or (a.time == b.time and a.to < b.to)
		end)
		for _, option in ipairs(options) do
			seen[option.to], order[depth] = true, option.to
			if Visit(option.to, depth + 1) then
				return true
			end
			seen[option.to], order[depth] = nil, nil
			budget = budget - 1
			if budget <= 0 then
				return false
			end
			if budget % count == 0 then
				coroutine.yield() -- spread a long search over several steps
			end
		end
		return false
	end
	return Visit(0, 1) and order or nil
end

-- Find the best 2-opt reversal. In a directed matrix every internal leg
-- changes direction, so compare the reversed interior as well as the ends.
---@param cost SPFStopOrderCost
---@param order integer[]
---@return integer[]?
local function Improve(cost, order)
	local left, right, saving = nil, nil, 0
	for i = 1, #order - 1 do
		local before, first = order[i - 1] or 0, order[i]
		-- The current tour consists of reachable edges.
		local oldEnter = cost(before, first) --[[@as number]]
		local forward, backward = 0, 0
		for j = i + 1, #order do
			local previous, last, after = order[j - 1], order[j], order[j + 1]
			local reverse = cost(last, previous)
			if not reverse then
				break
			end
			local oldLeg = cost(previous, last) --[[@as number]]
			forward = forward + oldLeg
			backward = backward + reverse
			local enter = cost(before, last)
			if enter then
				local leave = after and (cost(first, after) or math.huge) or 0
				local old = oldEnter + forward + (after and cost(last, after) or 0)
				local saved = old - (enter + backward + leave)
				if saved > saving then
					left, right, saving = i, j, saved
				end
			end
		end
	end
	if left and right then
		local improved = { unpack(order) }
		for i = left, right do
			improved[i] = order[right - (i - left)]
		end
		-- Require a strict improvement in the whole route even when sums round differently.
		if Total(cost, improved) < Total(cost, order) then
			return improved
		end
	end
	return nil
end

-- The solver asks for edges as needed, reusing the directed estimates nearest-next already collected.
-- A 2-opt pass also needs the reversed adjacent legs and the edges reconnecting each reversed section.
---@param count integer
---@return integer[]?
local function SolveOrder(count)
	---@type table<integer, table<integer, number|false>>
	local costs = {}
	---@type SPFStopOrderCost
	local function Cost(from, to)
		local row = costs[from]
		if not row then
			row = {}
			costs[from] = row
		end
		local time = row[to]
		if time == nil then
			time = coroutine.yield(from, to) or false
			row[to] = time
		end
		return time or nil
	end
	local order = Nearest(Cost, count)
	if order and count <= 2 then
		return order
	end
	if count <= EXACT_LIMIT then
		return Exact(Cost, count, order)
	end
	order = order or Any(Cost, count)
	while order do
		local improved = Improve(Cost, order)
		if not improved then
			break
		end
		order = improved
		coroutine.yield() -- a new improvement pass starts on another step
	end
	return order
end

-- The caller steps from a path job, whose uncached estimates pause at the frame budget.
-- Loading/combat leave the edge pending. Changes to the draft or context stop the job.
---@param stops SPFAPIStop[]
---@param from SPFAPIPlace
---@return SPFStopOrderJob
function Order.Begin(stops, from)
	local job = { status = "working" }
	local count = Count(stops, 64)
	---@type SPFAPIPlace?
	local origin = Place(from) and { map = from.map, x = from.x, y = from.y } or nil
	---@type SPFAPIStop[]
	local copies = {}
	if not count or not origin then
		job.status, job.reason = "invalid", "invalid"
	else
		for index = 1, count do
			local point = Stop(stops[index])
			if not point then
				job.status, job.reason = "invalid", "invalid"
				break
			end
			copies[index] = point
		end
	end
	local cancelled = false
	---@type thread?
	local solver
	---@type integer?, integer?
	local row, column
	---@type integer?
	local revision
	---@param active thread
	---@param time? number
	local function Advance(active, time)
		local ok, result, target = coroutine.resume(active, time)
		if not ok then
			error(result)
		end
		if coroutine.status(active) ~= "dead" then
			row, column = result, target
			return job.status
		end
		solver = nil
		local order = result --[[@as integer[]?]]
		if not order then
			job.status, job.reason = "unreachable", "unreachable"
			return job.status
		end
		local points = {}
		for index, id in ipairs(order) do
			points[index] = copies[id]
		end
		job.status, job.points = "ready", points
		return job.status, job.points
	end
	function job:Cancel()
		cancelled = true
		solver = nil
		self.points = nil
	end
	---@param pathJob? SPFPathJob the path job stepping, whose estimate pauses at the frame budget
	function job:Step(pathJob)
		if cancelled or self.status == "ready" or self.status == "invalid" or self.status == "unreachable" then
			return self.status, self.points
		end
		if not count or not origin then
			self.status, self.reason = "invalid", "invalid"
			return self.status
		end
		local api = ShortestPathForever and ShortestPathForever.API
		if not api then
			self.status, self.reason = "loading", "loading"
			return self.status
		end
		local active = solver
		if not active then
			active = coroutine.create(function()
				return SolveOrder(count)
			end)
			solver = active
			Advance(active)
		end
		if not row or not column then
			if not ns.APIInput.Ready() then
				local reason = InCombatLockdown() and "combat" or "loading"
				self.status, self.reason = reason, reason
				return self.status
			end
			if revision ~= ns.EstimateContextRevision() then
				self.status, self.reason = "invalid", "context-changed"
				solver = nil
				return self.status
			end
			self.status, self.reason = "working", nil
			return Advance(active)
		end
		local fromPoint, candidate = row == 0 and origin or copies[row], copies[column]
		local time, reason
		if pathJob then
			time, reason =
				ns.EstimateIn(pathJob, fromPoint.map, fromPoint.x, fromPoint.y, candidate.map, candidate.x, candidate.y)
		else
			time, reason =
				api.Estimate(fromPoint.map, fromPoint.x, fromPoint.y, candidate.map, candidate.x, candidate.y)
		end
		if cancelled then
			return self.status
		end
		if time == nil and reason ~= "unreachable" then
			self.status, self.reason = reason or "invalid", reason or "invalid"
			return self.status
		end
		-- Estimate updates the canonical context revision before answering. Compare before
		-- accepting this candidate, so earlier choices never mix routing contexts.
		local current = ns.EstimateContextRevision()
		if revision and current ~= revision then
			self.status, self.reason = "invalid", "context-changed"
			solver = nil
			return self.status
		end
		revision = current
		if time ~= nil and (not Number(time) or time < 0) then
			self.status, self.reason = "invalid", "invalid"
			solver = nil
			return self.status
		end
		self.status, self.reason = "working", nil
		return Advance(active, time)
	end
	return job
end
ns.StopOrder = Order

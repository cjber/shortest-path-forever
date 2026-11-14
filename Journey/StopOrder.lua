---@class SPFNamespace
local ns = select(2, ...)
if ns.broken then
	return
end

local Order = {}
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

-- Directed nearest-next estimates, not a globally optimal itinerary. The caller
-- schedules at most one Step per frame and cancels on changes to its draft/context.
-- Loading/combat leave the candidate pending: a later Step retries it. Unreachable
-- candidates are reconsidered from the next chosen stop, not discarded forever.
---@param stops SPFAPIStop[]
---@param from SPFAPIPlace
---@return SPFStopOrderJob
function Order.Begin(stops, from)
	local job = { status = "working" }
	local count = Count(stops, 64)
	---@type SPFAPIPlace?
	local origin = Place(from) and { map = from.map, x = from.x, y = from.y } or nil
	---@type SPFAPIStop[]
	local remaining, ordered = {}, {}
	if not count or not origin then
		job.status, job.reason = "invalid", "invalid"
	else
		for index = 1, count do
			local point = Stop(stops[index])
			if not point then
				job.status, job.reason = "invalid", "invalid"
				break
			end
			remaining[index] = point
		end
	end
	local cancelled, cursor, best, seconds = false, 1, nil, nil
	---@type integer?
	local revision
	function job:Cancel()
		cancelled = true
		self.points = nil
	end
	function job:Step()
		if cancelled or self.status == "ready" or self.status == "invalid" or self.status == "unreachable" then
			return self.status, self.points
		end
		if not origin then
			self.status, self.reason = "invalid", "invalid"
			return self.status
		end
		local candidate = remaining[cursor]
		local api = ShortestPathForever and ShortestPathForever.API
		if not api then
			self.status, self.reason = "loading", "loading"
			return self.status
		end
		local time, reason = api.Estimate(origin.map, origin.x, origin.y, candidate.map, candidate.x, candidate.y)
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
			return self.status
		end
		revision = current
		if time ~= nil then
			if not Number(time) or time < 0 then
				self.status, self.reason = "invalid", "invalid"
				return self.status
			end
			-- Strict comparison keeps the original input index on equal estimates.
			if seconds == nil or time < seconds then
				best, seconds = cursor, time
			end
		end
		self.status, self.reason = "working", nil
		cursor = cursor + 1
		if cursor > #remaining then
			if not best then
				self.status, self.reason = "unreachable", "unreachable"
				return self.status
			end
			origin = table.remove(remaining, best)
			ordered[#ordered + 1] = origin
			cursor, best, seconds = 1, nil, nil
			if #remaining == 0 then
				self.status, self.points = "ready", ordered
			end
		end
		return self.status, self.points
	end
	return job
end
ns.StopOrder = Order

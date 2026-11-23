---@type string, SPFNamespace
local addonName, ns = ...

if ns.broken then
	return
end
local Input = assert(ns.APIInput, "Core/APIInput.lua loads first")

-- Walking costs and paths for other addons, over the same data journeys use. The path queue owns frame scheduling
-- and the wait for combat. Each public search keeps its own requests by owner.

-- The most places one estimate may ask for. The searches share one frontier, so this bounds an answer rather than a
-- frame's work, which the path queue's own budget already does.
local MAX_TARGETS = 256

---@type table<string, fun()>
local estimates = {}
---@type table<string, fun()>
local paths = {}

-- The walking data a cost is measured against. A release ships its navigation maps and baked walks in the zip, so
-- the build's own version names them, and every new build can change a cost. An unpackaged checkout has no version
-- token, so its loaded maps' shape stands in, which changes when a map is rebaked.
---@return string
function ns.NavVersion()
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
	if type(version) == "string" and version ~= "" and not version:find("@", 1, true) then
		return version
	end
	local data = ShortestPathForeverPathData or {}
	local maps = {}
	for id in pairs(data) do
		maps[#maps + 1] = id
	end
	table.sort(maps)
	for index, id in ipairs(maps) do
		local map = data[id]
		local counts = map.counts or {}
		maps[index] = string.format("%d.%d.%d", id, map.format or 1, counts.graph or 0)
	end
	return "nav/" .. table.concat(maps, ",")
end

-- One walking search from `from` to every target on its map, under the path queue's own frame budget. Costs are the
-- real running yards of the walk the planner would take, without a journey's preferences: no hostile town is avoided
-- and no road is preferred. Every cost and the answer table itself are new.
---@param owner string
---@param from SPFPoint
---@param targets SPFPoint[]
---@param callback fun(costs: (number|false)[], reason: SPFAPIWalkReason?)
---@param water boolean
local function Find(owner, from, targets, callback, water)
	local count = #targets
	local previous = estimates[owner]
	if previous then
		previous()
	end
	local job
	local function cancel()
		if estimates[owner] == cancel then
			estimates[owner] = nil
			ns.Path.Cancel(job)
		end
	end
	job = ns.Path.FindMany(from.map, from, targets, function(costs, reason)
		if estimates[owner] ~= cancel then
			return
		end
		estimates[owner] = nil
		local answer = {}
		for index = 1, count do
			local cost = costs and costs[index]
			answer[index] = type(cost) == "number" and cost >= 0 and cost or false
		end
		ns.core.SafeCall("API walk estimate", callback, answer, reason)
	end, water, false, nil, nil)
	estimates[owner] = cancel
	return cancel
end

---@param owner any
---@param from any
---@param callback any
---@param opts any
---@return SPFPoint?
local function StartPoint(owner, from, callback, opts)
	if
		not Input.Owner(owner)
		or type(from) ~= "table"
		or type(callback) ~= "function"
		or (opts ~= nil and type(opts) ~= "table")
	then
		return nil
	end
	local water = opts and opts.waterWalking
	if water ~= nil and type(water) ~= "boolean" then
		return nil
	end
	return Input.Point(from.map, from.x, from.y)
end

---@param target any
---@param map number
---@return SPFPoint?
local function TargetPoint(target, map)
	if type(target) == "table" then
		local point = Input.Point(target.map, target.x, target.y)
		if point and point.map == map then
			return point
		end
	end
	return nil
end

---@param map number
---@param opts? SPFAPIWalkOptions
---@return boolean?, SPFAPIWalkRefusal?
local function ReadyWater(map, opts)
	if not Input.Loaded() then
		return Input.Loading()
	end
	if InCombatLockdown() then
		return nil, "combat"
	end
	if not ns.Path.HasData(map) then
		return nil, "nodata"
	end
	if opts and opts.waterWalking ~= nil then
		return opts.waterWalking
	end
	return ns.JourneyWaterWalking and (ns.JourneyWaterWalking()) or false
end

-- One walking search from `from` to every target on its map, all in uiMapIDs and 0-1 fractions. Returns a function
-- that cancels it, safe to call twice and never calling back once called, or nil and why it did not start.
---@param owner string
---@param from SPFAPIPlace
---@param targets SPFAPIPlace[]
---@param callback fun(costs: (number|false)[], reason: SPFAPIWalkReason?)
---@param opts? SPFAPIWalkOptions
---@return fun()? cancel, SPFAPIWalkRefusal? reason
function ns.EstimateWalks(owner, from, targets, callback, opts)
	local start = StartPoint(owner, from, callback, opts)
	if not start or type(targets) ~= "table" then
		return nil, "invalid"
	end
	local count = #targets
	if count < 1 or count > MAX_TARGETS then
		return nil, "invalid"
	end
	for key in pairs(targets) do
		if not Input.Number(key) or key % 1 ~= 0 or key < 1 or key > count then
			return nil, "invalid"
		end
	end
	local places = {}
	for index = 1, count do
		local point = TargetPoint(targets[index], start.map)
		if not point then
			return nil, "invalid"
		end
		places[index] = point
	end
	local water, reason = ReadyWater(start.map, opts)
	if water == nil then
		return nil, reason
	end
	return Find(owner, start, places, callback, water)
end

---@param owner string
---@param from SPFAPIPlace
---@param to SPFAPIPlace
---@param callback fun(path: SPFAPIWalkPath?, reason: SPFAPIWalkReason?)
---@param opts? SPFAPIWalkOptions
---@return fun()? cancel, SPFAPIWalkRefusal? reason
function ns.WalkPath(owner, from, to, callback, opts)
	local start = StartPoint(owner, from, callback, opts)
	local goal = start and TargetPoint(to, start.map)
	if not start or not goal then
		return nil, "invalid"
	end
	local water, reason = ReadyWater(start.map, opts)
	if water == nil then
		return nil, reason
	end
	local previous = paths[owner]
	if previous then
		previous()
	end
	local job
	local function cancel()
		if paths[owner] == cancel then
			paths[owner] = nil
			ns.Path.Cancel(job)
		end
	end
	job = ns.Path.Find(start.map, start, goal, function(points, cost)
		if paths[owner] ~= cancel then
			return
		end
		paths[owner] = nil
		if not points or type(cost) ~= "number" then
			ns.core.SafeCall("API walk path", callback, nil, type(cost) == "string" and cost or "error")
			return
		end
		local waypoints = {}
		for index, point in ipairs(points) do
			local place = Input.Place(point)
			if not place then
				ns.core.SafeCall("API walk path", callback, nil, "outside")
				return
			end
			place.z = nil
			waypoints[index] = place
		end
		ns.core.SafeCall(
			"API walk path",
			callback,
			{ waypoints = waypoints, yards = cost, navVersion = ns.NavVersion() }
		)
	end, water, nil, true)
	paths[owner] = cancel
	return cancel
end

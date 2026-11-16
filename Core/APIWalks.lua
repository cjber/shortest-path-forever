---@type string, SPFNamespace
local addonName, ns = ...

if ns.broken then
	return
end
local Input = assert(ns.APIInput, "Core/APIInput.lua loads first")

-- #913: walking costs for another addon's own route, over the same walking maps the journey plans with. The search is
-- Routing/PathJobs.lua's FindMany, so it shares the path queue's frame budget and its wait for combat; this file owns
-- only the public argument checks, one batch per owner, and the data's identity.

-- The most places one estimate may ask for. The searches share one frontier, so this bounds an answer rather than a
-- frame's work, which the path queue's own budget already does.
local MAX_TARGETS = 256

-- The searches other addons started, one per owner: a new batch from the same owner replaces the one still running,
-- as a new journey replaces a journey. A cancelled search never calls back.
---@type table<string, {job: SPFPathJob?, cancel: fun()}>
local searches = {}

---@param owner string
local function Abandon(owner)
	local entry = searches[owner]
	if entry then
		searches[owner] = nil
		entry.cancel()
	end
end

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
	Abandon(owner)
	local job
	local function cancel()
		local entry = searches[owner]
		if entry and entry.job == job then
			searches[owner] = nil
		end
		ns.Path.Cancel(job)
	end
	job = ns.Path.FindMany(from.map, from, targets, function(costs, reason, finished)
		local entry = searches[owner]
		if entry and entry.job == finished then
			searches[owner] = nil
		end
		local answer = {}
		for index = 1, count do
			local cost = costs and costs[index]
			answer[index] = type(cost) == "number" and cost >= 0 and cost or false
		end
		ns.core.SafeCall("API walk estimate", callback, answer, reason)
	end, water, false, nil, nil)
	searches[owner] = { job = job, cancel = cancel }
	return cancel
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
	if
		not Input.Owner(owner)
		or type(from) ~= "table"
		or type(targets) ~= "table"
		or type(callback) ~= "function"
		or (opts ~= nil and type(opts) ~= "table")
	then
		return nil, "invalid"
	end
	local water = opts and opts.waterWalking
	if water ~= nil and type(water) ~= "boolean" then
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
	local start = Input.Point(from.map, from.x, from.y)
	if not start then
		return nil, "invalid"
	end
	local places = {}
	for index = 1, count do
		local target = targets[index]
		if type(target) ~= "table" then
			return nil, "invalid"
		end
		-- A target may use a zone or a continent map of the same landmass: the walking search runs on the world map
		-- both places project to, and nowhere else.
		local point = Input.Point(target.map, target.x, target.y)
		if not point or point.map ~= start.map then
			return nil, "invalid"
		end
		places[index] = point
	end
	if not Input.Loaded() then
		return Input.Loading()
	end
	if InCombatLockdown() then
		return nil, "combat"
	end
	if not ns.Path.HasData(start.map) then
		return nil, "nodata"
	end
	if water == nil then
		water = ns.JourneyWaterWalking and (ns.JourneyWaterWalking()) or false
	end
	return Find(owner, start, places, callback, water)
end

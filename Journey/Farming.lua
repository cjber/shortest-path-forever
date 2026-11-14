---@class SPFNamespace
local ns = select(2, ...)
if ns.broken then
	return
end

---@class SPFFarmingFactory
local Farming = {}
ns.Farming = Farming
local instance = 0

local function Blocked()
	if InCombatLockdown() then
		return "combat"
	end
	if ns.Corpse and ns.Corpse.Active() then
		return "corpse"
	end
end

-- Input order is the caller's decision. Copy only flat records, before touching a live route.
---@param nodes SPFGatherMateNode[]
---@return SPFFarmingCursorNode[]?, string?
local function Snapshot(nodes)
	if type(nodes) ~= "table" then
		return nil, "invalid"
	end
	local copy, count, distinct = {}, 0, false
	for key in pairs(nodes) do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #nodes then
			return nil, "invalid"
		end
		count = count + 1
	end
	if count ~= #nodes then
		return nil, "invalid"
	end
	for i, node in ipairs(nodes) do
		if type(node) ~= "table" then
			return nil, "invalid"
		end
		local record = {}
		for key, value in pairs(node) do
			if
				type(key) ~= "string"
				or (type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean")
			then
				return nil, "invalid"
			end
			record[key] = value
		end
		local map, x, y = node.uiMapID, node.x, node.y
		if
			type(map) ~= "number"
			or map == math.huge
			or map <= 0
			or map % 1 ~= 0
			or type(x) ~= "number"
			or type(y) ~= "number"
			or not (x >= 0 and x <= 1 and y >= 0 and y <= 1)
		then
			return nil, "invalid"
		end
		if node.title ~= nil and type(node.title) ~= "string" then
			return nil, "invalid"
		end
		local point = ns.WorldPoint(map, x, y)
		if not point then
			return nil, "invalid"
		end
		for _, value in ipairs({ point.map, point.x, point.y }) do
			if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
				return nil, "invalid"
			end
		end
		if point.map == nil or point.x == nil or point.y == nil then
			return nil, "invalid"
		end
		copy[i] = record
		local first = copy[1]
		distinct = distinct or map ~= first.uiMapID or x ~= first.x or y ~= first.y
	end
	if not distinct then
		return nil, "too-few-locations"
	end
	return copy
end

---@return SPFFarmingController
function Farming.new()
	instance = instance + 1
	local identity = instance
	local api = ShortestPathForever.API
	---@type SPFFarmingDriverBatch?
	local current
	---@type {generation: integer, run: fun()}?
	local waiting
	local queued
	local frame = CreateFrame("Frame")
	---@type SPFFarmingCursor
	local cursor
	---@class SPFFarmingController
	local controller = {}
	local function detach(batch)
		if batch.unobserve then
			batch.unobserve()
			batch.unobserve = nil
		end
		if batch.unsubscribe then
			batch.unsubscribe()
			batch.unsubscribe = nil
		end
	end
	local function finish(batch, reason)
		if current ~= batch then
			return
		end
		current = nil
		detach(batch)
		if reason ~= "arrived" and ns.JourneyOwner() == batch.owner and not Blocked() then
			api.Cancel(batch.owner)
		end
		batch.done(reason)
	end
	local function inspect(batch)
		if current ~= batch or Blocked() then
			return
		end
		local index = api.CurrentStop(batch.owner)
		if not index then
			---@type string?
			local reason = api.Ended(batch.owner)
			if reason == "arrived" then
				local x, y, _, map = ns.JourneyPosition()
				local goal = batch.goal
				local reach = ns.db.arrivalDistance or 15
				if
					not batch.arrived
					or not goal
					or not x
					or not y
					or map ~= goal.map
					or (x - goal.x) ^ 2 + (y - goal.y) ^ 2 > reach ^ 2
				then
					reason = "unverified-arrival"
				end
			end
			if reason == "none" or reason == "loading" or not reason then
				reason = "ownership-lost"
			end
			finish(batch, reason)
			return
		end
		if ns.JourneyOwner() ~= batch.owner then
			finish(batch, "ownership-lost")
			return
		end
		local _, _, failure = ns.JourneyStatus()
		if failure then
			finish(batch, failure)
			return
		end
		local plan = ns.JourneyPlan()
		for _, leg in ipairs(plan and plan.legs or {}) do
			if leg.walkError then
				finish(batch, leg.walkError)
				return
			end
			if leg.mode ~= "walk" then
				finish(batch, "non-walking-plan")
				return
			end
		end
	end
	local function deferred(fn)
		local generation = cursor.generation
		C_Timer.After(0, function()
			if cursor.generation ~= generation then
				return
			end
			if Blocked() then
				waiting = { generation = generation, run = fn }
			else
				fn()
			end
		end)
	end
	cursor = ns.FarmingCursor.new({
		busy = function()
			return ns.HasJourney() or ns.JourneyOwner() ~= nil
		end,
		defer = deferred,
		submit = function(nodes, token, done)
			---@type SPFFarmingDriverBatch
			local batch = {
				token = token,
				done = done,
				count = #nodes,
				owner = "SPF:Farming:" .. identity .. ":" .. token.generation .. ":" .. token.serial,
			}
			local stops = {}
			for i, node in ipairs(nodes) do
				stops[i] = { map = node.uiMapID, x = node.x, y = node.y, title = node.title }
			end
			local final = stops[#stops]
			batch.goal = ns.WorldPoint(final.map, final.x, final.y)
			if not batch.goal or Blocked() or ns.HasJourney() or ns.JourneyOwner() ~= nil then
				return false
			end
			current = batch
			batch.unsubscribe = api.Subscribe(function()
				inspect(batch)
			end)
			batch.unobserve = ns.ObserveFarmingJourney(batch.owner, function(phase, index, goal, plan)
				if current ~= batch or Blocked() or ns.JourneyOwner() ~= batch.owner then
					return
				end
				inspect(batch)
				if current ~= batch or phase ~= "arrived" or index ~= batch.count then
					return
				end
				local expected = batch.goal
				local pending, _, failure, loading = ns.JourneyStatus()
				local valid = expected
					and goal
					and goal.map == expected.map
					and goal.x == expected.x
					and goal.y == expected.y
					and plan ~= nil
					and #plan.legs > 0
					and not plan.preview
					and not pending
					and not failure
					and not loading
				for _, leg in ipairs(plan and plan.legs or {}) do
					valid = valid and leg.mode == "walk" and leg.measured == true and not leg.walkError
				end
				local x, y, _, map = ns.JourneyPosition()
				local reach = ns.db.arrivalDistance or 15
				batch.arrived = valid
						and x ~= nil
						and y ~= nil
						and map == goal.map
						and (x - goal.x) ^ 2 + (y - goal.y) ^ 2 <= reach ^ 2
					or false
			end)
			-- No yield between the final ownership check and the internal walking submission.
			local ok, accepted = pcall(ns.NavigateFarmingRoute, batch.owner, stops)
			if not ok then
				finish(batch, "navigation-error")
				return false
			end
			if not accepted then
				current = nil
				detach(batch)
				return false
			end
			inspect(batch)
			return true
		end,
		pause = function(token)
			return current ~= nil and current.token == token and api.Pause(current.owner)
		end,
		resume = function(token)
			return current ~= nil and current.token == token and api.Resume(current.owner)
		end,
		cancel = function(token)
			local batch = current
			if batch and batch.token == token then
				current = nil
				detach(batch)
				if ns.JourneyOwner() == batch.owner then
					api.Cancel(batch.owner)
				end
			end
		end,
	})
	frame:SetScript("OnEvent", function()
		if Blocked() or queued then
			return
		end
		queued = true
		C_Timer.After(0, function()
			queued = nil
			if Blocked() then
				return
			end
			local work = waiting
			waiting = nil
			if work and work.generation == cursor.generation then
				work.run()
			end
			if current then
				inspect(current)
			end
		end)
	end)
	for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD" }) do
		frame:RegisterEvent(event)
	end
	function controller.Start(_, nodes)
		local snapshot, reason = Snapshot(nodes)
		if not snapshot then
			return false, reason
		end
		if ns.HasJourney() and (not current or ns.JourneyOwner() ~= current.owner) then
			return false, "occupied"
		end
		if Blocked() then
			return false, Blocked()
		end
		waiting = nil
		return cursor:start(snapshot)
	end
	function controller.Pause(_)
		return cursor:pause()
	end
	function controller.Resume(_)
		return cursor:resume()
	end
	function controller.Stop(_)
		waiting = nil
		cursor:stop()
	end
	function controller.Status(_)
		return waiting and "waiting" or cursor.state, waiting and Blocked() or cursor.reason, cursor.next, cursor.cycles
	end
	return controller
end

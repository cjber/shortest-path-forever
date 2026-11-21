---@class SPFNamespace
local ns = select(2, ...)
if ns.broken then
	return
end

---@class SPFFarmingFactory
local Farming = {}
ns.Farming = Farming
local instance = 0

-- The tour drives Shortest Path only through its public API.
---@return SPFAPIJourneyState?
local function State()
	return (ShortestPathForever.API.JourneyState())
end

---@param state? SPFAPIJourneyState
---@return SPFAPIBlocked?
local function Blocked(state)
	state = state or State()
	return state and state.blocked
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
		local point = ns.FarmingOrder.World(map, x, y)
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
		local state = State()
		if reason ~= "arrived" and state and state.owner == batch.owner and not state.blocked then
			api.Cancel(batch.owner)
		end
		batch.done(reason)
	end
	local function inspect(batch)
		local state = State()
		if current ~= batch or not state or state.blocked then
			return
		end
		local index = api.CurrentStop(batch.owner)
		if not index then
			---@type string?
			local reason = api.Ended(batch.owner)
			-- The proof was taken when the last stop was reached: a measured walk plan and the player inside reach.
			if reason == "arrived" and not batch.arrived then
				reason = "unverified-arrival"
			end
			if reason == "none" or reason == "loading" or not reason then
				reason = "ownership-lost"
			end
			finish(batch, reason)
			return
		end
		if state.owner ~= batch.owner then
			finish(batch, "ownership-lost")
			return
		end
		if state.failure then
			finish(batch, state.failure)
			return
		end
		for _, leg in ipairs(state.legs) do
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
			local state = State()
			return not state or state.busy
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
			local state = State()
			if not state or state.blocked or state.busy then
				return false
			end
			current = batch
			batch.unsubscribe = api.Subscribe(function()
				inspect(batch)
			end)
			batch.unobserve = api.ObserveStops(batch.owner, function(phase, index, _, seen)
				if current ~= batch or seen.blocked or seen.owner ~= batch.owner then
					return
				end
				inspect(batch)
				if current ~= batch or phase ~= "arrived" or index ~= batch.count then
					return
				end
				local valid = #seen.legs > 0
					and not seen.preview
					and not seen.pending
					and not seen.failure
					and not seen.settling
				for _, leg in ipairs(seen.legs) do
					valid = valid and leg.mode == "walk" and leg.measured and not leg.walkError
				end
				batch.arrived = valid and seen.distance ~= nil and seen.distance <= seen.reach or false
			end)
			-- No yield between the final ownership check and the walking submission.
			local ok, accepted = pcall(api.NavigateRoute, batch.owner, stops, { policy = "walking" })
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
				api.Cancel(batch.owner)
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
		local state = State()
		if state and state.busy and (not current or state.owner ~= current.owner) then
			return false, "occupied"
		end
		local blocked = Blocked(state)
		if blocked then
			return false, blocked
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

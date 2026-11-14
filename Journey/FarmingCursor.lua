---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Ordered snapshot only: the driver owns navigation, combat deferral and atomic ownership checks.
-- Driver functions must not yield; defer must queue a later frame, never invoke inline.
---@class SPFFarmingCursorFactory
local Cursor = {}
ns.FarmingCursor = Cursor

---@param driver SPFFarmingCursorDriver
---@return SPFFarmingCursor
function Cursor.new(driver)
	---@class SPFFarmingCursor
	local cursor = { generation = 0, serial = 0, state = "idle", nodes = {}, next = 1, cycles = 0 }
	local function invalidate(reason)
		cursor.generation = cursor.generation + 1
		cursor.state, cursor.reason = "stopped", reason
		cursor.pending = nil
	end
	local submit
	local function schedule()
		local generation = cursor.generation
		driver.defer(function()
			if cursor.generation == generation and cursor.state == "running" and not cursor.pending then
				submit()
			end
		end)
	end
	submit = function()
		if driver.busy() then
			invalidate("occupied")
			return false
		end
		local batch = {}
		local first = cursor.next
		local last = math.min(first + 63, #cursor.nodes)
		for i = first, last do
			batch[#batch + 1] = cursor.nodes[i]
		end
		cursor.serial = cursor.serial + 1
		local token = { generation = cursor.generation, serial = cursor.serial, last = last }
		cursor.pending = token
		local accepted = driver.submit(batch, token, function(reason)
			if cursor.generation ~= token.generation or cursor.pending ~= token then
				return
			end
			cursor.pending = nil
			if reason ~= "arrived" then
				invalidate(reason)
				return
			end
			cursor.next = last % #cursor.nodes + 1
			if last == #cursor.nodes then
				cursor.cycles = cursor.cycles + 1
			end
			if cursor.state == "running" then
				schedule()
			end
		end)
		if not accepted and cursor.pending == token then
			invalidate("submission-failed")
		end
		return accepted
	end
	function cursor.start(_, nodes)
		if #nodes == 0 then
			return false
		end
		local snapshot = {}
		for i, node in ipairs(nodes) do
			local copy = {}
			for key, value in pairs(node) do
				assert(type(value) ~= "table", "flat immutable stop records required")
				copy[key] = value
			end
			snapshot[i] = copy
		end
		cursor:stop()
		cursor.nodes = snapshot
		cursor.next, cursor.cycles, cursor.state, cursor.reason = 1, 0, "running", nil
		return submit()
	end
	function cursor.pause(_)
		if cursor.state ~= "running" then
			return false
		end
		if cursor.pending and not driver.pause(cursor.pending) then
			return false
		end
		cursor.state = "paused"
		return true
	end
	function cursor.resume(_)
		if cursor.state ~= "paused" then
			return false
		end
		if cursor.pending and not driver.resume(cursor.pending) then
			return false
		end
		cursor.state = "running"
		if not cursor.pending then
			schedule()
		end
		return true
	end
	function cursor.stop(_)
		local old = cursor.pending
		invalidate("cancelled") -- invalidate before Cancel can synchronously notify
		if old then
			driver.cancel(old)
		end
	end
	return cursor
end

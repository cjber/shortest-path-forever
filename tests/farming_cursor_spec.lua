local ns = {}
assert(loadfile("Journey/FarmingCursor.lua"))("ShortestPathForever", ns)
local Cursor = ns.FarmingCursor
local queue, batches, callbacks, occupied = {}, {}, {}, false
local driver = {
	busy = function()
		return occupied
	end,
	defer = function(fn)
		queue[#queue + 1] = fn
	end,
	submit = function(batch, _, done)
		assert(#batch >= 1 and #batch <= 64)
		batches[#batches + 1], callbacks[#callbacks + 1] = batch, done
		return true
	end,
	pause = function()
		return true
	end,
	resume = function()
		return true
	end,
	cancel = function() end,
}
local function flush()
	local pending = queue
	queue = {}
	for _, fn in ipairs(pending) do
		fn()
	end
end
local function nodes(n)
	local list = {}
	for i = 1, n do
		list[i] = { id = i }
	end
	return list
end
local c = Cursor.new(driver)
assert(c:start(nodes(300)))
assert(c.reason == nil)
for i = 1, 5 do
	callbacks[i]("arrived")
	flush()
end
assert(#batches[5] == 44 and batches[5][44].id == 300)
assert(batches[6][1].id == 1 and c.cycles == 1)
for i = 1, 300 do
	local b, j = math.floor((i - 1) / 64) + 1, (i - 1) % 64 + 1
	assert(batches[b][j].id == i)
end
local old = callbacks[6]
assert(c:pause())
old("arrived")
flush()
assert(c.state == "paused" and c.next == 65 and #batches == 6)
assert(c:resume())
flush()
assert(batches[7][1].id == 65)
local late = callbacks[7]
assert(c:start(nodes(2)))
late("arrived")
old("replaced")
flush()
assert(c.next == 1 and c.state == "running")
local current = callbacks[#callbacks]
current("arrived")
current("arrived")
occupied = true
flush()
assert(c.state == "stopped" and c.reason == "occupied")
occupied = false
for _, reason in ipairs({ "replaced", "cancelled", "cleared" }) do
	assert(c:start(nodes(65)))
	callbacks[#callbacks](reason)
	flush()
	assert(c.state == "stopped" and c.reason == reason)
end
assert(c:start(nodes(64)))
callbacks[#callbacks]("arrived")
c:stop()
flush()
assert(c.state == "stopped")
assert(c:start(nodes(1)))
callbacks[#callbacks]("arrived")
flush()
assert(#batches[#batches] == 1 and c.cycles == 1)
c:stop()
assert(not c:start({}))
print("PASS: ordered 300; tail; cycle; boundaries; pause; replacement; late callbacks; occupied gap; cancel")

-- Input snapshots are owned by the cursor, and invalid input cannot cancel a live batch.
local source = nodes(65)
assert(c:start(source))
source[1].id = -1
assert(c.nodes[1].id == 1 and batches[#batches][1].id == 1)
local generation, pending = c.generation, c.pending
assert(not pcall(function()
	c:start({ { nested = {} } })
end))
assert(c.generation == generation and c.pending == pending)
assert(not c:start({}) and c.pending == pending)

-- Rejected driver transitions leave local state and progress unchanged.
driver.pause = function(token)
	assert(token == pending)
	return false
end
assert(not c:pause() and c.state == "running" and c.next == 1)
driver.pause = function()
	return true
end
assert(c:pause())
driver.resume = function(token)
	assert(token == pending)
	return false
end
assert(not c:resume() and c.state == "paused" and c.next == 1)
driver.resume = function()
	return true
end
assert(c:resume())

-- A paused gap queues no work, and duplicate terminal notifications advance only once.
local finished = callbacks[#callbacks]
finished("arrived")
assert(c:pause())
flush()
assert(c.state == "paused" and c.next == 65 and not c.pending)
finished("arrived")
assert(c.next == 65)
assert(c:resume())
flush()
assert(#batches[#batches] == 1 and batches[#batches][1].id == 65)
local token = c.pending
assert(token.generation == c.generation and token.serial == c.serial and token.last == 65)

-- Invalidation precedes synchronous cancellation callbacks, including replacement starts.
driver.cancel = function(oldToken)
	assert(oldToken.generation ~= c.generation)
	callbacks[#callbacks]("arrived")
end
assert(c:start(nodes(2)))
assert(c.next == 1 and c.pending ~= token)
c:stop()
flush()
assert(c.state == "stopped" and not c.pending)

-- Submission failure is explicit and terminal, with no automatic retry.
driver.submit = function()
	return false
end
assert(not c:start(nodes(2)))
assert(c.state == "stopped" and c.reason == "submission-failed")
flush()
assert(not c.pending)
print(
	"PASS: snapshot ownership; rejected pause/resume; paused gap; token identity; synchronous cancel; failed submission"
)

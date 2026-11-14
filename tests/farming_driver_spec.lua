-- luacheck: globals C_Timer InCombatLockdown CreateFrame
local queue, listeners, frames, submissions = {}, {}, {}, {}
local combat, corpse, occupied, owner, index, ended, failure, walkError, measured, accept, steer
local proofListeners = {}
local position = 0
local ns = { db = {}, Corpse = {} }
local function reset()
	queue, listeners, submissions = {}, {}, {}
	combat, corpse, occupied, owner, index, ended, failure, walkError = false, false, false, nil, nil, nil, nil, nil
	measured, accept, steer = true, true, true
end
reset()
C_Timer = {
	After = function(_, fn)
		queue[#queue + 1] = fn
	end,
}
InCombatLockdown = function()
	return combat
end
CreateFrame = function()
	local frame = { RegisterEvent = function() end }
	function frame:SetScript(_, fn)
		self.event = fn
	end
	frames[#frames + 1] = frame
	return frame
end
ns.Corpse.Active = function()
	return corpse
end
ns.HasJourney = function()
	return occupied
end
ns.JourneyOwner = function()
	return owner
end
ns.WorldPoint = function(map, x, y)
	return { map = map, x = x * 1000, y = y * 1000 }
end
ns.JourneyPosition = function()
	return position, position, 0, 1
end
ns.JourneyStatus = function()
	return false, 0, failure, false
end
ns.JourneyPlan = function()
	return { legs = { { mode = "walk", measured = measured, walkError = walkError } } }
end
ns.ObserveFarmingJourney = function(who, fn)
	local entry = { owner = who, fn = fn, active = true }
	proofListeners[#proofListeners + 1] = entry
	return function()
		entry.active = false
	end
end
local function proof(phase)
	local stop = submissions[#submissions][index]
	for _, entry in ipairs(proofListeners) do
		if entry.active and entry.owner == owner then
			entry.fn(phase, index, ns.WorldPoint(stop.map, stop.x, stop.y), ns.JourneyPlan())
		end
	end
end
local api = {}
ShortestPathForever = { API = api }
api.CurrentStop = function(who)
	return owner == who and index or nil
end
api.Ended = function()
	return ended
end
api.Subscribe = function(fn)
	local entry = { fn = fn, active = true }
	listeners[#listeners + 1] = entry
	return function()
		entry.active = false
	end
end
api.Cancel = function(who)
	assert(who == owner, "never cancel foreign route")
	owner, index, occupied, ended = nil, nil, false, "cancelled"
	return true
end
api.Pause = function()
	return steer and not combat and not corpse
end
api.Resume = api.Pause
ns.NavigateFarmingRoute = function(who, stops)
	assert(not occupied and not owner, "atomic ownership check")
	if not accept then
		return false
	end
	owner, index, occupied = who, 1, true
	submissions[#submissions + 1] = stops
	return true
end
local function flush()
	local work = queue
	queue = {}
	for _, fn in ipairs(work) do
		fn()
	end
end
local function notify()
	for _, entry in ipairs(listeners) do
		if entry.active then
			entry.fn({ stop = true, ended = true })
		end
	end
end
local function nodes(n)
	local out = {}
	for i = 1, n do
		out[i] = { uiMapID = 1, x = i / 1000, y = i / 1000, title = tostring(i) }
	end
	return out
end
assert(loadfile("Journey/FarmingCursor.lua"))("SPF", ns)
-- This is deliberately red before the driver exists.
assert(loadfile("Journey/Farming.lua"))("SPF", ns)
local function arrive()
	index = #submissions[#submissions]
	notify() -- observe the actual final stop and its settled measured walking plan
	local stop = submissions[#submissions][index]
	position = stop.x * 1000
	proof("arrived")
	owner, index, occupied, ended = nil, nil, false, "arrived"
	notify()
end
local c = ns.Farming.new()
assert(not c:Start(nodes(1)))
assert(not c:Start({ nodes(2)[1], nodes(2)[1] }))
assert(not c:Start({ { uiMapID = 1, x = 0 / 0, y = 0 } }))
occupied = true
assert(not c:Start(nodes(2))) -- unowned player journey
occupied = false
assert(c:Start(nodes(300)))
local firstOwner = owner
local stale = listeners[1].fn
for _ = 1, 5 do
	arrive()
	flush()
end
assert(#submissions[5] == 44 and submissions[5][44].title == "300")
assert(submissions[6][1].title == "1")
local state, _, nextStop, cycles = c:Status()
assert(state == "running" and nextStop == 1 and cycles == 1)
for i = 1, 300 do
	assert(submissions[math.floor((i - 1) / 64) + 1][(i - 1) % 64 + 1].title == tostring(i))
end
assert(owner ~= firstOwner and not listeners[1].active)
stale()
assert(c:Status() == "running")
steer = false
assert(not c:Pause() and c:Status() == "running")
steer = true
assert(c:Pause() and c:Status() == "paused")
steer = false
assert(not c:Resume() and c:Status() == "paused")
steer = true
assert(c:Resume())
-- Arrival while paused commits a completed batch but does not submit the next one.
assert(c:Pause())
local beforePaused = #submissions
arrive()
flush()
assert(c:Status() == "paused" and #submissions == beforePaused)
assert(c:Resume())
flush()
assert(#submissions == beforePaused + 1)
c:Stop()
stale()
flush()
assert(c:Status() == "stopped")
for _, reason in ipairs({ "cleared", "replaced", "cancelled", "none" }) do
	reset()
	assert(c:Start(nodes(2)))
	owner, index, occupied, ended = nil, nil, false, reason
	notify()
	flush()
	local status, why, at, rounds = c:Status()
	assert(status == "stopped" and why == (reason == "none" and "ownership-lost" or reason) and at == 1 and rounds == 0)
end
for _, reason in ipairs({ "nodata", "outside", "unreachable", "error" }) do
	reset()
	assert(c:Start(nodes(2)))
	walkError = reason
	proof("settled")
	flush()
	local status, why, at = c:Status()
	assert(status == "stopped" and why == reason and at == 1 and not occupied)
end
reset()
failure = "error"
assert(c:Start(nodes(2)))
assert(select(2, c:Status()) == "error")
reset()
accept = false
assert(not c:Start(nodes(2)))
assert(select(2, c:Status()) == "submission-failed")
reset()
assert(c:Start(nodes(2)))
owner, index, occupied, ended = nil, nil, false, "arrived"
notify()
assert(select(2, c:Status()) == "unverified-arrival")
reset()
assert(c:Start(nodes(2)))
index = 2
notify()
position = -1000
owner, index, occupied, ended = nil, nil, false, "arrived"
notify()
assert(select(2, c:Status()) == "unverified-arrival")
reset()
assert(c:Start(nodes(65)))
arrive()
combat = true
flush()
assert(c:Status() == "waiting" and #submissions == 1)
combat = false
frames[1].event()
flush()
assert(#submissions == 2)
c:Stop()
reset()
assert(c:Start(nodes(65)))
arrive()
corpse = true
flush()
assert(c:Status() == "waiting")
corpse = false
occupied = true
frames[1].event()
flush()
assert(select(2, c:Status()) == "occupied" and #submissions == 1)
reset()
assert(c:Start(nodes(65)))
arrive()
combat = true
flush()
c:Stop()
combat = false
frames[1].event()
flush()
assert(#submissions == 1)
reset()
combat = true
assert(not c:Start(nodes(2)))
combat, corpse = false, true
assert(not c:Start(nodes(2)))
reset()
assert(c:Start(nodes(2)))
local other = ns.Farming.new()
assert(not other:Start(nodes(2)))
local previous = owner
c:Stop()
assert(other:Start(nodes(2)) and owner ~= previous)
other:Stop()
flush()
reset()
assert(c:Start(nodes(300)))
for _ = 1, 10 do
	arrive()
	flush()
end
assert(select(4, c:Status()) == 2 and #submissions == 11 and #submissions[10] == 44)
c:Stop()
flush()
reset()
assert(c:Start(nodes(64)))
local liveOwner = owner
assert(not c:Start({ { uiMapID = 1, x = 0.1, y = 0.1, nested = {} } }))
assert(owner == liveOwner and c:Status() == "running")
owner = "PlayerOtherAddon"
notify()
assert(select(2, c:Status()) == "ownership-lost" and owner == "PlayerOtherAddon")
reset()
measured = false
assert(c:Start(nodes(2)))
index = 2
notify()
position = 2
owner, index, occupied, ended = nil, nil, false, "arrived"
notify()
assert(select(2, c:Status()) == "unverified-arrival")
reset()
local navigate = ns.NavigateFarmingRoute
ns.NavigateFarmingRoute = function(who, stops)
	navigate(who, stops)
	error("navigation producer failed")
end
assert(not c:Start(nodes(2)))
assert(select(2, c:Status()) == "navigation-error" and not occupied)
ns.NavigateFarmingRoute = navigate
flush()
assert(#queue == 0)
print("PASS: ownership, 300/tail/cycles, stale callbacks, pause/resume, verified arrival, path failures, event wake")

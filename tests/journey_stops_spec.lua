-- Real journey and API producers, with the client harness supplying native game APIs.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local timers = {}
env.C_Timer = {
	After = function(_, fn)
		timers[#timers + 1] = fn
	end,
}
local function flush()
	local pending = timers
	timers = {}
	for _, fn in ipairs(pending) do
		fn()
	end
end
local dead = false
env.UnitIsDeadOrGhost = function()
	return dead
end
driver.load("Journey/StopOrder.lua")
driver.load("UI/JourneyStops.lua")
local api, checks = env.ShortestPathForever.API, 0
local function eq(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function stop(x)
	return { map = 1, x = x, y = 0.5 }
end
local c = ns.JourneyStopsEditor.new()
eq(c:Start(), false, "empty draft")
for _, bad in ipairs({
	driver.secret,
	false,
	1,
	"stop",
	{},
	{ map = 1, x = driver.secret, y = 0.5 },
	stop(math.huge),
	stop(0 / 0),
	stop(-1),
	stop(1.1),
	{ map = 0, x = 0.5, y = 0.5 },
	{ map = 1, x = 0.5, y = 0.5, z = driver.secret },
}) do
	eq(c:Add(bad), false, "invalid input refused")
	eq(#c.stops, 0, "invalid input does not mutate")
end
local input = stop(0.502)
eq(c:Add(input), true, "one stop valid")
input.x = 0.9
eq(c.stops[1].x, 0.502, "caller input copied")
eq(c:Add(stop(0.502)), false, "duplicate focuses existing")
eq(#c.stops, 1, "duplicate unchanged")
eq(c.selected, 1, "duplicate selection")
eq(c:Add({ map = 1, x = 0.502, y = 0.5, z = 7 }), true, "distinct floor retained")
eq(c:Move(-1), true, "move up selects manual order")
eq(c.stops[1].z, 7, "floor survives move")
eq(c.manual, true, "explicit order")
eq(c:Remove(), true, "remove")
eq(c.stops[1].z, nil, "nearest surviving selection")
-- Manual one-stop routes use the real normal policy and finish once.
eq(c:Start(), true, "start one stop")
local owner = c.owner
local db = ns.db
ns.db = nil
c:Observe()
eq(c.owner, owner, "loading retains owner")
eq(c.state, "loading", "loading is not completion")
c:Stop()
eq(c.owner, owner, "loading cancellation failure retains owner")
ns.db = db
c:Observe()
eq(c.state, "running", "loading recovery")
dead = true
eq(c:Pause(), false, "death prevents pause")
dead = false
eq(api.CurrentStop(owner), 1, "exact owner")
eq(c:Add(stop(0.51)), false, "active draft locked")
eq(c:Clear(), false, "active clear locked")
eq(c:Move(1), false, "active order locked")
eq(c:Pause(), true, "pause")
eq(c.state, "paused", "paused state")
eq(c:Resume(), true, "resume")
driver.path.settle()
c:Detach()
eq(api.CurrentStop(owner), 1, "closing preserves guidance")
c:Attach(function() end)
eq(c.owner, owner, "reopen same owner")
driver.move({ map = 1, x = 0, y = -100, z = 0 })
for _ = 1, 4 do
	driver.update(0.1)
end
flush()
c:Observe()
eq(api.Ended(owner), "arrived", "real final arrival")
eq(c.state, "complete", "finite completion")
eq(c.owner, nil, "completion releases controller")
eq(#c.stops, 1, "completed draft retained")
for _ = 1, 4 do
	driver.update(0.1)
end
eq(ns.HasJourney(), false, "no idle loop")
-- An external journey is never replaced or cancelled by controller actions.
driver.move({ map = 1, x = 0, y = 0, z = 0 })
eq(c:Start(), true, "restart reusable draft")
local previous = c.owner
eq(api.Navigate("External", 1, 0.52, 0.5), true, "external replacement")
c:Observe()
eq(api.Ended(previous), "replaced", "explicit replaced proof")
eq(c.state, "changed", "replacement is not completion")
eq(c:Pause(), false, "cannot pause replacement")
eq(c:Resume(), false, "cannot resume replacement")
c:Stop()
eq(api.CurrentStop("External"), 1, "stop preserves external owner")
eq(c:Start(), false, "start refuses external owner")
eq(api.CurrentStop("External"), 1, "start preserves external owner")
api.Cancel("External")
-- Stop retains a copied reusable draft and cancels only its own exact owner.
eq(c:Start(), true, "start after external stop")
owner = c.owner
c:Stop()
eq(api.Ended(owner), "cancelled", "owned cancellation")
eq(#c.stops, 1, "stop retains draft")
env.InCombatLockdown = function()
	return true
end
eq(c:Start(), false, "combat guarded")
env.InCombatLockdown = function()
	return false
end
dead = true
eq(c:Start(), false, "death guarded")
dead = false
c:Detach()
-- Capacity and malformed late input must not damage a valid draft.
c:Clear()
for i = 1, 64 do
	eq(c:Add(stop(0.5 + i / 10000)), true, "capacity")
end
eq(c:Add(stop(0.8)), false, "65th stop refused")
eq(#c.stops, 64, "capacity unchanged")
eq(c:Add({ map = 1, x = 0.6, y = false }), false, "malformed late stop")
eq(#c.stops, 64, "malformed preserves all stops")
eq(c:Clear(), true, "clear draft")
eq(c.manual, false, "clear restores automatic default")
-- Automatic work retains a pending loading candidate and never submits on interruption.
c:Add(stop(0.502))
c:Add(stop(0.503))
eq(c:Start(), true, "automatic starts job")
local pending = c.job
local savedDB = ns.db
ns.db = nil
c:Step()
eq(c.state, "loading", "pending candidate waits for load")
eq(c.job, pending, "loading retains order job")
ns.db = savedDB
for _ = 1, 3 do
	c:Step()
end
eq(c.state, "running", "loading retry finishes order")
eq(c.activeStops[1].x, 0.502, "active list follows submitted order")
c:Stop()
eq(c:Start(), true, "new automatic job")
env.InCombatLockdown = function()
	return true
end
c:Step()
eq(c.job, nil, "combat cancels pending order")
eq(c.state, "order-combat", "combat requires explicit restart")
env.InCombatLockdown = function()
	return false
end
eq(c:Start(), true, "restart after combat")
dead = true
c:Step()
eq(c.job, nil, "death cancels pending order")
dead = false
eq(c:Start(), true, "restart after death")
driver.move({ map = 1, x = 0, y = -30, z = 0 })
for _ = 1, 3 do
	c:Step()
end
eq(c.state, "moved", "moved origin refuses stale order")
eq(ns.HasJourney(), false, "movement cannot submit stale origin")
driver.move({ map = 1, x = 0, y = 0, z = 0 })
eq(c:Start(), true, "restart before draft mutation")
pending = c.job
c:Add(stop(0.504))
eq(c.job, nil, "draft edit cancels order")
eq(pending.points, nil, "cancelled order publishes no points")
c:Step()
eq(ns.HasJourney(), false, "cancelled work never submits")
c:Clear()
c:Add(stop(0.502))
c:Add(stop(0.503))
eq(c:Start(), true, "context-sensitive order starts")
c:Step()
local known = ns.known or {}
ns.known = known
known[987654] = true
c:Step()
eq(c.state, "context-changed", "changed context asks explicit restart")
eq(c.job, nil, "changed context releases ordering")
eq(ns.HasJourney(), false, "mixed-context order cannot start")
known[987654] = nil
c:Clear()
-- A deliberate manual order bypasses greedy ordering and API copies the whole snapshot.
c:Add(stop(0.502))
c:Add(stop(0.503))
eq(c:Move(-1), true, "manual farther stop first")
eq(c:Start(), true, "manual multi-stop start")
eq(c.job, nil, "manual order does not estimate")
eq(c.activeStops[1].x, 0.503, "active list follows explicit order")
driver.path.settle()
local goal = api.Journey().goal
eq(goal.x, 0.503, "manual farther stop submitted first")
c.stops[1].x = 0.9
eq(api.Journey().goal.x, 0.503, "draft mutation cannot mutate active snapshot")
c:Stop()
c:Clear()
-- Malformed complete snapshots cannot submit a prefix or replace a journey.
for _, bad in ipairs({
	driver.secret,
	false,
	{},
	{ stop(0.51), false },
	{ [1] = stop(0.51), [3] = stop(0.52) },
	{ stop(0.51), extra = stop(0.52) },
	{ stop(0.51), { map = 1, x = driver.secret, y = 0.5 } },
}) do
	eq(c:Submit(bad), false, "whole snapshot rejected")
	eq(ns.HasJourney(), false, "no prefix submitted")
end
print("journey_stops_spec: " .. checks .. " checks passed")

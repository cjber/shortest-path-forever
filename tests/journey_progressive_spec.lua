-- A first search draws its estimate, then follows a route of settled walks while the proof continues, once every
-- route the bounds still allow starts with the same walk.
-- Later walks wait until they are next on foot, and a cancelled or restarted search never speaks late.
local SPEED = 7
local function at(a, b)
	return a.map == b.map and a.x == b.x and a.y == b.y
end

local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, walking = driver.ns, driver.path
local Search = ns.JourneySearch
walking.auto = false
walking.bound = function(_, from, to)
	-- What the walking search can promise before it has searched: the bare straight line.
	return math.sqrt((from.x - to.x) ^ 2 + (from.y - to.y) ^ 2)
end

-- Two passages lead on from the start's side to C, from A and from B; C walks on to the goal. A takes aSeconds to
-- walk to, B bSeconds once its walk is known.
local from, goal = { map = 1, x = 0, y = 0 }, { map = 1, x = 1000, y = 5000 }
local enter = { A = { map = 1, x = 500, y = 100 }, B = { map = 1, x = 500, y = 200 } }
local exit = { map = 1, x = 500, y = 4000 }
local exit2 = { map = 1, x = 900, y = 4600 }
ns.Portals = {
	{ name = "Passage to A", kind = "passage", from = enter.A, to = exit, seconds = 5 },
	{ name = "Passage to B", kind = "passage", from = enter.B, to = exit, seconds = 5 },
}
local seconds = { A = 300, B = 200 }
local origin = from
local function yards(a, b)
	if at(a, b) then
		return 0
	elseif at(a, origin) and at(b, enter.A) then
		return seconds.A * SPEED
	elseif at(a, origin) and at(b, enter.B) then
		return seconds.B * SPEED
	elseif at(b, goal) and at(a, exit) then
		return 600 * SPEED
	elseif at(b, goal) and at(a, exit2) then
		return seconds.D * SPEED
	end
	return 100000 * SPEED
end

local news, route, progress = {}, nil, { index = 1 }
local onRoute
local function listen(planned, what)
	news[#news + 1] = what
	if what == "route" then
		route, progress.index, progress.departed = planned, 1, false
		if onRoute then
			onRoute()
		end
	end
end
local function heard()
	local list = table.concat(news, " ")
	news = {}
	return list
end
local function via()
	return route and (at(route.legs[1].to, enter.A) and "A" or at(route.legs[1].to, enter.B) and "B")
end
local made
local function begin()
	made = #walking.batches
	origin = from
	driver.move(from)
	route, progress.index, progress.departed = nil, 1, false
	Search.Clear(false)
	Search.Start(goal, nil, progress, listen)
end
-- Settles some targets of an endpoint batch and runs the search's progress callback, as a slice of it would.
local function settle(batch, costOf)
	local costs = {}
	for i, target in ipairs(batch.targets) do
		costs[i] = costOf(target, i)
	end
	batch.costs, batch.valid, batch.revision = costs, true, batch.revision + 1
	batch.progress(costs, nil, batch)
	walking.runAll()
end
-- The start batch knows A; the goal batch knows everything: B is the walk still being searched.
local function half()
	local start, back = walking.batches[made + 1], walking.batches[made + 2]
	start.snapped, back.snapped = true, true
	settle(back, function(target)
		return yards(target, goal)
	end)
	settle(start, function(target)
		return at(target, enter.A) and yards(origin, target) or at(target, origin) and 0 or nil
	end)
	return start, back
end
local function geometry(fail)
	for _, job in ipairs(walking.waiting(walking.finds)) do
		if fail and fail(job) then
			walking.finish(job, nil, "unreachable")
		else
			walking.finish(job, { job.from, job.to }, yards(job.from, job.to))
		end
	end
end
-- Spends the probe budget on searches that learn nothing, so the endpoint searches must prove the route.
local function exhaust()
	for _, probe in ipairs(walking.waiting(walking.probes)) do
		probe.cpu = math.huge
		walking.finish(probe, nil, "spent")
	end
end
local function finish(batch)
	local costs = {}
	for i, target in ipairs(batch.targets) do
		costs[i] = at(batch.from, goal) and yards(target, goal) or yards(batch.from, target)
	end
	walking.finish(batch, costs)
end

-- While a walk not yet measured could start a faster route, nothing is followed: offering A would send the player one
-- way while the proof may choose B (#1032). The proof's route is then the one route.
seconds.B = 280
begin()
assert(heard() == "searching" and not route)
local start, back = half()
assert(heard() == "rough" and not route, "the estimate is drawn at once, never followed")
geometry()
assert(heard() == "" and not route, "no offer while B's bound could beat A")
assert(#walking.waiting(walking.finds) == 0, "no walk is drawn before the proof")
exhaust()
finish(start)
finish(back)
geometry()
assert(
	heard() == "route" and via() == "B" and not route.provisional and Search.Status() == 0,
	"the optimum is the route"
)
Search.Reset()

-- With the first walk settled and shared by every route the bounds still allow, the player follows it while the goal
-- side is proved: two passages lead on from A, and the walk on from the second one is still being searched. The
-- proof keeps the offered route without redrawing it, or replaces it exactly once.
local portals = ns.Portals
ns.Portals = {
	{ name = "Passage to C", kind = "passage", from = enter.A, to = exit, seconds = 5 },
	{ name = "Passage to D", kind = "passage", from = enter.A, to = exit2, seconds = 5 },
}
local function exitOf(planned)
	local far = planned.legs[2] and planned.legs[2].to
	return far and (at(far, exit) and "C" or at(far, exit2) and "D")
end
for _, secondsD in ipairs({ 200, 900 }) do
	seconds.D = secondsD
	begin()
	assert(heard() == "searching" and not route)
	local startBatch, goalBatch = walking.batches[made + 1], walking.batches[made + 2]
	startBatch.snapped, goalBatch.snapped = true, true
	settle(goalBatch, function(target)
		return not at(target, exit2) and yards(target, goal) or nil
	end)
	settle(startBatch, function(target)
		return at(target, enter.A) and yards(origin, target) or at(target, origin) and 0 or nil
	end)
	assert(heard() == "rough" and not route)
	geometry()
	assert(heard() == "route" and via() == "A" and exitOf(route) == "C" and route.provisional, "follow the shared walk")
	assert(Search.Status() > 0 and select(2, Search.Status()) == 0, "the proof is still in progress")
	local first = route
	local leg = first.legs[1]
	assert(leg.measured and not leg.walkDeferred and #leg.walkPoints >= 2)
	exhaust()
	finish(startBatch)
	finish(goalBatch)
	geometry()
	if secondsD < 600 then
		assert(heard() == "route" and exitOf(route) == "D" and route ~= first, "replace the offer exactly once")
	else
		assert(heard() == "times" and route == first, "keep the offered route without redrawing")
	end
	assert(not route.provisional and Search.Status() == 0)
	driver.update(0.2)
	Search.Poll()
	geometry()
	assert(heard() == "", "the proved route stays in place")
	Search.Reset()
end
ns.Portals = portals

-- A cancelled search is never heard from again, though its rough route was drawn.
begin()
heard()
start, back = half()
assert(heard() == "rough")
Search.Cancel()
finish(start)
finish(back)
geometry()
assert(heard() == "" and not route, "a cancelled search is never heard from again")
Search.Reset()

-- A restart while the rough route shows (the travel policy changed) settles once to the optimum.
seconds.B = 200
begin()
heard()
start, back = half()
assert(heard() == "rough")
origin = { map = 1, x = 40, y = 10 }
driver.move(origin)
Search.Poll(true)
-- The goal's costs are kept; only the start's search begins again.
local previous = start
start = walking.batches[#walking.batches]
assert(start ~= previous and not start.reverse and previous.cancelled)
exhaust()
finish(start)
finish(back)
geometry()
local told = heard()
-- Nothing was followed, so the restart is a first search again: it draws its new estimate, then the one route.
assert(told == "searching rough route" and via() == "B", told)
geometry()
driver.update(0.2)
Search.Poll()
assert(heard() == "", "no oscillation after settling")
Search.Reset()

-- A walk beyond the one being followed is drawn when it becomes the next on foot, keeping the progress made.
begin()
heard()
start, back = half()
exhaust()
finish(start)
finish(back)
geometry()
heard()
local settled = route
local last = settled.legs[#settled.legs]
assert(last.mode == "walk" and last.walkDeferred and not last.measured, "the walk from C is not drawn yet")
local finds = #walking.finds
progress.index, progress.departed = #settled.legs, false
-- The journey resumes where the player now stands, at the exit of the passage.
origin = last.from
driver.move(origin)
made = #walking.batches
Search.Start(goal, settled, progress, listen)
finish(walking.batches[made + 1])
assert(#walking.finds == finds + 1, "the next walk on foot is searched")
geometry()
assert(route == settled and progress.index == #settled.legs, "progress is kept")
assert(last.measured and not last.walkDeferred and #last.walkPoints >= 2)
assert(heard():find("walks") and Search.Status() == 0)
Search.Reset()
-- A route listener can end the journey immediately, including a route starting at a passage.
from = enter.A
for _, stop in ipairs({ Search.Reset, Search.Cancel }) do
	onRoute = stop
	begin()
	heard()
	start, back = half()
	exhaust()
	finish(start)
	finish(back)
	geometry()
	assert(Search.Status() == 0, "a listener's cancellation leaves no endpoint searches running")
end
onRoute = nil
Search.Reset()

-- A bind point's walks finishing after the search has published its route are never heard from late (#516).
from = { map = 1, x = 0, y = 0 }
local hearth = { map = 1, x = 900, y = 4900, spell = 8690, cast = 10000, bind = true }
-- On cooldown: the search never waits for its walks, though it hears when they end.
ns.teleports, ns.teleportReady = { hearth }, { 10 ^ 12 }
local far, bound = true, walking.bound
-- B's walk looks too far to matter until the route is shown, then worth measuring, as a boat's later departure would.
walking.bound = function(map, a, b)
	if far and (at(a, enter.B) or at(b, enter.B)) then
		return 10 ^ 7
	end
	return bound(map, a, b)
end
begin()
local landing
start, back = nil, nil
for i = made + 1, #walking.batches do
	local batch = walking.batches[i]
	if at(batch.from, hearth) then
		landing = batch
	elseif batch.reverse then
		back = batch
	else
		start = batch
	end
end
-- Both have settled the targets on their own node; only B, far away, is still unknown.
back.snapped, start.snapped = true, true
settle(back, function(target)
	return yards(target, goal)
end)
settle(start, function(target)
	return not at(target, enter.B) and yards(origin, target) or nil
end)
geometry()
exhaust()
geometry()
assert(heard():find("route") and via() == "A" and Search.Status() == 0, "the search is over")
far = false
local costs = {}
for i = 1, #landing.targets do
	costs[i] = 1000
end
walking.finish(landing, costs)
assert(heard() == "" and via() == "A", "a search that is over is never heard from")
walking.bound, ns.teleports, ns.teleportReady = bound, nil, nil
Search.Reset()
print(
	"journey_progressive_spec: the measured offer guides before the proof, the optimum replaces it only when different, "
		.. "later walks wait, a finished search stays quiet: ok"
)

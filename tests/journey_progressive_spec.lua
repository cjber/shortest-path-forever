-- A first search shows one usable route before its proof ends: the plan of settled walks alone, once the walk to
-- take first is drawn. The proof goes on and its optimum replaces that route once, whatever it gains. Later walks
-- are drawn only when they are the next on foot, and a cancelled or restarted search never speaks late.
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
end
-- The start batch knows A; the goal batch knows everything: B is the walk still being searched.
local function half()
	local start, back = walking.batches[made + 1], walking.batches[made + 2]
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

-- The settled walk gives the first route, shown once its first walk is drawn; the proof waits for that drawing.
begin()
assert(heard() == "searching" and not route)
local start, back = half()
assert(heard() == "" and not route, "no route before the first walk is drawn")
assert(start.paused and back.paused, "the endpoint searches wait for the walk being drawn")
assert(#walking.waiting(walking.finds) == 1, "only the first walk is searched")
geometry()
assert(heard() == "route" and via() == "A" and route.provisional, "the offer is the settled way")
assert(#walking.waiting(walking.probes) > 0, "the proof goes on, with probes first")
exhaust()
assert(not start.paused, "then the endpoint search it needs")
local first = route
local leg = route.legs[1]
assert(leg.measured and not leg.walkDeferred and leg.walkPoints and #leg.walkPoints >= 2)
assert(select(2, Search.Status()) == 0 and Search.Status() > 0, "the proof is still ahead")
local walks = #walking.finds
for _, later in ipairs(route.legs) do
	assert(later == leg or later.mode ~= "walk" or later.walkDeferred and not later.measured, "later walks wait")
end
geometry()
assert(#walking.finds == walks, "no later walk is searched while the first is followed")

-- The optimum replaces the offer once, whatever it gains.
seconds.B = 280
finish(start)
finish(back)
assert(heard() == "" and via() == "A", "its first walk is drawn before it is shown")
geometry()
assert(heard() == "route" and via() == "B" and not route.provisional and route ~= first)
assert(Search.Status() == 0, "the search is over")
driver.update(0.2)
Search.Poll()
geometry()
assert(heard() == "" and via() == "B", "it never swaps back")
Search.Reset()

-- The proof ending on the offered journey keeps it: only its times move.
seconds.B = 500
begin()
heard()
start, back = half()
geometry()
assert(heard() == "route" and via() == "A")
first = route
finish(start)
finish(back)
geometry()
assert(heard() == "times" and route == first and not route.provisional and Search.Status() == 0)
Search.Reset()

-- A proof that ends first leaves no offer: its search stops and the route is the proved one.
seconds.B = 200
begin()
heard()
start = half()
local drawing = walking.waiting(walking.finds)[1]
assert(drawing and start.paused)
Search.Cancel()
assert(drawing.cancelled and start.paused)
walking.finish(drawing, { drawing.from, drawing.to }, yards(drawing.from, drawing.to))
assert(heard() == "" and not route, "a cancelled search is never heard from again")
Search.Reset()

begin()
heard()
start, back = half()
drawing = walking.waiting(walking.finds)[1]
finish(start)
finish(back)
assert(drawing.cancelled, "the offer's first walk is dropped once the proof is in")
geometry()
assert(heard() == "route" and via() == "B" and not route.provisional and Search.Status() == 0)
Search.Reset()

-- A geometry failure on the offer's first walk offers nothing; the proof still gives its route.
begin()
heard()
start, back = half()
geometry(function(job)
	return at(job.to, enter.A)
end)
assert(heard() == "" and not route)
exhaust()
assert(not start.paused, "the proof goes on without the offer")
finish(start)
finish(back)
geometry()
assert(heard() == "route" and via() == "B")
Search.Reset()

-- A restart while the offer shows (the travel policy changed) settles once to the optimum, not twice.
begin()
heard()
start, back = half()
geometry()
assert(heard() == "route" and route.provisional)
local shown = route
origin = { map = 1, x = 40, y = 10 }
driver.move(origin)
Search.Poll(true)
-- The goal's costs are kept; only the start's search begins again.
local previous = start
start = walking.batches[#walking.batches]
assert(start ~= previous and not start.reverse and previous.cancelled)
seconds.B = 200
exhaust()
finish(start)
finish(back)
geometry()
local told = heard()
assert(not told:find("searching") and select(2, told:gsub("route", "")) == 1, told)
assert(via() == "B" and route ~= shown and not route.provisional)
geometry()
driver.update(0.2)
Search.Poll()
assert(heard() == "", "no oscillation after settling")
Search.Reset()

-- A walk beyond the one being followed is drawn when it becomes the next on foot, keeping the progress made.
begin()
heard()
start, back = half()
geometry()
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
-- A route listener can end the journey immediately, including a provisional route starting at a passage.
from = enter.A
for _, stop in ipairs({ Search.Reset, Search.Cancel }) do
	onRoute = stop
	begin()
	heard()
	half()
	geometry()
	assert(Search.Status() == 0, "a listener's cancellation leaves no endpoint searches running")
end
onRoute = nil
Search.Reset()
print("journey_progressive_spec: settled walks offer one route, the optimum replaces it once, later walks wait: ok")

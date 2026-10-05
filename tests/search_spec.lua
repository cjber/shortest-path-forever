-- The journey search across its own interface: the real planner, the walking search answered by the spec, and a
-- listener standing where Journey does.
local SPEED = 7
local function at(a, b)
	return a.map == b.map and a.x == b.x and a.y == b.y
end
---@param yards fun(from: table, to: table): number|false running yards between two places, false when unwalkable
---@param bound? fun(from: table, to: table): number what the walking search can promise before it has searched
local function harness(yards, bound)
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local ns, walking = driver.ns, driver.path
	local Search = ns.JourneySearch
	walking.auto = false
	walking.bound = bound and function(_, from, to)
		return bound(from, to)
	end
	local h = { ns = ns, driver = driver, walking = walking, Search = Search, news = {}, progress = { index = 1 } }
	local function listen(route, what)
		h.news[#h.news + 1] = what
		if what == "route" then
			h.route, h.progress.index, h.progress.departed = route, 1, false
		end
	end
	-- Journey's StartJourney: a repeated goal keeps its route.
	function h.start(from, goal)
		driver.move(from)
		local previous = Search.Clear(h.goal and Search.SamePlace(h.goal, goal)) and h.route
		h.goal, h.route = goal, previous or nil
		if not previous then
			h.progress.index, h.progress.departed = 1, false
		end
		Search.Start(goal, h.route, h.progress, listen)
	end
	function h.clear()
		Search.Reset()
		h.goal, h.route = nil, nil
	end
	-- A frame `seconds` later, and with replan Journey's timed replan in it.
	function h.frame(seconds, replan)
		driver.update(seconds)
		Search.Poll()
		if replan then
			Search.Replan(nil, nil, false)
		end
	end
	-- Ends the endpoint searches still running with every target's cost.
	function h.costs()
		for _, batch in ipairs(walking.waiting(walking.batches)) do
			local costs = {}
			for i, target in ipairs(batch.targets) do
				if batch.reverse then
					costs[i] = yards(target, batch.from)
				else
					costs[i] = yards(batch.from, target)
				end
			end
			walking.finish(batch, costs)
		end
	end
	-- Ends the leg searches still running with their drawn points, or without any for a leg `fail` picks.
	function h.geometry(fail)
		for _, job in ipairs(walking.waiting(walking.finds)) do
			if fail and fail(job) then
				walking.finish(job, nil, "unreachable")
			else
				walking.finish(job, { job.from, job.to }, yards(job.from, job.to))
			end
		end
	end
	-- The news since the last call, as one string.
	function h.heard()
		local heard = table.concat(h.news, " ")
		h.news = {}
		return heard
	end
	function h.status()
		local pending, _, _, loading = Search.Status()
		return pending, loading
	end
	return h
end

-- Two passages come out at the goal, entered from A and from B. A takes oldSeconds to walk to and B newSeconds,
-- once open: the planner prefers whichever the walking search has made faster.
local function scenario(oldSeconds, newSeconds)
	local from, goal = { map = 1, x = 0, y = 0 }, { map = 1, x = 1000, y = 0 }
	local enter = { A = { map = 1, x = 500, y = 100 }, B = { map = 1, x = 500, y = 200 } }
	local open = false
	local h = harness(function(a, b)
		if at(b, enter.A) then
			return oldSeconds * SPEED
		elseif at(b, enter.B) then
			return open and newSeconds * SPEED
		end
		return at(a, b) and 0
	end, function(a, b)
		if at(a, goal) then
			return at(a, b) and 0 or 1000 * SPEED
		end
		return at(b, enter.A) and 100 * SPEED or at(b, enter.B) and 150 * SPEED or 1000 * SPEED
	end)
	h.ns.Portals = {
		{ name = "Passage to A", kind = "passage", from = enter.A, to = goal, seconds = 5 },
		{ name = "Passage to B", kind = "passage", from = enter.B, to = goal, seconds = 5 },
	}
	h.enter = enter
	local costs = h.costs
	function h.costs(choice)
		open = choice == "B"
		costs()
	end
	function h.via()
		return h.route and (at(h.route.legs[1].to, enter.A) and "A" or at(h.route.legs[1].to, enter.B) and "B")
	end
	-- A minute on, the timed replan searches again from `point`, or from a little further along the way to A.
	local along = 0
	function h.refresh(point)
		along = along + 1
		h.driver.move(point or { map = 1, x = 50 * along, y = 10 * along })
		h.frame(60, true)
	end
	h.start(from, goal)
	return h
end

-- Both the costs and the geometry must be in before the one route is given.
do
	local h = scenario(300, 200)
	assert(h.heard() == "searching" and not h.route and select(2, h.status()))
	h.frame(1)
	h.costs("B")
	assert(h.heard() == "" and not h.route)
	h.geometry()
	local pending, loading = h.status()
	local news = h.heard()
	assert((news == "route" or news == "route times") and h.via() == "B" and pending == 0 and not loading)
	h.frame(0.1)
	assert(h.heard() == "")
	h.clear()
end

-- Long initial searches keep lower-bound guesses private and settle to the faster route.
for _, case in ipairs({ { 300, 275 }, { 600, 560 }, { 200, 175 }, { 270, 240 } }) do
	local h = scenario(case[1], case[2])
	h.frame(2.9)
	assert(h.heard() == "searching" and not h.route)
	h.frame(0.1)
	assert(h.heard() == "" and not h.route, "elapsed time cannot validate a guessed walk")
	h.costs("B")
	assert(h.heard() == "" and not h.route)
	h.geometry()
	assert(h.via() == "B" and not select(2, h.status()))
	assert(h.route.legs[1].measured)
	h.heard()
	h.geometry()
	h.frame(0.1)
	assert(h.heard() == "", "settled geometry does not publish another route")
	h.clear()
end

-- Timed background work never reports a search or an intermediate plan.
do
	local h = scenario(300, 275)
	h.costs("A")
	h.geometry()
	local route = h.route
	assert(h.heard():gsub(" times", "") == "searching route")
	h.refresh()
	assert(not select(2, h.status()) and h.status() > 0)
	h.costs("B")
	h.geometry()
	assert(h.heard() == "times" and h.route == route and h.status() == 0, "a rejected route still ends the search")
	h.clear()
end

-- A background search that finds a real gain swaps once its geometry is in.
do
	local h = scenario(300, 200)
	h.costs("A")
	h.geometry()
	h.heard()
	h.refresh()
	h.costs("B")
	assert(h.heard() == "" and h.via() == "A" and not select(2, h.status()))
	h.geometry()
	assert(h.heard() == "route" and h.via() == "B")
	h.clear()
end

-- Moving through many origins must evict old walks; clearing also discards a still-reusable recent walk.
do
	local h = scenario(300, 275)
	local goal = h.goal
	h.costs("A")
	h.geometry()
	for i = 1, 70 do
		h.refresh({ map = 1, x = 0, y = -i * 50 })
		h.costs("A")
		h.geometry()
	end
	local count = #h.walking.finds
	h.refresh({ map = 1, x = 0, y = 0 })
	h.costs("A")
	h.geometry()
	assert(#h.walking.finds == count + 1, "the oldest origin's geometry must have been evicted")
	h.clear()
	h.start({ map = 1, x = 0, y = 0 }, goal)
	h.costs("A")
	h.geometry()
	assert(#h.walking.finds == count + 2, "clear must release even the most recent walk")
	h.clear()
end

-- One walk, straight to the goal: what each search asks of the walking search, and what its answers may change.
do
	local here, target = { map = 1, x = 0, y = 0 }, { map = 1, x = 1200, y = 0 }
	local h = harness(function()
		return 1400
	end)
	local ns, walking = h.ns, h.walking
	local batches, finds, logs = walking.batches, walking.finds, {}
	ns.db.debug = true
	ns.Print = function(message)
		logs[#logs + 1] = message
	end
	local function begin()
		h.clear()
		h.start(here, target)
	end
	local function move(point)
		here = point
		h.driver.move(point)
	end
	local function round()
		return (select(2, h.Search.Status()))
	end
	local function drawn()
		return h.route.legs[1].walkPoints
	end

	-- Neither a frame nor the first batch to finish can choose a route before both batches have.
	begin()
	assert(h.heard() == "searching" and h.status() == 2 and round() == 0 and #batches == 2 and #finds == 0)
	h.frame(0.6, true)
	for _ = 1, 3 do
		h.frame(0.5, true)
	end
	walking.costs(batches[2], 1400)
	assert(h.heard() == "" and #finds == 0 and #batches == 2)
	walking.costs(batches[1], 1400)
	assert(h.heard() == "" and h.status() == 1 and round() == 1 and #finds == 1, "wait for the chosen geometry")
	local first = finds[1]
	local points = { first.from, { map = 1, x = 600, y = 300 }, first.to }
	-- Even a disagreement only logs; geometry cannot start another plan.
	walking.finish(first, points, 2100)
	assert(h.heard() == "route" and #finds == 1 and #logs == 1 and drawn()[2] == points[2] and h.status() == 0)

	-- The rest of the walk you are on is its own cost, retimed without shrinking it again.
	move({ map = 1, x = 600, y = 300 })
	for _ = 1, 2 do
		h.frame(5, true)
		assert(h.heard() == "times" and #batches == 2 and #finds == 1)
		assert(math.abs(h.route.legs[1].yards - 1050) < 0.01, "retiming must not repeatedly shrink the cost basis")
	end
	assert(drawn()[#drawn()] == first.to)
	-- A minute refreshes only the start batch, in the background; geometry stays as it is.
	h.frame(60, true)
	assert(#batches == 3 and not batches[3].reverse and #finds == 1 and #drawn() == 3)
	walking.costs(batches[3], 1300)
	assert(h.heard() == "times" and #finds == 1 and h.status() == 0)

	-- An off-route refresh keeps the old points while its costs and its replacement geometry are pending.
	move({ map = 1, x = 600, y = -100 })
	h.frame(5, true)
	assert(#batches == 4 and not batches[4].reverse and #finds == 1)
	walking.costs(batches[4], 1500)
	assert(#finds == 2 and drawn()[2] == points[2])
	walking.finish(finds[2], nil, "unreachable")
	assert(h.heard() == "route" and drawn()[2] == points[2] and h.status() == 0, "a failed refresh keeps the points")

	-- Starting another journey or ending this one cancels both kinds of search; a late answer changes nothing.
	begin()
	local stale = batches[#batches]
	begin()
	local current = batches[#batches]
	walking.costs(stale, 1400)
	assert(stale.cancelled and h.status() == 2)
	h.costs()
	local stalePoints = finds[#finds]
	h.clear()
	h.heard()
	walking.costs(current, 1400)
	walking.finish(stalePoints, points, 1400)
	assert(stalePoints.cancelled and h.heard() == "" and h.status() == 0)

	-- A blocked endpoint is settled once, and a move retries the start without repeating the goal batch.
	move({ map = 1, x = 0, y = 0 })
	begin()
	walking.costs(batches[#batches], false)
	walking.costs(batches[#batches - 1], false)
	assert(h.heard() == "searching route" and not h.route and h.status() == 0)
	local count = #batches
	h.frame(5, true)
	assert(#batches == count)
	move({ map = 1, x = 1, y = 0 })
	h.frame(5, true)
	assert(#batches == count + 1 and not batches[#batches].reverse)
	h.costs()
	walking.finish(finds[#finds], nil, "error")
	assert(#drawn() == 0, "a terminal failure cannot keep a straight estimate")
	count = #finds
	move({ map = 1, x = 2, y = 0 })
	h.frame(5, true)
	h.costs()
	assert(#finds == count + 1, "moving after a failed point search must search the replacement geometry")
	h.geometry()

	-- Changing the water mode searches both batches and the points again, keeping what is drawn until then.
	begin()
	h.costs()
	first = finds[#finds]
	points = { first.from, { map = 1, x = 600, y = 300 }, first.to }
	walking.finish(first, points, 1400)
	count = #batches
	ns.water = true
	h.frame(5, true)
	assert(#batches == count + 2 and batches[#batches].water)
	h.costs()
	assert(finds[#finds].water and drawn()[2] == points[2])
	walking.finish(finds[#finds], points, 1400)

	-- Cancelling a pending replacement must keep the drawing it inherited from an earlier completed search.
	ns.water = nil
	move({ map = 1, x = 0, y = 0 })
	begin()
	h.costs()
	first = finds[#finds]
	points = { first.from, { map = 1, x = 600, y = 300 }, first.to }
	walking.finish(first, points, 1400)
	move({ map = 1, x = 600, y = -100 })
	h.frame(5, true)
	h.costs()
	local cancelled = finds[#finds]
	ns.water = true
	h.frame(5, true)
	assert(cancelled.cancelled)
	h.costs()
	assert(drawn()[2] == points[2], "a second replacement cannot reset drawn geometry")
	walking.finish(cancelled, nil, "error")
	assert(h.status() > 0, "a cancelled search's answer cannot finish the current replacement")
	h.geometry()
	assert(h.status() == 0)

	-- A searched two-point path is still genuine geometry, and survives a failed off-route replacement.
	ns.water = nil
	move({ map = 1, x = 0, y = 0 })
	begin()
	h.costs()
	first = finds[#finds]
	walking.finish(first, { first.from, first.to }, 1400)
	move({ map = 1, x = 600, y = -100 })
	h.frame(5, true)
	h.costs()
	walking.finish(finds[#finds], nil, "error")
	assert(#drawn() == 2 and drawn()[2] == first.to)
	h.clear()
end

print("search_spec: measured guidance, private guesses, background replans, reuse and cancellation: ok")

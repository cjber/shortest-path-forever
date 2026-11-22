local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, path = driver.ns, driver.path
driver.env._G = driver.env
driver.load("Core/APIInput.lua")
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
driver.load("UI/NearbyRank.lua")

local here = { map = 1, x = 0, y = 0, z = -12 }
local departure = { map = 1, x = 70, y = 0, z = 0 }
local landing = { map = 1, x = 7000, y = 0, z = 0 }
local goal = { map = 1, x = 7070, y = 0, z = 8 }
ns.TaxiNodes = { departure, landing }
ns.TaxiPaths = { { from = 1, to = 2, seconds = 40 } }
ns.known = { [1] = true, [2] = true }
ns.Floor = {
	Height = function()
		return here.z
	end,
}
ns.SpawnHeight = function(_, x)
	return x > 7000 and goal.z or 0
end
driver.move(here)
path.Path.ReuseMany = function(batch, source)
	return batch and batch.valid and ns.JourneySearch.SamePlace(batch.from, source)
end
-- A zero walk between distinct endpoints is treated as a transfer by the plain grouping estimate.
path.bound = function(_, from, to)
	return math.abs(from.x - to.x)
end

-- The door out of the shop is around the back, and a wall also separates the landing from the trainer.
-- Give the journey and Nearby the same directed terrain costs for their endpoint searches.
local function cost(from, to)
	if from.z == here.z and to.z == departure.z and math.abs(to.x - departure.x) < 1 then
		return 350
	end
	if from == landing or math.abs(from.x - landing.x) < 1 then
		if to.z == goal.z then
			return 210
		end
	end
	return math.abs(from.x - to.x)
end
local function drain()
	for _ = 1, 100 do
		path.runAll()
		local batches, probes, finds = path.waiting(path.batches), path.waiting(path.probes), path.waiting(path.finds)
		if #batches + #probes + #finds == 0 then
			return
		end
		for _, batch in ipairs(batches) do
			local costs = {}
			for i, target in ipairs(batch.targets) do
				costs[i] = batch.reverse and cost(target, batch.from) or cost(batch.from, target)
			end
			path.finish(batch, costs)
		end
		for _, probe in ipairs(probes) do
			path.finish(probe, cost(probe.from, probe.to))
		end
		for _, find in ipairs(finds) do
			path.finish(find, { find.from, find.to }, cost(find.from, find.to))
		end
	end
	error("the terrain search did not settle")
end

local function candidateAt(x)
	return { map = 1, x = 0.5, y = 0.5 - x / 50000 }
end

local function rankCandidate(candidate, walks, callback)
	return ns.Path.Run(function(job)
		local rank = ns.NearbyRank.New({ candidate }, function(...)
			return ns.EstimateIn(job, ...)
		end, 1, 0.5, 0.5, walks)
		-- The first pass only orders candidates by their bounds. Drain the refinement pass for an exact time.
		local _, time, more
		repeat
			_, time, more = rank:Step()
		until not more
		return time
	end, callback)
end

local function nearby(candidate)
	local seconds
	ns.NearbyRank.MeasureWalks({ candidate }, function(walks, pending)
		if pending then
			return
		end
		rankCandidate(candidate, walks, function(time)
			seconds = time
		end)
	end, 1, 0.5, 0.5)
	drain()
	return assert(seconds)
end

local route
ns.JourneySearch.Start(goal, nil, { index = 1 }, function(plan, news)
	if news == "route" then
		route = plan
	end
end)
drain()
assert(route and route.legs[2].mode == "flight", "the journey flies to the far trainer")
local trainer = candidateAt(goal.x)
local beforeRide, beforeWalks = #path.probes, #path.batches
local partial
ns.Path.Run(function(job)
	return ns.EstimateIn(job, 1, 0.5, 0.5, trainer.map, trainer.x, trainer.y, nil, nil, trainer, 70)
end, function(time)
	partial = time
end)
drain()
assert(partial and partial > 70, "the first measured walk proves the ride loses")
assert(#path.probes == beforeRide + 1, "the second endpoint is skipped once the ride cannot win")
local departureProbe = path.probes[beforeRide + 1]
assert(departureProbe.from.z == here.z and departureProbe.to.x == departure.x, "the shared departure is priced first")
local seconds = nearby(trainer)
local journeySeconds = route.arrive / 1000
assert(math.abs(seconds - journeySeconds) < 0.001, ("Nearby %.3fs, journey %.3fs"):format(seconds, journeySeconds))
-- Grouping measures only direct walks that can win. This ride only needs its two endpoint probes.
assert(#path.batches == beforeWalks, "single ride endpoints do not start a walking batch")
assert(#path.probes == beforeRide + 2, "an uncapped estimate finishes the ride whose partial result was not cached")
local landingProbe = path.probes[beforeRide + 2]
assert(
	landingProbe.from.x == landing.x and landingProbe.to.z == goal.z,
	"the probe follows the landing to the NPC's floor"
)
assert(nearby(trainer) == seconds and #path.probes == beforeRide + 2, "both ride walks are reused from the same node")
local footSeconds = nearby(candidateAt(35))
assert(math.abs(footSeconds - 5) < 0.001, ("the nearby trainer takes %.3fs, expected five"):format(footSeconds))
assert(#path.batches == beforeWalks + 1, "a walking row only measures its direct walk")

driver.move({ map = 1, x = 12, y = 0, z = here.z })
local rank = rankCandidate(trainer, { [trainer] = 7058 }, function()
	error("a cancelled ranking answered")
end)
path.runAll()
local walking = path.waiting(path.probes)[1]
assert(walking and rank.paused, "a ranking waits off the queue when its endpoint walk is outstanding")
ns.NearbyRank.Cancel(rank)
assert(walking.cancelled, "closing the ranking cancels its endpoint probe")
path.finish(walking, 0)

-- The lower-bound ride costs less than the direct walk. Its measured departure changes the choice.
landing = { map = 1, x = 430, y = 0, z = 0 }
goal = { map = 1, x = 500, y = 0, z = 8 }
ns.TaxiNodes = { departure, landing }
ns.SpawnHeight = function(_, x)
	return math.abs(x - goal.x) < 1 and goal.z or 0
end
local endpointCost = cost
cost = function(from, to)
	if from.x == here.x and math.abs(to.x - goal.x) < 1 then
		return 560
	end
	return endpointCost(from, to)
end
driver.move(here)
route = nil
ns.JourneySearch.Start(goal, nil, { index = 1 }, function(plan, news)
	if news == "route" then
		route = plan
	end
end)
drain()
assert(route and #route.legs == 1 and route.legs[1].mode == "walk", "the journey switches to the direct walk")
local switchedSeconds = nearby(candidateAt(goal.x))
assert(
	math.abs(switchedSeconds - route.arrive / 1000) < 0.001,
	("Nearby measures the direct walk after the ride loses: Nearby %.3fs, journey %.3fs"):format(
		switchedSeconds,
		route.arrive / 1000
	)
)

-- The real queue must park a ranking and wake it from a FindMany callback, even for a terminal fallback.
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	driver.load(file)
end
local frames, resumed = {}, false
ns.Path.after = function(fn, delay)
	if not delay then
		frames[#frames + 1] = fn
	end
end
ns.Path.Run(function(job)
	ns.Path.FindMany(999, here, {}, function(_, reason)
		assert(reason == "nodata" and job.paused)
		ns.Path.Resume(job)
	end)
	ns.Path.Wait()
	resumed = true
end)
for _ = 1, 10 do
	local frame = table.remove(frames, 1)
	if not frame then
		break
	end
	frame()
end
assert(resumed and #frames == 0, "a real parked job resumes and drains the path queue")

-- A pending walk that is already cheaper defers refining a ride; a slower measured walk lets the ride win.
do
	local walk, ride = { map = 1, x = 0.4, y = 0.5 }, { map = 1, x = 0.6, y = 0.5 }
	local function rankWalkAgainstRide(walks, pending)
		local refinements = 0
		local choice = ns.NearbyRank.New({ walk, ride }, function(_, _, _, _, toX, _, walkCost, bound)
			if toX == walk.x then
				return walkCost
			end
			if not bound then
				refinements = refinements + 1
			end
			return 120
		end, 1, 0.5, 0.5, walks, pending)
		repeat
			local _, _, pendingSteps = choice:Step()
		until not pendingSteps
		return choice, refinements
	end
	local waiting, refinements = rankWalkAgainstRide({}, { [walk] = 10 })
	assert(
		waiting.best == walk and not waiting.exact and refinements == 0,
		"a cheaper pending walk defers ride refinement"
	)
	local settled, refined = rankWalkAgainstRide({ [walk] = 150 })
	assert(settled.best == ride and settled.exact and refined == 1, "a slower measured walk lets the ride win")
end

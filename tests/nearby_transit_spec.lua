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
		local _, time = rank:Step()
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
	end)
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
local beforeRide = #path.batches
local seconds = nearby(trainer)
local journeySeconds = route.arrive / 1000
assert(math.abs(seconds - journeySeconds) < 0.001, ("Nearby %.3fs, journey %.3fs"):format(seconds, journeySeconds))
local batches = #path.batches
assert(batches == beforeRide + 3, "the direct walk and the two ride endpoints each use one batch")
assert(nearby(trainer) == seconds and #path.batches == batches, "both ride walks are reused from the same node")
assert(math.abs(nearby(candidateAt(35)) - 5) < 0.001, "the nearby trainer still takes five seconds on foot")
assert(#path.batches == batches + 1, "a walking row only measures its direct walk")

driver.move({ map = 1, x = 12, y = 0, z = here.z })
local rank = rankCandidate(trainer, { [trainer] = 7058 }, function()
	error("a cancelled ranking answered")
end)
path.runAll()
local walking = path.waiting(path.batches)[1]
assert(walking and rank.paused, "a ranking waits off the queue when its endpoint walk is outstanding")
ns.NearbyRank.Cancel(rank)
assert(walking.cancelled, "closing the ranking cancels its endpoint batch")
path.costs(walking, 0)

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

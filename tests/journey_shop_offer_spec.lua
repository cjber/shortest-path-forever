-- #1032: from inside a Stormwind Trade District shop, the Cooking trainer is a short walk away. While the walk out of
-- the shop is still being searched, the journey once followed the only plan with no walk to wait for: Hearthstone to
-- Westfall and a flight back. Every route shown while that walk is held must start with a walk, and the journey must
-- settle on the walk alone. Nearby listed the trainer at the straight line's time; it now plans on the walk the
-- journey's own search measures, so both say the same.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
	"Data/TownAreas.lua",
	"Data/Heights.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
}) do
	driver.load(file)
end
assert(loadfile("tools/load_nav.lua"))(0)
driver.load("Core/APIInput.lua")
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
driver.env._G = driver.env
-- Stormwind City's map projects onto Eastern Kingdoms.
local project = driver.env.C_Map.GetWorldPosFromMapPos
driver.env.C_Map.GetWorldPosFromMapPos = function(map, point)
	local _, world = project(map, point)
	return 0, world
end
driver.env.C_Timer = { After = function() end }
for _, file in ipairs({
	"UI/MenuModifier.lua",
	"UI/NearbyGroups.lua",
	"UI/NearbyQuestie.lua",
	"UI/NearbyEntrances.lua",
	"UI/NearbyRoles.lua",
	"UI/NearbyProfessions.lua",
	"UI/NearbyRank.lua",
	"UI/Nearby.lua",
}) do
	driver.load(file)
end

local NOW = 123456
ns.NowMs = function()
	return NOW
end
local nextFrame
ns.Path.after = function(fn)
	nextFrame = fn
end
ns.faction, ns.water, ns.speed, ns.known = "Alliance", false, 7, {}
for id in pairs(ns.TaxiNodes) do
	ns.known[id] = true
end
-- Hearthstone bound at Sentinel Hill, ready to cast.
ns.teleports = { { map = 0, x = -10628, y = 1037, z = 34, spell = 8690, item = 6948, cast = 10000, bind = true } }
ns.teleportReady = { 0 }

-- The shop (Stormwind 64.9, 72.2) and Stephen Ryback, the Cooking trainer, on his own floor as Nearby asks for him.
local shop = { map = 0, x = -8832.076, y = 595.038 }
local ryback = { map = 0, x = -8611, y = 365 }
ryback.z = ns.SpawnHeight(0, ryback.x, ryback.y, 8)
assert(ryback.z, "Ryback stands over another surface")

-- The walk out of the shop is the slow search: hold it for HOLD frames while the rest settles.
local HOLD = 300
local held = {}
local many = ns.Path.FindMany
ns.Path.FindMany = function(map, from, targets, ...)
	local job = many(map, from, targets, ...)
	if from.x == shop.x and from.y == shop.y then
		ns.Path.Pause(job)
		held[#held + 1] = job
	end
	return job
end

local function drain(each)
	local frames = 0
	while nextFrame do
		local fn = nextFrame
		nextFrame = nil
		fn()
		frames = frames + 1
		assert(frames < 20000, "the search ends")
		if each then
			each(frames)
		end
	end
end

driver.move(shop)
ns.StartJourney(ryback)
driver.path.settle()
local offered = {}
drain(function(frames)
	if frames == HOLD then
		for _, job in ipairs(held) do
			ns.Path.Resume(job)
		end
	end
	local shown = driver.shown()
	if shown then
		offered[#offered + 1] = shown.legs[1].mode
	end
end)
assert(#held > 0, "the walk out of the shop was held")
assert(#offered > 0, "a route is shown")
for _, mode in ipairs(offered) do
	assert(mode == "walk", "no Hearthstone or flight is offered while the walk out is searched, got " .. mode)
end
local shown = driver.shown()
assert(#shown.legs == 1 and shown.legs[1].mode == "walk", "the route is the walk to the trainer")
assert((shown.arrive - NOW) / 1000 < 90, "a short walk, not a trip across the map")
local journey = (shown.arrive - NOW) / 1000

-- Nearby's row for the same trainer, from the same spot.
ns.Path.FindMany = many
local function ui(point)
	return 0.5 - point.y / 50000, 0.5 - point.x / 50000
end
local place = { map = 1453, id = 5482, name = "Stephen Ryback" }
place.x, place.y = ui(ryback)
local from = {}
from.x, from.y = ui(shop)
local listed
ns.NearbyServices.MeasureWalks({ place }, function(walks, pending)
	if pending then
		return
	end
	assert(walks[place], "the walk to the trainer is measured")
	ns.Path.Run(function(job)
		return ns.EstimateIn(job, 1453, from.x, from.y, place.map, place.x, place.y, walks[place])
	end, function(seconds)
		listed = seconds
	end)
end, 1453, from.x, from.y)
drain()
assert(listed, "Nearby lists a time")
assert(math.abs(listed - journey) < 1, string.format("Nearby lists %.0f s, the journey takes %.0f s", listed, journey))
-- The panel measures again every tick: standing still, the last walks answer without a new search. Floor keeps the
-- clusters around you decoded, so that answer needs no decode in the asking frame.
driver.load("Routing/Floor.lua")
ns.Floor.Sample(0, shop.x, shop.y)
drain()
ns.Floor.Sample(0, shop.x, shop.y)
local searched = false
ns.Path.FindMany = function(...)
	searched = true
	return many(...)
end
local again
ns.NearbyServices.MeasureWalks({ place }, function(walks)
	again = walks[place]
end, 1453, from.x, from.y)
drain()
assert(not searched and again, "standing still reuses the walks")
-- A setting the walks were searched under changes: the same spot needs a new search.
ns.db.followRoads = not ns.db.followRoads
again = nil
ns.NearbyServices.MeasureWalks({ place }, function(walks)
	again = walks[place]
end, 1453, from.x, from.y)
drain()
assert(searched and again, "a new road setting searches again")
-- A place no walk reaches is measured as such (false), not left to the straight line: the stub search finds none.
ns.db.followRoads = not ns.db.followRoads
ns.Path.FindMany = function(_, _, targets, callback)
	local costs = {}
	for at in ipairs(targets) do
		costs[at] = false
	end
	callback(costs)
	return {}
end
local unreachable
ns.NearbyServices.MeasureWalks({ place }, function(walks, pending)
	if not pending then
		unreachable = walks[place]
	end
end, 1453, from.x, from.y)
drain()
assert(unreachable == false, "a place no walk reaches is measured as false")
ns.Path.FindMany = many
-- A grouping that fails still answers, so a row or a menu choice falls back on the planner's own estimates.
local profile, handler = ns.Hazards.Profile, driver.env.geterrorhandler
ns.Hazards.Profile = function()
	error("profile")
end
driver.env.geterrorhandler = function()
	return function() end
end
local answered
ns.NearbyServices.MeasureWalks({ place }, function(walks, pending)
	answered = not pending and next(walks) == nil
end, 1453, from.x, from.y)
drain()
ns.Hazards.Profile, driver.env.geterrorhandler = profile, handler
assert(answered, "a failed grouping answers with no walks")
-- A place the map cannot project yet is asked again by the next measure, not left out for the session.
local other = { map = 1453, id = 1, name = "later" }
other.x, other.y = place.x, place.y
local worldPoint = ns.WorldPoint
ns.WorldPoint = function() end
ns.NearbyServices.MeasureWalks({ other }, function() end, 1453, from.x, from.y)
drain()
ns.WorldPoint = worldPoint
local later
ns.NearbyServices.MeasureWalks({ other }, function(walks, pending)
	if not pending then
		later = walks[other]
	end
end, 1453, from.x, from.y)
drain()
assert(later, "a projection that failed once is tried again")
-- The lower-bound plan to Ironforge already takes transport. It never enters a walk batch.
local ironforge = { id = 6, map = 1453, name = "Ironforge" }
ironforge.x, ironforge.y = ui(ns.TaxiNodes[6])
local pruned
ns.Path.FindMany = function()
	error("a place reached by transport must not start a terrain search")
end
ns.NearbyServices.MeasureWalks({ ironforge }, function(walks, pending)
	pruned = next(walks) == nil and pending == nil
end, 1453, from.x, from.y)
drain()
assert(pruned, "the Ironforge flight master is neither pending nor measured as a walk")
ns.Path.FindMany = many

-- A same-node requeue resumes an unfinished, reusable batch. The first progress notification exposes its source
-- node before it has settled the walk, so pausing here tests the actual Path.Resume frontier.
local paused, resumed, firstMeasure
ns.db.followRoads, ns.db.roadDetour = true, 17
local resume = ns.Path.Resume
ns.Path.Resume = function(job)
	if job.paused then
		resumed = job
	end
	resume(job)
end
ns.Path.FindMany = function(map, start, targets, callback, water, reverse, progress, hazards)
	assert(not paused, "the requeue starts no new FindMany")
	return many(map, start, targets, callback, water, reverse, function(costs, reason, job)
		progress(costs, reason, job)
		if job.sourceNode and not paused then
			assert(costs[1] == nil, "the walk is still pending")
			paused = job
			ns.NearbyServices.Pause(firstMeasure)
		end
	end, hazards)
end
firstMeasure = ns.NearbyServices.MeasureWalks({ other }, function() end, 1453, from.x, from.y)
drain()
assert(paused and paused.paused and ns.NearbyServices.Holds(firstMeasure), "the unfinished batch still holds")
local replacement = ns.NearbyServices.MeasureWalks({ other }, function(walks)
	again = walks[other]
end, 1453, from.x, from.y, firstMeasure)
ns.NearbyServices.Cancel(firstMeasure)
drain()
assert(resumed == paused and again, "the replacement resumes and reads the kept batch")
ns.NearbyServices.Cancel(replacement)
ns.Path.FindMany, ns.Path.Resume = many, resume

-- A journey started from Nearby stops the panel's measure, whose searches would share its frame budget.
local stopped, route = 0, driver.env.ShortestPathForever.API.NavigateRoute
ns.StopServiceRanking = function()
	stopped = stopped + 1
end
driver.env.ShortestPathForever.API.NavigateRoute = function()
	return true
end
ns.NearbyServices.Navigate("cooking", place)
driver.env.ShortestPathForever.API.NavigateRoute, ns.StopServiceRanking = route, nil
assert(stopped == 1, "a journey from Nearby stops the panel's measure")

-- A ranking decides on the walks measured so far: a place still searched counts at its walk's lower bound, so the
-- cheapest place is exact only when no pending place could beat it.
local near, far = { name = "near" }, { name = "far" }
local function Ranked(walks, pending)
	local rank = ns.NearbyServices.Rank({ near, far }, function(_, _, _, _, _, _, walk)
		return walk
	end, 1453, 0, 0, walks, pending)
	repeat
		local _, _, more = rank:Step()
	until not more
	return rank
end
local decided = Ranked({ [near] = 40 }, { [far] = 100 })
assert(decided.best == near and decided.exact, "a far place's lower bound above the best leaves the row decided")
local open = Ranked({ [near] = 40 }, { [far] = 30 })
assert(open.best == far and not open.exact, "a pending place that may be cheaper keeps the row open")
local tie = Ranked({ [far] = 40 }, { [near] = 40 })
assert(tie.best == far and tie.exact, "on a tie the measured place decides the row")
print("journey_shop_offer_spec: ok")

local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, walking = driver.ns, driver.path
local here, target = { map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 1200, y = 0 }

-- Journey follows what its search reports: nothing is drawn while it searches, then the one route, from where you
-- stand.
walking.auto = false
driver.begin(here, target)
local settling, round, pending = ns.JourneyStatus()
assert(settling and round == 0 and pending == 2 and not driver.shown())
assert(select(2, ns.JourneyInfo())[1].text == "Finding the fastest way…")
driver.move({ map = 1, x = 7, y = 0, z = 0 })
driver.update(0.6)
assert(not driver.shown(), "searching must not draw previews while walking")
driver.move(here)
for _, batch in ipairs(walking.batches) do
	walking.costs(batch, 1400)
end
assert(not driver.shown(), "wait for all chosen geometry before committing")
local first = walking.finds[1]
local points = { first.from, { map = 1, x = 600, y = 300 }, first.to }
walking.finish(first, points, 1400)
assert(driver.shown().legs[1].walkPoints[2] == points[2] and not ns.JourneyStatus())
assert(select(2, ns.JourneyInfo())[1].text ~= "Finding the fastest way…")
here = { map = 1, x = 300, y = 150 }
driver.move(here)
driver.update(5)
local trimmed = driver.shown().legs[1].walkPoints
assert(trimmed[1].x == 300 and trimmed[1].y == 150 and trimmed[2] == points[2], "drawn from where you stand")
ns.ClearJourney()
assert(not driver.shown() and not ns.JourneyInfo() and not ns.JourneyStatus())

-- A recent ride remains observed after disembarking; a docked boat must not force a round trip.
walking.auto = true
driver.load("Data/Routes.lua")
local ratchet = ns.Routes[241]
local dock = ns.Docks[ratchet.stops[1].dock]
ns.CurrentRide = function()
	return 241
end
ns.FreshAnchors = function()
	return { [241] = { epoch = 0 } }
end
ns.NextStop = function()
	return ratchet.stops[2].dock, ratchet.stops[2].arrive - ns.NowMs()
end
here = { map = dock.map, x = dock.x, y = dock.y, z = dock.z }
ns.NowMs = function()
	return ratchet.stops[1].arrive + 1000
end
driver.begin(here, { map = here.map, x = here.x + 100, y = here.y })
assert(
	#driver.shown().legs == 1 and driver.shown().legs[1].mode == "walk",
	"a docked Ratchet ride must allow the 100-yard walk"
)
here.x = here.x + 35
driver.update(5)
assert(
	#driver.shown().legs == 1 and driver.shown().legs[1].mode == "walk",
	"walking away must not restore the stale ride"
)
ns.ClearJourney()
ns.NowMs = function()
	return ratchet.stops[1].depart + 55000
end
driver.begin(here, { map = dock.map, x = dock.x + 100, y = dock.y })
assert(
	driver.shown().legs[1].mode == "boat" and driver.shown().legs[1].aboard,
	"a ride in transit must still reach its next dock"
)
ns.ClearJourney()

-- Real Auberdine geometry, the actual Guide consumer and next-frame notifications from our own writes.
for _, destination in ipairs({ { map = 1, x = 6400, y = 100 }, { map = 0, x = 2271.09, y = -5340.8 } }) do
	local live = assert(loadfile("tests/journey_driver.lua"))()
	local addon = live.ns
	for _, file in ipairs({
		"Data/Routes.lua",
		"Data/Transports.lua",
		"Data/Taxi.lua",
		"Data/Portals.lua",
		"Data/Walks.lua",
		"Routing/PathGrid.lua",
		"Routing/Path.lua",
		"Routing/PathJobs.lua",
		"UI/Arrow.lua",
	}) do
		live.load(file)
	end
	for _, mapID in ipairs({ 0, 1, 2991 }) do
		assert(loadfile("tools/load_nav.lua"))(mapID)
	end
	local nextFrame, searches = nil, 0
	addon.Path.after = function(fn)
		nextFrame = fn
	end
	local findMany = addon.Path.FindMany
	addon.Path.FindMany = function(...)
		searches = searches + 1
		return findMany(...)
	end
	local function frame()
		local fn = nextFrame
		nextFrame = nil
		if fn then
			fn()
		end
		live.update(1 / 60)
	end
	local function drain()
		local frames = 0
		while nextFrame do
			frame()
			frames = frames + 1
			assert(frames < 20000, "Auberdine search must settle")
		end
		assert(not addon.JourneyStatus())
	end
	local position = { map = 1, x = 6407.6, y = 509.8, z = 16 }
	live.begin(position, destination)
	drain()
	local route = live.shown()
	assert(route and route.legs[1].measured)
	local path = route.legs[1].walkPoints
	local initialWaypoint = live.waypoint()
	assert(initialWaypoint and addon.IsJourneyGuided(), "Auberdine must start Guide automatically")
	-- An unavailable sample spanning a replan used to discard the route and permanently stop Guide.
	for _, unavailable in ipairs({ {}, { x = live.secret, y = live.secret, map = live.secret } }) do
		local held = live.shown()
		live.move(unavailable)
		for _ = 1, 360 do
			frame()
		end
		assert(live.shown() == held and addon.IsJourneyGuided(), "unreadable position must preserve the journey")
		live.move(position)
		frame()
	end
	local travelled, changes, previous = 0, 0, live.waypoint()
	for i = 2, #path do
		local a, b = path[i - 1], path[i]
		local length = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
		local frames = math.max(1, math.ceil(length / 7 * 60))
		for step = 1, frames do
			local t = step / frames
			position = {
				map = a.map,
				x = a.x + t * (b.x - a.x),
				y = a.y + t * (b.y - a.y),
				z = a.z and b.z and a.z + t * (b.z - a.z),
			}
			live.move(position)
			frame()
			travelled = travelled + length / frames
			local bend = addon.GuideTargets()
			local marker, tracking = live.waypoint()
			assert(marker and tracking and addon.IsJourneyGuided(), "deferred writes must retain Guide ownership")
			assert(math.abs(marker.position.x - (0.5 - bend.y / 50000)) < 1e-9)
			assert(math.abs(marker.position.y - (0.5 - bend.x / 50000)) < 1e-9)
			if marker ~= previous then
				changes, previous = changes + 1, marker
			end
			local start = live.shown().legs[1].walkPoints[1]
			assert(
				(start.x - position.x) ^ 2 + (start.y - position.y) ^ 2 < 5 ^ 2,
				"drawn start must trim within half a second while walking"
			)
			if travelled >= 180 then
				break
			end
		end
		if travelled >= 180 then
			break
		end
	end
	assert(changes >= 2 and searches == 2, "following bends reuses settled costs")
	-- A minute and an off-route move each replace only the start-side search.
	for _ = 1, 3600 do
		frame()
	end
	drain()
	assert(searches == 3)
	position = { map = 1, x = position.x + 80, y = position.y }
	live.move(position)
	for _ = 1, 360 do
		frame()
	end
	drain()
	assert(searches == 4 and addon.IsJourneyGuided())
	-- Player ownership still wins after removing per-frame ownership polling.
	live.env.C_SuperTrack.SetSuperTrackedQuestID(99)
	frame()
	local manual = live.env.UiMapPoint.CreateFromCoordinates(1, 0.2, 0.3)
	live.env.C_Map.SetUserWaypoint(manual)
	frame()
	assert(not addon.IsJourneyGuided() and live.waypoint() == manual)
	addon.ClearJourney()
	-- A fresh engine ensures the recovery test cannot pass using an already settled endpoint cache.
	live.load("Routing/PathGrid.lua")
	live.load("Routing/Path.lua")
	live.load("Routing/PathJobs.lua")
	addon.Path.after = function(fn)
		nextFrame = fn
	end
	live.begin({}, destination)
	assert(addon.IsJourneyGuided() and not live.shown())
	live.move(position)
	live.update(0.1)
	assert(nextFrame and addon.JourneyStatus())
	-- Finishing endpoint callbacks without a readable player position must not strand pendingCosts.
	live.move({})
	local waitingFrames = 0
	while nextFrame do
		frame()
		waitingFrames = waitingFrames + 1
		assert(waitingFrames < 20000)
	end
	assert(addon.JourneyStatus() and addon.IsJourneyGuided())
	live.move(position)
	for _ = 1, 7 do
		frame()
	end
	drain()
	assert(live.waypoint() and addon.IsJourneyGuided())
	addon.ClearJourney()
	print(
		"Auberdine -> map " .. destination.map .. ": Guide bends, deferred events, position recovery and trimming: ok"
	)
end

-- UnitPosition's height is a placeholder 0: the journey plans from an unknown height, never the lowest floor.
driver.move({ map = 0, x = -8876.2, y = 610.9, z = 0 })
local x, _, z, map = ns.JourneyPosition()
assert(x == -8876.2 and z == nil and map == 0, "the placeholder height reached the planner")

-- The durable long-route regression uses real Journey, Path and all three nav maps.
assert(loadfile("tests/journey_bench.lua"))()
print("journey_spec: ok")

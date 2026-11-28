local function client(saved)
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local ns, env = driver.ns, driver.env
	ns.charDB = saved or {}
	driver.load("UI/Looks.lua")
	driver.load("Core/APIInput.lua")
	driver.load("Core/APIStops.lua")
	driver.load("Core/API.lua")
	driver.load("Journey/Itinerary.lua")
	driver.load("Journey/Resume.lua")
	driver.load("Journey/StopOrder.lua")
	driver.load("UI/JourneyStops.lua")
	driver.fire("PLAYER_ENTERING_WORLD")
	return driver, env.ShortestPathForever.API
end

local function stop(x, title)
	return { map = 1, x = x, y = 0.5, title = title }
end

local first, second, third = stop(0.502, "First"), stop(0.503, "Second"), stop(0.504, "Third")
local function savedWith(...)
	return { journey = { stops = { ... } } }
end

do
	local driver, api = client()
	local ns = driver.ns
	local c = ns.JourneyStopsEditor.new()
	assert(c:Add(second) and c:Add(first) and c:Move(-1) and c:Add(third))
	assert(c:Start())
	local saved = ns.charDB
	assert(saved.journey and #saved.journey.stops == 3, "a running stops journey is kept")
	assert(saved.journeyStops and saved.journeyStops.manual, "the explicit draft order is kept")
	driver.path.settle()
	driver.move({ map = 1, x = 0, y = -100, z = 0 })
	for _ = 1, 4 do
		driver.update(0.1)
	end
	assert(api.CurrentStop(c.owner) == 2, "the journey advanced to its second stop")
	assert(#saved.journey.stops == 2 and saved.journey.stops[1].title == "Second", "completed stops are dropped")
	assert(#saved.journeyStops.stops == 3, "the reusable draft keeps all three stops")
	local fresh, freshAPI = client(saved)
	fresh.update(2)
	local restored = fresh.ns.JourneyStopsEditor.Current()
	assert(restored.manual and #restored.stops == 3, "the draft and order survive login")
	assert(freshAPI.CurrentStop(restored.owner) == 1 and fresh.ns.JourneyGoal().label == "Second")
	fresh.move({ map = 1, x = 0, y = -150, z = 0 })
	for _ = 1, 4 do
		fresh.update(0.1)
	end
	assert(#saved.journey.stops == 1 and saved.journey.stops[1].title == "Third", "the last stop is still kept")
	local last = client(saved)
	last.update(2)
	assert(last.ns.JourneyGoal().label == "Third", "a single remaining stop can resume as an editable-window journey")
	restored = last.ns.JourneyStopsEditor.Current()
	restored:Stop()
	assert(saved.journey == nil, "stopping forgets the itinerary")
	assert(restored:Remove() and #saved.journeyStops.stops == 2, "removing updates the saved draft")
	assert(restored:Clear() and saved.journeyStops == nil, "clearing forgets the draft and its order")
end

-- Re-adoption has its own fixture: the new controller has never submitted a journey.
do
	local driver, api = client(savedWith(second, third))
	driver.update(2)
	assert(driver.ns.JourneyGoal() and driver.ns.JourneyGoal().label == "Second", "the saved route starts")
	local c = driver.ns.JourneyStopsEditor.Current()
	assert(c.owner == driver.ns.JourneyOwner() and api.CurrentStop(c.owner) == 1, "the controller adopts the owner")
	assert(c.index == 1 and #c.activeStops == 2 and c.activeStops[2].title == "Third", "it adopts the remaining rows")
	assert(not c:Editable() and c:Pause() and c:Resume(), "the resumed journey can pause and resume")
	c:Stop()
	assert(not driver.ns.HasJourney(), "the controller can stop the resumed journey")
end

do
	local driver, api = client()
	local ns = driver.ns
	assert(api.Navigate("Shortest Path Forever", first.map, first.x, first.y, first.title))
	local original = ns.JourneyGoal()
	local c = ns.JourneyStopsEditor.Current()
	assert(c:Submit({ first }) and ns.JourneyGoal() == original, "the API hands over the same place")
	assert(ns.charDB.journey.stops[1].title == first.title, "a handover is kept as a Journey stops route")
	assert(api.Navigate("External", first.map, first.x, first.y, first.title))
	driver.fire("PLAYER_LOGOUT")
	assert(ns.charDB.journey == nil, "logout detects a same-place handover to another addon")
end

do
	local saved = savedWith(second, third)
	local driver, api = client(saved)
	assert(api.Navigate("External", 1, 0.52, 0.5))
	driver.update(2)
	assert(api.CurrentStop("External") == 1 and saved.journey == nil, "the external owner goes first")
end

do
	local saved = savedWith(second, third)
	local driver, api = client(saved)
	driver.env.InCombatLockdown = function()
		return true
	end
	driver.update(2)
	assert(not driver.ns.HasJourney() and saved.journey, "the itinerary waits through combat")
	driver.env.InCombatLockdown = function()
		return false
	end
	local corpse = true
	driver.ns.Corpse = {
		Active = function()
			return corpse
		end,
	}
	driver.fire("PLAYER_REGEN_ENABLED")
	local c = driver.ns.JourneyStopsEditor.Current()
	assert(api.CurrentStop(c.owner) == 1 and not driver.ns.JourneyPlan(), "the route queues behind the corpse run")
	corpse = false
	driver.ns.ResumeJourney()
	driver.path.settle()
	assert(driver.ns.JourneyPlan(), "the queued stop plans after resurrection")
end

do
	local saved = savedWith(first, { map = 1, x = math.huge, y = 0.5 })
	saved.journeyStops = { manual = true, stops = { [1] = first, [3] = third } }
	local driver = client(saved)
	driver.update(2)
	assert(not driver.ns.HasJourney() and saved.journey == nil, "a damaged itinerary is dropped in full")
	local c = driver.ns.JourneyStopsEditor.Current()
	assert(#c.stops == 0 and not c.manual and saved.journeyStops == nil, "a damaged draft is dropped")
end

-- Inside a dungeon there is no position and the API refuses the route: it waits there, through a second reload.
do
	local saved = savedWith(second, third)
	local function inside()
		local driver, api = client(saved)
		local position = driver.env.UnitPosition
		driver.env.UnitPosition = function() end
		driver.env.C_Map.GetPlayerMapPosition = function() end
		driver.update(2)
		return driver, api, position
	end
	local driver = inside()
	assert(not driver.ns.HasJourney() and #saved.journey.stops == 2, "a refused route is kept")
	driver.fire("PLAYER_REGEN_ENABLED")
	assert(#saved.journey.stops == 2, "the end of combat inside keeps it too")
	driver.fire("PLAYER_LOGOUT")
	assert(#saved.journey.stops == 2, "logout keeps it")
	local again, api, position = inside()
	again.env.UnitPosition = position
	again.fire("PLAYER_ENTERING_WORLD")
	again.update(2)
	local c = again.ns.JourneyStopsEditor.Current()
	assert(api.CurrentStop(c.owner) == 1 and #saved.journey.stops == 2, "leaving the instance starts it")
end

-- A Start made while the kept route waits wins over it.
do
	local saved = savedWith(second, third)
	local driver, api = client(saved)
	local c = driver.ns.JourneyStopsEditor.Current()
	assert(c:Add(first) and c:Add(third) and c:Start())
	driver.update(2)
	assert(c.job and not driver.ns.HasJourney(), "the kept route leaves the ordering alone")
	for _ = 1, 4 do
		c:Step()
	end
	assert(api.CurrentStop(c.owner) == 1 and driver.ns.JourneyGoal().label == "First", "the new order starts")
end

do
	local saved = savedWith(second, third)
	local driver = client(saved)
	driver.ns.db.journey = false
	driver.update(2)
	assert(not driver.ns.HasJourney() and saved.journey == nil, "Journeys off drops a kept route")
end

print("journey_stops_resume_spec: ok")

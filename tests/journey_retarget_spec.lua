-- A guide that re-points at the stop it already had, or moves it to another objective of the step it is on, must not
-- restart the journey. Restarting tore down the drawn route, the tracker and the native waypoint, and the tracking
-- writes that went with it made the guide re-point again: the arrow, the line and the tracker flashed between two
-- objectives while the player stood between them (#693).
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env

driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API

-- Two objectives of one guide step on a zone map, 1000 yards apart: the map coordinates and the world points the route
-- draws to.
local ONE_MAP, TWO_MAP = { map = 1, x = 0.4, y = 0.5 }, { map = 1, x = 0.42, y = 0.5 }
local ONE, TWO = ns.WorldPoint(1, 0.4, 0.5), ns.WorldPoint(1, 0.42, 0.5)

local starts, searches, writes, clears = 0, 0, 0, 0
local startJourney, startSearch = ns.StartJourney, ns.JourneySearch.Start
ns.StartJourney = function(...)
	starts = starts + 1
	return startJourney(...)
end
ns.JourneySearch.Start = function(...)
	searches = searches + 1
	return startSearch(...)
end
local setWaypoint, clearWaypoint = env.C_Map.SetUserWaypoint, env.C_Map.ClearUserWaypoint
env.C_Map.SetUserWaypoint = function(point)
	writes = writes + 1
	return setWaypoint(point)
end
env.C_Map.ClearUserWaypoint = function(...)
	clears = clears + 1
	return clearWaypoint(...)
end
-- The arrow places the bend it is handed at once, as the real one's poll does; the guide then writes its waypoint.
ns.PointGuideArrow = function(points, placeBend)
	if points and placeBend then
		placeBend(points[#points], false)
	end
end

---@param point table a map point
---@return table
local function stop(point, title)
	return { map = point.map, x = point.x, y = point.y, title = title }
end

---@return string?
local function title()
	return (ns.JourneyInfo())
end

---@return table? goal
local function goal()
	return ns.JourneyGoal()
end

---@return table? legs
local function planned()
	local plan = ns.JourneyPlan()
	return plan and plan.legs
end

---@param legs table?
---@param point table a world point
---@return boolean
local function endsAt(legs, point)
	local last = legs and legs[#legs]
	if not last then
		return false
	end
	local to = last.to
	return to.map == point.map and to.x == point.x and to.y == point.y
end

driver.move({ map = 1, x = 0, y = 0, z = 0 })
assert(API.NavigateRoute("Guide", { stop(ONE_MAP, "Objective One") }), "a guide starts a journey")
driver.path.settle()
assert(API.CurrentStop("Guide") == 1, "the guide owns the journey")
assert(ns.IsJourneyGuided(), "every journey starts guided")
assert(driver.waypoint(), "the guide writes its waypoint")
assert(title() == "Journey to Objective One", "the tracker names the objective")
assert(starts == 1 and searches == 1, "one journey, one search")
local held = driver.shown()
assert(held and endsAt(held.legs, ONE), "the map draws the route to the objective")
local heldWrites, heldClears = writes, clears

-- The same destination sent again, as a guide does when it answers our tracking writes: a relabel, not a journey.
assert(API.NavigateRoute("Guide", { stop(ONE_MAP, "Objective One renamed") }))
driver.update(0)
assert(starts == 1, "the same destination is not a new journey")
assert(searches == 1, "and is not searched again")
assert(writes == heldWrites and clears == heldClears, "the guide's waypoint is never taken away")
assert(driver.waypoint(), "guidance keeps its waypoint")
assert(ns.IsJourneyGuided(), "and stays guided")
assert(title() == "Journey to Objective One renamed", "the stop is relabelled in place")
assert(API.CurrentStop("Guide") == 1, "the stop under way is kept")

-- The guide moves to the other objective of its step in the same area: the goal moves, the journey stays, and the
-- route already drawn stays until the new plan lands, so nothing blanks or flashes.
assert(API.NavigateRoute("Guide", { stop(TWO_MAP, "Objective Two") }))
assert(starts == 1, "a moved objective is not a new journey")
assert(searches == 2, "only the search for the new place starts")
assert(ns.IsJourneyGuided(), "guidance is not stopped and started again")
assert(driver.waypoint(), "the guide keeps its waypoint while the new plan is searched")
assert(writes == heldWrites and clears == heldClears, "and does not rewrite it for the move")
assert(goal().label == "Objective Two", "the journey's goal is the new objective")
local drawn = driver.shown()
assert(drawn and endsAt(drawn.legs, ONE), "the route already drawn stays until the new plan lands")
assert(title() == "Journey to Objective Two", "the tracker names the new objective at once")
driver.path.settle()
assert(driver.shown() and endsAt(planned(), TWO), "the new plan replaces the drawn route once")
assert(title() == "Journey to Objective Two", "the tracker keeps the new objective")
assert(starts == 1, "the move never restarts the journey")

-- TomTom and RestedXP re-point their arrow whenever the destination tracking they were given changes, including for
-- our own writes. That echo names the stop the journey already has and must not restart it.
local echo = env.CreateFrame("Frame")
echo:RegisterEvent("SUPER_TRACKING_CHANGED")
echo:RegisterEvent("USER_WAYPOINT_UPDATED")
echo:SetScript("OnEvent", function()
	assert(API.NavigateRoute("Guide", { stop(TWO_MAP, "Objective Two") }))
end)
local startsBefore, searchesBefore = starts, searches
for _ = 1, 10 do
	driver.update(0.1)
end
assert(starts == startsBefore, "an arrow re-pointed at the journey's own stop starts nothing")
assert(searches == searchesBefore, "and searches nothing")
assert(ns.IsJourneyGuided() and driver.waypoint(), "guidance survives the echo")
assert(API.CurrentStop("Guide") == 1, "the journey is still the guide's")
echo:SetScript("OnEvent", nil)

-- A player picking a quest of their own ends the guide's waypoint. When the guide then moves to another objective,
-- the held route must leave the quest tracked until the new plan can lead to the new objective.
env.C_SuperTrack.SetSuperTrackedQuestID(999)
driver.update(0)
assert(driver.waypoint() == nil and not ns.JourneyPinTracked(), "the player's quest selection takes the marker")
assert(API.NavigateRoute("Guide", { stop(ONE_MAP, "Objective One") }))
assert(driver.waypoint() == nil and not ns.JourneyPinTracked(), "the held route does not reclaim the marker")
assert(env.C_SuperTrack.GetSuperTrackedQuestID() == 999, "the quest stays tracked while the new objective plans")
driver.path.settle()
assert(ns.JourneyPinTracked(), "the guide leads again once the replacement plan is ready")
assert(driver.waypoint() ~= nil and endsAt(planned(), ONE), "the new plan has a waypoint")

do
	ns.ClearJourney()
	local instance = 33
	ns.Entrances = { [instance] = { map = 1, x = ONE.x, y = ONE.y, name = "Test Dungeon" } }
	local inside = false
	env.GetInstanceInfo = function()
		return nil, nil, nil, nil, nil, nil, nil, inside and instance or nil
	end
	env.GetRealZoneText = function()
		return "Test Dungeon"
	end
	local first = { map = instance, x = 0.4, y = 0.5, title = "First objective" }
	local moved = { map = instance, x = 0.42, y = 0.5, title = "Moved objective" }
	local nextStop = stop(TWO_MAP, "Next stop")
	assert(API.NavigateRoute("Guide", { first, nextStop }))
	driver.path.settle()
	local doorPlan, searchCount = ns.JourneyPlan(), searches
	assert(API.NavigateRoute("Guide", { moved, nextStop }))
	assert(goal().stop.label == moved.title, "the shared door represents the replacement objective")
	assert(ns.JourneyPlan() == doorPlan and searches == searchCount, "the shared door keeps its settled route")
	inside = true
	driver.fire("PLAYER_ENTERING_WORLD")
	driver.update(0.1)
	assert(API.CurrentStop("Guide") == 2, "entering the dungeon advances to the next stop")
end

do
	ns.ClearJourney()
	driver.move({ map = 1, x = 0, y = 0, z = 0 })
	assert(API.NavigateRoute("Guide", { stop(ONE_MAP, "Old stop") }))
	driver.path.settle()
	local retained = ns.JourneyPlan()
	assert(API.NavigateRoute("Guide", { stop(TWO_MAP, "New stop") }))

	local dead = true
	ns.Corpse = {
		Active = function()
			return dead
		end,
	}
	ns.SuspendJourney()
	driver.move(ONE)
	driver.path.auto = false
	dead = false
	ns.ResumeJourney()
	assert(ns.JourneyPlan() == retained, "resurrection keeps the displayed route until the replacement settles")
	driver.update(0.1)
	assert(goal() and goal().label == "New stop", "reaching the superseded route's end after resurrection cannot arrive")
	driver.path.auto = true
	driver.path.settle()
	assert(endsAt(planned(), TWO), "the resumed replacement reaches the new stop")
end

do
	ns.ClearJourney()
	driver.move({ map = 1, x = 0, y = 0, z = 0 })
	assert(API.NavigateRoute("Guide", { stop(ONE_MAP, "Old stop") }))
	driver.path.settle()
	local retained = ns.JourneyPlan()
	local path = driver.path
	local find = path.Path.Find
	path.Path.Find = function(...)
		path.auto = false
		return find(...)
	end
	assert(API.NavigateRoute("Guide", { stop(TWO_MAP, "New stop") }))
	path.settle()
	path.Path.Find = find
	assert(#path.waiting(path.finds) > 0 and ns.JourneyPlan() == retained, "replacement walk geometry is pending")

	local flying = true
	env.UnitOnTaxi = function()
		return flying
	end
	path.auto = true
	path.settle()
	assert(ns.JourneyPlan() == retained, "a replacement walk cannot take over after taxi boarding")
	driver.update(0.1)
	assert(ns.JourneyPlan() == retained, "the replacement continues to wait in flight")
	flying = false
	local landing = { map = 1, x = 500, y = 0, z = 0 }
	driver.move(landing)
	driver.update(0.1)
	local legs = planned()
	assert(endsAt(legs, TWO) and legs[1].from.x == landing.x, "the replacement starts at the taxi landing")
end

print("journey retarget: guide updates preserve stop identity and the followed route")

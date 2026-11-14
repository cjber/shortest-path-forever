-- A guide that re-points at the stop it already had, or moves it to another objective of the step it is on, must not
-- restart the journey. Restarting tore down the drawn route, the tracker and the native waypoint, and the tracking
-- writes that went with it made the guide re-point again: the arrow, the line and the tracker flashed between two
-- objectives while the player stood between them (#693).
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env

driver.load("UI/Looks.lua")
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
echo:UnregisterAllEvents()

-- A player picking a quest of their own ends the guide's waypoint. When the guide then moves to another objective,
-- that destination is a guide instruction, not the player's: the guide leads again instead of leaving no marker.
env.C_SuperTrack.SetSuperTrackedQuestID(999)
driver.update(0)
assert(driver.waypoint() == nil and not ns.JourneyPinTracked(), "the player's quest selection takes the marker")
assert(API.NavigateRoute("Guide", { stop(ONE_MAP, "Objective One") }))
assert(ns.JourneyPinTracked(), "the guide leads again for the objective it moved to")
assert(driver.waypoint() ~= nil, "with its waypoint written afresh")
driver.path.settle()

print("journey retarget: a guide re-pointing at its stop keeps the journey")

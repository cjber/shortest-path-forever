-- Run from the repository root: luajit tests/guide_navigation_spec.lua
-- Native navigation belongs to whoever holds it (#531): Adventure Guide focuses the quest whose area the player
-- walked into and restores the super-tracked waypoint afterwards, so a quest that stays selected while the guide's
-- waypoint is still super-tracked and leading is not the player taking navigation over. A player's own quest click
-- still yields, because the waypoint is no longer the one being tracked.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env

driver.move({ map = 1, x = 0, y = 0, z = 0 })
local placeBend
ns.PointGuideArrow = function(_, callback)
	placeBend = callback
end
ns.JourneyGuide.Start()
ns.JourneyGuide.To({ map = 1, x = 1200, y = 0 }, { { map = 1, x = 1200, y = 0 } }, { routeTitle = "Test destination" })
assert(placeBend, "the guide hands its bend to the arrow")
assert(placeBend({ map = 1, x = 1200, y = 0 }), "the guide writes and tracks its waypoint")
local waypoint = driver.waypoint()
assert(waypoint, "the guide holds a waypoint")
assert(ns.JourneyPinTracked(), "the guide's waypoint is tracked")

-- Adventure Guide focuses the quest whose area the player walked into, then keeps the waypoint it found tracked.
-- SUPER_TRACKING_CHANGED arrives after both writes, as the client dispatches events at the frame boundary.
env.C_SuperTrack.SetSuperTrackedQuestID(226)
env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
driver.update(0)
assert(driver.waypoint(), "a quest focused behind the guide's waypoint leaves the waypoint in place")
assert(select(2, driver.waypoint()), "and still super-tracked")
assert(ns.JourneyPinTracked(), "so the guide has not yielded")

-- A guide selecting its quest can leave the waypoint super-tracked while reporting the quest as the leading type for
-- a moment. Which icon the client draws is not ownership: the waypoint is still the destination it follows, so the
-- guide keeps it and does not yield (#693).
driver.setTrackingType("quest")
driver.update(0)
assert(driver.waypoint(), "a transient quest priority keeps the guide's waypoint")
assert(ns.JourneyPinTracked(), "and the guide still owns navigation")

-- The player clicking a quest is a different thing: nothing restores the waypoint, so the guide yields and clears
-- its waypoint while the route arrow keeps leading.
env.C_SuperTrack.SetSuperTrackedQuestID(999)
driver.update(0)
assert(driver.waypoint() == nil, "the player's quest selection ends the guide's waypoint")
assert(not ns.JourneyPinTracked(), "and the guide has yielded")

-- The native waypoint marks the step destination while the screen arrow leads the walk.
ns.ClearJourney()
ns.db.guideStops = true
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 1200, y = 0 })
local bend = { map = 1, x = 200, y = 0 }
assert(placeBend(bend) == false, "the arrow leads with step-end marks")
local stepWaypoint = assert(driver.waypoint(), "the native waypoint marks the destination")
assert(ns.JourneyPinTracked(), "the guide still leads, so the goal keeps its gold pin")

-- Changing mark density updates both the waypoint's position and which pointer leads.
ns.db.guideStops = false
assert(placeBend(bend), "the native marker leads with every bend marked")
assert(driver.waypoint().position.y ~= stepWaypoint.position.y, "the waypoint moves to the bend")
assert(ns.JourneyPinTracked(), "and still leads")
ns.db.guideStops = true
assert(placeBend(bend) == false, "with step-end marks the arrow leads again")
assert(driver.waypoint().position.y == stepWaypoint.position.y, "the waypoint returns to the step end")

-- The guide restores the player's waypoint and tracking when the journey stops.
ns.ClearJourney()
local saved = env.UiMapPoint.CreateFromCoordinates(1, 0.2, 0.3, 42)
env.C_Map.SetUserWaypoint(saved)
env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
driver.update(0)
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 1200, y = 0 })
assert(placeBend(bend) == false, "the arrow leads while the guide borrows the player's waypoint")
local active, activeTracked = driver.waypoint()
assert(ns.JourneyGuide.SameWaypoint(active, stepWaypoint) and activeTracked, "the borrowed pin marks the step end")
ns.ClearJourney()
local kept, keptTracked = driver.waypoint()
assert(kept and kept.position.x == 0.2 and kept.position.y == 0.3 and keptTracked, "restore the player's waypoint")

-- Reload the guide while retaining the saved variables and the client's waypoint slot.
for _, case in ipairs({ "tracked", "untracked", "replaced" }) do
	env.C_Map.SetUserWaypoint(saved)
	env.C_SuperTrack.SetSuperTrackedUserWaypoint(case == "tracked")
	local guide = ns.JourneyGuide
	guide.Start()
	guide.To(bend, { bend }, { map = 1, x = 1200, y = 0 })
	placeBend(bend)
	assert(ns.JourneyGuide.SameWaypoint(driver.waypoint(), stepWaypoint), "the guide owns the slot before reload")
	local expected = saved
	if case == "replaced" then
		expected = env.UiMapPoint.CreateFromCoordinates(1, 0.7, 0.8)
		env.C_Map.SetUserWaypoint(expected)
		env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
	driver.load("Journey/JourneyGuide.lua")
	ns.JourneyGuide.ClearOrphan()
	local point, tracked = driver.waypoint()
	assert(point and point.uiMapID == expected.uiMapID, "login leaves the expected pin on the map")
	assert(
		point.position.x == expected.position.x and point.position.y == expected.position.y,
		"login restores only the borrowed pin"
	)
	assert(point.z == expected.z, "login preserves the pin altitude")
	assert(tracked == (case ~= "untracked"), "login restores tracking only for the borrowed pin")
	assert(not ns.charDB.guideWaypoint, "login consumes the ownership record")
end

print("guide navigation: a focused quest does not take the guide's waypoint")

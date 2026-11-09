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

-- The player clicking a quest is a different thing: nothing restores the waypoint, so the guide yields and clears
-- its waypoint while the route arrow keeps leading.
env.C_SuperTrack.SetSuperTrackedQuestID(999)
driver.update(0)
assert(driver.waypoint() == nil, "the player's quest selection ends the guide's waypoint")
assert(not ns.JourneyPinTracked(), "and the guide has yielded")

print("guide navigation: a focused quest does not take the guide's waypoint")

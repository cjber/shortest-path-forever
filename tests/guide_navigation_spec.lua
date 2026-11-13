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

-- "Mark only where steps end": one native marker cannot sit at the step's end and follow the walk's bends, so the
-- guide places no marker at all and the screen arrow leads instead (#817).
ns.ClearJourney()
ns.db.guideStops = true
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 1200, y = 0 })
assert(placeBend({ map = 1, x = 1200, y = 0 }) == false, "with only step ends marked the guide places no marker")
assert(driver.waypoint() == nil, "so the game's navigation marker is not set")
assert(ns.JourneyPinTracked(), "the guide still leads, so the goal keeps its gold pin")

-- Turning the setting off mid-journey places the marker again, and turning it back on takes the marker it placed
-- away, so the arrow leads and the step's end stays on the map alone.
ns.db.guideStops = false
assert(placeBend({ map = 1, x = 1200, y = 0 }), "with the setting off the guide places its marker again")
assert(ns.JourneyPinTracked(), "and still leads")
ns.db.guideStops = true
assert(placeBend({ map = 1, x = 1200, y = 0 }) == false, "turning it on takes the marker back")
assert(driver.waypoint() == nil, "so no marker is left on the walk")

-- The player's own waypoint and super-track are untouched by a guide that places none, and given back as before
-- when the journey stops.
ns.ClearJourney()
env.C_Map.SetUserWaypoint(env.UiMapPoint.CreateFromCoordinates(1, 0.2, 0.3))
env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
driver.update(0)
ns.db.guideStops = true
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 1200, y = 0 })
assert(placeBend({ map = 1, x = 1200, y = 0 }) == false, "the guide places nothing over the player's pin")
local owned, ownedTracked = driver.waypoint()
assert(owned and ownedTracked, "the player's own waypoint stays exactly where it was")
ns.ClearJourney()
local kept, keptTracked = driver.waypoint()
assert(kept and keptTracked, "and is still there and tracked when the journey stops")

print("guide navigation: a focused quest does not take the guide's waypoint")

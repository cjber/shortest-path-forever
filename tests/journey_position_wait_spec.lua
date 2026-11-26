-- The client may temporarily withhold UnitPosition, even when a nearby stop is already known.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
driver.move({})
assert(ns.StartJourney({ map = 1, x = 100, y = 0, hold = true }))
local _, rows = ns.JourneyInfo(tostring)
assert(rows[1].key == "searching", "a short route awaiting position is still searching")
driver.move({ map = 1, x = 0, y = 0 })
driver.update(0.1)
local route = assert(ns.JourneyPlan(), "the short route resolves when the client's position returns")
assert(route.legs[1].measured, "the short walk was measured")

-- A manual TomTom waypoint keeps the arrow while RestedXP guidance is running (#1390).
local boot = assert(loadfile("tests/tomtom_arrow_driver.lua"))()
local c = boot({ tomtomArrow = true, restedXPBridge = true }, true)
c.driver.path.settle()
assert(c.API.CurrentStop("RestedXP") == 1)

local guide = c.bridgeStep(1)
local manual = c.tomtom:Way(1, 10, 20, "Manual waypoint")
c.runTimers()
assert(c.tomtom.Arrow() == manual and not c.crazy.hidden, "the manual waypoint stays visible during guide navigation")

-- On arrival TomTom clears the manual target immediately and selects the closest waypoint on its next update.
c.tomtom:RemoveWaypoint(manual)
c.tomtom:ArrowUpdate(guide)
assert(c.tomtom.Arrow() == guide and not c.crazy.hidden, "TomTom can hand the arrow back to the guide at arrival")
print("tomtom manual waypoint with RestedXP: ok")

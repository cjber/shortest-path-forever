local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
local goal = { map = 1, x = 1000, y = 0 }
local result = { legs = { { mode = "walk", to = goal } } }
local progress = { index = 1 }

assert(ns.JourneyProgressChanged(goal, result, progress), "the first progress check is fresh")
assert(not ns.JourneyProgressChanged(goal, result, progress), "unchanged progress is cached")
ns.db.offPathTolerance = 40
assert(ns.JourneyProgressChanged(goal, result, progress), "changing tolerance invalidates stationary progress")
assert(not ns.JourneyProgressChanged(goal, result, progress), "the new tolerance is cached")

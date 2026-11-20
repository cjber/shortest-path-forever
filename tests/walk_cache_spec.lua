-- OnWalk caches each walk's segment lengths: a points table edited in place, at the same length or grown, is
-- measured again rather than read from the cache.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local OnWalk = driver.ns.OnWalk

local points = { { map = 0, x = 0, y = 0 }, { map = 0, x = 10, y = 0 } }
local _, _, after, total = OnWalk(points, { map = 0, x = 5, y = 0 })
assert(total == 10 and after == 5, "a fresh walk is measured")
_, _, after, total = OnWalk(points, { map = 0, x = 5, y = 0 })
assert(total == 10 and after == 5, "a repeat reads the same lengths")

points[2].x = 20
_, _, after, total = OnWalk(points, { map = 0, x = 5, y = 0 })
assert(total == 20 and after == 15, "a point moved in place is measured again")

points[3] = { map = 0, x = 20, y = 10 }
_, _, after, total = OnWalk(points, { map = 0, x = 5, y = 0 })
assert(total == 30 and after == 25, "a walk grown in place is measured again")
print("walk cache: 4 checks passed")

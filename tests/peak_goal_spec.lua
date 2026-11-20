-- A spot on a Feralas plateau ringed by faces past the player's slope and step limits: no walk from any place reaches
-- it, in the grid or in the full-resolution mesh (#1113). The route ends at the nearest ground the places reach,
-- where a player can stand, rather than finding no route at all.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
	"Data/TownAreas.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
}) do
	driver.load(file)
end
for _, map in ipairs({ 0, 1, 2991 }) do
	assert(loadfile("tools/load_nav.lua"))(map)
end
local Path = ns.Path

local PEAK = { map = 1, x = -5338, y = 827 }
local MOJACHE = { map = 1, x = -4424, y = 202 } -- Camp Mojache
local VALLEY = { map = 1, x = -4450, y = 1350 }
local function distance(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

-- The goal batch: no target walks to the peak, so the batch names the nearest ground they do walk to.
local costs, _, _, moved = Path.FindManySync(1, PEAK, { MOJACHE, VALLEY }, false, true)
assert(costs[1] == false and costs[2] == false, "nothing walks onto the plateau")
assert(moved and moved.map == 1, "an unreachable goal moves to reachable ground")
assert(distance(moved, PEAK) < 200, "the moved goal stays beside the plateau: " .. distance(moved, PEAK))
local again = Path.FindManySync(1, moved, { MOJACHE, VALLEY }, false, true)
assert(again[1] and again[2], "both places walk to the moved goal")
local points = assert(Path.FindSync(1, VALLEY, moved), "the walk reaches the moved goal")
local last = points[#points]
assert(last.x == moved.x and last.y == moved.y, "the walk ends where the player can stand")

-- A goal the places reach stays where it is.
local reached, _, _, stays = Path.FindManySync(1, VALLEY, { MOJACHE }, false, true)
assert(reached[1] and stays == nil, "a reachable goal never moves")

-- The journey: from Stormwind, a click on the plateau draws a route that ends on the moved ground.
ns.faction, ns.level = "Alliance", 21
local nextFrame
Path.after = function(fn)
	nextFrame = fn
end
driver.begin({ map = 0, x = -8849, y = 647.9, z = 98 }, { map = 1, x = PEAK.x, y = PEAK.y, z = 0 })
local frames = 0
while nextFrame do
	local fn = nextFrame
	nextFrame = nil
	fn()
	driver.update(1 / 60)
	frames = frames + 1
	assert(frames < 20000, "journey did not settle")
end
local route = assert(driver.shown(), "a click on the plateau draws a route")
local final = route.legs[#route.legs].to
assert(final.map == 1 and distance(final, moved) < 1, "the route ends on the moved ground")

-- A player already on the plateau walks to the spot itself: the walk from here reaches it, so it does not move, and a
-- goal moved for the last journey is not moved for this one.
ns.JourneySearch.Reset()
local ON = { map = 1, x = PEAK.x - 50, y = PEAK.y }
assert(Path.FindSync(1, ON, PEAK), "the plateau is walkable on top")
driver.begin(ON, { map = 1, x = PEAK.x, y = PEAK.y, z = 0 })
frames = 0
while nextFrame do
	local fn = nextFrame
	nextFrame = nil
	fn()
	driver.update(1 / 60)
	frames = frames + 1
	assert(frames < 20000, "journey on the plateau did not settle")
end
local top = assert(driver.shown(), "a walk across the plateau is drawn")
local stop = top.legs[#top.legs].to
assert(distance(stop, PEAK) < 1, "a goal the player can walk to stays where it is")
print("peak goal: moved " .. math.floor(distance(moved, PEAK)) .. " yd to reachable ground")

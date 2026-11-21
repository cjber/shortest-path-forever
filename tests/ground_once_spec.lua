-- A goal no place walks to moves once to the nearest ground the places reach (#1113), and the search starts again
-- toward it. The Arathi hills above Refuge Pointe were such a goal only because the base walking graph was cut apart:
-- pruning dropped two entrances' edges each in favour of the other, so the walks never left a small pocket while the
-- flood that names ground took every edge (#1141, #1149). Pruning now keeps a way on, the flood takes the edges the
-- walks take, and a goal batch whose frontier is spent proves on its own that here cannot walk in, so the walk from
-- here no longer searches the whole landmass before the goal moves. A goal still moves at most once (#1141).
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

local places = {}
for _, node in pairs(ns.TaxiNodes) do
	if node.map == 0 then
		places[#places + 1] = { map = 0, x = node.x, y = node.y, z = node.z }
	end
end
local function reached(costs)
	for i = 1, #places do
		if costs[i] then
			return true
		end
	end
	return false
end

local HILLS = { map = 0, x = -593.3, y = -4001.9 }
assert(reached(Path.FindManySync(0, HILLS, places, false, true)), "a place walks to the hills above Refuge Pointe")

-- Ground in the hills no place walks to: the moved goal is ground the walks reach.
local WALLED = { map = 0, x = -1200, y = -4000 }
local _, _, _, moved = Path.FindManySync(0, WALLED, places, false, true)
assert(moved, "no place walks to the walled ground")
assert(reached(Path.FindManySync(0, moved, places, false, true)), "a place walks to the ground the goal moved to")

ns.faction, ns.level = "Alliance", 40
local nextFrame
Path.after = function(fn)
	nextFrame = fn
end
local STORMWIND = { map = 0, x = -8833, y = 628, z = 94 }
local batches, movedWith = {}, nil
local FindMany = Path.FindMany
Path.FindMany = function(map, from, targets, callback, ...)
	local job = FindMany(map, from, targets, callback, ...)
	batches[#batches + 1] = job
	return job
end
local WalksInto = Path.WalksInto
local proofs = 0
Path.WalksInto = function(job, point)
	local walks = WalksInto(job, point)
	proofs = proofs + (walks == false and 1 or 0)
	return walks
end
driver.begin(STORMWIND, { map = 0, x = WALLED.x, y = WALLED.y, z = 0 })
local frames = 0
while nextFrame do
	local fn = nextFrame
	nextFrame = nil
	fn()
	driver.update(1 / 60)
	frames = frames + 1
	if not movedWith and #batches > 2 then
		movedWith = batches[1]
	end
	assert(frames < 20000, "the search never settles: the goal keeps moving")
end
local pending, _, _, loading = ns.JourneyStatus()
assert(not pending and not loading, "the journey leaves loading")
assert(proofs > 0, "the goal batch proves here cannot walk to the walled ground")
assert(movedWith and not movedWith.done, "the goal moves before the walk from here has searched the landmass")
print("ground once: settled in " .. frames .. " frames")

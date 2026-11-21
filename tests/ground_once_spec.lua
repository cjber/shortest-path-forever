-- A goal no place walks to moves once to the nearest ground the places reach (#1113). That ground is found by a flood
-- over cluster entrances, which can name ground the walks themselves never reach: in the Arathi hills above Refuge
-- Pointe the moved goal was no more reachable than the click. The search then moved the goal onto itself and started
-- again forever, so the rough line stayed and the journey never left loading (#1141). A goal moves at most once.
-- The map baked for #1011 walks up that hill as the raw navmesh does (5191 yards from Refuge Pointe), so the click
-- there no longer moves; the journey to it must still settle.
-- A goal batch whose frontier is spent proves on its own that here cannot walk in (#1149): the walk from here no
-- longer searches the whole landmass before a goal no place walks to moves.
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

local HILLS = { map = 0, x = -593.3, y = -4001.9 }
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

-- The hill is ground the places walk to, so the goal stays where it was clicked.
local _, _, _, hillMoved = Path.FindManySync(0, HILLS, places, false, true)
assert(not hillMoved, "the goal moved off ground the places walk to")
assert(reached(Path.FindManySync(0, HILLS, places, false, true)), "no place walks up the hill the raw navmesh climbs")

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

-- The original Azshara click has a tiny inbound pocket and no route from Orgrimmar. The goal batch can rule
-- out the direct walk while its probe is pending, before the probe exhausts the continent from the other end.
ns.ClearJourney()
ns.faction, ns.level = "Horde", 15
local ORGRIMMAR = { map = 1, x = 1630, y = -4420, z = 15 }
local AZSHARA = { map = 1, x = 2600, y = -4300 }
local FindCost = Path.FindCost
local originalProbe
Path.FindCost = function(map, from, to, ...)
	local job = FindCost(map, from, to, ...)
	if math.abs(from.x - ORGRIMMAR.x) < 1e-6 and math.abs(to.x - AZSHARA.x) < 1e-6 then
		originalProbe = job
	end
	return job
end
driver.begin(ORGRIMMAR, AZSHARA)
frames = 0
while nextFrame do
	local fn = nextFrame
	nextFrame = nil
	fn()
	driver.update(1 / 60)
	frames = frames + 1
	assert(frames < 20000, "the Azshara journey must settle")
end
assert(
	originalProbe and originalProbe.cancelled and not originalProbe.done,
	"the reverse proof stops the forward probe"
)
local route = assert(driver.shown(), "the moved goal has a route")
assert(#route.legs == 1 and route.legs[1].mode == "walk", "the moved goal is reached on foot")

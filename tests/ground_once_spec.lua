-- A goal no place walks to moves once to the nearest ground the places reach (#1113). That ground is found by a flood
-- over cluster entrances, which can name ground the walks themselves never reach: in the Arathi hills above Refuge
-- Pointe the moved goal was no more reachable than the click. The search then moved the goal onto itself and started
-- again forever, so the rough line stayed and the journey never left loading (#1141). A goal moves at most once.
-- The map baked for #1011 walks up that hill as the raw navmesh does (5191 yards from Refuge Pointe), so the click
-- there no longer moves; the journey to it must still settle.
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
-- The hill is ground the places walk to, so the goal stays where it was clicked.
local costs, _, _, moved = Path.FindManySync(0, HILLS, places, false, true)
assert(not moved, "the goal moved off ground the places walk to")
local reached = 0
for i = 1, #places do
	reached = reached + (costs[i] and 1 or 0)
end
assert(reached > 0, "no place walks up the hill the raw navmesh climbs")

ns.faction, ns.level = "Alliance", 40
local nextFrame
Path.after = function(fn)
	nextFrame = fn
end
local REFUGE = { map = 0, x = -1256, y = -2513, z = 0 }
driver.begin(REFUGE, { map = 0, x = HILLS.x, y = HILLS.y, z = 0 })
local frames = 0
while nextFrame do
	local fn = nextFrame
	nextFrame = nil
	fn()
	driver.update(1 / 60)
	frames = frames + 1
	assert(frames < 20000, "the search never settles: the goal keeps moving")
end
local pending, _, _, loading = ns.JourneyStatus()
assert(not pending and not loading, "the journey leaves loading")
print("ground once: settled in " .. frames .. " frames")

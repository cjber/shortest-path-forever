-- A goal no place walks to moves once to the nearest ground the places reach (#1113). That ground is found by a flood
-- over cluster entrances, which can name ground the walks themselves never reach: in the Arathi hills above Refuge
-- Pointe the moved goal is no more reachable than the click. The search then moved the goal onto itself and started
-- again forever, so the rough line stayed and the journey never left loading (#1141). A goal moves at most once.
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
-- The case itself: the flood names ground for the click, and no place walks to that ground either.
local _, _, _, moved = Path.FindManySync(0, HILLS, places, false, true)
assert(moved, "no place walks to the click")
local again = Path.FindManySync(0, moved, places, false, true)
for i = 1, #places do
	assert(again[i] == false, "a place walks to the moved goal: the case no longer applies")
end

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

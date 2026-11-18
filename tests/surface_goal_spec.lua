-- A spot picked on a map over the Undercity names the Ruins of Lordaeron, the surface above the city, so a journey
-- there from inside the city must leave by a lift (#923). A spot on the city's own map still names its floor.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local input = driver.ns
local RUINS = { x = 1650, y = 240 } -- the Ruins of Lordaeron, over the city
local CITY_BOX = { 1238, -86, 1878, 873 } -- Data/Zones.lua 1458: where the city's map lies in the world
driver.env.C_Map.GetWorldPosFromMapPos = function()
	return 0, {
		GetXY = function()
			return RUINS.x, RUINS.y
		end,
	}
end
driver.env.C_Map.GetMapPosFromWorldPos = function(_, world, id)
	local x, y = world:GetXY()
	return id,
		{
			GetXY = function()
				return (x - CITY_BOX[1]) / (CITY_BOX[3] - CITY_BOX[1]), (y - CITY_BOX[2]) / (CITY_BOX[4] - CITY_BOX[2])
			end,
		}
end
-- Shift-clicking Tirisfal Glades over the city, as JourneyInput.lua names a map spot.
local CLICK = assert(input.WorldPoint(1420, 0.5, 0.5))

local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Teleports.lua",
	"Data/Walks.lua",
	"Transport/Model.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
	"Routing/Savings.lua",
	"Routing/Planner.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path, Planner = ns.Path, ns.Planner

local FLIGHT_MASTER = { map = 0, x = 1568.62, y = 267.97, z = -43.1 } -- Data/Taxi.lua node 11

-- The plan a map click makes: the walk to the nearest lift, the lift, and the walk on across the Ruins.
local places = {}
for id, dock in pairs(ns.Docks) do
	local point = dock.walk or dock
	places[#places + 1] = { kind = "dock", id = id, map = point.map, x = point.x, y = point.y, z = point.z }
end
for id, node in pairs(ns.TaxiNodes) do
	places[#places + 1] = { kind = "taxi", id = id, map = node.map, x = node.x, y = node.y, z = node.z }
end
local function OnMap(point)
	return point.map == FLIGHT_MASTER.map
		and Planner.Landmass(point, ns.Landmasses) == Planner.Landmass(FLIGHT_MASTER, ns.Landmasses)
end
local function Walks(from, targets, reverse)
	local costs = Path.FindManySync(0, from, targets, nil, reverse)
	local walks = {}
	for index, target in ipairs(targets) do
		if costs[index] then
			walks[#walks + 1] = { from = from, to = target, cost = costs[index] }
		end
	end
	return walks
end
-- As JourneySearch.lua measures them: the start's batch also prices the goal, and the goal's batch prices every
-- place a walk on from it.
local near = {}
for _, place in ipairs(places) do
	if OnMap(place) then
		near[#near + 1] = place
	end
end
local startTargets = {}
for _, place in ipairs(near) do
	startTargets[#startTargets + 1] = place
end
startTargets[#startTargets + 1] = CLICK
local walks = Walks(FLIGHT_MASTER, startTargets, false)
for _, walk in ipairs(Walks(CLICK, near, true)) do
	walks[#walks + 1] = walk
end
local plan = assert(Planner.Plan({
	from = FLIGHT_MASTER,
	to = CLICK,
	now = 0,
	walkSpeed = 7,
	faction = "Horde",
	taxiKnown = {},
	anchors = {},
	docks = ns.Docks,
	routes = ns.Routes,
	taxiNodes = ns.TaxiNodes,
	taxiPaths = ns.TaxiPaths,
	taxiTimes = {},
	teleports = {},
	teleportReady = {},
	landmasses = ns.Landmasses,
	baked = ns.Walks,
	walks = walks,
}))
local lift
for _, leg in ipairs(plan.legs) do
	if leg.mode == "lift" then
		lift = leg
	end
end
if not lift then
	-- Red on a map spot with no height: one walk into the city, ending under the Ruins.
	local ends = assert(Path.FindSync(0, FLIGHT_MASTER, CLICK))
	assert(
		false,
		("the journey to the Ruins ends at z %s in the city, with no lift"):format(tostring(ends[#ends - 1].z))
	)
end
assert(lift.from.z and lift.to.z and lift.to.z > lift.from.z, "the lift rises to the Ruins' level")
assert(plan.legs[1].mode == "walk" and plan.legs[1].yards and plan.legs[1].yards < 100, "a short walk to the lift")
assert(
	plan.legs[#plan.legs].mode == "walk" and plan.legs[#plan.legs].yards and plan.legs[#plan.legs].yards < 150,
	"and a short walk on across the Ruins"
)
assert(CLICK.z == 55.718, "the map over the city names the Ruins' surface height")
local LIFT_TOP = { map = 0, x = 1596.15, y = 291.8, z = 55.718 } -- Data/Transports.lua dock 1009
local walked = assert(Path.FindSync(0, LIFT_TOP, CLICK))
assert(walked[#walked - 1].z and walked[#walked - 1].z > 50, "and the walk on from the lift ends on the Ruins")
print("surface_goal_spec: a map spot over the city leaves the Undercity by a lift to reach the Ruins above it")

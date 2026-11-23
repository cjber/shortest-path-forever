-- A ride that lands somewhere the walk into a high-level goal zone is no shorter must not win (#1300): the walk from
-- the landing pays the goal zone's charge for its share of it, as the walk straight there does.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
driver.load("Data/Zones.lua")
driver.load("Data/Taxi.lua")
ns.Zones = { [1431] = ns.Zones[1431], [1434] = ns.Zones[1434] }
ns.zoneAt = function(_, x)
	return x < -11200 and 1434 or 1431
end
driver.env.C_Map.GetMapInfo = function()
	return { name = "Stranglethorn Vale", mapType = 3 }
end
local darkshire = ns.TaxiNodes[12]
-- A second Duskwood flight point a short hop further from the goal: the walk from it crosses as much of the zone.
local hop = {}
for key, value in pairs(darkshire) do
	hop[key] = value
end
hop.id, hop.x, hop.y = 99, darkshire.x + 300, darkshire.y + 300
ns.TaxiNodes = { [12] = darkshire, [99] = hop }
ns.TaxiPaths = { { from = 12, to = 99, seconds = 5 } }
ns.faction, ns.level, ns.known = "Alliance", 22, { [12] = true, [99] = true }
ns.db.avoidHighZones = true
-- A few steps from the flight master, as on its platform: no zero-yard transfer joins the two.
local start = { map = 0, x = darkshire.x - 10, y = darkshire.y, z = darkshire.z }
local goal = { map = 0, x = -11600, y = darkshire.y, z = 40 }

driver.begin(start, goal)
local _, rows, plan = ns.JourneyInfo()
assert(plan, "a plan")
for _, row in ipairs(rows) do
	assert(row.mode ~= "flight", "a flight away from the goal is not quicker: " .. tostring(row.text))
	assert(row.key ~= "ride-note", "no ride is explained when the journey walks")
end
assert(#plan.legs == 1 and plan.legs[1].mode == "walk", "the journey walks straight into the goal zone")
local walk = ns.LegSpan(plan.legs[1])
ns.ClearJourney()

-- The charge weighs the choice only: with avoidance off the same walk takes the same time.
ns.db.avoidHighZones = false
driver.begin(start, goal)
local _, _, plain = ns.JourneyInfo()
assert(plain and #plain.legs == 1 and ns.LegSpan(plain.legs[1]) == walk, "the zone charge does not inflate the ETA")
ns.ClearJourney()
print("journey_goal_zone_ride_spec: no ride around the goal zone charge: ok")

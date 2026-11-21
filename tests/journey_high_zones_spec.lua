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
local darkshire, bootyBay = ns.TaxiNodes[12], ns.TaxiNodes[19]
ns.TaxiNodes = { [12] = darkshire, [19] = bootyBay }
-- A slow flight, so walking straight there wins on real time, even with the long-walk ride preference.
ns.TaxiPaths = { { from = 12, to = 19, seconds = 800 } }
ns.faction, ns.level, ns.known = "Alliance", 22, { [12] = true, [19] = true }
local border = { map = 0, x = -11190, y = -650, z = 40 }
local goal = { map = 0, x = bootyBay.x, y = bootyBay.y, z = bootyBay.z }

local function journey(avoid)
	ns.db.avoidHighZones = avoid
	driver.begin(border, goal)
	local _, rows, plan = ns.JourneyInfo()
	assert(plan)
	local reason, flight
	for _, row in ipairs(rows) do
		reason = reason or row.text == "Rides to spend less time walking through Stranglethorn Vale (level 30-45)"
		flight = flight or row.mode == "flight"
	end
	ns.ClearJourney()
	return flight, reason, plan
end

local flight, reason = journey(true)
assert(flight, "the level 22 character should fly to Booty Bay to cut the walk through Stranglethorn")
assert(reason, "the journey explains why it chose the flight")
local offFlight, offReason, walk = journey(false)
assert(not offFlight and not offReason and walk.legs[1].mode == "walk", "turning avoidance off restores the walk")
ns.TaxiPaths = {}
local onlyFlight, onlyReason, only = journey(true)
assert(
	not onlyFlight and not onlyReason and only.legs[1].mode == "walk",
	"a high-level goal is still reachable on foot"
)
assert(ns.LegSpan(only.legs[1]) == ns.LegSpan(walk.legs[1]), "the zone charge does not inflate the walking ETA")
-- A teleport slower than the walk but quicker than its charge is chosen without the ride's explanation.
local cast = ns.LegSpan(walk.legs[1]) * 1.6
ns.teleports = { { map = 0, x = bootyBay.x, y = bootyBay.y, z = bootyBay.z, spell = 3561, cast = cast } }
ns.teleportReady = { 0 }
driver.env.C_Spell = { GetSpellName = tostring, GetSpellTexture = tostring }
local teleportFlight, teleportReason, teleported = journey(true)
assert(teleported.legs[1].mode == "teleport", "the teleport beats the charged walk")
assert(not teleportFlight and not teleportReason, "a teleport is not explained as a ride")
ns.teleports, ns.teleportReady = nil, nil
ns.TaxiPaths = { { from = 12, to = 19, seconds = 100 } }
local fasterFlight, fasterReason = journey(true)
assert(fasterFlight and not fasterReason, "a flight that already beats walking needs no hazard explanation")
print("journey_high_zones_spec: Booty Bay flight, opt-out and walking fallback: ok")

local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
for _, file in ipairs({
	"Data/Zones.lua",
	"Data/ZoneCells.lua",
	"Data/Taxi.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
}) do
	driver.load(file)
end
assert(loadfile("tools/load_nav.lua"))(0, nil, driver.env, true)
ns.zoneAt = ns.Hazards.ZoneAt
ns.level, ns.faction, ns.db.avoidHighZones = 39, "Alliance", true
local stormwind, lakeshire, morgansVigil, farholde =
	ns.TaxiNodes[2], ns.TaxiNodes[5], ns.TaxiNodes[71], ns.TaxiNodes[3276]
ns.TaxiNodes = { [2] = stormwind, [5] = lakeshire, [71] = morgansVigil }
assert(ns.ZoneMap(0, farholde.x, farholde.y) == 2548, "Farholde Keep is in Riverglades")

local paths, burningSteppesFlight = {}, nil
for _, path in ipairs(ns.TaxiPaths) do
	if path.from == 2 and (path.to == 5 or path.to == 71) then
		paths[#paths + 1] = path
		if path.to == 71 then
			burningSteppesFlight = path
		end
	end
end

-- The level 39 character knows both alternatives but has yet to discover Farholde Keep.
local hazards = ns.Hazards.Profile(stormwind, farholde)
local pump
ns.Path.after = function(fn, delay)
	if not delay then
		pump = fn
	end
end
local function finish(job)
	while not job.done do
		local frame = assert(pump)
		pump = nil
		frame()
	end
	return job
end
local job = finish(ns.Path.FindMany(0, farholde, { lakeshire, morgansVigil }, function() end, nil, true, nil, hazards))
local walks = { { from = stormwind, to = stormwind, cost = 0 } }
for i, from in ipairs({ lakeshire, morgansVigil }) do
	walks[#walks + 1] = { from = from, to = farholde, cost = job.costs[i], choice = job.choices and job.choices[i] }
end
local function plan(taxiPaths)
	return assert(ns.Planner.Plan({
		from = stormwind,
		to = farholde,
		now = 0,
		walkSpeed = 7,
		faction = "Alliance",
		taxiNodes = ns.TaxiNodes,
		taxiKnown = { [2] = true, [5] = true, [71] = true },
		taxiPaths = taxiPaths,
		walks = walks,
		hazards = hazards,
		feasibleOnly = true,
	}))
end

local safer = plan(paths)
assert(safer.legs[1].to.id == 5, "level 39 should fly to Lakeshire for Riverglades with avoidance on")
local risky = plan({ assert(burningSteppesFlight) })
assert(risky.arrive < safer.arrive, "the Burning Steppes route would win on travel time alone")
assert(risky.charged > (safer.charged or safer.arrive), "walking exposure tips the choice toward Lakeshire")
local walk = risky.legs[2]
assert(math.abs(walk.arrive - walk.depart - job.costs[2] / 7 * 1000) < 1e-6, "the hazard charge leaves the ETA real")

-- A focused probe can settle this same walk before the reverse batch finishes.
for _ = 1, 2 do
	local probe = finish(ns.Path.FindCost(0, morgansVigil, farholde, function() end, nil, hazards))
	assert(math.abs(probe.choice - job.choices[2]) < 1e-6, "the probe and its warm cache preserve the batch score")
end

ns.db.avoidHighZones = false
local unguarded = ns.Hazards.Profile(stormwind, farholde)
local probe = finish(ns.Path.FindCost(0, morgansVigil, farholde, function() end, nil, unguarded))
assert(not probe.choice, "turning the setting off removes the weighted cost from the route comparison")

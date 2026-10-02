-- The planning context through its own interface, against a small client stub, then the two callers that plan
-- with it: what they share, and the inputs each keeps for itself.
local secret = setmetatable({}, {
	__lt = function()
		error("secret speed compared")
	end,
})
local client = { speed = 7, moving = 0, faction = "Alliance", now = 100000 }
local known, anchors, teleports, ready =
	{ [1] = true }, {}, { { spell = 5, map = 1, x = 0, y = 0, cast = 10000 } }, { 0 }
local ns = {
	db = { otherFaction = true, hearthMinimumSavings = 90 },
	Docks = {
		[1] = { map = 1, x = 0, y = 0 },
		[2] = { map = 1, x = 5000, y = 0 },
	},
	Routes = {
		[9] = {
			kind = "boat",
			period = 100000,
			stops = { { dock = 1, arrive = 0, depart = 20000 }, { dock = 2, arrive = 50000, depart = 70000 } },
		},
	},
	TaxiNodes = {
		[1] = { map = 1, x = 100, y = 0, name = "Ours", faction = "Alliance" },
		[2] = { map = 1, x = 200, y = 0, name = "Theirs", faction = "Horde" },
	},
	TaxiPaths = {},
	Portals = {},
	Landmasses = { { map = 1, minX = -10, maxX = 150, minY = -10, maxY = 10 } },
	Walks = {},
	NowMs = function()
		return client.now
	end,
	KnownTaxiNodes = function()
		return known
	end,
	FreshAnchors = function()
		return anchors
	end,
	UsableTeleports = function(now)
		assert(now == client.now, "teleport readiness is read at the plan's own time")
		return teleports, ready
	end,
	CurrentRide = function()
		return client.ride
	end,
}
local env = setmetatable({
	GetUnitSpeed = function()
		return client.moving, client.speed
	end,
	canaccessvalue = function(value)
		return value ~= secret
	end,
	UnitFactionGroup = function()
		return client.faction
	end,
}, { __index = _G })
for _, file in ipairs({ "Transport/Model.lua", "Routing/Planner.lua", "Core/PlanContext.lua" }) do
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end
local Context = ns.PlanContext

assert(Context.RunSpeed() == 7)
client.speed = 14
assert(Context.RunSpeed() == 14, "standing still preserves mounted run speed")
client.speed, client.moving = 3.5, 3.5
assert(Context.RunSpeed() == 3.5, "slows below base speed are respected")
client.speed, client.moving = secret, secret
assert(Context.RunSpeed() == 3.5, "secret values preserve the last readable run speed")
for _, invalid in ipairs({ 0, -1, math.huge, 0 / 0, "14", false }) do
	client.speed = invalid
	assert(Context.RunSpeed() == 3.5, "invalid readings preserve the last readable speed")
end
client.speed = 7
assert(Context.RunSpeed() == 7, "dismounting or a slow expiring restores base speed")

local from, to = { map = 1, x = 0, y = 0 }, { map = 1, x = 70, y = 0 }
local options = Context.Options(from, to)
local expected = {
	from = from,
	to = to,
	now = client.now,
	walkSpeed = 7,
	faction = "Alliance",
	otherFaction = true,
	taxiKnown = known,
	anchors = anchors,
	docks = ns.Docks,
	routes = ns.Routes,
	taxiNodes = ns.TaxiNodes,
	taxiPaths = ns.TaxiPaths,
	portals = ns.Portals,
	teleports = teleports,
	teleportReady = ready,
	hearthMinimumSavings = 90,
	landmasses = ns.Landmasses,
	baked = ns.Walks,
}
for name, value in pairs(expected) do
	assert(options[name] == value, name)
end
for name in pairs(options) do
	assert(expected[name] ~= nil, name .. " belongs to one caller, not the shared context")
end
assert(Context.Options(from, to) ~= options, "each plan gets its own table to add to")
assert(ns.Planner.Plan(options).arrive == client.now + 10000, "the planner takes it as gathered")
client.speed, client.faction, ns.db = secret, "Horde", nil
options = Context.Options(from, to)
assert(options.walkSpeed == 7 and options.faction == "Horde", "speed in combat and faction are read per plan")
assert(options.otherFaction == false and options.hearthMinimumSavings == 0, "settings default before the db loads")
-- Specs and the UI harness rebind the data tables after load.
local routes = ns.Routes
ns.Routes = {}
assert(Context.Options(from, to).routes == ns.Routes, "data tables are read per plan")
ns.Routes, client.faction, client.speed = routes, "Alliance", 7

local function ride(here)
	return Context.Ride(Context.Options(here, to))
end
assert(ride(from) == nil, "on foot")
client.ride = 9
ns.NextStop = function(routeID)
	assert(routeID == 9)
	return client.next, client.next and 30000
end
assert(ride(from) == nil, "no sighting, no schedule")
client.next = 2
local aboard = ride(from)
assert(aboard.route == 9 and aboard.dock == 2 and aboard.arrive == client.now + 30000, "unsighted ride")
-- Sighted so the boat is docked at dock 1 now.
anchors[9] = { epoch = client.now - 10000 }
assert(ride(from) == nil, "standing at the dock the boat is at: disembarked, the ride lingers 30 s")
assert(ride({ map = 1, x = 300, y = 0 }) ~= nil, "250 yards clear of that dock")
assert(ride({ map = 2, x = 0, y = 0 }) ~= nil, "another map")
anchors[9].epoch = client.now - 30000
aboard = ride(from)
assert(aboard and aboard.dock == 2, "the boat has sailed: aboard at the same spot")
client.next = nil
assert(ride(from) == nil, "no next stop")
client.ride, anchors[9] = nil, nil

local function kinds(places)
	local list = {}
	for index, place in ipairs(places) do
		list[index] = place.kind .. place.id
	end
	return table.concat(list, " ")
end
local places, faction = Context.Places(teleports)
assert(kinds(places) == "dock1 dock2 taxi1 teleport5" and faction == "Alliance", kinds(places))
assert(kinds((Context.Places())) == "dock1 dock2 taxi1", "a landing's targets leave teleports out")
client.faction = "Horde"
places, faction = Context.Places()
assert(kinds(places) == "dock1 dock2 taxi2" and faction == "Horde")
client.faction = "Alliance"
assert(Context.Landmass(ns.Docks[1]) == 1 and Context.Landmass(ns.Docks[2]) == nil)
ns.Landmasses = nil
assert(Context.Landmass(ns.Docks[1]) == nil, "no landmass data")
local leg = { mode = "boat", route = 9, from = from, to = to }
assert(#Context.LegPoints(leg) == 2, "a route without frames draws its two ends")
print("plan context: speed, options, ride, places, landmass and leg points passed")

-- The journey and the estimate plan from the same context. What each adds is listed here so a change to either
-- shows up as a failure rather than as drift.
local driver = assert(loadfile("tests/journey_driver.lua"))()
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
local fixture, API = driver.ns, driver.env.ShortestPathForever.API
local function estimate(seconds)
	local found = API.Estimate(1, 0.5, 0.5, 1, 0.5014, 0.5)
	assert(math.abs(found - seconds) < 1e-6, "ETA and estimate cache follow readable run speed")
end
estimate(10)
fixture.speed = 14
estimate(5)
fixture.speed = 3.5
estimate(20)
fixture.speed = driver.secret
estimate(20)
fixture.speed = 7
local plan, planned = fixture.Planner.Plan, nil
fixture.Planner.Plan = function(given)
	planned = given
	return plan(given)
end
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 700, y = 0 })
assert(planned.walkSpeed == 7)
fixture.speed = 14
driver.update(0.1)
assert(planned.walkSpeed == 14, "mounting replans the active route before the five-second timer")
fixture.speed = 3.5
driver.update(0.1)
assert(planned.walkSpeed == 3.5, "slows replan the active route immediately")
fixture.speed = driver.secret
driver.update(0.1)
assert(planned.walkSpeed == 3.5, "secret combat speed retains the usable route speed")
fixture.speed = 7
driver.update(0.1)
assert(planned.walkSpeed == 7, "dismounting or expiring slow replans the active route")

fixture.known = {}
fixture.teleports, fixture.teleportReady = { { spell = 5, map = 1, x = 600, y = 0, cast = 10000 } }, { 0 }
fixture.CurrentRide, fixture.NextStop = function()
	return 9
end, function()
	return 1, 30000
end
driver.update(6)
local journey = planned
assert(journey.ride and journey.ride.route == 9 and journey.walks, "the journey plans its ride and measured walks")
assert(journey.teleportReady == fixture.teleportReady, "and casts from where you stand")
local function estimated(x)
	planned = nil
	fixture.EstimateLegs({ map = 1, x = x, y = 0 }, { map = 1, x = 700, y = 0 })
	return planned
end
local near, far = estimated(10), estimated(400)
assert(near.ride == nil and near.walks == nil, "an estimate plans no ride and no measured walks")
assert(near.teleportReady == fixture.teleportReady, "an estimate from where you stand may cast")
assert(next(far.teleportReady) == nil, "an estimate from elsewhere does not know the cooldowns")
assert(near.cache and near.cache ~= journey.cache, "topology is never shared between the two")
for _, name in ipairs({ "walkSpeed", "faction", "otherFaction", "taxiKnown", "docks", "routes", "taxiNodes" }) do
	assert(near[name] == journey[name], name)
end
for _, name in ipairs({ "taxiPaths", "portals", "teleports", "hearthMinimumSavings", "landmasses", "baked" }) do
	assert(near[name] == journey[name], name)
end
print("plan context: the journey and the estimate share it, each with its own additions")

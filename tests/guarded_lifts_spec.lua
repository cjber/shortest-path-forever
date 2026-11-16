-- Guarded landings gate boarding by default without claiming physical lift ownership.
local shipped = { Docks = {}, Routes = {} }
assert(loadfile("Data/Transports.lua"))("ShortestPathForever", shipped)
for _, route in pairs(shipped.Routes) do
	if route.kind == "lift" then
		assert(route.guardedFaction == "Horde", "each shipped lift has validated landing guard metadata")
	else
		assert(route.guardedFaction == nil, "tram boarding is unchanged")
	end
end
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/API.lua")
local Context = ns.PlanContext
local from, to = { map = 1, x = 0, y = 0 }, { map = 1, x = 7000, y = 0 }
ns.Docks = { [1] = from, [2] = to }
local lift = {
	kind = "lift",
	period = 10000,
	stops = { { dock = 1, arrive = 0, depart = 0 }, { dock = 2, arrive = 1000, depart = 1000 } },
}
ns.Routes = { [9] = lift }
ns.Portals, ns.TaxiPaths = {}, {}
local function hasLift(plan)
	for _, leg in ipairs(assert(plan).legs) do
		if leg.mode == "lift" then
			return true
		end
	end
	return false
end
local cache = {}
local function plan()
	local options = Context.Options(from, to)
	options.cache = cache
	options.ride = Context.Ride(options)
	return ns.Planner.Plan(options)
end
assert(hasLift(plan()), "unmarked lifts remain usable")
ns.db.transit = false
assert(hasLift(plan()), "hiding transit pins does not change routing")
lift.guardedFaction = "Horde"
ns.Routes = { [9] = lift }
assert(not hasLift(plan()), "Alliance cannot board a Horde-guarded lift by default")
local saved = ns.db
local anchors = ns.Timetable.Anchors
ns.Timetable.Anchors = function()
	return {}
end
ns.db = nil
assert(not Context.Options(from, to).routes[9], "guarded lifts are excluded before saved settings load")
ns.db = saved
ns.Timetable.Anchors = anchors
ns.db.otherFaction = true
assert(not hasLift(plan()), "other-faction visibility cannot reopen guarded boarding")
local filtered = Context.Options(from, to).routes
assert(filtered == Context.Options(from, to).routes, "filtered route identity is stable between plans")
assert(ns.Routes[9] == lift, "filtering does not mutate the shipped route table")
local places = Context.Places()
assert(places[1].kind == "dock" and places[2].kind == "dock", "landings remain physical walking destinations")
for id, kind in ipairs({ "boat", "zeppelin", "tram" }) do
	ns.Routes = { [id] = { kind = kind, period = lift.period, stops = lift.stops }, [9] = lift }
	local options = Context.Options(from, to)
	assert(options.routes[id] == ns.Routes[id] and not options.routes[9], kind .. " is unaffected")
	assert(options.taxiNodes == ns.TaxiNodes and options.taxiPaths == ns.TaxiPaths, "flights are unaffected")
	assert(options.portals == ns.Portals, "portals are unaffected")
end
ns.Routes = { [9] = lift }
-- The current ride is an alighting edge, not permission to board the excluded route again.
ns.CurrentRide = function()
	return 9
end
ns.Timetable.NextStop = function()
	return 2, 1000
end
local aboard = plan()
assert(hasLift(aboard) and aboard.legs[1].aboard, "an already-boarded hostile lift still reaches its next stop")
assert(not Context.Options(from, to).routes[9], "current ride does not reopen lift boarding")
local anchor, visit = ns.Timetable.Anchor, ns.Timetable.Visit
ns.Timetable.Anchor = function()
	return {}
end
ns.Timetable.Visit = function()
	return true
end
assert(Context.Ride(Context.Options(from, to)) == nil, "a stale ride at a dock cannot reopen the guarded lift")
ns.Timetable.Anchor, ns.Timetable.Visit = anchor, visit
assert(Context.Ride(Context.Options(from, to, "walking")) == nil, "internal walking policy still excludes rides")
assert(next(Context.Options(from, to, "walking").routes) == nil)
ns.CurrentRide = function() end

local function estimate()
	return { legs = ns.EstimateLegs(from, to) }
end
ns.faction = "Horde"
assert(hasLift(estimate()), "Horde can use its guarded lifts")
local revision = ns.EstimateContextRevision()
ns.faction = "Alliance"
assert(not hasLift(estimate()), "estimates change with faction and invalidate topology")
assert(ns.EstimateContextRevision() > revision, "incremental estimate callers see faction changes")
local API = driver.env.ShortestPathForever.API
ns.faction = "Horde"
local friendly = API.Estimate(1, 0.5, 0.5, 1, 0.5, 0.36)
ns.faction = "Alliance"
local opposing = API.Estimate(1, 0.5, 0.5, 1, 0.5, 0.36)
assert(friendly < opposing, "cached public estimates invalidate on a guarded boarding policy change")
ns.faction = "Horde"
driver.begin(from, to)
assert(hasLift(driver.shown()), "Horde active journey uses the lift")
ns.faction = "Alliance"
ns.TravelPolicyChanged()
driver.update(5)
assert(not hasLift(driver.shown()), "replanning guidance honours guarded landings")
ns.faction = "Horde"
ns.TravelPolicyChanged()
driver.update(5)
assert(hasLift(driver.shown()), "replanning for the friendly faction restores the lift")
print("guarded lifts: neutrality, faction inputs, cache, current ride, estimates and guidance passed")

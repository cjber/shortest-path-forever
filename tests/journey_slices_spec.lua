-- Slow slices must never publish unmeasured walking guidance. The search still settles to a reachable route.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
}) do
	driver.load(file)
end
assert(loadfile("tools/load_nav.lua"))(1)
ns.faction, ns.db.debug = "Horde", true
ns.Print = function(message)
	error(message)
end
-- Every clock read costs a tenth of the 3 ms budget: about one read per 64 expansions, whatever the machine.
local now = 0
ns.Path.clock = function()
	now = now + ns.Path.budget / 10
	return now
end
local nextFrame
ns.Path.after = function(fn)
	nextFrame = fn
end
local commit = ns.SetJourneyRoute
ns.SetJourneyRoute = function(g, route)
	local first = route and route.legs[1]
	assert(not first or first.mode ~= "walk" or first.measured, "guidance requires measured geometry")
	commit(g, route)
end
driver.begin(ns.TaxiNodes[25], ns.TaxiNodes[22])
local frames = 0
while nextFrame do
	local fn = nextFrame
	nextFrame = nil
	fn()
	frames = frames + 1
	driver.update(1 / 60)
	assert(frames < 20000, "journey did not settle")
end
assert(not ns.JourneyStatus())
local route = assert(driver.shown(), "expected a reachable journey")
for _, leg in ipairs(route.legs) do
	assert(
		leg.mode ~= "walk" or (leg.measured or leg.walkDeferred) and not leg.walkError,
		"the committed route's walks are proven"
	)
end
print("journey_slices_spec: ok")

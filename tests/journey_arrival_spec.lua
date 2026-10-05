local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
}) do
	driver.load(file)
end
ns.Path.IsLoaded = function(map)
	return map == 1
end
local goal = ns.TaxiNodes[67]
driver.begin(ns.TaxiNodes[26], goal)
local followed = assert(driver.shown())
local index = #followed.legs
local leg = followed.legs[index]
assert(leg.mode == "walk" and leg.from.map == 0 and leg.walkDeferred and not leg.measured)
local finds = #driver.path.finds
-- Resume the retained journey at its landing, through the same-journey branch in JourneySearch.
driver.move(leg.from)
local published
ns.JourneySearch.Start(goal, followed, { index = index }, function(route)
	published = route
end)
driver.path.settle()
assert(published == followed, "arrival should preserve the retained journey")
assert(#driver.path.finds > finds, "arrival did not request the deferred geometry")
assert(leg.measured and leg.walkDrawn and not leg.walkDeferred and not leg.walkError)
assert(#leg.walkPoints >= 2)
print("journey_arrival_spec: retained journey refines deferred geometry on arrival")

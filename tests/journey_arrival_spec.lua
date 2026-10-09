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
assert(not ns.SkipJourneyStep(index + 1), "manual skip rejects a stale non-current leg")
print("journey_arrival_spec: retained journey refines deferred geometry on arrival")

local manual = assert(loadfile("tests/journey_driver.lua"))()
local journey = manual.ns
journey.teleports = { { map = 1, x = 6930, y = 0, spell = 8690, item = 6948, cast = 10000 } }
journey.teleportReady = { 0 }
local origin, destination = { map = 1, x = 0, y = 0 }, { map = 1, x = 7000, y = 0 }
manual.begin(origin, destination)
assert(manual.shown().legs[1].teleport.item == 6948, "the journey initially chooses Hearthstone")
assert(not journey.SkipJourneyStep(2), "a stale step cannot complete the current Hearthstone")
manual.env.InCombatLockdown = function()
	return true
end
assert(not journey.SkipJourneyStep(1), "manual completion waits until combat ends")
manual.env.InCombatLockdown = function()
	return false
end
assert(journey.SkipJourneyStep(1), "the current Hearthstone can be skipped")
assert(journey.JourneyWithoutHearth(), "Hearthstone refusal lasts for this journey")
assert(
	journey.PlanContext.Options(origin, destination).withoutHearth == nil,
	"estimates do not inherit a journey refusal"
)
manual.update(5)
for _, remaining in ipairs(manual.shown().legs) do
	assert(
		not (remaining.teleport and remaining.teleport.item == 6948),
		"timed replans do not restore the refused Hearthstone"
	)
end
manual.begin(origin, destination)
assert(
	not journey.JourneyWithoutHearth() and manual.shown().legs[1].teleport.item == 6948,
	"a new journey can use Hearthstone again"
)
assert(journey.SkipJourneyStep(1) and journey.SkipJourneyStep(2), "current steps can be completed manually")
assert(not journey.HasJourney(), "completing the final step ends the journey")
print("journey_arrival_spec: manual completion and journey-local Hearthstone refusal ok")

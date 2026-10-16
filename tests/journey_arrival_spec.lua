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

-- A stop inside a dungeon is planned to the instance's door and completed by going in, not by standing at the door:
-- the next stop, inside too, starts once you are in.
local dungeon = assert(loadfile("tests/journey_driver.lua"))()
local game = dungeon.ns
local instance = 0
dungeon.env.GetInstanceInfo = function()
	return "", "none", 0, "", 0, 0, false, instance
end
dungeon.env.GetRealZoneText = function()
	return ""
end
game.Entrances = { [36] = { name = "Deadmines", map = 1, x = 3000, y = 0 } }
local boss, chest = { map = 36, x = 10, y = 10, label = "Boss" }, { map = 36, x = 20, y = 20, label = "Chest" }
local started
game.NextJourneyStop = function(point)
	started = point
	return point.stop == boss and chest or nil
end
dungeon.move({ map = 1, x = 0, y = 0 })
assert(game.StartJourney(boss))
dungeon.path.settle()
local planned = assert(dungeon.shown(), "the dungeon stop plans a journey")
local last = planned.legs[#planned.legs].to
assert(last.map == 1 and last.x == 3000 and last.y == 0 and last.label == "Boss", "it ends at the door")
dungeon.move({ map = 1, x = 3000, y = 0 })
dungeon.update(1)
assert(game.HasJourney() and started == nil, "standing at the door does not complete the stop")
dungeon.fire("PLAYER_ENTERING_WORLD")
assert(game.HasJourney() and started == nil, "loading into another place is not going in")
instance = 36
dungeon.fire("PLAYER_ENTERING_WORLD")
assert(started and started.stop == boss, "going in completes the stop the door stood for")
assert(game.HasJourney(), "the next stop inside the dungeon starts")
print("journey_arrival_spec: a dungeon stop is completed by going in ok")

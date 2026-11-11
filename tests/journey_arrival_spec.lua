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

-- Arrival distance (#733): the setting decides how close counts at the journey's final destination, a stop with
-- another after it keeps the fixed reach, and a map pin that was the destination is cleared rather than put back.
local function arrivalDriver(setting)
	local driven = assert(loadfile("tests/journey_driver.lua"))()
	local map = driven.env.C_Map
	-- Where a point stands on its zone map, as Core.Locate reads it, rather than the harness's fixed map centre.
	driven.ns.Locate = function(point)
		local uiMap, position = map.GetMapPosFromWorldPos(point.map, driven.env.CreateVector2D(point.x, point.y))
		local x, y = position:GetXY()
		return { uiMap = uiMap, x = x, y = y, zone = "Test" }
	end
	driven.ns.db.arrivalDistance = setting
	return driven
end
local function mapPin(driven, x, y)
	-- The stub's map position for a world point: world x grows from map y, world y from map x.
	return driven.env.UiMapPoint.CreateFromCoordinates(1, 0.5 - y / 50000, 0.5 - x / 50000)
end
local camp = { map = 1, x = 0, y = 0, label = "The Camp" }

local close = arrivalDriver(15)
close.move({ map = 1, x = 0, y = 100, z = 0 })
assert(close.ns.StartJourney(camp))
close.path.settle()
close.update(0.1)
close.move({ map = 1, x = 0, y = 20, z = 0 })
close.update(0.1)
assert(close.ns.HasJourney(), "20 yards is not arrival at the default 15")
close.move({ map = 1, x = 0, y = 15, z = 0 })
close.update(0.1)
assert(not close.ns.HasJourney(), "15 yards arrives at the default 15")

local wide = arrivalDriver(30)
wide.move({ map = 1, x = 0, y = 100, z = 0 })
assert(wide.ns.StartJourney(camp))
wide.path.settle()
wide.update(0.1)
wide.move({ map = 1, x = 0, y = 30, z = 0 })
wide.update(0.1)
assert(not wide.ns.HasJourney(), "30 yards arrives when the setting is 30")
print("journey_arrival_spec: the setting decides the arrival distance ok")

local multi = arrivalDriver(50)
local first = { map = 1, x = 0, y = 0, label = "First" }
local second = { map = 1, x = 0, y = -300, label = "Second" }
local current
multi.ns.NextJourneyStop = function(point)
	return point == first and second or nil
end
multi.ns.JourneyChanged = function(point)
	current = point
end
multi.move({ map = 1, x = 0, y = 100, z = 0 })
assert(multi.ns.StartJourney(first))
multi.path.settle()
multi.update(0.1)
multi.move({ map = 1, x = 0, y = 40, z = 0 })
multi.update(0.1)
assert(current == first and multi.ns.HasJourney(), "a stop with another after it keeps the fixed 15")
multi.move({ map = 1, x = 0, y = 10, z = 0 })
multi.update(0.1)
assert(current == second, "the fixed reach still arrives at a stop with another after it")
multi.path.settle()
print("journey_arrival_spec: only the final destination uses the setting ok")

local pinned = arrivalDriver(30)
local pinnedMap = pinned.env.C_Map
-- The guide hands its bends to the arrow; the harness has no arrow, so this holds the callback that writes them.
local pinnedBend
pinned.ns.PointGuideArrow = function(_, callback)
	pinnedBend = callback or pinnedBend
end
pinned.move({ map = 1, x = 0, y = 100, z = 0 })
assert(pinnedMap.SetUserWaypoint(mapPin(pinned, 0, 0)))
assert(pinned.ns.StartJourney(camp))
pinned.path.settle()
assert(pinnedBend and pinnedBend(camp), "the guide writes the destination as its waypoint")
pinned.update(0.1)
pinned.move({ map = 1, x = 0, y = 30, z = 0 })
pinned.update(0.1)
assert(not pinned.ns.HasJourney(), "the journey to the pin's own place arrives")
assert(pinned.waypoint() == nil, "a pin at the journey's destination is cleared on arrival")

local elsewhere = arrivalDriver(30)
local elsewhereMap = elsewhere.env.C_Map
local elsewhereBend
elsewhere.ns.PointGuideArrow = function(_, callback)
	elsewhereBend = callback or elsewhereBend
end
local saved = mapPin(elsewhere, 1000, 0)
elsewhere.move({ map = 1, x = 0, y = 100, z = 0 })
assert(elsewhereMap.SetUserWaypoint(saved))
assert(elsewhere.ns.StartJourney(camp))
elsewhere.path.settle()
assert(elsewhereBend and elsewhereBend(camp), "the guide writes its own waypoint elsewhere")
elsewhere.update(0.1)
elsewhere.move({ map = 1, x = 0, y = 30, z = 0 })
elsewhere.update(0.1)
assert(not elsewhere.ns.HasJourney(), "the journey elsewhere arrives")
local restored = assert(elsewhere.waypoint(), "a pin somewhere else comes back after arrival")
assert(
	restored.uiMapID == saved.uiMapID
		and restored.position.x == saved.position.x
		and restored.position.y == saved.position.y,
	"the player's earlier pin is restored as it was"
)
print("journey_arrival_spec: arrival clears a pin at the destination and restores any other ok")

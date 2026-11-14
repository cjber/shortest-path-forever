-- One tracked quest and TomTom framing the same objective, then a jump: the player's height rises and falls, the
-- client says it is falling, and the position samples arrive in the air. None of that is guidance's business, and a
-- frame where the client has no map for the player must not take the native waypoint away either: clearing it there
-- would drop the game's own pin and write it back on the next readable frame, so guidance would blink while the
-- journey scanned (#826).
local Fake = assert(loadfile("tests/tomtom_fake.lua"))()
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env

driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
driver.load("Core/Zygor.lua")

-- The client's TomTom, installed and enabled as the AddOns folder orders it (Shortest Path loads first).
local timers, created = {}, {}
env.C_AddOns = {
	DoesAddOnExist = function(name)
		return name == "TomTom"
	end,
	IsAddOnLoaded = function(name)
		return name == "TomTom" and env.TomTom ~= nil
	end,
	GetAddOnEnableState = function()
		return 2
	end,
}
env.UnitName = function()
	return "Tester"
end
env.hooksecurefunc = function(target, key, hook)
	local original = target[key] or function() end
	target[key] = function(...)
		local result = original(...)
		hook(...)
		return result
	end
end
env.C_Timer = {
	After = function(_, fn)
		timers[#timers + 1] = fn
	end,
}
local createFrame = env.CreateFrame
env.CreateFrame = function(...)
	local frame = createFrame(...)
	created[#created + 1] = frame
	return frame
end
ns.db.tomtom, ns.db.tomtomFollow = true, true

-- The arrow places the bend it is handed, and its 0.1 s poll places it again while the player moves, which a jump
-- does: through the air the guide is asked for its waypoint on every frame. `poll` stands for that poll.
local placed
ns.PointGuideArrow = function(points, placeBend)
	placed = points and placeBend and { points[#points], placeBend } or nil
	if placed then
		placed[2](placed[1], false)
	end
end
local function poll()
	if placed then
		placed[2](placed[1], false)
	end
end

local starts, searches, writes, clears = 0, 0, 0, 0
local startJourney, startSearch = ns.StartJourney, ns.JourneySearch.Start
ns.StartJourney = function(...)
	starts = starts + 1
	return startJourney(...)
end
ns.JourneySearch.Start = function(...)
	searches = searches + 1
	return startSearch(...)
end
local setWaypoint, clearWaypoint = env.C_Map.SetUserWaypoint, env.C_Map.ClearUserWaypoint
env.C_Map.SetUserWaypoint = function(point)
	writes = writes + 1
	return setWaypoint(point)
end
env.C_Map.ClearUserWaypoint = function(...)
	clears = clears + 1
	return clearWaypoint(...)
end

driver.load("Core/TomTom.lua")
local API = env.ShortestPathForever.API
local tomtom = Fake.New(nil)
function tomtom.ShowHideCrazyArrow() end
env.TomTom = tomtom
created[#created]:OnEvent("ADDON_LOADED", "TomTom")
tomtom:Enable()
created[#created]:OnEvent("PLAYER_ENTERING_WORLD")
for _, fn in ipairs(timers) do
	fn()
end
driver.path.settle()

-- One quest tracked, and the journey the tracker binding plans: the player's own, to the quest's objective. TomTom's
-- arrow then takes the same objective under its own name, so the journey changes hands without starting again.
local QUEST = 1234
env.C_SuperTrack.SetSuperTrackedQuestID(QUEST)
local MAP, X, Y = 1, 0.6, 0.5
local objective = assert(ns.WorldPoint(MAP, X, Y))
objective.label, objective.questID, objective.questIDs = "The Escape", QUEST, { QUEST }
driver.move({ map = 1, x = 0, y = 0, z = 0 })
assert(ns.StartJourney(objective))
driver.path.settle()
assert(tomtom:AddWaypoint(MAP, X, Y, { title = "The Escape" }))
driver.path.settle()
assert(ns.IsJourneyGuided() and driver.waypoint(), "the journey guides and writes its waypoint")
assert(starts == 1 and searches == 1, "one journey, one search")
local held = { starts = starts, searches = searches, writes = writes, clears = clears }
local waypoint = driver.waypoint()

-- The jump its own self: the client's falling answer, a height that rises and falls, and position samples in the air.
local falling = true
env.IsFalling = function()
	return falling
end
driver.fire("PLAYER_STARTED_MOVING")
for step = 1, 20 do
	local rise = step <= 5 and step * 1.2 or math.max(0, 6 - (step - 5) * 1.2)
	driver.move({ map = 1, x = -step * 3, y = 0, z = rise })
	driver.update(0.05)
	poll()
end
driver.move({ map = 1, x = -60, y = 0, z = 0 })
falling = false
driver.fire("PLAYER_STOPPED_MOVING")
driver.update(0.05)
poll()
driver.path.settle()
assert(starts == held.starts and searches == held.searches, "a jump starts no journey and no search")
assert(clears == held.clears, "a jump takes no waypoint away")
assert(ns.IsJourneyGuided() and driver.waypoint(), "guidance and its waypoint are still there")
assert(driver.shown(), "the drawn route stays")
assert(API.CurrentStop("TomTom") == 1, "the journey is still TomTom's, to the quest's objective")

-- A second jump, through frames where the client has no map for the player: the waypoint Guide placed is still the
-- guidance the player has, and the next map the client names places it. Taking it away for those frames and writing it
-- back on landing is the blink the journey must not show.
local bestMap = env.C_Map.GetBestMapForUnit
local inAir = false
env.C_Map.GetBestMapForUnit = function(...)
	if inAir then
		return nil
	end
	return bestMap(...)
end
falling, inAir = true, true
driver.fire("PLAYER_STARTED_MOVING")
for step = 1, 12 do
	driver.move({ map = 1, x = -60 - step * 2, y = 0, z = step <= 4 and step * 1.5 or 0 })
	driver.update(0.05)
	poll()
end
assert(ns.IsJourneyGuided(), "a frame without a map answer does not stop the guide")
assert(driver.waypoint() == waypoint, "and does not take the waypoint away")
assert(clears == held.clears, "the native waypoint is never cleared in the air")
inAir, falling = false, false
driver.move({ map = 1, x = -90, y = 0, z = 0 })
driver.fire("PLAYER_STOPPED_MOVING")
driver.update(0.05)
poll()
driver.path.settle()
assert(driver.waypoint() == waypoint, "and it is the same one on landing")
assert(starts == held.starts and searches == held.searches, "the map answer in the air starts nothing")

print("journey jump: guidance keeps its waypoint through a jump and a missing map answer")

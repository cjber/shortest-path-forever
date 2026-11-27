-- A Nearby pick made mid-fight is queued and said, never silently refused as the public route calls are (#1413).
local fixture = assert(loadfile("tests/nearby_spec.lua"))()
local env, ns = fixture.env, fixture.ns
-- The shared fixture ends on a menu with no QuestieDB: read a full one again.
fixture.fresh(fixture.lib)

local picked, notices = nil, 0
ns.PickInCombat = function(stop)
	picked = stop
	return true
end
ns.NoticeQueuedDestination = function()
	notices = notices + 1
end
env.InCombatLockdown = function()
	return true
end
local routed = 0
env.ShortestPathForever.API.NavigateRoute = function()
	routed = routed + 1
	return true
end

-- With no planner to compare places, the nearest one is picked at once.
env.SlashCmdList.SPFNEAR("repair")
assert(picked and picked.title == "Neutral repairs" and routed == 0, "a single pick goes to the queueing call")

-- With several places to compare, the click says the pick is queued; the search itself waits for the fight to end.
local searches = 0
ns.EstimateIn = function() end
ns.JourneyGoal = function() end
ns.JourneySearch = { Here = function() end }
ns.Path.Run = function()
	searches = searches + 1
	return {}
end
picked, searches, notices = nil, 0, 0
env.SlashCmdList.SPFNEAR("class")
assert(searches > 0, "the places are compared")
assert(notices == 1 and picked == nil and routed == 0, "the choice is confirmed and nothing starts in combat")
print("nearby_combat_spec: mid-fight Nearby picks are queued and confirmed")

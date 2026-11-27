-- A Nearby pick made mid-fight is queued and said, never silently refused as the public route calls are (#1413).
local fixture = assert(loadfile("tests/nearby_spec.lua"))()
local env, ns = fixture.env, fixture.ns
-- The shared fixture ends on a menu with no QuestieDB: read a full one again.
fixture.fresh(fixture.lib)

local picked, requests = nil, 0
ns.PickInCombat = function(stop)
	picked = stop
	return true
end
-- Journey/JourneyInput.lua counts the player's picks; what it counts and says is combat_destination_spec's.
ns.PlayerPicked = function()
	requests = requests + 1
end
ns.PlayerRequests = function()
	return requests
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

-- With several places to compare, the click counts as a pick; the search itself waits for the fight to end.
local searches = 0
ns.EstimateIn = function() end
ns.JourneySearch = { Here = function() end }
ns.Path.Cancel = function() end
ns.Path.Run = function()
	searches = searches + 1
	return {}
end
picked, searches, requests = nil, 0, 0
env.SlashCmdList.SPFNEAR("class")
assert(searches > 0, "the places are compared")
assert(requests == 1 and picked == nil and routed == 0, "the pick is counted and nothing starts in combat")
-- A choice compared after the fight starts unless the player picked or cleared something since: a journey the addon
-- ended or moved meanwhile (an arrival, a quest handed in, a guide's next step) is not a newer request.
local chosen
-- The chooser's searches are NearbyRank's own specs: here its answer arrives when the spec says.
local function upvalue(fn, wanted)
	for i = 1, math.huge do
		local name, value = debug.getupvalue(fn, i)
		if name == wanted then
			return value, i
		end
		assert(name, "no upvalue " .. wanted)
	end
end
local travel = upvalue(env.SlashCmdList.SPFNEAR, "Travel")
local _, slot = upvalue(travel, "Choose")
debug.setupvalue(travel, slot, function(candidates, _, _, _, callback)
	chosen = function()
		callback(candidates[1])
	end
	return function() end
end)
env.InCombatLockdown = function()
	return false
end
for _, newer in ipairs({ false, true }) do
	routed = 0
	env.SlashCmdList.SPFNEAR("class")
	if newer then
		requests = requests + 1
	end
	chosen()
	assert(routed == (newer and 0 or 1), "only the player's newer request drops the choice: " .. tostring(newer))
end
print("nearby_combat_spec: mid-fight Nearby picks are queued, and the player's newer request wins")

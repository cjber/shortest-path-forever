-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")

-- Deleting the map pin that planned a journey ends that route in the real client event flow (#1348),
-- while leaving a Shift-click journey and an API guide journey alone.
scenario("deleting the focused map pin cancels its journey (#1348)", {
	addons = ForeverCore.addons(),
}, function(sim)
	local player = sim.world.player
	player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
	player.map, player.x, player.y = 1429, 0.42, 0.65
	player.worldX, player.worldY, player.instance = -9449, 64, 0
	sim.world.maps[947] = { name = "Azeroth", mapType = 1 }
	sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
	sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }

	local waypoint, tracked
	sim.impl["C_Map.CanSetUserWaypointOnMap"] = function()
		return true
	end
	sim.impl["C_Map.HasUserWaypoint"] = function()
		return waypoint ~= nil
	end
	sim.impl["C_Map.GetUserWaypoint"] = function()
		return waypoint
	end
	sim.impl["C_Map.SetUserWaypoint"] = function(point)
		waypoint = point
		sim.world.waypoint = { map = point.uiMapID, x = point.position.x, y = point.position.y }
		sim:event("USER_WAYPOINT_UPDATED")
		return true
	end
	sim.impl["C_Map.ClearUserWaypoint"] = function()
		waypoint = nil
		sim.world.waypoint = nil
		sim:event("USER_WAYPOINT_UPDATED")
	end
	sim.impl["C_SuperTrack.IsSuperTrackingUserWaypoint"] = function()
		return tracked == true
	end
	sim.impl["C_SuperTrack.SetSuperTrackedUserWaypoint"] = function(value)
		tracked = value == true
		sim:event("SUPER_TRACKING_CHANGED")
	end
	sim.impl["C_Map.GetWorldPosFromMapPos"] = function(_, pos)
		local x, y = pos:GetXY()
		return 0, sim.G.CreateVector2D(-9449 + (0.65 - y) * 1000, 64 + (0.42 - x) * 1000)
	end
	sim.impl["C_Map.GetMapPosFromWorldPos"] = function(_, world)
		local wx, wy = world:GetXY()
		return 1429, sim.G.CreateVector2D(0.42 - (wy - 64) / 1000, 0.65 - (wx + 9449) / 1000)
	end

	sim:login()
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns, "full addon namespace loaded")

	-- Player drops a map pin: Shortest Path plans a journey to it.
	sim:input(function()
		sim.G.C_Map.SetUserWaypoint(sim.G.UiMapPoint.CreateFromCoordinates(1429, 0.5, 0.5))
	end)
	sim:advance(0.2)
	assert(ns.HasJourney(), "placing a map pin starts a journey")

	-- Player deletes the map pin: the journey cancels at once.
	sim:input(function()
		sim.G.C_Map.ClearUserWaypoint()
	end)
	sim:advance(0.2)
	assert(not ns.HasJourney(), "deleting the map pin cancels its journey")
	assert(waypoint == nil, "the deleted pin stays gone")

	-- A Shift-click journey (not started by a pin) survives clearing the waypoint.
	sim:input(function()
		assert(ns.JourneyToMapPoint(1429, 0.55, 0.55), "manual map point starts a journey")
	end)
	sim:advance(0.2)
	local manualGoal = ns.JourneyGoal()
	assert(manualGoal, "manual journey is active")
	sim:input(function()
		sim.G.C_Map.ClearUserWaypoint()
	end)
	sim:advance(0.2)
	assert(ns.JourneyGoal() == manualGoal, "clearing the pin preserves a manual journey")
	ns.ClearJourney()

	-- An API guide journey survives clearing the waypoint.
	local API = sim.G.ShortestPathForever.API
	sim:input(function()
		assert(API.NavigateRoute("Guide", { { map = 1429, x = 0.5, y = 0.5, title = "Step 1" } }))
	end)
	sim:advance(0.2)
	local guideGoal = ns.JourneyGoal()
	assert(guideGoal and API.CurrentStop("Guide") == 1, "guide journey is active")
	sim:input(function()
		sim.G.C_Map.ClearUserWaypoint()
	end)
	sim:advance(0.2)
	assert(ns.JourneyGoal() == guideGoal and API.CurrentStop("Guide") == 1, "clearing the pin keeps a guide journey")
	API.Cancel("Guide")

	sim:expectNoErrors(ADDON)
end)

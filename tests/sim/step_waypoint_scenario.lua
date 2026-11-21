-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")

local function check(mode)
	scenario("step waypoint stays at the destination: " .. mode, {
		addons = ForeverCore.addons(),
	}, function(sim)
		local player = sim.world.player
		player.map, player.x, player.y = 1429, 0.1, 0.1
		player.worldY, player.worldX, player.instance = 100, 100, 0
		sim.world.maps[1429] = { name = "Elwynn Forest", mapType = 3 }
		sim.impl["GetPlayerFacing"] = function()
			return 0
		end
		sim.impl["C_Map.GetMapPosFromWorldPos"] = function(_, world)
			local x, y = world:GetXY()
			return 1429, sim.G.CreateVector2D(x / 1000, y / 1000)
		end
		local waypoint, tracked
		local writes, projections = 0, 0
		sim.impl["C_Map.ClearUserWaypoint"] = function()
			waypoint = nil
		end
		sim.impl["C_Map.GetWorldPosFromMapPos"] = function(_, position)
			-- Waypoint UI rounds this X to 0.5, so projecting the requested X exposes a stale comparison.
			if position.y == 0.4 and position.x == 0.50025 then
				projections = projections + 1
			end
			return 0, sim.G.CreateVector2D(position.x * 1000, position.y * 1000)
		end
		sim.impl["C_Map.GetUserWaypoint"] = function()
			return waypoint
		end
		sim.impl["C_Map.SetUserWaypoint"] = function(point)
			waypoint = point
			writes = writes + 1
			return true
		end
		sim.impl["C_SuperTrack.IsSuperTrackingUserWaypoint"] = function()
			return tracked == true
		end
		sim.impl["C_SuperTrack.SetSuperTrackedUserWaypoint"] = function(value)
			tracked = value
		end
		sim:login()
		local ns
		for _, entry in ipairs(sim.loader.addons) do
			if entry.name == ADDON then
				ns = entry.ns
			end
		end
		assert(ns and ns.db.guideStops and not ns.db.arrowDirect, "use default guidance settings")
		local handovers = 0
		local function loadWaypointUI()
			local isLoaded = sim.impl["C_AddOns.IsAddOnLoaded"]
			sim.impl["C_AddOns.IsAddOnLoaded"] = function(name)
				return name == "WaypointUI" or isLoaded(name)
			end
			sim.G.WaypointUIAPI = {
				Navigation = {
					IsUserNavigationTracked = sim.impl["C_SuperTrack.IsSuperTrackingUserWaypoint"],
					GetUserNavigation = sim.impl["C_Map.GetUserWaypoint"],
					NewUserNavigation = function(opts)
						handovers = handovers + 1
						sim.G.C_Map.SetUserWaypoint(
							sim.G.UiMapPoint.CreateFromCoordinates(
								opts.mapID,
								math.floor(opts.x * 10) / 1000,
								math.floor(opts.y * 10) / 1000
							)
						)
						sim.G.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
						return opts
					end,
				},
			}
		end
		if mode == "Waypoint UI" then
			loadWaypointUI()
		end
		local start = { map = 0, x = 100, y = 100 }
		local bend = { map = 0, x = 200, y = 200 }
		local legEnd = { map = 0, x = 300, y = 200 }
		local goal = { map = 0, x = 500.25, y = 400, routeTitle = "Goldshire" }
		ns.JourneyGuide.Start()
		ns.JourneyGuide.To(legEnd, { start, bend, legEnd }, goal)
		local function expectWaypoint(x, y)
			assert(waypoint, "expected a waypoint at the step destination")
			local actualX, actualY = waypoint.position.x, waypoint.position.y
			assert(
				math.abs(actualX - x) < 1e-6 and math.abs(actualY - y) < 1e-6,
				("expected waypoint at %.2f, %.2f; got %.2f, %.2f"):format(x, y, actualX, actualY)
			)
		end
		local expectedX = mode == "Waypoint UI" and 0.5 or 0.50025
		expectWaypoint(expectedX, 0.4)
		assert(ns.GuideState() == bend and ns.ArrowLeads(), "Shortest Path's arrow leads to the bend")
		local initialProjections = projections
		player.worldY, player.worldX = bend.x, bend.y
		sim:advance(0.2)
		assert(ns.GuideState() == legEnd and ns.ArrowLeads(), "the arrow advances to the leg end")
		expectWaypoint(expectedX, 0.4)
		ns.JourneyGuide.To(goal, { legEnd, goal }, goal)
		expectWaypoint(expectedX, 0.4)
		assert(writes == 1 and handovers == (mode == "Waypoint UI" and 1 or 0), "the step waypoint is written once")
		if mode == "Waypoint UI" then
			assert(projections == initialProjections, "moving frames must use the exact waypoint read-back")
		end
		if mode == "late Waypoint UI" then
			loadWaypointUI()
			sim:event("ADDON_LOADED", "WaypointUI")
			assert(writes == 2 and handovers == 1, "late Waypoint UI receives the current destination once")
			expectedX = 0.5
			expectWaypoint(expectedX, 0.4)
			player.worldY = player.worldY + 1
			sim:advance(0.2)
			assert(writes == 2 and handovers == 1, "the handover is not repeated")
		end

		local guide = ns.JourneyGuide
		local cast = { mode = "teleport", from = legEnd, to = start, teleport = { item = 6948 } }
		local function waitForCast(destination)
			local function notLanded()
				return false
			end
			assert(ns.AdvanceJourneyProgress({ cast }, { index = 1 }, destination, nil, false, notLanded, guide))
		end
		local beforeCast = writes
		waitForCast(goal)
		assert(guide.Casting() and ns.ArrowLeads() and not ns.GuideState(), "the cast prompt takes over the arrow")
		expectWaypoint(expectedX, 0.4)
		ns.JourneyGuide.To(goal, { legEnd, goal }, goal)
		expectWaypoint(expectedX, 0.4)
		assert(writes == beforeCast, "walk, cast and walk share one step-end write")

		local nextGoal = { map = 0, x = 600, y = 500, routeTitle = "Next step" }
		waitForCast(nextGoal)
		assert(waypoint == nil, "a cast for a different destination clears the old waypoint")
		ns.JourneyGuide.To(nextGoal, { goal, nextGoal }, nextGoal)
		expectWaypoint(0.6, 0.5)
		sim:expectNoErrors(ADDON)
	end)
end

check("Waypoint UI")
check("late Waypoint UI")
check("native")

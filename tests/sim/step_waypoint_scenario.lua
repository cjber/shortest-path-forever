-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")

local function check(withWaypointUI)
	scenario("step waypoint stays at the destination: " .. (withWaypointUI and "Waypoint UI" or "native"), {
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
		local writes = 0
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
		if withWaypointUI then
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
							sim.G.UiMapPoint.CreateFromCoordinates(opts.mapID, opts.x / 100, opts.y / 100)
						)
						sim.G.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
						return opts
					end,
				},
			}
		end
		local start = { map = 0, x = 100, y = 100 }
		local bend = { map = 0, x = 200, y = 200 }
		local legEnd = { map = 0, x = 300, y = 200 }
		local goal = { map = 0, x = 500, y = 400, routeTitle = "Goldshire" }
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
		expectWaypoint(0.5, 0.4)
		assert(ns.GuideState() == bend and ns.ArrowLeads(), "Shortest Path's arrow leads to the bend")
		player.worldY, player.worldX = bend.x, bend.y
		sim:advance(0.2)
		assert(ns.GuideState() == legEnd and ns.ArrowLeads(), "the arrow advances to the leg end")
		expectWaypoint(0.5, 0.4)
		ns.JourneyGuide.To(goal, { legEnd, goal }, goal)
		expectWaypoint(0.5, 0.4)
		assert(writes == 1 and handovers == (withWaypointUI and 1 or 0), "the step waypoint is written once")

		local nextGoal = { map = 0, x = 600, y = 500, routeTitle = "Next step" }
		ns.JourneyGuide.To(nextGoal, { goal, nextGoal }, nextGoal)
		expectWaypoint(0.6, 0.5)
		sim:expectNoErrors(ADDON)
	end)
end

check(true)
check(false)

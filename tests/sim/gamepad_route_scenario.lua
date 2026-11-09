-- luacheck: read globals scenario ADDON
-- With Gamepad UI on, a Shift-click on the world map starts a journey from the map's own canvas click. The guide
-- then sets the client's user waypoint; while the map is shown that runs the map's waypoint provider and pin code in
-- the addon's taint, which the controller's close reads as it pops the map's focus and blocks
-- SetPreferredGamepadInteractTarget (#581). The guide leaves the waypoint write until the map has closed.
scenario("a gamepad shift-click route leaves the map close secure", function(sim)
	local G = sim.G
	local player = sim.world.player
	player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
	player.map, player.x, player.y = 1429, 0.1, 0.1
	player.worldX, player.worldY, player.instance = -9449, 64, 0
	sim.world.maps[947] = { name = "Azeroth", mapType = 1 }
	sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
	sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
	sim:login()
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns, "full addon namespace loaded")

	-- The simulator's map geometry is a stand-in: one world point stands in for the clicked empty space, and only
	-- that point resolves back to Elwynn Forest. The client's waypoint provider refreshes synchronously when the
	-- waypoint changes, while the map is up.
	sim.impl.GetPlayerFacing = function()
		return 0
	end
	sim.impl["C_Map.GetWorldPosFromMapPos"] = function()
		return 0, G.CreateVector2D(-9000, 100)
	end
	sim.impl["C_Map.GetMapPosFromWorldPos"] = function(map, world)
		local x, y = world:GetXY()
		if map == 0 and x == -9000 and y == 100 then
			return 1429, G.CreateVector2D(0.42, 0.65)
		end
	end
	local waypointProvider
	for provider in pairs(G.WorldMapFrame.dataProviders or {}) do
		if provider.RefreshAllData == G.WaypointLocationDataProviderMixin.RefreshAllData then
			waypointProvider = provider
		end
	end
	assert(waypointProvider, "the map's waypoint provider is loaded")
	sim.impl["C_Map.HasUserWaypoint"] = function()
		return sim.world.waypoint ~= nil
	end
	sim.impl["C_Map.GetUserWaypoint"] = function()
		local waypoint = sim.world.waypoint
		if waypoint then
			return { uiMapID = waypoint.map, position = G.CreateVector2D(waypoint.x, waypoint.y) }
		end
	end
	sim.impl["C_Map.SetUserWaypoint"] = function(point)
		local position = point.position
		local x, y = position.x, position.y
		if type(x) ~= "number" and position.GetXY then
			x, y = position:GetXY()
		end
		sim.world.waypoint = { map = point.uiMapID, x = x, y = y }
		if waypointProvider and G.WorldMapFrame:IsShown() then
			waypointProvider:RefreshAllData()
		end
		return true
	end
	sim.impl["C_Map.ClearUserWaypoint"] = function()
		sim.world.waypoint = nil
		if waypointProvider and G.WorldMapFrame:IsShown() then
			waypointProvider:RefreshAllData()
		end
		return true
	end

	-- The simulator's terrain cannot plan this synthetic walk, so the route drawing is left out and the guide step
	-- that writes the waypoint is driven directly, as the journey's own planner would.
	local setJourneyRoute, refreshJourneyPin = ns.SetJourneyRoute, ns.RefreshJourneyPin
	ns.SetJourneyRoute = function() end
	ns.RefreshJourneyPin = function() end

	sim:setGamepad(true)
	sim:openWorldMap(1429)
	local map = G.WorldMapFrame
	local scroll = map.ScrollContainer
	sim.modifiers.shift = true
	sim.mouseX, sim.mouseY = 800, 450
	sim:input(function()
		scroll:OnMouseDown("LeftButton")
		scroll:OnMouseUp("LeftButton")
	end)
	sim.modifiers.shift = false
	ns.SetJourneyRoute, ns.RefreshJourneyPin = setJourneyRoute, refreshJourneyPin
	local goal = ns.JourneyGoal()
	assert(goal, "the Shift-click starts the journey")
	assert(ns.JourneyGuide.Active(), "the journey starts guided")

	local function blocked()
		local out = {}
		for _, e in ipairs(sim.errors) do
			if e.event == "ADDON_ACTION_BLOCKED" then
				out[#out + 1] = e.message
			end
		end
		return out
	end

	-- The route's guide step, while the map is still open.
	sim:input(function()
		ns.JourneyGuide.To(goal, nil, goal)
	end)
	assert(
		#blocked() == 0,
		"the guide left the native waypoint until the map closed:\n" .. table.concat(blocked(), "\n")
	)
	assert(sim.world.waypoint == nil, "no waypoint is written while the map is open")

	-- The controller's close: FrameControlsManager pops the map's focus and the gamepad action bar makes its
	-- protected call.
	sim:closeWorldMap()
	sim:advance(0.2)
	sim:gamepadNavigate()
	sim:advance(0.2)
	assert(#blocked() == 0, "the map close leaves the gamepad focus secure:\n" .. table.concat(blocked(), "\n"))

	-- The next guide update, with the map gone, writes the waypoint without touching the map's close path. The
	-- simulator cannot plan the synthetic walk, so the journey's search gives up and the guide is started again.
	sim:input(function()
		ns.JourneyGuide.Start()
		ns.JourneyGuide.To(goal, nil, goal)
	end)
	assert(sim.world.waypoint, "the guide writes the waypoint once the map has closed")

	sim:advance(0.2)
	sim:expectNoErrors(ADDON)
end)

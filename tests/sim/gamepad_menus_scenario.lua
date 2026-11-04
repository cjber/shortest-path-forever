-- luacheck: read globals scenario ADDON
-- Under the gamepad interface, Forever's FrameControlsManager takes every menu that shows (MenuProxy.OnShow) and
-- every UI panel (UIParentPanelManager.ShowUIPanel) into its focus, pushing a binding set whose change runs the
-- gamepad action bar's UpdateInteractIcons and its protected SetPreferredGamepadInteractTarget in the same call.
-- A menu or panel Shortest Path's own code shows therefore makes that call tainted and the client blocks it (#158).
scenario("addon menus and map turns leave the gamepad focus to the game", function(sim)
	local G = sim.G
	local player = sim.world.player
	player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
	player.map, player.x, player.y = 1429, 0.42, 0.65
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

	-- What FrameControlsManager would take into its focus, and the taint it would run under. The simulator cannot
	-- draw a menu or turn the map, so the calls that would are recorded at their entry points instead: a context
	-- menu always shows (MenuProxy.OnShow), and the map handler sets the map and its pins.
	local focused = {}
	local function Record(kind)
		if sim.gamepad then
			focused[#focused + 1] = { kind = kind, taint = sim.taint.current }
		end
	end
	G.MenuUtil.CreateContextMenu = function()
		Record("context menu")
	end
	local openWorldMap = G.C_Map.OpenWorldMap
	G.C_Map.OpenWorldMap = function(...)
		if not sim.taint.current then
			return openWorldMap(...)
		end
		Record("world map")
	end

	sim:openWorldMap(1429)
	sim:input(function()
		ns.StartJourney(ns.DockPoint(5))
	end)
	sim:advance(1)
	assert(ns.JourneyGoal(), "the journey starts with the map open")
	sim:setGamepad(true)

	local tracker = G.ShortestPathForeverObjectiveTracker
	assert(tracker, "the tracker section exists")
	-- Each is what a click on our own frame runs: the tracker's journey header and the Nearby services command.
	sim:input(function()
		tracker:OnBlockHeaderClick({ id = "journey" }, "RightButton")
	end)
	sim:advance(0.1)
	-- With the world map up, as the game opened it.
	sim:openWorldMap(1429)
	assert(G.WorldMapFrame:IsShown(), "the map is open")
	sim:input(function()
		G.SlashCmdList.SPFNEAR("")
	end)
	sim:advance(0.1)
	-- Show on map with the map already open: the game's own code turns it.
	sim:input(function()
		ns.OpenWorldMap(1415)
	end)
	sim:advance(0.1)
	sim:gamepadNavigate()

	local tainted = {}
	for _, f in ipairs(focused) do
		if f.taint then
			tainted[#tainted + 1] = f.kind .. " by " .. f.taint
		end
	end
	assert(#tainted == 0, "gamepad focus taken under taint: " .. table.concat(tainted, ", "))
	sim:closeWorldMap()
	sim:expectNoErrors(ADDON)
end)

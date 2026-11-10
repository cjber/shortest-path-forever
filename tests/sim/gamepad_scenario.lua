-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")
-- The full TOC under the native client, which loads no deprecation fallbacks: a journey on the open world map,
-- then the gamepad interface, combat and another map. Controller players reported a blocked
-- SetPreferredGamepadInteractTarget (#158); Shortest Path must leave the tables the gamepad walks untouched.
scenario("journey on the world map leaves gamepad tables native", { addons = ForeverCore.addons() }, function(sim)
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
	sim:openWorldMap(1429)
	-- The simulator's map geometry is a stand-in, so start from the addon's own world coordinates: Menethil's pier.
	sim:input(function()
		ns.StartJourney(ns.DockPoint(5))
	end)
	sim:advance(1)
	assert(ns.JourneyGoal(), "the journey starts with the map open")
	sim:zoomMap(2)
	sim:panMap(40, 20)
	sim:setGamepad(true)
	sim:gamepadNavigate()
	sim:enterCombat()
	sim:advance(0.5)
	sim:gamepadNavigate()
	sim:leaveCombat()
	sim:closeWorldMap()
	sim:openWorldMap(1415)
	sim:advance(0.5)
	sim:gamepadNavigate()
	sim:closeWorldMap()
	sim:expectNoErrors(ADDON)
end)

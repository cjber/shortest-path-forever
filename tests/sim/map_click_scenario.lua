-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")
-- A journey-key click on the world map canvas, through Blizzard's own scroll container and click registry, beside a
-- map addon that takes left clicks first. OpenMap zooms in on every plain or Alt left click at priority 1000, so
-- with Alt as the journey key the map zoomed and no journey was planned (#1076).

-- An OpenMap stand-in: its canvas handler leaves Shift-clicks to other addons and takes every other left click.
local OPENMAP = [[
local zooms = 0
WorldMapFrame:AddCanvasClickHandler(function(_, button)
	if button == "LeftButton" and not IsShiftKeyDown() then
		zooms = zooms + 1
		return true
	end
	return false
end, 1000)
function OpenMapStandInZooms()
	return zooms
end
]]

local function Click(sim, key)
	local sc = sim.G.WorldMapFrame.ScrollContainer
	local left, bottom, width, height = sc:GetRect()
	local scale = sc:GetEffectiveScale()
	sim.mouseX, sim.mouseY = (left + width * 0.4) * scale, (bottom + height * 0.6) * scale
	sim:hover(sc)
	sim.modifiers[key] = true
	sim:input(function()
		sim.widgets.dispatch(sc, "OnMouseDown", "LeftButton")
	end)
	sim:input(function()
		sim.widgets.dispatch(sc, "OnMouseUp", "LeftButton", true)
	end)
	sim.modifiers[key] = nil
	sim:advance(0.2)
end

for _, key in ipairs({ "shift", "alt" }) do
	scenario("a " .. key .. "-click on the map plans a journey before another map addon's click handler", {
		addons = ForeverCore.addons(),
	}, function(sim)
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
		sim:runAs("OpenMap", OPENMAP)
		ns.db.journeyKey = key
		sim:openWorldMap(1429)
		sim:advance(0.5)
		-- The planner itself needs world data the simulator stands in for; the click reaching it is what matters.
		local planned
		local plan = ns.JourneyToMapPoint
		ns.JourneyToMapPoint = function(mapID, x, y)
			planned = { mapID = mapID, x = x, y = y }
		end
		Click(sim, key)
		ns.JourneyToMapPoint = plan
		assert(planned and planned.mapID == 1429, key .. "-click reached the journey planner")
		assert(sim.G.OpenMapStandInZooms() == 0, key .. "-click was not also taken as a zoom")
	end)
end

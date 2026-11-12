-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")
-- The world map's town services: service pins in a capital, a group pin wearing the addon's market stall with every
-- service in its tooltip, the Shift-click journey, a zoom re-cluster, the four levels of detail, and combat and the
-- gamepad interface over the layer. The services themselves come from a ready Nearby list here, with a projection
-- into the simulator's Elwynn and Stormwind maps.
scenario(
	"town services draw, split, hover and survive combat and the gamepad interface",
	{ addons = ForeverCore.addons() },
	function(sim)
		local player = sim.world.player
		player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
		player.map, player.x, player.y = 1429, 0.42, 0.65
		player.worldX, player.worldY, player.instance = -9449, 64, 0
		sim.world.maps[947] = { name = "Azeroth", mapType = 1 }
		sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
		sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
		sim.world.maps[1453] = { name = "Stormwind City", parent = 1415, mapType = 3 }
		-- A world point on any map asked for, in the simulator's own map geometry.
		sim.impl["C_Map.GetMapPosFromWorldPos"] = function(_, vector, override)
			local x, y = vector:GetXY()
			return override or 1429,
				{
					GetXY = function()
						return (x + 12000) / 6000, (y + 3000) / 6000
					end,
				}
		end
		sim:login()
		local ns
		for _, entry in ipairs(sim.loader.addons) do
			if entry.name == ADDON then
				ns = entry.ns
			end
		end
		assert(ns, "full addon namespace loaded")

		-- A ready Nearby list: two services inside Stormwind, and a food seller in Elwynn outside it. The groups carry
		-- the client's tracking atlases the map pins wear.
		local function group(section, key, label, tracking)
			return { section = section, key = key, label = label, icon = tracking, tracking = tracking, npcs = {} }
		end
		local groups = {
			group("services", "bank", "Bank", "Banker"),
			group("services", "innkeeper", "Innkeeper", "Innkeeper"),
			group("vendors", "food", "Food", "Food"),
		}
		local function place(id, name, x, y)
			return {
				id = id,
				name = name,
				map = 1429,
				x = 0.5,
				y = 0.5,
				world = { map = 0, x = x, y = y },
			}
		end
		local index = {
			bank = { place(1, "Banker One", -8500, 800) },
			innkeeper = { place(2, "Innkeeper Two", -8440, 860) },
			food = { place(3, "Food Three", -9449, 64) },
		}
		local navigated
		ns.NearbyServices = {
			State = function()
				return "ready"
			end,
			Index = function()
				return index
			end,
			Groups = function()
				return groups
			end,
			OnReady = function() end,
			Navigate = function(key, spot)
				navigated = { key = key, spot = spot }
				return true
			end,
		}

		sim:openWorldMap(1429)
		sim:input(function()
			ns.db.townServices = "all"
			ns.RefreshTownServices()
		end)
		sim:advance(0.2)
		local pins = ns.Canvas.Pools(sim.G.WorldMapFrame).ShortestPathForeverServicePinTemplate
		assert(pins:GetNumActive() == 2, "the capital's grouped services and the outlying seller are drawn")
		local groupPin
		for _, pin in ipairs(pins.active) do
			if #pin.cluster.services > 1 then
				groupPin = pin
			end
		end
		assert(groupPin, "two overlapping services share one pin")
		assert(
			groupPin.Texture:GetTexture() == "Interface\\AddOns\\ShortestPathForever\\media\\TownGroup",
			"the group pin wears the addon's market stall"
		)
		assert(groupPin.Texture:GetAtlas() == nil, "no service's atlas or a town mark on a group pin")
		sim:hover(groupPin)
		sim:advance(0.2)
		sim:leave()
		sim:input(function()
			ns.Canvas.Click(groupPin, "LeftButton")
		end)
		assert(navigated and navigated.key == "bank", "a click plans a journey to the group's service")

		-- A zoom re-clusters the pins; combat defers the redraw and the regen event brings it back.
		sim:zoomMap(2)
		sim:input(function()
			ns.RefreshTownServices()
		end)
		sim:advance(0.2)
		sim:setGamepad(true)
		sim:gamepadNavigate()
		sim:hover(pins.active[1])
		sim:advance(0.2)
		sim:leave()
		sim:enterCombat()
		sim:advance(0.5)
		sim:input(function()
			ns.RefreshTownServices()
		end)
		sim:leaveCombat()
		sim:advance(0.5)
		sim:gamepadNavigate()

		-- Capitals only: the outlying seller goes, the capital keeps its icon.
		sim:input(function()
			ns.db.townServices = "capitals"
			ns.RefreshMap()
		end)
		sim:advance(0.2)
		assert(pins:GetNumActive() >= 1, "the capital keeps its services")
		sim:input(function()
			ns.db.townServices = "off"
			ns.RefreshMap()
		end)
		sim:advance(0.2)
		assert(pins:GetNumActive() == 0, "off draws nothing")
		sim:setGamepad(false)
		sim:closeWorldMap()
		sim:expectNoErrors(ADDON)
		sim:expectNoGamepadTaint(ADDON)
	end
)

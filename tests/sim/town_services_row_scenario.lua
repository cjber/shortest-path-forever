-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")
-- Ticking a service's row in the Nearby services panel while the layer is off turns the layer on with that service
-- alone, and its pins draw on the open map without another refresh (#1069).
scenario(
	"a Nearby services row turns the town layer on and its pins draw at once",
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
			group("vendors", "arrows", "Arrows", "Ammunition"),
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
			arrows = { place(6, "Arrow Six", -9440, 70) },
		}
		ns.NearbyServices = {
			Request = function() end,
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
		}

		sim:openWorldMap(1429)
		sim:input(function()
			ns.db.townServices = "off"
			ns.RefreshTownServices()
		end)
		sim:advance(0.2)
		local pins = ns.Canvas.Pools(sim.G.WorldMapFrame).ShortestPathForeverServicePinTemplate
		assert(pins:GetNumActive() == 0, "off draws nothing")
		sim:input(function()
			ns.SetTownServiceGroupShown(groups[4], true)
		end)
		sim:advance(0.2)
		assert(ns.db.townServices == "all", "the row turns the layer on")
		assert(pins:GetNumActive() == 1, "the arrow seller's pin draws at once, alone")
		assert(pins.active[1].cluster.services[1].entry.id == 6, "the pin is the arrow seller")
		sim:closeWorldMap()
		sim:expectNoErrors(ADDON)
	end
)

-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")
-- Nearby services quick map button (#1342): sits on the world map without touching Blizzard's map tables, left-click
-- toggles the Nearby services panel, right-click opens ForeverCore.ContextMenu with one checkbox per service kind
-- bound to the same settings the panel uses, and survives combat and the gamepad interface with zero taint.
scenario(
	"Nearby services map button toggles the panel, filters pins via right-click menu, and stays taint-free",
	{ addons = ForeverCore.addons() },
	function(sim)
		local G = sim.G
		local player = sim.world.player
		player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
		player.map, player.x, player.y = 1429, 0.42, 0.65
		player.worldX, player.worldY, player.instance = -9449, 64, 0
		sim.world.maps[947] = { name = "Azeroth", mapType = 1 }
		sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
		sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
		sim.world.maps[1453] = { name = "Stormwind City", parent = 1415, mapType = 3 }
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

		local function group(section, key, label, tracking)
			return { section = section, key = key, label = label, icon = tracking, tracking = tracking, npcs = {} }
		end
		local groups = {
			group("vendors", "arrows", "Arrows", "Ammunition"),
			group("services", "bank", "Bank", "Banker"),
			group("services", "flight", "Flight master", "FlightMaster"),
		}
		local function place(id, name, x, y)
			return { id = id, name = name, map = 1429, x = 0.5, y = 0.5, world = { map = 0, x = x, y = y } }
		end
		local index = {
			arrows = { place(1, "Arrow One", -9440, 70) },
			bank = { place(2, "Bank Two", -8500, 800) },
			flight = { place(3, "Flight Three", -9400, 60) },
		}
		local nearby = ns.NearbyServices
		nearby.Request = function() end
		nearby.State = function()
			return "ready"
		end
		nearby.Index = function()
			return index
		end
		nearby.Groups = function()
			return groups
		end
		nearby.OnReady = function() end
		nearby.Sections = function()
			return {
				{
					section = "vendors",
					label = "Vendors",
					count = 1,
					collapsed = false,
					rows = { { id = "arrows", group = groups[1], npc = index.arrows[1] } },
				},
			}
		end
		nearby.Shortlist = function(key)
			return index[key] or {}
		end

		sim:openWorldMap(1429)
		sim:advance(0.2)
		local button = assert(ns.nearbyMapButton, "map button exists")
		assert(button:IsShown(), "map button is visible by default")
		assert(G.C_Texture.GetAtlasInfo("common-button-square-gray-up"), "up atlas exists in client")
		assert(G.C_Texture.GetAtlasInfo("common-button-square-gray-down"), "down atlas exists in client")
		assert(G.C_Texture.GetAtlasInfo("Banker"), "Banker icon atlas exists in client")

		-- Hover shows and hides tooltip cleanly.
		sim:hover(button)
		sim:advance(0.1)
		sim:leave()

		-- Left-click opens and toggles the Nearby services panel.
		sim:input(function()
			button:GetScript("OnClick")(button, "LeftButton")
		end)
		sim:advance(0.1)
		assert(G.ForeverCore.QuestLogTabs.Selected() == "services", "left-click selects Nearby services panel")
		sim:input(function()
			button:GetScript("OnClick")(button, "LeftButton")
		end)
		sim:advance(0.1)
		assert(G.ForeverCore.QuestLogTabs.Selected() == nil, "second left-click toggles panel back to quests")

		-- Right-click opens ForeverCore.ContextMenu and ticking Arrows turns town services on with its pin.
		sim:input(function()
			ns.db.townServices = "off"
			ns.RefreshTownServices()
		end)
		sim:advance(0.1)
		local pins = ns.Canvas.Pools(G.WorldMapFrame).ShortestPathForeverServicePinTemplate
		assert(pins:GetNumActive() == 0, "no service pins while layer is off")
		sim:input(function()
			button:GetScript("OnClick")(button, "RightButton")
		end)
		sim:advance(0.1)
		local popup = assert(G.ForeverCoreContextMenu, "ForeverCore context menu opened")
		assert(popup:IsShown(), "context menu popup is visible")
		local arrowRow
		for _, row in ipairs(popup.rows) do
			if row:IsShown() and row:GetText() == "Arrows" then
				arrowRow = row
				break
			end
		end
		assert(arrowRow, "Arrows checkbox row is shown in context menu")
		sim:input(function()
			arrowRow:GetScript("OnClick")(arrowRow)
		end)
		sim:advance(0.2)
		assert(ns.db.townServices == "all", "ticking Arrows from button menu turns town services on")
		assert(pins:GetNumActive() == 1, "Arrows service pin draws on the open map")

		-- Setting hides and restores the button.
		sim:input(function()
			ns.SetOption("nearbyMapButton", false)
		end)
		assert(not button:IsShown(), "turning off nearbyMapButton hides the button")
		sim:input(function()
			ns.SetOption("nearbyMapButton", true)
		end)
		assert(button:IsShown(), "turning on nearbyMapButton restores the button")

		-- Combat and gamepad interface stay clean and taint-free.
		sim:enterCombat()
		sim:advance(0.2)
		sim:leaveCombat()
		sim:advance(0.2)
		sim:setGamepad(true)
		sim:gamepadNavigate()
		sim:input(function()
			button:GetScript("OnClick")(button, "LeftButton")
			button:GetScript("OnClick")(button, "RightButton")
		end)
		sim:advance(0.1)
		assert(G.ForeverCore.QuestLogTabs.Selected() == nil, "gamepad left-click does not switch tabs")
		assert(not popup:IsShown(), "gamepad right-click does not open context menu")
		sim:setGamepad(false)
		sim:closeWorldMap()
		sim:expectNoErrors(ADDON)
		sim:expectNoGamepadTaint(ADDON)
	end
)

-- luacheck: read globals scenario ADDON
-- The world map's filter menu (MENU_WORLD_MAP_TRACKING) carries two of our modifiers: the map filters (UI/Map.lua)
-- and the Nearby services submenu (UI/Nearby.lua, also on MENU_MINIMAP_TRACKING). #161 reports a client assertion
-- (ldebug.c:747) on opening it. This opens the real menu again and again, in and out of combat, with the mouse and
-- the gamepad interface, and checks that every entry the menu holds is well formed: text that is a plain string,
-- selection getters that answer a boolean, filters that toggle and toggle back, and a Nearby service that starts
-- its journey and closes the menu. The ldebug.c assertion itself is a client check the simulator cannot raise.

local FILTERS = {
	{ key = "mapFlightMasters", label = "Flight Masters" },
	{ key = "mapRoutes", label = "Boat and Zeppelin Routes" },
	{ key = "pins", label = "Boats & Zeppelins" },
	{ key = "transit", label = "Lifts & Tram" },
	{ key = "portals", label = "Portals" },
	{ key = "otherFaction", label = "Other Faction's Routes" },
}

-- A QuestieDB with three Elwynn services, enough for the Nearby submenu to list real buttons.
local function FakeQuestieDB()
	local npcs = {
		[1] = { "Innkeeper Farley", nil, { [12] = { { 43.7, 65.8 } } }, "AH", 128 },
		[2] = { "Ariena Stormfeather", nil, { [12] = { { 41.0, 64.0 } } }, "A", 8 },
		[3] = { "Brother Wilhelm", "Paladin Trainer", { [12] = { { 41.1, 66.0 } } }, "A", 16 },
	}
	return {
		RequireContract = function()
			return true
		end,
		Enum = {
			byExpansion = {
				Classic = {
					npcFlags = {
						VENDOR = 4,
						TRAINER = 16,
						REPAIR = 16384,
						INNKEEPER = 128,
						BANKER = 256,
						AUCTIONEER = 4096,
						FLIGHT_MASTER = 8,
						STABLEMASTER = 8192,
					},
				},
			},
		},
		Support = {
			Get = function()
				return { private = { areaIdToUiMapId = "return {[12]=1429}", subZoneToParentZone = "return {}" } }
			end,
		},
		Npc = {
			GetAllIds = function()
				return { 1, 2, 3 }
			end,
			GetAll = function(id, fields)
				local row = npcs[id]
				if not row then
					return nil
				end
				local at = { name = 1, subName = 2, spawns = 3, friendlyToFaction = 4, npcFlags = 5 }
				local values = {}
				for _, field in ipairs(fields) do
					values[#values + 1] = row[at[field]]
				end
				values.n = #values
				return values
			end,
		},
	}
end

-- A logged-in Elwynn Forest client with QuestieDB's services indexed. Answers the addon's namespace.
local function Login(sim, saved)
	local G = sim.G
	local player = sim.world.player
	player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
	player.map, player.x, player.y = 1429, 0.42, 0.65
	player.worldX, player.worldY, player.instance = -9449, 64, 0
	sim.world.maps[947] = { name = "Azeroth", mapType = 1 }
	sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
	sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
	-- The client's SetToDefaults clears a region's anchors, which Blizzard_Menu's texture pool relies on; the
	-- simulator's keeps them, so a reused checkbox texture reports a false anchor loop (cjber/forever-core#100).
	for _, methods in pairs(sim.widgets.methods) do
		local setToDefaults = methods.SetToDefaults
		if setToDefaults and methods.ClearAllPoints then
			methods.SetToDefaults = function(region)
				region:ClearAllPoints()
				return setToDefaults(region)
			end
		end
	end
	G.LibQuestieDB = FakeQuestieDB()
	-- QuestieDB's zone tables are Lua source that Nearby loads in an empty environment. The simulator's loadstring
	-- instruments the chunk with a global marker that environment lacks (cjber/forever-core#99), so load these
	-- data chunks plainly, as the client does.
	local addonLoadstring = G.loadstring
	G.loadstring = function(code, name)
		if type(code) == "string" and code:match("^return {") then
			return loadstring(code, name)
		end
		return addonLoadstring(code, name)
	end
	sim:login({ savedVariables = saved })
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns, "full addon namespace loaded")
	-- The services index builds a slice per frame, out of combat.
	sim:advance(1)
	assert(ns.NearbyServices.State() == "ready", "the services index is ready: " .. tostring(ns.NearbyServices.State()))
	return ns
end

-- Every element of a menu description, depth first, with its parent's path.
local function Walk(G, description, path, out)
	out = out or {}
	for _, element in description:EnumerateElementDescriptions() do
		local text = G.MenuUtil.GetElementText(element)
		out[#out + 1] = { element = element, text = text, path = path or "" }
		Walk(G, element, (path or "") .. "/" .. tostring(text), out)
	end
	return out
end

-- How many top-level entries carry this text.
local function Count(entries, text)
	local count = 0
	for _, entry in ipairs(entries) do
		if entry.text == text and entry.path == "" then
			count = count + 1
		end
	end
	return count
end

scenario(
	"the world map filter menu opens cleanly with both modifiers, mouse and gamepad, in and out of combat",
	function(sim)
		local G = sim.G
		local ns = Login(sim)

		local navigations = 0
		local api = G.ShortestPathForever.API
		local navigate = api.NavigateRoute
		api.NavigateRoute = function(...)
			navigations = navigations + 1
			return navigate(...)
		end

		local function Readable(value)
			return not (G.issecretvalue and G.issecretvalue(value))
		end

		local function Find(entries, text, path)
			for _, entry in ipairs(entries) do
				if entry.text == text and (not path or entry.path == path) then
					return entry
				end
			end
		end

		local opens = 0
		local function OpenFilterMenu(how)
			local button = G.WorldMapFrame.WorldMapTrackingOptionsButton
			assert(button and button:IsShown(), "the filter button shows on the open map")
			assert(not button:IsMenuOpen(), how .. ": the filter menu starts closed")
			sim:input(function()
				button:OpenMenu()
			end)
			sim:advance(0.1)
			assert(button:IsMenuOpen(), how .. ": the filter menu opens")
			opens = opens + 1
			local description = button.menuDescription
			assert(description, how .. ": the open menu has a description")
			local entries = Walk(G, description)
			for _, entry in ipairs(entries) do
				local where = how .. ": " .. entry.path .. "/" .. tostring(entry.text)
				assert(
					entry.text == nil or (type(entry.text) == "string" and Readable(entry.text)),
					where .. " has plain text"
				)
				assert(entry.text ~= "", where .. " has no empty label")
				local ok, selected = pcall(entry.element.IsSelected, entry.element)
				assert(ok, where .. " answers IsSelected: " .. tostring(selected))
				assert(
					selected == nil or type(selected) == "boolean",
					where .. " is selected or not, never " .. type(selected)
				)
			end

			-- Our filters: each once, after the game's own, and each pick toggles its option and back.
			for _, filter in ipairs(FILTERS) do
				local label = ns.L[filter.label]
				local count = Count(entries, label)
				assert(count == 1, how .. ": " .. label .. " appears once, not " .. count .. " times")
				local entry = Find(entries, label, "")
				local before = ns.db[filter.key]
				assert(
					entry.element:IsSelected() == (before and true or false),
					how .. ": " .. label .. " shows its setting"
				)
				sim:input(function()
					entry.element:Pick(G.MenuInputContext.MouseButton, "LeftButton")
				end)
				assert(ns.db[filter.key] == not before, how .. ": " .. label .. " toggles its setting")
				sim:input(function()
					entry.element:Pick(G.MenuInputContext.MouseButton, "LeftButton")
				end)
				assert(ns.db[filter.key] == before, how .. ": " .. label .. " toggles back")
			end

			-- The Nearby services submenu: once, with a button per service that is here and a title for none.
			local nearby = ns.L["Nearby services"]
			local count = Count(entries, nearby)
			assert(count == 1, how .. ": Nearby services appears once, not " .. count .. " times")
			local inn = Find(entries, ns.L["Innkeeper"], "/" .. nearby)
			assert(inn, how .. ": the innkeeper is listed under Nearby services")
			return entries
		end

		local function CloseMenus()
			local button = G.WorldMapFrame.WorldMapTrackingOptionsButton
			sim:input(function()
				button:CloseMenu()
			end)
			sim:advance(0.1)
			assert(not button:IsMenuOpen(), "the filter menu closes")
		end

		local function Round(how)
			sim:openWorldMap(1429)
			for _ = 1, 3 do
				OpenFilterMenu(how)
				CloseMenus()
			end
			sim:closeWorldMap()
			sim:advance(0.1)
		end

		Round("mouse")
		sim:enterCombat()
		Round("mouse, in combat")
		sim:leaveCombat()
		sim:advance(0.5)
		Round("mouse, after combat")

		-- A Nearby service picked from the filter menu hands the place to the journey and closes the menu. The
		-- Forever client's MenuUtil has no CloseAllMenus, which the service buttons used to call after starting it.
		sim:openWorldMap(1429)
		local entries = OpenFilterMenu("picking a service")
		local inn = Find(entries, ns.L["Innkeeper"], "/" .. ns.L["Nearby services"])
		-- As the player does: open the submenu, then click the service in it.
		sim:input(function()
			Find(entries, ns.L["Nearby services"], "").element:ForceOpenSubmenu()
		end)
		sim:advance(0.1)
		sim:input(function()
			inn.element:Pick(G.MenuInputContext.MouseButton, "LeftButton")
		end)
		sim:advance(0.1)
		sim:expectNoErrors(ADDON)
		assert(navigations == 1, "the innkeeper button navigates once, not " .. navigations .. " times")
		assert(not G.WorldMapFrame.WorldMapTrackingOptionsButton:IsMenuOpen(), "picking a service closes the menu")
		sim:closeWorldMap()

		assert(opens == 10, "opened the filter menu 10 times, not " .. opens)
		sim:expectNoErrors(ADDON)
	end
)

-- A fresh client for the gamepad: the game's menus stay the game's, because an addon modifier on the menu's show
-- path taints the focus write and the gamepad action bar's protected interact call (#158, #581).
scenario("the world map filter menu stays the game's under the gamepad", function(sim)
	local G = sim.G
	local ns = Login(sim)
	sim:setGamepad(true)
	sim:openWorldMap(1429)
	local button = G.WorldMapFrame.WorldMapTrackingOptionsButton
	for _ = 1, 3 do
		sim:input(function()
			button:OpenMenu()
		end)
		sim:advance(0.1)
		assert(button:IsMenuOpen(), "the filter menu opens")
		local entries = Walk(G, button.menuDescription)
		assert(Count(entries, ns.L["Flight Masters"]) == 0, "no addon map filters on the gamepad")
		assert(Count(entries, ns.L["Nearby services"]) == 0, "no Nearby services on the gamepad")
		sim:input(function()
			button:CloseMenu()
		end)
		sim:advance(0.1)
		assert(not button:IsMenuOpen(), "the filter menu closes")
	end
	sim:gamepadNavigate()
	sim:closeWorldMap()
	sim:advance(0.2)
	sim:expectNoErrors(ADDON)
end)

-- `/path menutest` leaves one of our two modifiers out of the world map filter menu from the next /reload, so the
-- owner can A/B #161 in game without editing files. Each value is a fresh client logged in with it saved.
for _, case in ipairs({
	{ value = "map", filters = false, nearby = true },
	{ value = "nearby", filters = true, nearby = false },
	{ value = "both", filters = false, nearby = false },
}) do
	scenario("/path menutest " .. case.value .. " leaves its modifiers out of the filter menu", function(sim)
		local G = sim.G
		local ns = Login(sim, { ShortestPathForeverDB = { menuTest = case.value } })
		sim:openWorldMap(1429)
		local button = G.WorldMapFrame.WorldMapTrackingOptionsButton
		sim:input(function()
			button:OpenMenu()
		end)
		sim:advance(0.1)
		local entries = Walk(G, button.menuDescription)
		local filters = Count(entries, ns.L["Flight Masters"])
		local nearby = Count(entries, ns.L["Nearby services"])
		assert(filters == (case.filters and 1 or 0), case.value .. ": map filters listed " .. filters .. " times")
		assert(nearby == (case.nearby and 1 or 0), case.value .. ": Nearby services listed " .. nearby .. " times")
		sim:input(function()
			button:CloseMenu()
		end)
		sim:closeWorldMap()

		-- The command itself: back to off, which a /reload would apply; an unknown value changes nothing.
		sim:input(function()
			G.SlashCmdList.SHORTESTPATHFOREVER("menutest off")
		end)
		assert(ns.db.menuTest == nil, "menutest off clears the test")
		sim:input(function()
			G.SlashCmdList.SHORTESTPATHFOREVER("menutest everything")
		end)
		assert(ns.db.menuTest == nil, "an unknown value changes nothing")
		sim:expectNoErrors(ADDON)
	end)
end

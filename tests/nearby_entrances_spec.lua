-- Dungeons and raids in the Nearby services list (#688): a row per instance door on the player's continent, the
-- other continent's left out, the panel's travel times ordering the doors once they land and the straight line
-- before then, and the door stop JourneyInput.lua builds when one is picked, in the panel's sections and the
-- tracking menu.
local timers, trackingMenus, journeys = {}, {}, {}
-- Where Core.Locate puts a door: the fixture's zone map at the door's own fractions, in the zone its x names.
local DOOR_ZONES = { [800] = "Westfall", [200] = "The Barrens", [100] = "Silverpine Forest" }
-- Instance doors (Data/Portals.lua ns.Entrances): two on the player's continent and one on the other.
local ENTRANCES = {
	[36] = { name = "Deadmines", map = 1, x = 800, y = 800 },
	[43] = { name = "Wailing Caverns", map = 1, x = 200, y = 900 },
	[33] = { name = "Shadowfang Keep", map = 2, x = 100, y = 100 },
}

-- A menu node, as Blizzard_Menu hands one to a modifier: titles, buttons with callbacks, and a scroll extent.
local function node(text)
	local n = { text = text, children = {} }
	function n:CreateButton(childText, callback)
		local child = node(childText)
		child.callback = callback
		self.children[#self.children + 1] = child
		return child
	end
	function n:CreateTitle(title)
		self.children[#self.children + 1] = { text = title, title = true }
	end
	function n:SetEnabled(enabled)
		self.enabled = enabled
	end
	function n:SetScrollMode(extent)
		self.scrollExtent = extent
	end
	function n:SetTooltip(fn)
		self.tooltip = fn
	end
	return n
end

-- A QuestieDB with nothing in it: this fixture's places are the instance doors, which need no NPC rows.
local function QuestieDB()
	return {
		RequireContract = function(version)
			return version == 2
		end,
		Enum = { byExpansion = { Classic = { npcFlags = {} } } },
		Support = {
			Get = function(name)
				assert(name == "ZoneDB", "the zone tables are the support module this file reads")
				return { private = { areaIdToUiMapId = "return {[10]=100}", subZoneToParentZone = "return {}" } }
			end,
		},
		Npc = {
			GetAllIds = function()
				return {}
			end,
			GetAll = function()
				error("this fixture has no NPCs")
			end,
		},
		Item = {
			GetAllIds = function()
				return {}
			end,
			GetAll = function()
				error("this fixture has no items")
			end,
		},
	}
end

local env = setmetatable({
	LibQuestieDB = QuestieDB(),
	CreateFrame = function()
		return { RegisterEvent = function() end, SetScript = function() end }
	end,
	Menu = {
		ModifyMenu = function(tag, callback)
			trackingMenus[tag] = callback
		end,
	},
	MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 },
	UnitFactionGroup = function()
		return "Alliance"
	end,
	-- The client's name for an instance map; the empty answer falls back to the data's name.
	GetRealZoneText = function(instance)
		return instance == 36 and "The Deadmines" or ""
	end,
	C_Map = {
		GetBestMapForUnit = function()
			return 100
		end,
		GetPlayerMapPosition = function()
			return {
				GetXY = function()
					return 0.1, 0.1
				end,
			}
		end,
	},
	C_Timer = {
		After = function(_, fn)
			timers[#timers + 1] = fn
		end,
	},
	debugprofilestop = function()
		return 0
	end,
	InCombatLockdown = function()
		return false
	end,
	geterrorhandler = function()
		return error
	end,
	SlashCmdList = {},
	-- The client's own event queue: the read begins once everything has loaded, which is already true here.
	EventUtil = {
		ContinueAfterAllEvents = function(fn)
			fn()
		end,
	},
}, { __index = _G })
env._G = env
local ForeverCore = dofile("tests/forever_core.lua")
local coreNs = ForeverCore.load(env, "ForeverCore", { "Locales/enUS.lua", "Core/Text.lua" })
env.ForeverCore = { Text = coreNs.Text }

-- A logged-in client over the fixture entrances, read to the end. Returns its namespace.
local function load()
	timers, trackingMenus, journeys = {}, {}, {}
	local initializers = {}
	local ns = {
		Init = function(fn)
			initializers[#initializers + 1] = fn
		end,
		WorldPoint = function(_, x, y)
			return { map = 1, x = x * 1000, y = y * 1000 }
		end,
		Entrances = ENTRANCES,
		Path = {
			Busy = function()
				return false
			end,
		},
		-- Where Core.Locate puts a door: the fixture's zone map at the door's own fractions, in the zone its x names.
		Locate = function(point)
			return { uiMap = 100, x = point.x / 1000, y = point.y / 1000, zone = DOOR_ZONES[point.x] }
		end,
		-- The door stop JourneyInput.lua builds for the instance, as a Nearby services row journeys to it.
		EntranceStop = function(instance, point)
			local door = ENTRANCES[instance]
			return {
				map = 100,
				x = door.x / 1000,
				y = door.y / 1000,
				label = "Enter " .. instance,
				entrance = instance,
				stop = point,
			}
		end,
		StartJourney = function(point)
			journeys[#journeys + 1] = point
			return true
		end,
		db = {},
		GamepadUI = function()
			return false
		end,
		core = {
			SafeCall = function(_, fn, ...)
				return true, fn(...)
			end,
		},
	}
	setfenv(assert(loadfile("Locales/enUS.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("Data/Services.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/MenuModifier.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyQuestie.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyEntrances.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/Nearby.lua")), env)("ShortestPathForever", ns)
	for _, fn in ipairs(initializers) do
		fn()
	end
	while #timers > 0 do
		table.remove(timers, 1)()
	end
	assert(ns.NearbyServices.State() == "ready", "the fixture reads")
	return ns
end

-- The panel's sections: the doors on this continent, nearest first, then by the panel's travel times once they land
-- and by the straight line for the doors without one.
local ns = load()
local here = { map = 1, x = 100, y = 100 }
local function sections(query, collapse, seconds)
	return ns.NearbyServices.Sections(here, query, collapse, seconds)
end
local function sectionOf(list, key)
	for _, section in ipairs(list) do
		if section.section == key then
			return section
		end
	end
end
local function rowLabels(section)
	local labels = {}
	for _, row in ipairs(section.rows) do
		labels[#labels + 1] = row.group.label
	end
	return table.concat(labels, ",")
end
local all = sections("")
local raids = assert(sectionOf(all, "entrances"), "the doors are a section of their own")
assert(raids.count == 2, "both doors on this continent are listed, and the other continent's is not")
assert(rowLabels(raids) == "Wailing Caverns,The Deadmines", "the nearest door leads before any travel time is known")
local timed = sections("", nil, { ["entrance:36"] = 10, ["entrance:43"] = 20 })
assert(
	rowLabels(sectionOf(timed, "entrances")) == "The Deadmines,Wailing Caverns",
	"the panel's travel times order the doors"
)
local partial = sections("", nil, { ["entrance:36"] = 10 })
assert(
	rowLabels(sectionOf(partial, "entrances")) == "The Deadmines,Wailing Caverns",
	"a door with a travel time leads, then the doors without one by straight line"
)
local orderRows = {
	{ id = "entrance:far", npc = { world = { map = 1, x = 100, y = 400 } } },
	{ id = "entrance:near", npc = { world = { map = 1, x = 100, y = 200 } } },
	{ id = "entrance:timed", npc = { world = { map = 1, x = 100, y = 900 } } },
}
ns.NearbyEntrances.Order("entrances", orderRows, here, { ["entrance:timed"] = 5 })
local order = {}
for _, row in ipairs(orderRows) do
	order[#order + 1] = row.id
end
assert(
	table.concat(order, ",") == "entrance:timed,entrance:near,entrance:far",
	"one travel time leads, and the rest stay in straight-line order"
)

-- A door is a place like any other: the client names the instance, the data names it when the client does not, the
-- row's detail is the zone under it, and a search by instance name keeps its door.
local places = ns.NearbyServices.Index()
local deadmines = assert((places["entrance:36"] or {})[1], "the door is a place like any other")
assert(deadmines.name == "The Deadmines", "the client's name for the instance map")
assert((places["entrance:43"] or {})[1].name == "Wailing Caverns", "the data's name when the client has none")
assert(
	ns.NearbyServices.Detail("entrance:36", deadmines, "") == "Westfall",
	"the row names the zone under the instance"
)
local byInstance = sections("deadmines")
assert(#byInstance == 1 and rowLabels(byInstance[1]) == "The Deadmines", "a search by instance name keeps its door")

-- A dungeon row in the tracking menu starts the door stop the map's own instance journey gets, and the other
-- continent's door is left out, never shown unavailable.
local function entry(entries, text)
	for _, item in ipairs(entries) do
		if item.text == text then
			return item
		end
	end
end
local menu = node("menu")
trackingMenus.MENU_MINIMAP_TRACKING(nil, menu)
local submenu = assert(entry(menu.children, "Nearby services"), "the tracking menu carries the Nearby services submenu")
local dungeon =
	assert(entry(submenu.children, "The Deadmines"), "a dungeon row is listed by the client's instance name")
assert(not entry(submenu.children, "Shadowfang Keep"), "a door on another continent is left out, never unavailable")
assert(dungeon.callback() == env.MenuResponse.CloseAll, "a dungeon row starts a journey and closes the menu")
local door = journeys[#journeys]
assert(door and door.entrance == 36, "a dungeon row starts a journey whose stop carries the instance")
assert(door.label == "Enter 36", "through the door stop of JourneyInput.lua")
print("nearby_entrances: instance doors, their order in the panel and their journey: ok")

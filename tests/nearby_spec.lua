local function noop() end
local timers, initializers, frames, navigated = {}, {}, {}, {}
local clock, busy, combat = 0, false, false
local function region()
	return {
		SetText = function(self, t)
			self.text = t
		end,
	}
end
local function frame(_, name, parent, template)
	local f = { name = name, parent = parent, template = template, scripts = {}, shown = false }
	function f:SetScript(event, fn)
		self.scripts[event] = fn
	end
	function f:SetPoint(...)
		self.point = { ... }
	end
	function f:Show()
		self.shown = true
	end
	function f:Hide()
		self.shown = false
	end
	function f:IsShown()
		return self.shown
	end
	function f:SetText(text)
		self.text = text
	end
	function f:SetEnabled(enabled)
		self.enabled = enabled
	end
	function f:SetPropagateKeyboardInput(v)
		self.propagate = v
	end
	function f:SetScrollChild(child)
		self.child = child
	end
	f.SetSize, f.SetFrameStrata, f.SetClampedToScreen, f.EnableKeyboard, f.SetWidth, f.SetHeight, f.SetVerticalScroll =
		noop, noop, noop, noop, noop, noop, noop
	if template == "BasicFrameTemplateWithInset" then
		f.TitleText = region()
	end
	frames[#frames + 1] = f
	return f
end
local data = {
	[1] = { "Near vendor", "General Goods", { [10] = { { 10, 10 } } }, "A", 4, n = 5 },
	[2] = { "Far vendor", "Reagents", { [10] = { { 80, 80 } } }, "A", 4, n = 5 },
	[3] = { "Horde vendor", "Reagents", { [10] = { { 11, 11 } } }, "H", 4, n = 5 },
	[4] = { "Hostile vendor", "Reagents", { [10] = { { 12, 12 } } }, nil, 4, n = 5 },
	[5] = { "No coordinates", "Reagents", nil, "A", 4, n = 5 },
	[6] = { "Mage trainer", "Mage Trainer", { [10] = { { 30, 30 } } }, "A", 16, n = 5 },
	[7] = { "Warrior trainer", "Warrior Trainer", { [10] = { { 1, 1 } } }, "A", 16, n = 5 },
	[8] = { "Alchemy trainer", "Alchemy Trainer", { [10] = { { 40, 40 } } }, "A", 16, n = 5 },
	[9] = { "Bad position", "Reagents", { [10] = { { -1, -1 }, { 101, 1 } } }, "A", 4, n = 5 },
	[10] = { "Neutral repairs", nil, { [11] = { { 20, 20 } } }, "AH", 16384, n = 5 },
}
local flags = {
	VENDOR = 4,
	TRAINER = 16,
	REPAIR = 16384,
	INNKEEPER = 128,
	BANKER = 256,
	AUCTIONEER = 4096,
	FLIGHT_MASTER = 8,
	STABLEMASTER = 8192,
}
local calls = 0

local menuEntries, closedMenus, releaseMenu, trackingMenus = {}, 0, nil, {}
local mapOpens = 0
local function menuNode()
	local node = {}
	function node.CreateTitle(_self, text)
		menuEntries[#menuEntries + 1] = { text = text, title = true }
	end
	function node.CreateButton(_self, text, callback)
		local entry = { text = text, callback = callback, children = {} }
		function entry.CreateButton(_entry, childText, childCallback)
			local child = { text = childText, callback = childCallback, children = {}, SetEnabled = function() end }
			function child.CreateButton(c, childText2, childCallback2)
				local grandchild = { text = childText2, callback = childCallback2, SetEnabled = function() end }
				c.children[#c.children + 1] = grandchild
				return grandchild
			end
			entry.children[#entry.children + 1] = child
			return child
		end
		function entry.SetEnabled(_entry, enabled)
			entry.enabled = enabled
		end
		function entry.CreateTitle(_entry, titleText)
			entry.children[#entry.children + 1] = { text = titleText, title = true }
		end
		menuEntries[#menuEntries + 1] = entry
		return entry
	end
	return node
end
local lib = {
	RequireContract = function(v)
		assert(v == 2)
		return true
	end,
	Enum = { byExpansion = { Classic = { npcFlags = flags } } },
	Support = {
		Get = function(name)
			assert(name == "ZoneDB")
			return { private = { areaIdToUiMapId = "return {[10]=100}", subZoneToParentZone = "return {[11]=10}" } }
		end,
	},
	Npc = {
		GetAllIds = function(...)
			assert(select("#", ...) == 0, "installed DB APIs use dot calls")
			return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
		end,
		GetAll = function(id, fields)
			assert(type(id) == "number" and #fields == 5, "packed GetAll actual contract")
			calls = calls + 1
			return data[id]
		end,
	},
}
local env = setmetatable({
	LibQuestieDB = lib,
	TweaksForever = {
		API = {
			version = 2,
			Trainers = function()
				return { { npc = 6, map = 100, x = 0.3, y = 0.3 } }
			end,
		},
	},
	CreateFrame = frame,
	Menu = {
		ModifyMenu = function(tag, callback)
			trackingMenus[tag] = callback
		end,
	},
	MenuUtil = {
		CreateContextMenu = function(_, callback)
			menuEntries = {}
			local root = menuNode()
			root.AddMenuReleasedCallback = function(_, callbackFn)
				releaseMenu = callbackFn
			end
			callback(nil, root)
		end,
		CloseAllMenus = function()
			closedMenus = closedMenus + 1
		end,
	},
	UIParent = {},
	UnitFactionGroup = function()
		return "Alliance"
	end,
	C_Map = {
		OpenWorldMap = function(uiMapID)
			assert(uiMapID == nil, "the menu opens the map where the player is")
			mapOpens = mapOpens + 1
		end,
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
		clock = clock + 0.4
		return clock
	end,
	InCombatLockdown = function()
		return combat
	end,
	geterrorhandler = function()
		return function(err)
			error(err)
		end
	end,
	SlashCmdList = {},
	ShortestPathForever = {
		API = {
			Navigate = function(owner, map, x, y, title, kind)
				assert(
					type(owner) == "string" and map == 100 and x >= 0 and x <= 1 and y >= 0 and y <= 1,
					"public API receives UI coordinates"
				)
				navigated[#navigated + 1] = { owner, map, x, y, title, kind }
				return true
			end,
		},
	},
}, { __index = _G })
env._G = env
local ns = {
	Init = function(fn)
		initializers[#initializers + 1] = fn
	end,
	WorldPoint = function(map, x, y)
		assert(map == 100)
		return { map = 1, x = x * 1000, y = y * 1000 }
	end,
	Path = {
		Busy = function()
			return busy
		end,
	},
}
setfenv(assert(loadfile("Locales/enUS.lua")), env)("ShortestPathForever", ns)
setfenv(assert(loadfile("UI/Nearby.lua")), env)("ShortestPathForever", ns)
for _, fn in ipairs(initializers) do
	fn()
end
env.SlashCmdList.SPFNEAR("")
assert(mapOpens == 1, "opening the menu asks the game to open the map")
assert(ns.NearbyServices.State() == "building" and calls == 0, "index does not block click")
local trackingMenu = assert(trackingMenus.MENU_WORLD_MAP_TRACKING, "registers the native world-map tracking dropdown")
local minimapMenu = assert(trackingMenus.MENU_MINIMAP_TRACKING, "registers the native minimap tracking dropdown")
trackingMenu(nil, menuNode())
local loadingEntry
for _, item in ipairs(menuEntries) do
	if item.text == "Nearby services" then
		loadingEntry = item
	end
end
assert(
	loadingEntry and loadingEntry.children and loadingEntry.children[1].text == "Loading QuestieDB…",
	"tracking menu reports loading"
)
env.SlashCmdList.SPFNEAR("")
assert(#menuEntries > 0 and menuEntries[1].title, "nearby opens an addon-owned map menu")
local dismissedMenuCount = #menuEntries
assert(releaseMenu, "native menu release callback is registered")
releaseMenu()
local function pump()
	local fn = table.remove(timers, 1)
	assert(fn)
	fn()
end
busy = true
pump()
assert(calls == 0, "index shares idle budget with path jobs")
busy = false
combat = true
pump()
assert(calls == 0, "combat defers index work")
combat = false
while #timers > 0 do
	pump()
end
assert(ns.NearbyServices.State() == "ready")
assert(#menuEntries == dismissedMenuCount, "dismissed menu does not reopen after async loading")
menuEntries = {}
trackingMenu(nil, menuNode())
local tracking = menuEntries[1]
assert(#tracking.children == 10, "tracking menu exposes all service categories")
tracking.children[3].callback()
assert(navigated[#navigated][5] == "Neutral repairs", "tracking repair action routes nearest")
menuEntries = {}
local opensBefore = mapOpens
minimapMenu(nil, menuNode())
assert(#menuEntries[1].children == 10, "the minimap's tracking menu carries the same services")
menuEntries[1].children[1].callback()
assert(navigated[#navigated][5] == "Mage trainer", "a service chosen from the minimap routes to the nearest")
assert(mapOpens == opensBefore, "the minimap's menu routes without opening the world map")
local places = ns.NearbyServices.Index()
assert(#places.vendor == 2, "hostile,wrong faction,unknown and malformed spawns excluded")
assert(#places.reagents == 1, "reagent title required; general vendor is not labelled reagents")
assert(#places.class == 1 and places.class[1].id == 6, "class subset from companion IDs, not nearest wrong class")
local here = { map = 1, x = 100, y = 100 }
assert(ns.NearbyServices.Nearest("vendor", here).id == 1)
assert(ns.NearbyServices.Nearest("trainer", here, "Alchemy Trainer").id == 8)
assert(ns.NearbyServices.Nearest("vendor", { map = 2, x = 100, y = 100 }) == nil)
assert(places.repair[1].map == 100, "subzone uses parent map")
local function entry(text)
	for _, item in ipairs(menuEntries) do
		if item.text == text then
			return item
		end
	end
	error("no menu entry: " .. text)
end
env.SlashCmdList.SPFNEAR("")
entry("Class trainer").callback()
assert(navigated[#navigated][5] == "Mage trainer", "class action routes nearest class trainer")
env.SlashCmdList.SPFNEAR("")
local trainers = entry("Trainers by specialty")
assert(#trainers.children > 0, "trainer category has specialty submenu")
for _, child in ipairs(trainers.children) do
	if child.text == "Alchemy Trainer" then
		child.callback()
	end
end
assert(navigated[#navigated][5] == "Alchemy trainer", "specialty picker sends actual chosen trainer")
env.SlashCmdList.SPFNEAR("")
entry("Reagents").callback()
assert(navigated[#navigated][5] == "Far vendor", "reagents ignores closer general vendor")
assert(closedMenus > 0, "successful menu actions close the map menu")
local before = calls
local beforeMenus = #menuEntries
for _ = 1, 20 do
	env.SlashCmdList.SPFNEAR("")
end
assert(#menuEntries == beforeMenus, "menu rebuilds without creating frames")
assert(calls == before, "opening does not rebuild DB")
env.SlashCmdList.SPFNEAR("repair")
assert(navigated[#navigated][5] == "Neutral repairs")

-- A fresh copy of the menu over another QuestieDB, read to the end, then opened here or on another continent.
local function fresh(questie, away)
	local elsewhere = false
	env.LibQuestieDB = questie
	local starts = {}
	local copy = {
		L = ns.L,
		Path = ns.Path,
		Init = function(fn)
			starts[#starts + 1] = fn
		end,
		WorldPoint = function(_, x, y)
			return { map = elsewhere and 2 or 1, x = x * 1000, y = y * 1000 }
		end,
	}
	setfenv(assert(loadfile("UI/Nearby.lua")), env)("ShortestPathForever", copy)
	for _, fn in ipairs(starts) do
		fn()
	end
	while #timers > 0 do
		pump()
	end
	elsewhere = away
	env.SlashCmdList.SPFNEAR("")
	return copy
end
-- A zone QuestieDB has nothing for: every service, the two with specialties too, reads as unavailable here.
assert(fresh(lib, true).NearbyServices.State() == "ready" and #menuEntries == 11)
for position = 2, #menuEntries do
	local item = menuEntries[position]
	assert(item.text:find("unavailable here", 1, true) and item.enabled == false and #item.children == 0, item.text)
end
-- No QuestieDB, and one whose zone tables do not read, each say so in a line of their own.
assert(fresh(nil).NearbyServices.State() == "missing")
assert(#menuEntries == 2 and menuEntries[2].text == "Nearby services need the QuestieDB addon.")
local broken = setmetatable({}, { __index = lib })
for _, private in ipairs({
	{ areaIdToUiMapId = { [10] = 100 }, subZoneToParentZone = "return {[11]=10}" },
	{ areaIdToUiMapId = "return {[10]=100}", subZoneToParentZone = "return {" },
	{ areaIdToUiMapId = "error('gone')", subZoneToParentZone = "return {[11]=10}" },
}) do
	broken.Support = {
		Get = function()
			return { private = private }
		end,
	}
	assert(fresh(broken).NearbyServices.State() == "failed")
	assert(#menuEntries == 2 and menuEntries[2].text == "Nearby services could not read QuestieDB.")
end
env.LibQuestieDB = lib
print(
	"nearby: installed QuestieDB contract, sliced loading, faction/class/specialty, "
		.. "real map-menu callbacks and UI-coordinate dispatch: ok"
)

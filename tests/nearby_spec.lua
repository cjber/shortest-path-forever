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
	UIParent = {},
	UnitFactionGroup = function()
		return "Alliance"
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
setfenv(assert(loadfile("Nearby.lua")), env)("ShortestPathForever", ns)
for _, fn in ipairs(initializers) do
	fn()
end
ns.OpenNearby()
assert(ns.NearbyServices.State() == "building" and calls == 0, "index does not block click")
local panel
for _, f in ipairs(frames) do
	if f.name == "ShortestPathForeverNearby" then
		panel = f
	end
end
assert(panel and panel.shown and panel.point[1] == "CENTER")
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
local places = ns.NearbyServices.Index()
assert(#places.vendor == 2, "hostile,wrong faction,unknown and malformed spawns excluded")
assert(#places.reagents == 1, "reagent title required; general vendor is not labelled reagents")
assert(#places.class == 1 and places.class[1].id == 6, "class subset from companion IDs, not nearest wrong class")
local here = { map = 1, x = 100, y = 100 }
assert(ns.NearbyServices.Nearest("vendor", here).id == 1)
assert(ns.NearbyServices.Nearest("trainer", here, "Alchemy Trainer").id == 8)
assert(ns.NearbyServices.Nearest("vendor", { map = 2, x = 100, y = 100 }) == nil)
assert(places.repair[1].map == 100, "subzone uses parent map")
local function row(text)
	for _, f in ipairs(frames) do
		if f.shown and f.text == text then
			return f
		end
	end
	error("no visible row: " .. text)
end
row("Class trainer").scripts.OnClick()
assert(navigated[#navigated][5] == "Mage trainer" and not panel.shown)
ns.OpenNearby()
row("Trainers by specialty").scripts.OnClick()
row("Alchemy Trainer").scripts.OnClick()
assert(navigated[#navigated][5] == "Alchemy trainer", "specialty picker sends actual chosen trainer")
ns.OpenNearby()
row("Reagents").scripts.OnClick()
assert(navigated[#navigated][5] == "Far vendor", "reagents ignores closer general vendor")
local before = calls
for _ = 1, 20 do
	ns.OpenNearby()
end
assert(calls == before, "opening does not rebuild DB")
local count = #frames
ns.OpenNearby()
assert(#frames == count, "panel reuses rows")
panel.scripts.OnKeyDown(panel, "A")
assert(panel.propagate)
panel.scripts.OnKeyDown(panel, "ESCAPE")
assert(not panel.shown and not panel.propagate)
env.SlashCmdList.SPFNEAR("repair")
assert(navigated[#navigated][5] == "Neutral repairs")
print(
	"nearby: installed QuestieDB contract, sliced loading, faction/class/specialty, "
		.. "real panel callbacks and UI-coordinate dispatch: ok"
)

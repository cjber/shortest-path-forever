-- Battlemasters, portal trainers and the player's own class trainers in Nearby services (#688): each NPC is grouped
-- by the role the shipped classic-db data names for it, never by its title; the other side's NPCs are left out; a
-- portal trainer is offered to mages only; and each row's journey carries the stop kind its nameplate arrows read.
local timers, navigated = {}, {}
local FLAGS = { VENDOR = 4, TRAINER = 16 }

-- QuestieDB's side is the only faction filter: the battlemaster and portal trainer on the other side are in the
-- database and dropped here, as every other service is.
local NPCS = {
	[1001] = { "Alliance battlemaster", "A", 0, "Warsong Gulch Battlemaster", { [10] = { { 20, 20 } } } },
	[1002] = { "Horde battlemaster", "H", 0, "Arathi Basin Battlemaster", { [10] = { { 30, 30 } } } },
	[1003] = { "Mage trainer", "A", FLAGS.TRAINER, "Mage Trainer", { [10] = { { 40, 40 } } } },
	[1004] = { "Warrior trainer", "A", FLAGS.TRAINER, "Warrior Trainer", { [10] = { { 50, 50 } } } },
	[1005] = { "Portal trainer", "A", FLAGS.TRAINER, "Portal Trainer", { [10] = { { 60, 60 } } } },
	[1006] = { "Horde portal trainer", "H", FLAGS.TRAINER, "Portal Trainer", { [10] = { { 70, 70 } } } },
}

local function QuestieDB()
	return {
		RequireContract = function(version)
			return version == 2
		end,
		Enum = { byExpansion = { Classic = { npcFlags = FLAGS } } },
		Support = {
			Get = function(name)
				assert(name == "ZoneDB", "the zone tables are the support module this file reads")
				return { private = { areaIdToUiMapId = "return {[10]=100}", subZoneToParentZone = "return {}" } }
			end,
		},
		Npc = {
			GetAllIds = function()
				return { 1001, 1002, 1003, 1004, 1005, 1006 }
			end,
			GetAll = function(id, fields)
				local row = NPCS[id]
				if not row then
					return nil
				end
				if #fields == 1 then
					assert(fields[1] == "spawns", "an NPC's spawns are read on their own, once it is kept")
					return { row[5], n = 1 }
				end
				assert(#fields == 4, "an NPC's name, side, flags and title are read together")
				return { row[1], row[2], row[3], row[4], n = 4 }
			end,
		},
		Item = {
			GetAllIds = function()
				return {}
			end,
			GetAll = function()
				error("this fixture sells nothing")
			end,
		},
	}
end

local env = setmetatable({
	LibQuestieDB = QuestieDB(),
	CreateFrame = function()
		return { RegisterEvent = function() end, SetScript = function() end }
	end,
	Menu = { ModifyMenu = function() end },
	MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 },
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
		return 0
	end,
	InCombatLockdown = function()
		return false
	end,
	geterrorhandler = function()
		return error
	end,
	SlashCmdList = {},
	EventUtil = {
		ContinueAfterAllEvents = function(fn)
			fn()
		end,
	},
	ShortestPathForever = {
		API = {
			NavigateRoute = function(_, stops)
				navigated[#navigated + 1] = stops[1]
				return true
			end,
		},
	},
}, { __index = _G })
env._G = env
local ForeverCore = dofile("tests/forever_core.lua")
local coreNs = ForeverCore.load(env, "ForeverCore", { "Locales/enUS.lua", "Core/Text.lua" })
env.ForeverCore = { Text = coreNs.Text }

-- A logged-in client of one class, read to the end. Returns its namespace.
local function load(classID)
	timers, navigated = {}, {}
	local initializers = {}
	local ns = {
		Init = function(fn)
			initializers[#initializers + 1] = fn
		end,
		WorldPoint = function(_, x, y)
			return { map = 1, x = x * 1000, y = y * 1000 }
		end,
		Path = {
			Busy = function()
				return false
			end,
		},
		db = {},
		core = {
			SafeCall = function(_, fn, ...)
				return true, fn(...)
			end,
		},
		GamepadUI = function()
			return false
		end,
		Print = function() end,
		OpenWorldMap = function()
			return true
		end,
		-- The roles classic-db names, as Data/Services.lua ships them: two mage trainers are portal trainers, and
		-- the battlemasters on either side.
		ClassTrainers = { [1003] = 8, [1004] = 1 },
		ProfessionTrainers = {},
		PortalTrainers = { [1005] = 8, [1006] = 8 },
		Battlemasters = { [1001] = 1, [1002] = 3 },
	}
	env.UnitClass = function()
		return "Warrior", "WARRIOR", classID
	end
	setfenv(assert(loadfile("Locales/enUS.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/MenuModifier.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyGroups.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyQuestie.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyEntrances.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyRoles.lua")), env)("ShortestPathForever", ns)
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

local function group(ns, key)
	for _, item in ipairs(ns.NearbyServices.Groups()) do
		if item.key == key then
			return item
		end
	end
end
local function npcs(ns, key)
	local seen, list = {}, {}
	for _, place in ipairs(ns.NearbyServices.Index()[key] or {}) do
		if not seen[place.id] then
			seen[place.id] = true
			list[#list + 1] = place.id
		end
	end
	table.sort(list)
	return list
end
local function same(actual, expected)
	if #actual ~= #expected then
		return false
	end
	for at, value in ipairs(actual) do
		if value ~= expected[at] then
			return false
		end
	end
	return true
end

-- A warrior: the own-class group is the warrior trainer, the mage's portal group is not offered at all, and both
-- battlemasters share the services section while the Horde's is filtered by side.
local warrior = load(1)
assert(same(npcs(warrior, "class"), { 1004 }), "the class trainer is the player's own class")
assert(group(warrior, "portal") == nil, "a warrior is not offered a portal trainer")
assert(same(npcs(warrior, "battlemaster"), { 1001 }), "the Alliance battlemaster is here, the Horde one is not")
assert(same(npcs(warrior, "profession:1"), {}), "no profession trainer is invented")
local battlemaster = group(warrior, "battlemaster")
assert(battlemaster.label == "Battlemaster" and battlemaster.section == "services")
assert(group(warrior, "class").label == "Class trainer")
assert(warrior.NearbyServices.Navigate("battlemaster", warrior.NearbyServices.Index().battlemaster[1]))
assert(
	navigated[1].kind == "battlemaster" and navigated[1].npc == 1001,
	"a battlemaster row's stop carries the client's battlemaster mark and the NPC id"
)

-- A mage: both the mage class trainer and the portal trainer are offered, and the portal group drops the other
-- side's portal trainer.
local mage = load(8)
assert(same(npcs(mage, "class"), { 1003 }), "the mage class trainer is the player's own class")
assert(group(mage, "portal"), "a mage is offered the portal trainer")
assert(group(mage, "portal").label == "Portal trainer")
assert(same(npcs(mage, "portal"), { 1005 }), "the other side's portal trainer is filtered by side")
local mageSections = mage.NearbyServices.Sections({ map = 1, x = 100, y = 100 }, "")
local trainers
for _, section in ipairs(mageSections) do
	if section.section == "trainers" then
		trainers = section
	end
end
assert(trainers and trainers.count == 2, "the class and portal trainers are two rows under Trainers")
assert(mage.NearbyServices.Navigate("portal", mage.NearbyServices.Index().portal[1]))
assert(
	navigated[#navigated].kind == "trainer" and navigated[#navigated].npc == 1005,
	"a portal trainer row's stop points at that trainer"
)

print("nearby_roles: battlemasters, portal trainers and own-class trainers: ok")

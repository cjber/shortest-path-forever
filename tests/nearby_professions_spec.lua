-- Only my professions (#914): a profession trainer shows only for a profession this character has learned, and a
-- vendor only when the goods it sells supply one of those professions. A vendor's game title is never read, so a
-- Trade Supplies vendor selling thread and dye follows Tailoring while one selling flux follows Blacksmithing, and
-- a general vendor with no profession goods always shows. The same rule dresses the world map's town services
-- (tests/town_services_spec).
local timers = {}

local FLAGS = { VENDOR = 4, TRAINER = 16 }
local NPCS = {
	[3001] = { "Tailor trainer", { [10] = { { 20, 20 } } }, "A", FLAGS.TRAINER, "Tailoring Trainer" },
	[3002] = { "Smith trainer", { [10] = { { 25, 25 } } }, "A", FLAGS.TRAINER, "Blacksmithing Trainer" },
	[3003] = { "Thread and dye", { [10] = { { 20, 20 } } }, "A", FLAGS.VENDOR, "Trade Supplies" },
	[3004] = { "Flux and hammers", { [10] = { { 10, 10 } } }, "A", FLAGS.VENDOR, "Trade Supplies" },
	[3005] = { "General supplier", { [10] = { { 30, 30 } } }, "A", FLAGS.VENDOR, "Trade Supplies" },
	[3006] = { "Alchemy trainer", { [10] = { { 45, 45 } } }, "A", FLAGS.TRAINER, "Alchemy Trainer" },
	[3007] = { "Herb and vial supplier", { [10] = { { 40, 40 } } }, "A", FLAGS.VENDOR, "Trade Supplies" },
	[3008] = { "Bread and spices", { [10] = { { 35, 35 } } }, "A", FLAGS.VENDOR, "Trade Supplies" },
}
-- Every vendor sells a trade good, so each sits in the list's own trade supplies group. What the filter reads is the
-- generated profession set of the goods it sells in the row being judged, never the goods' item class or the NPC's
-- title.
local ITEMS = {
	[2604] = { { 3003 }, 7, 0, "Coarse Thread" },
	[2605] = { { 3004 }, 7, 0, "Smithing Flux" },
	[2606] = { { 3007 }, 7, 9, "Peacebloom" },
	[2609] = { { 3005 }, 7, 0, "Smooth Pebble" },
	[4540] = { { 3008 }, 0, 0, "Tough Hunk of Bread" },
	[2678] = { { 3008 }, 7, 0, "Mild Spices" },
}
local itemIDs, npcIDs = {}, {}
for id in pairs(ITEMS) do
	itemIDs[#itemIDs + 1] = id
end
for id in pairs(NPCS) do
	npcIDs[#npcIDs + 1] = id
end
table.sort(itemIDs)
table.sort(npcIDs)

local function QuestieDB()
	return {
		RequireContract = function(version)
			return version == 2
		end,
		Enum = { npcFlags = FLAGS, byExpansion = { Classic = { npcFlags = FLAGS } } },
		Support = {
			Get = function(name)
				assert(name == "ZoneDB", "the zone tables are the support module this file reads")
				return { private = { areaIdToUiMapId = "return {[10]=100}", subZoneToParentZone = "return {}" } }
			end,
		},
		Npc = {
			GetAllIds = function()
				return npcIDs
			end,
			GetAll = function(id, fields)
				local row = NPCS[id]
				if not row then
					return nil
				end
				if #fields == 1 then
					assert(fields[1] == "spawns", "an NPC's spawns are read on their own, once it is kept")
					return { row[2], n = 1 }
				end
				assert(#fields == 4, "an NPC's name, side, flags and title are read together")
				return { row[1], row[3], row[4], row[5], n = 4 }
			end,
		},
		Item = {
			GetAllIds = function()
				return itemIDs
			end,
			GetAll = function(id, fields)
				assert(#fields == 5, "item fields: vendors, class, subClass, name, requiredLevel")
				local row = ITEMS[id]
				return row and { row[1], row[2], row[3], row[4], row[5], n = 5 }
			end,
		},
	}
end

local menuEntries, trackingMenus = {}, {}
local function menuNode()
	local root = {}
	function root.CreateTitle(_, text)
		menuEntries[#menuEntries + 1] = { text = text, title = true }
	end
	function root.SetScrollMode() end
	function root.CreateDivider() end
	function root.CreateButton(_, text, callback)
		local entry = { text = text, callback = callback, children = {} }
		function entry.CreateTitle(_, title)
			entry.children[#entry.children + 1] = { text = title, title = true }
		end
		function entry.SetScrollMode() end
		function entry.CreateDivider() end
		function entry.SetEnabled() end
		function entry.CreateButton(_, childText, childCallback)
			local child = { text = childText, callback = childCallback, children = {}, SetEnabled = function() end }
			entry.children[#entry.children + 1] = child
			return child
		end
		menuEntries[#menuEntries + 1] = entry
		return entry
	end
	return root
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
	C_TradeSkillUI = {
		GetTradeSkillDisplayName = function(skill)
			return ({ [164] = "Blacksmithing", [171] = "Alchemy", [182] = "Herbalism", [197] = "Tailoring" })[skill]
				or ""
		end,
	},
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
			NavigateRoute = function()
				return true
			end,
		},
	},
}, { __index = _G })
env._G = env
local ForeverCore = dofile("tests/forever_core.lua")
local coreNs = ForeverCore.load(env, "ForeverCore", { "Locales/enUS.lua", "Core/Text.lua" })
env.ForeverCore = { Text = coreNs.Text }

-- The character's professions, as GetProfessions and GetProfessionInfo answer them: an empty first slot, so the
-- learned one is only found by counting every returned value.
local learned = 197
env.GetProfessions = function()
	return nil, 1
end
env.GetProfessionInfo = function(book)
	assert(book == 1, "the slot's book is passed on")
	return "", 0, 1, 300, 0, 0, learned
end

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
	ClassTrainers = {},
	PortalTrainers = {},
	Battlemasters = {},
}
setfenv(assert(loadfile("Data/Services.lua")), env)("ShortestPathForever", ns)

local function carries(skills, skill)
	for _, value in ipairs(skills) do
		if value == skill then
			return true
		end
	end
	return false
end

-- The generated table covers the goods the classic suppliers sell, by what each good supplies: thread serves the
-- professions that use it, an item no vendor sells is absent, and so is bread, which no profession's work consumes.
local generated = ns.ItemProfessions
assert(type(generated) == "table", "the generated item professions load")
local thread = generated[2320]
assert(type(thread) == "table", "a sold profession good is classified")
assert(carries(thread, 164) and carries(thread, 197), "thread serves blacksmithing and tailoring")
assert(generated[2589] == nil, "an item no vendor sells is absent, so it never decides a row")
assert(generated[4540] == nil, "bread is no profession's good, so a food seller always shows")

-- The fixture's own goods and trainers, so a data refresh cannot move the cases below.
ns.ProfessionTrainers = { [3001] = 197, [3002] = 164, [3006] = 171 }
ns.ItemProfessions = {
	[2604] = { 197 },
	[2605] = { 164 },
	[2606] = { 171, 182 },
	[2678] = { 129, 185 },
}
for _, file in ipairs({
	"Locales/enUS.lua",
	"UI/MenuModifier.lua",
	"UI/NearbyGroups.lua",
	"UI/NearbyQuestie.lua",
	"UI/NearbyEntrances.lua",
	"UI/NearbyRoles.lua",
	"UI/NearbyProfessions.lua",
	"UI/Nearby.lua",
}) do
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end
for _, fn in ipairs(initializers) do
	fn()
end
ns.NearbyServices.Request()
while #timers > 0 do
	table.remove(timers, 1)()
end
assert(ns.NearbyServices.State() == "ready", "the fixture reads")

local Professions = ns.NearbyProfessions
local function group(key)
	for _, item in ipairs(ns.NearbyServices.Groups()) do
		if item.key == key then
			return item
		end
	end
end
assert(group("profession:197").iconFile == ns.ProfessionIcons[197], "tailoring uses its generated client icon")
assert(group("profession:164").iconFile == ns.ProfessionIcons[164], "smithing uses its generated client icon")
assert(group("profession:197").iconFile ~= group("profession:164").iconFile, "professions have distinct icons")
local function place(id)
	for _, groupKey in pairs({ "profession:197", "profession:164", "profession:171", "trade", "food" }) do
		for _, item in ipairs(ns.NearbyServices.Index()[groupKey] or {}) do
			if item.id == id then
				return item
			end
		end
	end
end
local here = { map = 1, x = 100, y = 100 }
local function nearest(key)
	local item = ns.NearbyServices.Nearest(key, here)
	return item and item.id
end

assert(Professions.Learned()[197] == true and Professions.Learned()[185] == nil, "the learned skills, holes and all")

-- Off, every service shows and every vendor leads with the nearest one.
assert(Professions.Shown(group("profession:164")) == true, "off, an unlearned trainer shows")
assert(nearest("trade") == 3004, "off, the nearest supply vendor leads")

-- On, only the learned profession's trainer and the vendors whose goods serve it stay.
ns.db.onlyMyProfessions = true
assert(Professions.Shown(group("profession:197")) == true, "the learned profession's trainer shows")
assert(Professions.Shown(group("profession:164")) == false, "an unlearned profession's trainer goes")
assert(Professions.Shown(group("trade"), place(3003)) == true, "the learned profession's supplier stays")
assert(
	Professions.Shown(group("trade"), place(3004)) == false,
	"a Trade Supplies vendor selling another profession's goods goes, whatever its title says"
)
assert(Professions.Shown(group("trade"), place(3005)) == true, "a general supplier with no profession goods stays")
assert(Professions.Shown(group("trade"), place(3007)) == false, "a supplier for two unlearned professions goes")
assert(
	Professions.Shown(group("innkeeper"), place(3004)) == true,
	"another service on the same NPC is not a vendor's goods"
)
assert(nearest("trade") == 3003, "the unlearned profession's nearest vendor gives way")

-- A vendor supplying two professions stays when either is learned.
learned = 182
assert(Professions.Shown(group("trade"), place(3007)) == true, "one learned profession from the goods is enough")
learned = 164
assert(Professions.Shown(group("trade"), place(3004)) == true, "the other profession's goods stay when it is learned")

-- The row decides, not the NPC: the bread this vendor sells is no profession's good, so its Food row stays for a
-- character without Cooking, while the Mild Spices beside it put its Trade supplies row behind Cooking.
learned = 197
assert(Professions.Shown(group("food"), place(3008)) == true, "food with no profession goods keeps its Food row")
assert(Professions.Shown(group("trade"), place(3008)) == false, "the cooking reagent beside it hides the Trade row")
assert(nearest("food") == 3008, "the Food row still leads with it")
learned = 185
assert(Professions.Shown(group("trade"), place(3008)) == true, "learning Cooking brings its row back")

-- The list itself: the panel's sections and the tracking menu follow the same rule.
learned = 197
local function sections()
	return ns.NearbyServices.Sections(here)
end
local function sectionKeys(list, section)
	for _, entry in ipairs(list) do
		if entry.section == section then
			local keys = {}
			for _, row in ipairs(entry.rows) do
				keys[#keys + 1] = row.group.key
			end
			return entry.count, keys
		end
	end
end
local count, keys = sectionKeys(sections(), "trainers")
assert(count == 1 and keys[1] == "profession:197", "the panel lists only the learned profession's trainer")
menuEntries = {}
assert(trackingMenus.MENU_WORLD_MAP_TRACKING, "the tracking menu is registered")
trackingMenus.MENU_WORLD_MAP_TRACKING(nil, menuNode())
local trainerRows, inTrainers = {}, false
for _, item in ipairs(menuEntries[1].children) do
	if item.title then
		inTrainers = item.text == "Trainers"
	elseif inTrainers then
		trainerRows[#trainerRows + 1] = item.text:match("^(.-) —") or item.text
	end
end
local listed = table.concat(trainerRows, ",")
assert(listed:find("Tailoring", 1, true), "the menu keeps the learned profession")
assert(not listed:find("Blacksmithing", 1, true), "the menu leaves the unlearned profession out")

print("nearby_professions_spec: without the filter every service shows; with it only the character's professions ok")

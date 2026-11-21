-- UI/NearbyQuestie.lua and UI/Nearby.lua's start of it: QuestieDB is read through its public API, a slice a frame,
-- once Questie has had its own start (its corrections change what the database says), and what was read is kept
-- under the inputs that produced it, so a later session reads nothing. An NPC's spawns are read only when the rest of
-- its row puts it in the list. A database that does not read says so once, in the list, instead of throwing out of the
-- menu and trying again every time it opens.
local FLAGS = {
	VENDOR = 4,
	TRAINER = 16,
	INNKEEPER = 128,
	BANKER = 256,
	FLIGHT_MASTER = 8,
	STABLEMASTER = 8192,
	AUCTIONEER = 4096,
	REPAIR = 16384,
}

-- A QuestieDB with one NPC per kind: an innkeeper friendly to both sides, a flight master and a vendor of arrows of
-- the Alliance, a Horde innkeeper this character can never use, and a passer-by with no service at all. `count` says
-- how many rows were read, and `spawns` how many of those reads asked for spawn trees.
---@param count {items: integer, npcs: integer, spawns: integer?}
local function QuestieDB(count)
	local npcs = {
		[9101] = { "Farley", { [12] = { { 40, 60 } } }, "AH", FLAGS.INNKEEPER },
		[9102] = { "Ariena", { [12] = { { 41, 61 } } }, "A", FLAGS.FLIGHT_MASTER, "Flight Master" },
		[9103] = { "Bow merchant", { [12] = { { 42, 62 } } }, "A", FLAGS.VENDOR, "Bow Merchant" },
		[9104] = { "Horde innkeeper", { [12] = { { 43, 63 } } }, "H", FLAGS.INNKEEPER },
		[9105] = { "Passer-by", { [12] = { { 44, 64 } } }, "A", 0 },
	}
	local items = { [2512] = { { 9103 }, 6, 2, "Rough Arrow", 1 } }
	return {
		RequireContract = function(version)
			return version == 2
		end,
		Enum = { npcFlags = FLAGS, byExpansion = { Classic = { npcFlags = FLAGS } } },
		Support = {
			Get = function(name)
				assert(name == "ZoneDB", "the zone tables are the support module this file reads")
				return { private = { areaIdToUiMapId = "return {[12]=1429}", subZoneToParentZone = "return {}" } }
			end,
		},
		Npc = {
			GetAllIds = function()
				return { 9101, 9102, 9103, 9104, 9105 }
			end,
			GetAll = function(id, fields)
				count.npcs = count.npcs + 1
				local row = npcs[id]
				local spawns = false
				for _, field in ipairs(fields) do
					spawns = spawns or field == "spawns"
				end
				if spawns then
					count.spawns = (count.spawns or 0) + 1
					count.spawned = count.spawned or {}
					count.spawned[id] = true
				end
				if #fields == 1 then
					assert(fields[1] == "spawns", "a kept NPC's spawns are asked for on their own, once")
					return row and { row[2], n = 1 }
				end
				if #fields == 5 then
					return row and { row[1], row[2], row[3], row[4], row[5], n = 5 }
				end
				assert(#fields == 4, "name, side, flags and title are one read; the spawns are not")
				assert(fields[1] == "name" and fields[2] == "friendlyToFaction" and fields[3] == "npcFlags")
				return row and { row[1], row[3], row[4], row[5], n = 4 }
			end,
		},
		Item = {
			GetAllIds = function()
				return { 2512 }
			end,
			GetAll = function(id, fields)
				assert(fields[5] == "requiredLevel", "the level each item needs is read with it")
				count.items = count.items + 1
				local row = items[id]
				return row and { row[1], row[2], row[3], row[4], row[5], n = 5 }
			end,
		},
	}
end

-- The world map's tracking menu, whose Nearby services submenu builds the list.
local function MenuNode()
	local root = { children = {} }
	root.CreateTitle = function() end
	root.SetScrollMode = function() end
	root.CreateButton = function(_, text, callback)
		local entry = { text = text, callback = callback, children = {} }
		entry.CreateTitle = function() end
		entry.SetScrollMode = function() end
		entry.SetEnabled = function() end
		entry.SetTooltip = function() end
		entry.CreateButton = function()
			return entry
		end
		root.children[#root.children + 1] = entry
		return entry
	end
	return root
end

-- A logged-in client over `options.lib`, its saved variables and Questie's API, with the addon's files loaded in TOC
-- order. `options.questie` is Questie's global, nil when it is not installed.
---@param options table
---@return table
local function Load(options)
	local timers, trackingMenus, reported, logins = {}, {}, {}, {}
	local env = setmetatable({
		Menu = {
			ModifyMenu = function(tag, callback)
				trackingMenus[tag] = callback
			end,
		},
		MenuResponse = { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 },
		C_Timer = {
			After = function(seconds, fn)
				timers[#timers + 1] = { seconds = seconds, fn = fn }
			end,
		},
		debugprofilestop = function()
			return options.clock and options.clock() or 0
		end,
		InCombatLockdown = function()
			return false
		end,
		geterrorhandler = function()
			return function(message)
				reported[#reported + 1] = "handler: " .. tostring(message)
			end
		end,
		UnitFactionGroup = function()
			return options.faction or "Alliance"
		end,
		UnitClass = function()
			return "Warrior", "WARRIOR", 1
		end,
		UnitPowerMax = function()
			return 0
		end,
		GetLocale = function()
			return "enUS"
		end,
		-- The metadata a read's key is made of, and the addon's own version.
		C_AddOns = {
			GetAddOnMetadata = function(addon, field)
				if addon == "QuestieDB" then
					if field == "Version" then
						return options.questiedbVersion or "1.0.13"
					end
					return field == "X-Flavor" and "Forever" or nil
				end
				if addon == "Questie" then
					return field == "Version" and options.questieVersion or nil
				end
				return field == "Version" and "1.25.1" or nil
			end,
		},
		C_Map = {
			GetBestMapForUnit = function()
				return 1429
			end,
			GetPlayerMapPosition = function()
				return {
					GetXY = function()
						return 0.4, 0.6
					end,
				}
			end,
			GetMapInfo = function()
				return { name = "Elwynn Forest" }
			end,
		},
		-- The client's own event queue: the read begins once its events have fired, which the spec fires with Login.
		EventUtil = {
			ContinueAfterAllEvents = function(fn, event)
				logins[#logins + 1] = { fn = fn, event = event }
			end,
		},
		SlashCmdList = {},
	}, { __index = _G })
	env._G = env
	env.LibQuestieDB = options.lib
	env.Questie = options.questie
	local ns = { db = options.db or {}, charDB = {} }
	---@param label string
	---@param fn function
	ns.core = {
		SafeCall = function(label, fn, ...)
			local ok, result = pcall(fn, ...)
			if not ok then
				reported[#reported + 1] = label .. ": " .. tostring(result)
			end
			return ok, result
		end,
	}
	-- A module's start runs inside the addon's shared error capture, as Core/Core.lua runs it.
	ns.Init = function(fn)
		ns.core.SafeCall("module start", fn)
	end
	-- ForeverCore's text helpers, which the Nearby search folds with; this spec never opens the quest log tab.
	local coreNs = dofile("tests/forever_core.lua").load(env, "ForeverCore", { "Locales/enUS.lua", "Core/Text.lua" })
	env.ForeverCore = { Text = coreNs.Text, QuestLogTabs = { Select = function() end } }
	ns.OpenWorldMap = function()
		return true
	end
	ns.WorldPoint = function(_, x, y)
		return { map = 1, x = x * 1000, y = y * 1000 }
	end
	ns.Path = {
		Busy = function()
			return options.busy and options.busy() or false
		end,
	}
	-- A mouse client: no gamepad interface, so UI/MenuModifier.lua keeps its entries in place.
	ns.GamepadUI = function()
		return false
	end
	env.CreateFrame = function()
		return { RegisterEvent = function() end, SetScript = function() end }
	end
	setfenv(assert(loadfile("Locales/enUS.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("Data/Services.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/MenuModifier.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyGroups.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyQuestie.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyEntrances.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyRoles.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyProfessions.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/NearbyRank.lua")), env)("ShortestPathForever", ns)
	setfenv(assert(loadfile("UI/Nearby.lua")), env)("ShortestPathForever", ns)
	local requests = 0
	local read = ns.NearbyQuestie.Read
	ns.NearbyQuestie.Read = function(...)
		requests = requests + 1
		return read(...)
	end
	-- Runs the timers the addon scheduled: only the frame's own when `zeroOnly`, all of them (the waits too) when not.
	---@param zeroOnly boolean
	local function Run(zeroOnly)
		for _ = 1, 100000 do
			local at
			for index, timer in ipairs(timers) do
				if not zeroOnly or timer.seconds == 0 then
					at = index
					break
				end
			end
			if not at then
				return
			end
			local timer = table.remove(timers, at)
			timer.fn()
		end
		error("the timers never settle")
	end
	return {
		ns = ns,
		env = env,
		reported = reported,
		Run = Run,
		-- Timers queued during a frame run on a later frame, as in the client.
		Frame = function()
			local pending = timers
			timers = {}
			for _, timer in ipairs(pending) do
				timer.seconds = timer.seconds - 1 / 60
				if timer.seconds <= 0 then
					timer.fn()
				else
					timers[#timers + 1] = timer
				end
			end
		end,
		Requests = function()
			return requests
		end,
		-- The client's login events: the addon asks to be called after PLAYER_LOGIN, and nothing reads before it.
		Login = function(event)
			local pending = logins
			logins = {}
			for _, login in ipairs(pending) do
				assert(login.event == (event or "PLAYER_LOGIN"), "the read waits for " .. tostring(login.event))
				login.fn()
			end
		end,
		OpenMenu = function(tag)
			local menu = trackingMenus[tag or "MENU_WORLD_MAP_TRACKING"]
			assert(menu, "the world map's tracking menu is registered")
			menu(nil, MenuNode())
		end,
	}
end

-- Questie's own API, with its ready callback kept for the spec to fire.
local function QuestieAPI()
	local ready
	local questie = {
		API = {
			isReady = false,
			RegisterOnReady = function(callback)
				ready = callback
			end,
		},
	}
	return questie,
		function()
			questie.API.isReady = true
			assert(ready, "the addon registered for Questie's ready callback")
			ready()
		end
end

-- Thousands of ordinary NPCs, service NPCs and vendor items exercise all three scan passes.
local function LargeQuestieDB()
	local lib = QuestieDB({ items = 0, npcs = 0 })
	local items, npcs = {}, {}
	for id = 1, 8000 do
		items[id] = id
	end
	for id = 1, 12000 do
		npcs[id] = id
	end
	lib.Item.GetAllIds = function()
		return items
	end
	lib.Item.GetAll = function(id)
		return { { 1 + id % 2000 }, 6, 2, "Arrow " .. id, 1, n = 5 }
	end
	lib.Npc.GetAllIds = function()
		return npcs
	end
	lib.Npc.GetAll = function(id, fields)
		if #fields == 1 then
			return { { [12] = { { 40, 60 }, { 41, 61 } } }, n = 1 }
		end
		return { "NPC " .. id, "AH", id <= 2000 and FLAGS.VENDOR or 0, "", n = 4 }
	end
	return lib
end

-- A fresh scan gets its slice even when the planner never becomes idle.
do
	local clock = 0
	local run = Load({
		lib = LargeQuestieDB(),
		clock = function()
			-- One hundred row resumes per slice, independent of the host's CPU speed.
			clock = clock + 0.01
			return clock
		end,
	})
	run.ns.Path.Busy = function()
		return true
	end
	local combat = true
	run.env.InCombatLockdown = function()
		return combat
	end
	run.Login()
	local read
	run.ns.NearbyQuestie.Read({ "VENDOR" }, function(result, state)
		assert(state == "ready", "the fresh scan succeeds")
		read = result
	end)
	for _ = 1, 60 do
		run.Frame()
	end
	assert(clock == 0 and not read, "combat still holds the scan without doing work")
	combat = false
	for _ = 1, 512 do
		run.Frame()
		if read then
			break
		end
	end
	assert(read, "a fresh read finishes within 512 frames while the planner stays busy")
	assert(read.items[8000] and read.npcs[2000], "the entire database was scanned")
	assert(#read.npcs[2000].spawns == 2 and not read.npcs[12000], "service spawns survive the scan")
	assert(#run.reported == 0, "the fresh scan reports no errors")
end

-- Login, passive subscribers and unrelated work never request or scan the catalogue.
do
	local count = { items = 0, npcs = 0 }
	local run = Load({ lib = QuestieDB(count) })
	local notified = 0
	run.ns.NearbyServices.OnReady(function()
		notified = notified + 1
	end)
	run.Login()
	run.Login("PLAYER_ENTERING_WORLD")
	run.Run(false)
	assert(run.Requests() == 0 and count.items == 0 and count.npcs == 0, "no demand means zero reads or scans")
	assert(run.ns.NearbyServices.State() == "idle" and notified == 0, "subscription stays passive")
	run.OpenMenu()
	run.OpenMenu()
	assert(run.Requests() == 1, "the first tracking menu requests once")
	run.Run(true)
	run.OpenMenu()
	run.ns.NearbyServices.Request()
	assert(run.Requests() == 1 and count.items == 1 and count.npcs == 8, "repeated demand keeps the completed read")
	assert(notified == 1, "the subscriber receives completion")
end

-- Each public UI entry point can be the first demand, with stable repeat behavior.
for _, consumer in ipairs({ "panel", "slash", "minimap" }) do
	local run = Load({ lib = QuestieDB({ items = 0, npcs = 0 }) })
	local function Demand()
		if consumer == "panel" then
			run.ns.NearbyServices.Open()
		elseif consumer == "slash" then
			run.env.SlashCmdList.SPFNEAR("innkeeper")
		else
			run.OpenMenu("MENU_MINIMAP_TRACKING")
		end
	end
	run.Login()
	assert(run.Requests() == 0, consumer .. ": login is passive")
	Demand()
	Demand()
	run.Run(true)
	-- A ready slash navigates, which is covered by nearby_spec; repeat the request seam here.
	run.ns.NearbyServices.Request()
	assert(run.Requests() == 1, consumer .. ": first demand requests exactly once")
end

-- A fresh read waits for Questie's own start, and is kept for the next session, which reads nothing.
do
	local count = { items = 0, npcs = 0, spawns = 0 }
	local db = {}
	local questie, Ready = QuestieAPI()
	local run = Load({ lib = QuestieDB(count), questie = questie, db = db, questieVersion = "12.0" })
	assert(count.items == 0 and count.npcs == 0, "nothing is read at ADDON_LOADED")
	assert(run.ns.NearbyServices.State() == "idle", "the list has not started")
	run.Login()
	run.ns.NearbyServices.Request()
	assert(run.ns.NearbyQuestie.State() == "waiting", "a fresh read waits for Questie's own start")
	assert(count.items == 0 and count.npcs == 0, "and reads nothing before it")
	assert(run.ns.NearbyServices.State() == "building", "the list says it is still loading")
	run.Run(true)
	assert(count.items == 0 and count.npcs == 0, "the frame's own work does not read either")
	Ready()
	run.Run(true)
	assert(run.ns.NearbyServices.State() == "ready", "the list is ready once Questie reports ready")
	assert(count.items == 1 and count.npcs == 8, "every item and NPC was read once")
	assert(count.npcs == 8, "and once more only for the kept NPCs' spawns")
	assert(count.spawns == 3, "the spawns of only the NPCs the list keeps")
	assert(
		count.spawned[9101] and count.spawned[9102] and count.spawned[9103],
		"the innkeeper, flight master and vendor each had their spawns read"
	)
	assert(
		not count.spawned[9104] and not count.spawned[9105],
		"neither the other side's innkeeper nor a passer-by had a spawn tree decoded"
	)
	local kept = db.nearbyRead
	assert(type(kept) == "table" and type(kept.key) == "string", "the read is kept for the next session")
	assert(kept.key:find("questiedb=1.0.13", 1, true), "under QuestieDB's own version: " .. tostring(kept.key))
	assert(kept.key:find("questie=12.0", 1, true), "and Questie's: " .. tostring(kept.key))
	assert(kept.npcs[9104] == nil, "an NPC of the other side is not kept: QuestieDB's rows are per faction")
	assert(kept.npcs[9101] and kept.npcs[9101].name == "Farley", "and the innkeeper is")
	assert(#kept.npcs[9101].spawns == 1, "with the spawns the second read brought")

	-- The next session, over the same saved variables: nothing is read.
	local second = Load({ lib = QuestieDB(count), questie = questie, db = db, questieVersion = "12.0" })
	second.Login()
	second.ns.NearbyServices.Request()
	second.Run(true)
	assert(count.npcs == 8 and count.items == 1, "a later session reads no item and no NPC at all")
	assert(second.ns.NearbyServices.State() == "ready", "it is ready at once")
	local here = { map = 1, x = 0, y = 0 }
	assert(second.ns.NearbyServices.Nearest("innkeeper", here).id == 9101, "and the services are all there")
	assert(second.ns.NearbyServices.Nearest("flight", here).id == 9102)
	assert(second.ns.NearbyServices.Nearest("arrows", here).id == 9103)
	-- Questie's own start finishing after the saved read was adopted changes none of it.
	Ready()
	second.Run(true)
	assert(count.npcs == 8, "a saved read is not read again when Questie's ready callback arrives")
	assert(#run.reported == 0 and #second.reported == 0, "nothing was thrown")
end

-- Without Questie there are no corrections to wait for: the database is read at once, and kept.
do
	local count = { items = 0, npcs = 0, spawns = 0 }
	local db = {}
	local run = Load({ lib = QuestieDB(count), db = db })
	run.Login()
	run.ns.NearbyServices.Request()
	run.Run(true)
	assert(run.ns.NearbyServices.State() == "ready", "the list is ready without Questie")
	assert(count.npcs == 8, "the database was read")
	assert(type(db.nearbyRead) == "table", "and kept, since Questie has no corrections to add")
end

-- A read from another QuestieDB version is not used: the database is read again, and kept under the new version.
do
	local count = { items = 0, npcs = 0, spawns = 0 }
	local db = {}
	local first = Load({ lib = QuestieDB(count), db = db })
	first.Login()
	first.ns.NearbyServices.Request()
	first.Run(true)
	local kept = db.nearbyRead
	assert(type(kept) == "table")
	local run = Load({ lib = QuestieDB(count), db = db, questiedbVersion = "1.0.14" })
	run.Login()
	run.ns.NearbyServices.Request()
	run.Run(true)
	assert(count.npcs == 16, "a read from another QuestieDB version is not used: every NPC is read again")
	assert(db.nearbyRead ~= kept, "and the saved read is replaced")
	assert(db.nearbyRead.key:find("questiedb=1.0.14", 1, true), "under the version that produced it")
end

-- Questie can never report ready: the database is read as it stands after the wait, and that read is not kept.
do
	local count = { items = 0, npcs = 0, spawns = 0 }
	local db = {}
	local run = Load({
		lib = QuestieDB(count),
		db = db,
		questie = { API = { isReady = false, RegisterOnReady = function() end } },
	})
	run.Login()
	run.ns.NearbyServices.Request()
	assert(run.ns.NearbyQuestie.State() == "waiting", "Questie is waited for")
	run.Run(true)
	assert(count.npcs == 0, "the wait holds the read, frame after frame")
	run.Run(false)
	assert(count.npcs == 8 and run.ns.NearbyServices.State() == "ready", "the wait runs out and the database is read")
	assert(db.nearbyRead == nil, "but that read is not kept: it has none of Questie's corrections")
end

-- Questie reports ready after the wait has run out: the database is read again with its corrections, and kept.
do
	local count = { items = 0, npcs = 0, spawns = 0 }
	local db = {}
	local questie, Ready = QuestieAPI()
	local run = Load({ lib = QuestieDB(count), db = db, questie = questie })
	run.Login()
	run.ns.NearbyServices.Request()
	run.Run(false)
	assert(count.npcs == 8 and db.nearbyRead == nil, "read as it stood, and not kept")
	Ready()
	run.Run(true)
	assert(count.npcs == 16, "Questie's late ready callback has the database read again")
	assert(type(db.nearbyRead) == "table", "and that read, with its corrections, is kept")
	assert(run.ns.NearbyServices.State() == "ready", "the list stays ready over it")
	assert(#run.reported == 0, "nothing is thrown")
end

-- A database that does not read as this file does is a failure, not an error out of the menu, and it is answered once.
for _, case in ipairs({
	{
		why = "a zone table that is not a table",
		break_ = function(lib)
			lib.Support = {
				Get = function()
					return 42
				end,
			}
		end,
	},
	{
		why = "a zone table that throws",
		break_ = function(lib)
			lib.Support = {
				Get = function()
					error("gone")
				end,
			}
		end,
	},
	{
		why = "a database with no NPC ids",
		break_ = function(lib)
			lib.Npc.GetAllIds = nil
		end,
	},
	{
		why = "a database without the contract",
		break_ = function(lib)
			lib.RequireContract = nil
		end,
	},
}) do
	local count = { items = 0, npcs = 0, spawns = 0 }
	local lib = QuestieDB(count)
	case.break_(lib)
	local run = Load({ lib = lib })
	run.Login()
	run.ns.NearbyServices.Request()
	run.Run(true)
	assert(
		run.ns.NearbyServices.State() == "failed",
		case.why .. ": the list says it could not read QuestieDB, not " .. tostring(run.ns.NearbyServices.State())
	)
	assert(#run.reported == 0, case.why .. ": nothing is thrown out of the menu: " .. table.concat(run.reported, "; "))
	run.OpenMenu()
	run.OpenMenu()
	assert(run.ns.NearbyServices.State() == "failed", case.why .. ": opening the menu again keeps the answer")
	assert(count.items == 0 and count.npcs == 0, case.why .. ": and reads nothing again")
	assert(#run.reported == 0, case.why .. ": nor does it throw again")
end

-- No QuestieDB at all: the one plain line saying what to install.
do
	local run = Load({ lib = nil })
	run.Login()
	run.ns.NearbyServices.Request()
	run.Run(true)
	assert(run.ns.NearbyServices.State() == "missing", "without QuestieDB the list says it is missing")
	run.OpenMenu()
	assert(run.ns.NearbyServices.State() == "missing")
	assert(#run.reported == 0)
end

-- Forever's released corrections mark NPC 270581 at Stormwind 47.96,84.60 with
-- GOSSIP + TRANSMOGRIFIER. The active enum owns that bit; Classic does not.
do
	local count = { items = 0, npcs = 0 }
	local lib = QuestieDB(count)
	local active = {}
	for name, value in pairs(FLAGS) do
		active[name] = value
	end
	active.TRANSMOGRIFIER = 536870912
	lib.Enum.npcFlags = active
	local get = lib.Npc.GetAll
	lib.Npc.GetAllIds = function()
		return { 270581, 9105 }
	end
	lib.Npc.GetAll = function(id, fields)
		if id ~= 270581 then
			local row = get(id, fields)
			if #fields == 4 then
				row[1], row[3], row[4] = "Transmogrifier", 268435456, "Transmogrifier"
			end
			return row
		end
		if #fields == 1 then
			return { { [1519] = { { 47.96, 84.60 } } }, n = 1 }
		end
		return { "Fyrenz Vishonar", "A", 536870913, "", n = 4 }
	end
	lib.Support.Get = function()
		return { private = { areaIdToUiMapId = "return {[1519]=1453}", subZoneToParentZone = "return {}" } }
	end
	local db = {}
	local run = Load({ lib = lib, db = db })
	run.Login()
	run.ns.NearbyServices.Request()
	run.Run(true)
	local entry = run.ns.NearbyServices.Nearest("transmog", { map = 1, x = 480, y = 846 })
	assert(entry and entry.id == 270581, "the active Forever flag finds the transmogrifier without title matching")
	assert(db.nearbyRead.npcs[270581].spawns[1][1] == 1453, "the NPC's own city map is retained")
	assert(not db.nearbyRead.npcs[9105], "neither a matching title nor the other expansion flag classifies an NPC")
	local sections = run.ns.NearbyServices.Sections({ map = 1, x = 480, y = 846 }, "transmog")
	assert(#sections == 1 and sections[1].section == "services", "transmog search finds the service section")
	assert(sections[1].rows[1].npc.id == 270581, "the search row leads to the flagged NPC")
	-- A saved scan made before services=3 omitted newly classified service NPCs, even at the same addon version.
	db.nearbyRead.key = db.nearbyRead.key:gsub("\nservices=3", "\nservices=2")
	local old = db.nearbyRead
	local second = Load({ lib = lib, db = db })
	second.Login()
	second.ns.NearbyServices.Request()
	second.Run(true)
	assert(db.nearbyRead ~= old and db.nearbyRead.npcs[270581], "the old service scan is rebuilt")
end

print("nearby_questie: Questie's ready wait, the saved read, and a database that does not read: ok")

-- A large saved service read: thousands of vendor goods and service NPCs, with multiple spawns.
-- The matching key comes from the real reader, so this exercises login's saved path without database reads.
do
	local count = { items = 0, npcs = 0 }
	local db = {}
	local seed = Load({ lib = QuestieDB(count), db = db })
	seed.Login()
	seed.ns.NearbyServices.Request()
	seed.Run(true)
	local read = assert(db.nearbyRead)
	read.items, read.npcs = {}, {}
	for id = 1, 2000 do
		read.npcs[id] = {
			name = "Service " .. id,
			flags = FLAGS.INNKEEPER,
			spawns = { { 1429, 0.4, 0.6 }, { 1429, 0.5, 0.5 } },
		}
	end
	for id = 1, 8000 do
		read.items[id] = { name = "Goods " .. id, class = 6, subClass = 2, level = 1, vendors = { id % 2000 + 1 } }
	end
	local reads = count.npcs + count.items
	for _, busySeconds in ipairs({ 0, 60 }) do
		local frame, cpu = 0, 0
		local run = Load({
			lib = QuestieDB(count),
			db = db,
			clock = function()
				return os.clock() * 1000
			end,
			busy = function()
				return frame <= busySeconds * 60
			end,
		})
		run.Login()
		run.ns.NearbyServices.Request()
		while run.ns.NearbyServices.State() ~= "ready" and frame < 7200 do
			frame = frame + 1
			local start = os.clock()
			run.Frame()
			cpu = cpu + os.clock() - start
		end
		print(
			string.format(
				"nearby assembly: 8000 items, 2000 NPCs, 4000 spawns, busy=%ds, frames=%d, CPU=%.3fms",
				busySeconds,
				frame,
				cpu * 1000
			)
		)
		assert(run.ns.NearbyServices.State() == "ready")
	end
	-- Deterministic clock: 100 resumes per slice, independent of machine speed.
	local clock = 0
	local run = Load({
		lib = QuestieDB(count),
		db = db,
		clock = function()
			clock = clock + 0.01
			return clock
		end,
		busy = function()
			return true
		end,
	})
	run.Login()
	run.ns.NearbyServices.Request()
	for _ = 1, 256 do
		run.Frame()
	end
	assert(run.ns.NearbyServices.State() == "ready", "saved assembly must finish while the planner stays busy")
	assert(count.npcs + count.items == reads, "saved assembly never scans QuestieDB")
	assert(run.ns.NearbyServices.Nearest("innkeeper", { map = 1, x = 0, y = 0 }), "service pins have indexed spawns")
	assert(#run.reported == 0)
end

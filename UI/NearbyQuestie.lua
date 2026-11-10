---@type string, SPFNamespace
local addonName, ns = ...

if ns.broken then
	return
end

-- QuestieDB as the Nearby services list reads it: who sells what, and where a service NPC stands. The database is
-- read through its public API only (WFA-28), a slice a frame, after Questie has finished its own start, because
-- Questie's corrections change what the database says. What was read is kept in the saved variables under the inputs
-- that produced it, so a later session adopts it whole and reads nothing.

local ADDON = "QuestieDB"
-- The contract this file was written against: QuestieDB checks a range, so a newer additive release keeps working.
-- The entities and zone tables read here are type-checked by Fit, so a database that is not the one this was written
-- for says so in the list rather than throwing.
local CONTRACT = 2
-- Questie can load and never report ready, when its own start stops on an error for one character. Past this the
-- database is read as it stands, and that read is not kept: the next login reads the corrected one.
local READY_WAIT = 60
-- The fields read for each item and NPC, in the order QuestieDB answers them. An NPC's spawns are a table QuestieDB
-- decodes fresh on every read, so they are asked for only once its other fields have put it in the list.
local ITEM_FIELDS = { "vendors", "class", "subClass", "name", "requiredLevel" }
local NPC_FIELDS = { "name", "friendlyToFaction", "npcFlags", "subName" }
local NPC_SPAWNS = { "spawns" }

-- "idle" before anything is asked, "waiting" for Questie's ready callback, "reading" through the database a slice a
-- frame, "ready" with a read in hand, "missing" without QuestieDB, "failed" when it does not read as this file does.
local state = "idle"
---@type SPFNearbyQuestieRead?
local read
-- The one caller to answer, the NPC flags it groups on, and the key a fresh read is kept under.
---@type fun(read: SPFNearbyQuestieRead?, state: string)?
local answer
---@type string[]
local flagNames = {}
local cacheKey = ""
-- Whether the read under way began with Questie's own corrections applied.
local corrected = false
-- Questie's ready callback arrived while a read without its corrections was under way: the database is read again.
local again = false

-- One of QuestieDB's zone tables, which it keeps as Lua source; nil when it does not read as a table.
---@param source any
---@return table?
local function Table(source)
	local chunk = type(source) == "string" and loadstring(source)
	if not chunk then
		return nil
	end
	setfenv(chunk, {})
	local ok, value = pcall(chunk)
	return ok and type(value) == "table" and value or nil
end

---@class SPFNearbyQuestieFit
---@field lib table QuestieDB's public API
---@field flags table<string, integer> its Classic NPC flags
---@field area table<integer, integer>
---@field areaOverride table<integer, integer>
---@field parent table<integer, integer>
---@field parentOverride table<integer, integer>

-- QuestieDB as this file reads it, or the state to answer with: "missing" when it is not installed, "failed" when it
-- is not the one this file was written for or cannot be read. Every part is type-checked here, once, so the scan and
-- the assembly never index something that is not there.
---@return SPFNearbyQuestieFit? fit
---@return string? failure
local function Fit()
	local lib = rawget(_G, "LibQuestieDB")
	if lib == nil then
		return nil, "missing"
	end
	if type(lib) ~= "table" or type(lib.RequireContract) ~= "function" then
		return nil, "failed"
	end
	local called, fits = pcall(lib.RequireContract, CONTRACT)
	if not (called and fits) then
		return nil, "failed"
	end
	local support = lib.Support
	local zoneDB
	if type(support) == "table" and type(support.Get) == "function" then
		local answered, result = pcall(support.Get, "ZoneDB")
		zoneDB = answered and result or nil
	end
	local private = type(zoneDB) == "table" and zoneDB.private
	if type(private) ~= "table" then
		return nil, "failed"
	end
	local area, parent = Table(private.areaIdToUiMapId), Table(private.subZoneToParentZone)
	local expansion = type(lib.Enum) == "table"
		and type(lib.Enum.byExpansion) == "table"
		and lib.Enum.byExpansion.Classic
	local flags = type(expansion) == "table" and expansion.npcFlags
	local npc = lib.Npc
	if not (area and parent and type(flags) == "table") then
		return nil, "failed"
	end
	if type(npc) ~= "table" or type(npc.GetAll) ~= "function" or type(npc.GetAllIds) ~= "function" then
		return nil, "failed"
	end
	return {
		lib = lib,
		flags = flags,
		area = area,
		areaOverride = Table(private.areaIdToUiMapIdOverride) or {},
		parent = parent,
		parentOverride = Table(private.subZoneToParentZoneOverride) or {},
	}
end

-- The side this character can deal with, as QuestieDB spells it.
---@return string
local function Faction()
	local group = UnitFactionGroup and UnitFactionGroup("player")
	return group == "Alliance" and "A" or "H"
end

-- What an addon's metadata says, or "?" before the client can answer.
---@param addon string
---@param field string
---@return string
local function Metadata(addon, field)
	local api = rawget(_G, "C_AddOns")
	if not (type(api) == "table" and type(api.GetAddOnMetadata) == "function") then
		return "?"
	end
	local ok, value = pcall(api.GetAddOnMetadata, addon, field)
	return ok and tostring(value) or "?"
end

-- The inputs that decide what a read says: QuestieDB's own version and flavour, Questie's version (its policy
-- corrections join QuestieDB's own when it is installed), the client's language, and the side this character is on,
-- which QuestieDB's corrections follow (classicNPCFixes.lua picks its spawns by UnitFactionGroup). This addon's
-- version is in there too, since a release may group on more of the database.
---@return string
local function Key()
	local locale = type(GetLocale) == "function" and GetLocale() or "?"
	return table.concat({
		"questiedb=" .. Metadata(ADDON, "Version"),
		"flavour=" .. Metadata(ADDON, "X-Flavor"),
		"questie=" .. Metadata("Questie", "Version"),
		"locale=" .. tostring(locale),
		"faction=" .. Faction(),
		"nearby=" .. Metadata(addonName, "Version"),
	}, "\n")
end

-- The saved read this session can use as it is, or nil. Its shape is checked, so a truncated or foreign save is read
-- again rather than trusted.
---@param key string
---@return SPFNearbyQuestieRead?
local function Saved(key)
	local db = ns.db
	local saved = type(db) == "table" and db.nearbyRead or nil
	if type(saved) ~= "table" or saved.key ~= key then
		return nil
	end
	if type(saved.flags) ~= "table" or type(saved.items) ~= "table" or type(saved.npcs) ~= "table" then
		return nil
	end
	local itemID, item = next(saved.items)
	if itemID ~= nil and (type(itemID) ~= "number" or type(item) ~= "table" or type(item.vendors) ~= "table") then
		return nil
	end
	local npcID, npc = next(saved.npcs)
	if npcID ~= nil and (type(npcID) ~= "number" or type(npc) ~= "table" or type(npc.spawns) ~= "table") then
		return nil
	end
	return saved
end

-- QuestieDB as this file reads it, as a coroutine body: every item a vendor sells, then every NPC the caller could
-- group, and only those NPCs' spawns. `yield` is called between rows, so a read never holds a frame.
---@param fit SPFNearbyQuestieFit
---@param wanted string[] the NPC flag names whose rows the caller needs
---@param yield fun()
---@return SPFNearbyQuestieRead
local function Scan(fit, wanted, yield)
	local lib = fit.lib
	local mask, faction = 0, Faction()
	for _, name in ipairs(wanted) do
		local value = fit.flags[name]
		if type(value) == "number" then
			mask = bit.bor(mask, value)
		end
	end
	-- An area's map, or its parent zone's: without one a spawn is on no map, and reads as no service anywhere.
	---@param area integer
	---@return integer?
	local function Map(area)
		local map = fit.areaOverride[area] or fit.area[area]
		local parent = not map and (fit.parentOverride[area] or fit.parent[area])
		return map or (parent and (fit.areaOverride[parent] or fit.area[parent])) or nil
	end
	-- Every item a vendor sells, with what the caller groups it by; who sells what is also who can be grouped.
	local items, sells = {}, {}
	local entity = lib.Item
	if type(entity) == "table" and type(entity.GetAllIds) == "function" and type(entity.GetAll) == "function" then
		for _, itemID in ipairs(entity.GetAllIds()) do
			local values = entity.GetAll(itemID, ITEM_FIELDS)
			if values then
				local vendors, class, subClass, name, requiredLevel = unpack(values, 1, values.n)
				if
					type(name) == "string"
					and type(class) == "number"
					and type(subClass) == "number"
					and type(vendors) == "table"
				then
					local sold = {}
					for _, npc in ipairs(vendors) do
						if type(npc) == "number" then
							sold[#sold + 1] = npc
							sells[npc] = true
						end
					end
					if sold[1] then
						items[itemID] = {
							name = name,
							class = class,
							subClass = subClass,
							level = type(requiredLevel) == "number" and requiredLevel or nil,
							vendors = sold,
						}
					end
				end
			end
			yield()
		end
	end
	-- Every NPC that sells something, keeps one of the caller's services or trains a class or a profession.
	local trainers = {}
	for npc in pairs(ns.ClassTrainers or {}) do
		trainers[npc] = true
	end
	for npc in pairs(ns.ProfessionTrainers or {}) do
		trainers[npc] = true
	end
	local npcs = {}
	-- The NPCs whose spawns the read still owes, in the order they were found.
	local kept = {}
	for _, id in ipairs(lib.Npc.GetAllIds()) do
		local values = lib.Npc.GetAll(id, NPC_FIELDS)
		if values then
			local name, friendly, flags, title = unpack(values, 1, values.n)
			if
				type(name) == "string"
				and type(friendly) == "string"
				and type(flags) == "number"
				and (sells[id] or trainers[id] or bit.band(flags, mask) ~= 0)
				and (friendly == "AH" or friendly == faction)
			then
				kept[#kept + 1] = { id = id, name = name, flags = flags, title = title }
			end
		end
		yield()
	end
	-- Only the NPCs the list keeps have their spawns read: a spawn tree is the largest thing QuestieDB decodes, and
	-- most NPCs are not a service, a trainer or a vendor.
	for _, row in ipairs(kept) do
		local values = lib.Npc.GetAll(row.id, NPC_SPAWNS)
		local spawns = values and values[1]
		local spots = {}
		for area, points in pairs(type(spawns) == "table" and spawns or {}) do
			local map = type(area) == "number" and Map(area) or nil
			for _, spot in ipairs(map and type(points) == "table" and points or {}) do
				local x, y = spot[1], spot[2]
				if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
					spots[#spots + 1] = { map, x / 100, y / 100 }
				end
			end
		end
		if spots[1] then
			npcs[row.id] = {
				name = row.name,
				title = type(row.title) == "string" and row.title ~= "" and row.title or nil,
				flags = row.flags,
				spawns = spots,
			}
		end
		yield()
	end
	-- A copy of the flags this read was grouped by, so the saved read owns everything it holds.
	local constants = {}
	for name, value in pairs(fit.flags) do
		if type(value) == "number" then
			constants[name] = value
		end
	end
	return { flags = constants, items = items, npcs = npcs }
end

-- Keeps a read for the next session, under the key that produced it. A read that began without Questie's own
-- corrections is not kept: it says what the database said before them.
---@param result SPFNearbyQuestieRead
---@param key string
local function Remember(result, key)
	local db = ns.db
	if not corrected or type(db) ~= "table" then
		return
	end
	result.key = key
	db.nearbyRead = result
end

-- The state as the caller hears it: a read under way is still "building", as the list's own states say.
---@return string
local function AnswerState()
	if state == "waiting" or state == "reading" then
		return "building"
	end
	return state
end

-- Answers the caller: once with a read, and again when Questie's late ready callback has the database read again.
local function Answer()
	local fn = answer
	if fn then
		fn(state == "ready" and read or nil, AnswerState())
	end
end

-- Whether Questie has finished its own start, which changes what the database says. With no Questie installed there
-- are no corrections to wait for.
---@return boolean
local function Corrected()
	local questie = rawget(_G, "Questie")
	local api = type(questie) == "table" and questie.API
	return type(api) ~= "table" or api.isReady == true
end

-- Reads the database as it now stands, a slice a frame, then answers with it and keeps it for the next session.
local function ReadDatabase()
	state = "reading"
	corrected = Corrected()
	again = false
	local fit, failure = Fit()
	if not fit then
		state = failure --[[@as string]]
		Answer()
		return
	end
	local co = coroutine.create(function()
		return Scan(fit, flagNames, coroutine.yield)
	end)
	local function Pump()
		if InCombatLockdown() or ns.Path.Busy() then
			C_Timer.After(0.1, Pump)
			return
		end
		local finish = debugprofilestop() + 1
		repeat
			local ok, result = coroutine.resume(co)
			if not ok then
				state = "failed"
				geterrorhandler()(result)
				Answer()
				return
			end
			if coroutine.status(co) == "dead" then
				read = result --[[@as SPFNearbyQuestieRead]]
				if again then
					ReadDatabase()
					return
				end
				Remember(read, cacheKey)
				state = "ready"
				Answer()
				return
			end
		until debugprofilestop() >= finish
		C_Timer.After(0, Pump)
	end
	C_Timer.After(0, Pump)
end

-- Questie's ready callback: the database is read now, or again when the read under way began without its corrections.
local function Ready()
	if state == "waiting" then
		ReadDatabase()
	elseif not corrected then
		if state == "reading" then
			again = true
		elseif state == "ready" then
			ReadDatabase()
		end
	end
end

-- Questie's own start, when it is installed: a fresh read waits for its ready callback, and goes ahead without the
-- wait when it is absent. A callback that never comes is waited on for READY_WAIT.
---@param key string
local function Await(key)
	cacheKey = key
	local questie = rawget(_G, "Questie")
	local api = type(questie) == "table" and questie.API
	if not (type(api) == "table" and type(api.RegisterOnReady) == "function") or api.isReady == true then
		ReadDatabase()
		return
	end
	state = "waiting"
	local called, accepted = pcall(api.RegisterOnReady, Ready)
	if not called or accepted == false then
		ReadDatabase()
		return
	end
	C_Timer.After(READY_WAIT, function()
		if state == "waiting" then
			ReadDatabase()
		end
	end)
end

-- The first ask: a saved read under this key is used as it is, so a later session reads nothing; otherwise the
-- database is read once Questie has had its own start.
local function Start()
	local key = Key()
	local saved = Saved(key)
	if saved then
		-- Only a read with Questie's own corrections is kept, so the saved one needs nothing more from Questie.
		read, state, corrected = saved, "ready", true
		Answer()
		return
	end
	Await(key)
end

-- Answers `onRead` each time a read lands, or with the state that stopped it. `flags` names the NPC flags whose rows
-- the caller needs: an NPC with none of them that sells nothing and trains nobody is left out of the read.
---@alias SPFNearbyQuestieAnswer fun(read: SPFNearbyQuestieRead?, state: string)
---@param flags string[]
---@param onRead SPFNearbyQuestieAnswer
local function Read(flags, onRead)
	if state ~= "idle" then
		onRead(state == "ready" and read or nil, state)
		return
	end
	answer, flagNames = onRead, flags
	if not ns.core.SafeCall("nearby QuestieDB", Start) and state ~= "ready" then
		state = "failed"
		Answer()
	end
end

---@class SPFNearbyItemRow
---@field name string
---@field class integer
---@field subClass integer
---@field level? integer the level it needs, for the groups that sell it in tiers
---@field vendors integer[] the NPCs that sell it

-- A spawn as the index keeps it: its map, and its own 0-1 coordinates on that map.
---@class SPFNearbySpawn
---@field [1] integer the map
---@field [2] number x
---@field [3] number y

---@class SPFNearbyNpcRow
---@field name string
---@field title? string
---@field flags integer QuestieDB's Classic NPC flags
---@field spawns SPFNearbySpawn[] where it stands, on maps the zone tables place

---@class SPFNearbyQuestieRead
---@field key? string the inputs the read was made under
---@field flags table<string, integer> QuestieDB's Classic NPC flags
---@field items table<integer, SPFNearbyItemRow>
---@field npcs table<integer, SPFNearbyNpcRow>

---@class SPFNearbyQuestie
---@field Read fun(flags: string[], onRead: SPFNearbyQuestieAnswer)
---@field State fun(): string

ns.NearbyQuestie = {
	Read = Read,
	State = function()
		return state
	end,
}

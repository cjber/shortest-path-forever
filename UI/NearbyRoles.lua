---@type string, SPFNamespace
local _, ns = ...

if ns.broken then
	return
end
local L = ns.L

-- The roles classic-db names for an NPC, beside the vendors and services QuestieDB's own flags carry: the class it
-- trains, the mage portal trainers, and the battlemasters battlemaster_entry links to a battleground. Data/Services.lua
-- holds them, so no title or name is matched here.
---@class SPFNearbyRolesAPI
---@field PlayerClass fun(): integer?
---@field ClassTrainerIDs fun(tweaks: table?, anyLevel: boolean?): table<number, boolean>
---@field CanTeachClass fun(npc: number, level: number?): boolean
---@field AddClassGroup fun(Add: fun(group: SPFNearbyGroup), GroupNPCs: fun(key: string): number[])
---@field AddWeaponGroup fun(Add: fun(group: SPFNearbyGroup), GroupNPCs: fun(key: string): number[])
---@field AddPortalGroup fun(Add: fun(group: SPFNearbyGroup), GroupNPCs: fun(key: string): number[])
---@field AddBattlemasterGroup fun(Add: fun(group: SPFNearbyGroup), GroupNPCs: fun(key: string): number[])
---@field OnTeachableChanged fun(level: number?)? set by UI/Nearby.lua: a level-up or learned cap may outgrow a trainer
---@field AddKeys fun(keys: string[], id: integer, classIDs: table<number, boolean>, classID: integer?)
local Roles = {}
ns.NearbyRoles = Roles

-- The player's class, as the client numbers it.
---@return integer?
local function PlayerClass()
	local classID = UnitClass and select(3, UnitClass("player"))
	return type(classID) == "number" and classID or nil
end
Roles.PlayerClass = PlayerClass

-- Whether Data/Services.lua names portal trainers of the player's own class: mages are the only ones today.
---@return boolean
local function HasPortalTrainers()
	local classID = PlayerClass()
	if not classID then
		return false
	end
	for _, class in pairs(ns.PortalTrainers or {}) do
		if class == classID then
			return true
		end
	end
	return false
end

-- A live cap takes precedence over the shipped data. Above a known cap the trainer is outgrown.
---@param npc number
---@param level number?
---@return boolean
local function CanTeachClass(npc, level)
	local learned = ns.db and ns.db.classTrainerCaps
	local cap = learned and learned[npc] or ns.ClassTrainerCaps and ns.ClassTrainerCaps[npc]
	return type(level) ~= "number" or type(cap) ~= "number" or level <= cap
end
Roles.CanTeachClass = CanTeachClass

-- The class trainer group: the companion addon's list, merged with the class trainers in Data/Services.lua for
-- the player's own class and level. With `anyLevel`, trainers the player has outgrown are kept too.
---@param tweaks table?
---@param anyLevel boolean?
---@return table<number, boolean>
function Roles.ClassTrainerIDs(tweaks, anyLevel)
	local ids = {}
	local level = not anyLevel and UnitLevel and UnitLevel("player") or nil
	if
		tweaks
		and tweaks.API
		and type(tweaks.API.version) == "number"
		and tweaks.API.version >= 2
		and tweaks.API.Trainers
	then
		for _, trainer in ipairs(tweaks.API.Trainers()) do
			if CanTeachClass(trainer.npc, level) then
				ids[trainer.npc] = true
			end
		end
	end
	local classID = PlayerClass()
	if classID then
		for npc, class in pairs(ns.ClassTrainers or {}) do
			if class == classID and CanTeachClass(npc, level) then
				ids[npc] = true
			end
		end
	end
	return ids
end

local function LearnClassTrainerCap()
	local guid = UnitGUID("target") -- secret-ok: canaccessvalue is checked on the next line
	if (canaccessvalue and not canaccessvalue(guid)) or type(guid) ~= "string" then
		return
	end
	-- The NPC entry is the GUID's sixth field, before the spawn identifier.
	local npc = tonumber(guid:match("^Creature%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-%x+$"))
	local class = npc and ns.ClassTrainers and ns.ClassTrainers[npc]
	if not (class and class == PlayerClass() and ns.db) then
		return
	end
	-- A hidden service can have the highest requirement. Read only a complete list and leave the filters alone.
	if
		not (
			GetTrainerServiceTypeFilter("available")
			and GetTrainerServiceTypeFilter("unavailable")
			and GetTrainerServiceTypeFilter("used")
		)
	then
		return
	end

	local cap
	for index = 1, GetNumTrainerServices() do
		local name, _, category = GetTrainerServiceInfo(index)
		if category ~= "header" then
			local level = GetTrainerServiceLevelReq(index)
			if not name or name == "" or type(level) ~= "number" then
				return
			end
			cap = math.max(cap or 0, level)
		end
	end
	if cap and npc then
		local caps = ns.db.classTrainerCaps or {}
		local changed = caps[npc] ~= cap
		caps[npc] = cap
		ns.db.classTrainerCaps = caps
		if changed and Roles.OnTeachableChanged then
			Roles.OnTeachableChanged()
		end
	end
end

ns.Init(function()
	if
		GetNumTrainerServices
		and GetTrainerServiceInfo
		and GetTrainerServiceLevelReq
		and GetTrainerServiceTypeFilter
	then
		local events = CreateFrame("Frame")
		events:RegisterEvent("TRAINER_SHOW")
		events:RegisterEvent("PLAYER_LEVEL_UP")
		events:SetScript("OnEvent", function(_, event, level)
			if event == "TRAINER_SHOW" then
				LearnClassTrainerCap()
			elseif Roles.OnTeachableChanged then
				-- UnitLevel can still answer the old level during the event, so the event's own level is used.
				Roles.OnTeachableChanged(level)
			end
		end)
	end
end)

-- The class trainer group, always offered.
---@param Add fun(group: SPFNearbyGroup)
---@param GroupNPCs fun(key: string): number[]
function Roles.AddClassGroup(Add, GroupNPCs)
	Add({
		section = "trainers",
		key = "class",
		label = L["Class trainer"],
		icon = "Class",
		tracking = ns.NearbyGroups.roles.class,
		npcs = GroupNPCs("class"),
	})
end

-- Weapon masters are derived from taught weapon skills, independently of class trainers.
---@param Add fun(group: SPFNearbyGroup)
---@param GroupNPCs fun(key: string): number[]
function Roles.AddWeaponGroup(Add, GroupNPCs)
	if not next(ns.WeaponMasters or {}) then
		return
	end
	Add({
		section = "trainers",
		key = "weapon",
		label = L["Weapon master"],
		icon = "Class",
		tracking = ns.NearbyGroups.roles.weapon,
		npcs = GroupNPCs("weapon"),
	})
end

-- The portal trainer group, offered to a class that can train from one.
---@param Add fun(group: SPFNearbyGroup)
---@param GroupNPCs fun(key: string): number[]
function Roles.AddPortalGroup(Add, GroupNPCs)
	if not HasPortalTrainers() then
		return
	end
	Add({
		section = "trainers",
		key = "portal",
		label = L["Portal trainer"],
		icon = "TaxiNode_Continent_Neutral",
		-- A portal trainer is a mage trainer, so its map pin wears the class trainer's icon.
		tracking = ns.NearbyGroups.roles.portal,
		npcs = GroupNPCs("portal"),
	})
end

-- The battlemaster group, when the shipped data names any.
---@param Add fun(group: SPFNearbyGroup)
---@param GroupNPCs fun(key: string): number[]
function Roles.AddBattlemasterGroup(Add, GroupNPCs)
	if not next(ns.Battlemasters or {}) then
		return
	end
	Add({
		section = "services",
		key = "battlemaster",
		label = L["Battlemaster"],
		icon = "BattleMaster",
		tracking = ns.NearbyGroups.roles.battlemaster,
		npcs = GroupNPCs("battlemaster"),
	})
end

-- The role groups an NPC belongs to, for the nearby index.
---@param keys string[]
---@param id integer
---@param classIDs table<number, boolean>
---@param classID integer?
function Roles.AddKeys(keys, id, classIDs, classID)
	if ns.WeaponMasters and ns.WeaponMasters[id] then
		keys[#keys + 1] = "weapon"
	end
	if classIDs[id] then
		keys[#keys + 1] = "class"
	end
	if classID and ns.PortalTrainers and ns.PortalTrainers[id] == classID then
		keys[#keys + 1] = "portal"
	end
	if ns.Battlemasters and ns.Battlemasters[id] then
		keys[#keys + 1] = "battlemaster"
	end
end

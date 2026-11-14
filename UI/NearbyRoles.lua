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
---@field ClassTrainerIDs fun(tweaks: table?): table<number, boolean>
---@field AddClassGroup fun(Add: fun(group: SPFNearbyGroup), GroupNPCs: fun(key: string): number[])
---@field AddPortalGroup fun(Add: fun(group: SPFNearbyGroup), GroupNPCs: fun(key: string): number[])
---@field AddBattlemasterGroup fun(Add: fun(group: SPFNearbyGroup), GroupNPCs: fun(key: string): number[])
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

-- The class trainer group: the companion addon's list, merged with the class trainers in Data/Services.lua for
-- the player's own class.
---@param tweaks table?
---@return table<number, boolean>
function Roles.ClassTrainerIDs(tweaks)
	local ids = {}
	if
		tweaks
		and tweaks.API
		and type(tweaks.API.version) == "number"
		and tweaks.API.version >= 2
		and tweaks.API.Trainers
	then
		for _, trainer in ipairs(tweaks.API.Trainers()) do
			ids[trainer.npc] = true
		end
	end
	local classID = PlayerClass()
	if classID then
		for npc, class in pairs(ns.ClassTrainers or {}) do
			if class == classID then
				ids[npc] = true
			end
		end
	end
	return ids
end

-- The class trainer group, always offered.
---@param Add fun(group: SPFNearbyGroup)
---@param GroupNPCs fun(key: string): number[]
function Roles.AddClassGroup(Add, GroupNPCs)
	Add({
		section = "trainers",
		key = "class",
		label = L["Class trainer"],
		icon = "Class",
		tracking = "Class",
		npcs = GroupNPCs("class"),
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
		-- A portal trainer is a mage trainer, so its map pin wears the minimap's trainer icon.
		tracking = "Class",
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
		tracking = "BattleMaster",
		npcs = GroupNPCs("battlemaster"),
	})
end

-- The role groups an NPC belongs to, for the nearby index.
---@param keys string[]
---@param id integer
---@param classIDs table<number, boolean>
---@param classID integer?
function Roles.AddKeys(keys, id, classIDs, classID)
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

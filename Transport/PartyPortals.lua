---@class SPFNamespace
local ns = select(2, ...)

-- A party mage's capital portals. The client exposes no API for another player's spellbook, so the player declares
-- them: the setting says a mage is in the group and which capitals that mage can open. The destinations and their
-- positions come from Data/Teleports.lua (mage teleports that spend a Rune of Teleportation), matched to the capital
-- zones in Data/Zones.lua; no coordinate is typed in here.
local MAGE_RUNE = 17031
-- The ask and the portal together: a Hearthstone's cast plus a short wait.
local ASK = 13000
-- The generated mage teleports, each with the setting that says the mage can open it.
local SETTINGS = {
	[3561] = "partyMageStormwind",
	[3562] = "partyMageIronforge",
	[3565] = "partyMageDarnassus",
	[3563] = "partyMageUndercity",
	[3566] = "partyMageThunderBluff",
	[3567] = "partyMageOrgrimmar",
}
-- A hop starts where the player stands, so a plan from elsewhere cannot ask this mage.
local HERE = 15
-- Off, or no mage: the planner gets no party portals at all.
local NONE = {}

local function Readable(value)
	local canAccess = rawget(_G, "canaccessvalue")
	if canAccess and not canAccess(value) then
		return nil
	end
	return value
end

-- The first other mage in the party or raid, by the name the player sees. A secret name is no mage to name.
---@return string?
local function Mage()
	local raid = IsInRaid and IsInRaid()
	if not raid and not (IsInGroup and IsInGroup()) then
		return nil
	end
	local size = _G.GetNumGroupMembers and tonumber(_G.GetNumGroupMembers()) or (raid and 40 or 4)
	for index = 1, math.min(size, 40) do
		local unit = raid and ("raid" .. index) or (index == size and "player" or "party" .. index)
		if unit ~= "player" and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
			local _, class = UnitClass(unit)
			if Readable(class) == "MAGE" then
				local name = Readable(UnitName(unit))
				if name then
					return name
				end
			end
		end
	end
end

-- The capital whose zone box holds a teleport's landing.
---@param point SPFPoint
---@return string? city, number? uiMap
local function Capital(point)
	for uiMap, zone in pairs(ns.Zones or {}) do
		if
			zone.city
			and point.map == zone.map
			and point.x >= zone.minX
			and point.x <= zone.maxX
			and point.y >= zone.minY
			and point.y <= zone.maxY
		then
			return zone.city, uiMap
		end
	end
end

-- The destination as the client names its zone, so guidance reads "Stormwind" in every language. The shipped spell
-- name is the fallback when the client has no map name for it.
local function Destination(uiMap, spell)
	local info = C_Map and C_Map.GetMapInfo and uiMap and C_Map.GetMapInfo(uiMap)
	if info and info.name then
		return info.name
	end
	local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
	if name then
		return (name:gsub("^[^:]+:%s*", ""))
	end
	return UNKNOWN
end

-- The stable key for the current declaration: off, no mage, or the mage and the portals ticked. It changes when the
-- mage leaves or joins, the player's faction changes, or a portal is ticked, so the planner rebuilds its topology.
local function Key()
	local db = ns.db
	if not (db and db.partyMagePortals) then
		return "off"
	end
	local mage = Mage()
	if not mage then
		return "none"
	end
	local faction = UnitFactionGroup("player")
	if not faction then
		return "none"
	end
	local spells = {}
	for spell, key in pairs(SETTINGS) do
		if db[key] ~= false then
			spells[#spells + 1] = spell
		end
	end
	table.sort(spells)
	return mage .. "|" .. faction .. "|" .. table.concat(spells, ",")
end

-- The portal destinations this mage can open for the player, from the shipped teleports and capital boxes.
---@return SPFPartyPortal[]
local function Build()
	local mage = Mage()
	local faction = UnitFactionGroup("player")
	local db = ns.db
	local places = {}
	for _, teleport in ipairs(ns.Teleports or {}) do
		local key = SETTINGS[teleport.spell]
		if key and teleport.to and teleport.reagents and teleport.reagents[MAGE_RUNE] and db[key] ~= false then
			local city, uiMap = Capital(teleport.to)
			if city == faction then
				local destination = Destination(uiMap, teleport.spell)
				places[#places + 1] = {
					spell = teleport.spell,
					map = teleport.to.map,
					x = teleport.to.x,
					y = teleport.to.y,
					z = teleport.to.z,
					cast = ASK,
					label = destination,
					destination = destination,
					partyMage = mage,
				}
			end
		end
	end
	return places
end

local cached, cachedKey = NONE, nil

-- The party portal places for a plan from `from`, or none when the setting is off, no other mage is in the group, or
-- the plan does not start where the player stands. The same list is returned while the declaration is unchanged, so
-- the planner keeps its topology between plans.
---@param from SPFPoint
---@return SPFPartyPortal[]
function ns.PartyPortalPlaces(from)
	if not (ns.db and ns.db.partyMagePortals) then
		return NONE
	end
	local hereX, hereY, _, hereMap
	if ns.JourneyPosition then
		hereX, hereY, _, hereMap = ns.JourneyPosition()
	end
	if not from or not hereX or hereMap ~= from.map or (hereX - from.x) ^ 2 + (hereY - from.y) ^ 2 > HERE ^ 2 then
		return NONE
	end
	local key = Key()
	if key ~= cachedKey then
		cachedKey = key
		cached = (key == "off" or key == "none") and NONE or Build()
	end
	return cached
end

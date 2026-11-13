---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- The player's height band: the heights the player can be standing at, measured from the client's own range checks
-- to nearby NPCs the client names exactly, whose single idle spawn Data/IdleSpawns.lua holds.
--
-- The client gives no player height (UnitPosition's third value is a placeholder 0, #737), so a walk from where you
-- stand starts from every surface at your spot and keeps the cheapest. Where floors stack that can be a floor you are
-- not on: the hall above the Undercity's city, the ground under Stormwind (#602). A stationary NPC is at a height the
-- spawn data knows. Its creature ID in UnitGUID names it without a position (UnitPosition answers for party members
-- only, #737), and a creature with one idle spawn on this map stands at that spawn. The client compares a spell's
-- range R against the 3D distance to a unit, so "in range" means
-- sqrt(d^2 + (zP - zN)^2) <= R for the player's 2D distance d to that NPC at height zN, which bounds
-- |zP - zN| <= sqrt(R^2 - d^2). Each NPC in range adds such a bound around its own height, and the bounds intersect
-- into a band the player's height lies in; a search starts only from the surfaces inside it.
--
-- A unit counts whether it is friendly or hostile: a friendly NPC answers the player's spells that target an ally or
-- any unit, and a hostile one the spells that target an enemy or any unit. A hostile unit is only measured while it
-- stands still at its one spawn too.
--
-- The calls: C_Spell.IsSpellInRange(spellID, unit) answers true, false, or nil when that spell cannot be cast on
-- that unit (a harmful spell on a friendly NPC, a self-only spell, a spell the player does not know). It returns no
-- secret and is not restricted, unlike UnitInRange (Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:
-- SecretReturns, and party members only) and UnitDistanceSquared (party members only, outdoors only).
-- C_Item.IsItemInRange(itemID, unit) answers the same way for an item the player carries, using the range of the
-- item's on-use spell, which the client exposes only in its item and spell tables: Data/SpellTargets.lua carries
-- that range, generated from ItemXItemEffect/ItemEffect/SpellMisc/SpellRange. CheckInteractDistance takes a 1-5
-- index whose yards are server constants, so it is not used.
-- The deprecated IsItemInRange was #nocombat for a friendly unit (the 10.2 hotfix re-permitted enemy units in
-- combat). The pinned ItemDocumentation.lua carries no HasRestrictions flag for C_Item.IsItemInRange and
-- tools/forever_sim/restrictions.txt does not name it, but a friendly NPC's item checks wait for combat to end,
-- which loses nothing because searches and tracker updates wait too; an enemy's are asked in combat.
--
-- Every yard value here is the client's own: C_Spell.GetSpellInfo reads the spell's row of SpellRange.dbc at the
-- client's build, whose 1.60.1 rows are 0-5 (Interact), 0-5 (Combat), 0-10, 0-15, 0-20, 0-25, 0-30, 0-35 and 0-40
-- yd (wago.tools db2/SpellRange, build 1.60.1.70862). Rows with Flag 1 ("Use combat reach range", the 0-5 Combat
-- row) add both units' combat reaches to the distance, which no client call reports, so 5 yd and shorter ranges are
-- left out. Every longer row carries Flags 0. A spell or item with a minimum range still bounds the distance from
-- above by its maximum: a true answer says the unit is no farther than that, and the minimum is never used as a
-- lower bound on the player's height.
---@class SPFBand
---@field map number
---@field lo number lowest height the player may stand at, in yards
---@field hi number highest
---@field anchors SPFBandAnchor[] the range checks it holds while they stay in range

---@class SPFBandAnchor
---@field x number the NPC's world x when it was measured
---@field y number
---@field z number the height of the spawn it stands at
---@field reach number the range (yd) of the check that answered
---@field inside number the bound that answer puts on |player z - z|, in yards

---@class SPFBandCheck
---@field kind "spell"|"item"
---@field id number the spell or item ID to ask the client about
---@field range number its maxRange in yards, from the client's own spell data

---@class SPFBandLadders
---@field friendly SPFBandCheck[]
---@field hostile SPFBandCheck[]

---@class SPFBandChecks
---@field byRange table<number, SPFBandCheck[]>
---@field ranges number[]

local Band = {}
ns.Band = Band

local sqrt = math.sqrt

-- A value the client may keep secret, read through its guard: `canaccessvalue` refuses a secret, and a client
-- without it hands every value over.
---@param value any
---@return any
local function Readable(value)
	local canAccess = rawget(_G, "canaccessvalue")
	if canAccess and not canAccess(value) then
		return nil
	end
	return value
end

-- The player's height is known within a whole yard: a spawn's surface is stored in whole yards.
local ROUND = 0.5
-- 5 yd is the shortest range a check may use: 5 yd and shorter rows add combat reach (see above), and the object
-- spells that use the 0-5 Interact row answer for game objects, not units.
local SHORTEST = 5
-- Up to PER_RANGE spells and PER_RANGE items at each of LADDER ranges: a check that cannot be used on an NPC
-- answers nil, and the next one of the same range may be one that can.
local PER_RANGE = 3
local LADDER = 6

---@param byRange table<number, SPFBandCheck[]>
---@param ranges number[]
---@param check SPFBandCheck
local function AddCheck(byRange, ranges, check)
	local list = byRange[check.range]
	if not list then
		list = {}
		byRange[check.range] = list
		ranges[#ranges + 1] = check.range
	end
	if #list < PER_RANGE then
		list[#list + 1] = check
	end
end

-- One ladder from the spells and items of a category, tightest range first. Up to LADDER distinct ranges are kept,
-- with a range's spells before its items because either answer gives the same bound.
---@param spellByRange table<number, SPFBandCheck[]>
---@param spellRanges number[]
---@param itemByRange table<number, SPFBandCheck[]>
---@param itemRanges number[]
---@return SPFBandCheck[]
local function Combine(spellByRange, spellRanges, itemByRange, itemRanges)
	local combined = {}
	for _, range in ipairs(spellRanges) do
		local list = combined[range] or {}
		combined[range] = list
		for _, check in ipairs(spellByRange[range]) do
			list[#list + 1] = check
		end
	end
	for _, range in ipairs(itemRanges) do
		local list = combined[range] or {}
		combined[range] = list
		for _, check in ipairs(itemByRange[range]) do
			list[#list + 1] = check
		end
	end
	local ranges = {}
	for range in pairs(combined) do
		ranges[#ranges + 1] = range
	end
	table.sort(ranges)
	local out = {}
	for index = 1, math.min(#ranges, LADDER) do
		for _, check in ipairs(combined[ranges[index]]) do
			out[#out + 1] = check
		end
	end
	return out
end

-- The spells the spellbook holds, split by the units they can be asked about, read once per class and level rather
-- than once per measurement. A pet spell would answer for the pet and a self spell for the caster, neither of which
-- is the NPC the band measured, so Data/SpellTargets.lua keeps only spells that target another unit.
local spellCache, spellKey

---@return { friendly: SPFBandChecks, hostile: SPFBandChecks }?
local function SpellLadders()
	-- A client with no spellbook to read, or no class and level to key it by, has no spell ladder.
	if
		not (
			UnitClass
			and UnitLevel
			and C_SpellBook
			and C_SpellBook.GetNumSpellBookSkillLines
			and C_Spell
			and C_Spell.GetSpellInfo
		)
	then
		return nil
	end
	local _, class = UnitClass("player")
	local level = UnitLevel("player")
	local key = tostring(class) .. ":" .. tostring(level)
	if key == spellKey then
		return spellCache
	end
	spellKey = key
	local friendly = { byRange = {}, ranges = {} }
	local hostile = { byRange = {}, ranges = {} }
	local allowedFriendly = ns.SpellTargets
	local allowedHostile = ns.HostileSpells
	local lines = C_SpellBook.GetNumSpellBookSkillLines() or 0
	for index = 1, lines do
		local line = C_SpellBook.GetSpellBookSkillLineInfo(index)
		if line and canaccessvalue(line.numSpellBookItems) and line.numSpellBookItems then
			local first = (line.itemIndexOffset or 0) + 1
			for slot = first, first + line.numSpellBookItems - 1 do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
				local spell = item and not item.isPassive and item.spellID
				local info = spell and C_Spell.GetSpellInfo(spell)
				local high = info and info.maxRange
				-- The minimum range is not read: a true answer still says the unit is no farther than the maximum.
				if high and canaccessvalue(high) and high > SHORTEST then
					local check = { kind = "spell", id = spell, range = high }
					if allowedFriendly and allowedFriendly[spell] then
						AddCheck(friendly.byRange, friendly.ranges, check)
					end
					if allowedHostile and allowedHostile[spell] then
						AddCheck(hostile.byRange, hostile.ranges, check)
					end
				end
			end
		end
	end
	spellCache = { friendly = friendly, hostile = hostile }
	return spellCache
end

-- The usable items the player carries whose on-use spell targets another unit, split by the units that spell can be
-- asked about. Read per measurement because the bags change; only an item held right now counts.
---@return SPFBandChecks, SPFBandChecks
local function ItemLadders()
	local friendly = { byRange = {}, ranges = {} }
	local hostile = { byRange = {}, ranges = {} }
	local items = ns.BandItems
	local count = C_Item and C_Item.GetItemCount
	local isInRange = C_Item and C_Item.IsItemInRange
	if not (items and count and isInRange) then
		return friendly, hostile
	end
	local carried = {}
	for item in pairs(items) do
		local held = Readable(count(item))
		if type(held) == "number" and held > 0 then
			carried[#carried + 1] = item
		end
	end
	table.sort(carried)
	for _, item in ipairs(carried) do
		local entry = items[item]
		local range = entry and entry.range
		if range and range > SHORTEST then
			local check = { kind = "item", id = item, range = range }
			if entry.friendly then
				AddCheck(friendly.byRange, friendly.ranges, check)
			end
			if entry.hostile then
				AddCheck(hostile.byRange, hostile.ranges, check)
			end
		end
	end
	return friendly, hostile
end

---@return SPFBandLadders
local function Ladder()
	local spells = SpellLadders()
	if not spells then
		return { friendly = {}, hostile = {} }
	end
	local friendlyItems, hostileItems = ItemLadders()
	return {
		friendly = Combine(
			spells.friendly.byRange,
			spells.friendly.ranges,
			friendlyItems.byRange,
			friendlyItems.ranges
		),
		hostile = Combine(spells.hostile.byRange, spells.hostile.ranges, hostileItems.byRange, hostileItems.ranges),
	}
end

-- The one spawn a creature of npc on map stands still at, from Data/IdleSpawns.lua, or nil where the creature has
-- none or more than one: two spawns leave which one the range check answered about unknown. The generated row holds
-- one "x y z" triple per spawn, so a second spawn is a row this does not read.
---@param map number
---@param npc number
---@return number? x, number? y, number? z
local function Spawn(map, npc)
	local spawns = ns.IdleSpawns and ns.IdleSpawns[map]
	local row = spawns and spawns[npc]
	local sx, sy, sz
	if row then
		sx, sy, sz = row:match("^(%S+) (%S+) (%S+)$")
	end
	if not (sx and sy and sz) then
		return nil
	end
	return tonumber(sx), tonumber(sy), tonumber(sz)
end

-- The unit tokens an NPC can carry on this client: the two the player points at, then the nameplates. A token that
-- names a player, a dead unit, a unit whose GUID the client withholds, or a creature without one idle spawn on this
-- map is dropped by Anchor. A hostile unit is not dropped.
---@return string[]
local function Tokens()
	local out = { "target", "mouseover" }
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
	for _, plate in ipairs(plates or {}) do
		if plate.namePlateUnitToken then
			out[#out + 1] = plate.namePlateUnitToken
		end
	end
	return out
end

-- The range checks a living NPC that the client names with a creature ID whose one idle spawn on map is (nx, ny, z)
-- gives, as its one tightest bound: the first check that answers true bounds |zP - zN| by sqrt(range^2 - d^2), and
-- a false answer only says the player is away from this NPC's height, which is no band and is not used. A check
-- whose range is shorter than the 2D distance cannot be in range and is not asked. A hostile unit answers the
-- spells and items that target an enemy or any unit; a friendly one those that target an ally or any unit.
---@param token string
---@param map number
---@param x number the player's world x
---@param y number
---@param ladders SPFBandLadders
---@return SPFBandAnchor?
local function Anchor(token, map, x, y, ladders)
	if not UnitExists(token) or UnitIsUnit(token, "player") or UnitIsPlayer(token) then
		return nil
	end
	if UnitIsDeadOrGhost(token) then
		return nil
	end
	local hostile = UnitCanAttack("player", token) and true or false
	-- The creature ID is the sixth field: Creature-0-<server>-<map>-<instance>-<creature ID>[-<spawn>].
	local guid = Readable(UnitGUID(token))
	if type(guid) ~= "string" then
		return nil
	end
	local npc = tonumber(guid:match("^Creature%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)"))
	local nx, ny, z
	if npc then
		nx, ny, z = Spawn(map, npc)
	end
	if not (nx and ny and z) then
		return nil
	end
	local d2 = (nx - x) ^ 2 + (ny - y) ^ 2
	-- A friendly unit's item check is the legacy #nocombat call; an enemy's is permitted in combat. Searches wait
	-- for combat to end anyway, so this only keeps a restricted call from being made.
	local itemAllowed = hostile or not (InCombatLockdown and InCombatLockdown())
	for _, check in ipairs(hostile and ladders.hostile or ladders.friendly) do
		if check.range * check.range > d2 then
			local answer
			if check.kind == "spell" then
				answer = Readable(C_Spell.IsSpellInRange(check.id, token))
			elseif itemAllowed then
				answer = Readable(C_Item.IsItemInRange(check.id, token))
			end
			if answer == true then
				return {
					x = nx,
					y = ny,
					z = z,
					reach = check.range,
					inside = sqrt(check.range * check.range - d2) + ROUND,
				}
			end
		end
	end
	return nil
end

-- A band measured now from the NPCs around (x, y) on map, or nil when no NPC there answered a range check.
---@param map number
---@param x number
---@param y number
---@return SPFBand?
function Band.Measure(map, x, y)
	local ladders = Ladder()
	if #ladders.friendly == 0 and #ladders.hostile == 0 then
		return nil
	end
	local lo, hi, anchors = -math.huge, math.huge, {}
	for _, token in ipairs(Tokens()) do
		local anchor = Anchor(token, map, x, y, ladders)
		if anchor then
			lo, hi = math.max(lo, anchor.z - anchor.inside), math.min(hi, anchor.z + anchor.inside)
			anchors[#anchors + 1] = anchor
		end
	end
	if #anchors == 0 or lo > hi then
		return nil
	end
	return { map = map, lo = lo, hi = hi, anchors = anchors }
end

local kept -- the band measured last, while the player stays in range of the NPCs it came from

-- The band the player is standing in on map, measured when there is none kept. A measured band is kept while the
-- player stays within every anchor's range of that NPC, and dropped when they move away from one: a range check is
-- the client's answer about the distance to a unit, and it still holds while that unit is that close.
---@param map number
---@param x number
---@param y number
---@return SPFBand?
function Band.At(map, x, y)
	if kept and kept.map == map then
		local holds = true
		for _, anchor in ipairs(kept.anchors) do
			if (anchor.x - x) ^ 2 + (anchor.y - y) ^ 2 > anchor.reach * anchor.reach then
				holds = false
				break
			end
		end
		if holds then
			return kept
		end
	end
	kept = Band.Measure(map, x, y)
	return kept
end

-- Whether a surface at height z is one the player can be standing on.
---@param band SPFBand
---@param z number
---@return boolean
function Band.Holds(band, z)
	return z >= band.lo and z <= band.hi
end

-- The band is no longer about this player: on a loading screen, a teleport, or a floor that moved without them.
function Band.Forget()
	kept = nil
end

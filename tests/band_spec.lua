-- Routing/Band.lua bounds the player's height from the client's own range checks to NPCs that stand still at a spawn
-- whose height Data/IdleSpawns.lua holds, so a walk from where they stand starts on the floor they are on: on
-- Stormwind Keep's upper floor, not on the ground 46 yards under it that today's search starts from and runs along
-- (#602's shape). An NPC is named by the creature ID in its GUID, because UnitPosition answers only for the player's
-- group (#737). A friendly NPC answers spells and items that target an ally or any unit; a hostile one those that
-- target an enemy or any unit, and a carried item's range comes from its on-use spell in Data/SpellTargets.lua.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
	"Data/IdleSpawns.lua",
	"Data/SpellTargets.lua",
	"Routing/Band.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path, Band = ns.Path, ns.Band
Path.after = function() end

local sqrt, abs = math.sqrt, math.abs
local function near(actual, expected, what)
	assert(
		actual and abs(actual - expected) < 0.01,
		what .. ": " .. tostring(actual) .. " is not " .. tostring(expected)
	)
end

-- The client. A unit is named by its GUID, whose fifth field is the creature ID; a spell's range is the client's own;
-- and the range check measures the 3D distance to the player's real height, which no call reports. UnitPosition is
-- defined only so that a call to it fails the spec, and SECRET is what a restricted call answers: canaccessvalue
-- refuses it. The spellbook holds real spells the generated target tables decide on: Arcane Intellect targets an
-- ally, Hunter's Mark targets any unit, Fireball targets an enemy, and Dismiss Pet and Ice Barrier target the pet
-- and the caster, which are not the NPC the band measured. The items are real too: a Linen Bandage heals an ally,
-- and item 1191's use spell targets an enemy.
local SECRET = {}
local ALLY, MIN, ANY, WIDE, PET, CASTER, HOSTILE = 1459, 1461, 1130, 1460, 2641, 11426, 133
local known = { ALLY, MIN, ANY, WIDE, PET, CASTER, HOSTILE }
local spells = {
	[ALLY] = { max = 10, friendly = true },
	[MIN] = { max = 25, min = 8, friendly = true },
	[ANY] = { max = 30, friendly = true, hostile = true },
	[WIDE] = { max = 40, friendly = true },
	[PET] = { max = 20, friendly = true },
	[CASTER] = { max = 15, friendly = true },
	[HOSTILE] = { max = 35, hostile = true },
}
local LINEN, RUNECLOTH, ENEMY_ITEM = 1251, 14530, 1191
local carried = {}
local player = { map = 0, x = 0, y = 0, z = 0 }
local units = {}
local asked, itemAsked, restricted, combat

_G.canaccessvalue = function(value)
	return value ~= SECRET
end
_G.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
_G.C_NamePlate = {
	GetNamePlates = function()
		return {}
	end,
}
_G.C_SpellBook = {
	GetNumSpellBookSkillLines = function()
		return 1
	end,
	GetSpellBookSkillLineInfo = function()
		return { itemIndexOffset = 0, numSpellBookItems = #known }
	end,
	GetSpellBookItemInfo = function(slot)
		return { spellID = known[slot] }
	end,
}
_G.C_Spell = {
	GetSpellInfo = function(id)
		return { minRange = spells[id] and spells[id].min or 0, maxRange = spells[id] and spells[id].max }
	end,
	IsSpellInRange = function(id, token)
		asked[#asked + 1] = id
		if restricted then
			return SECRET
		end
		local unit, spell = units[token], spells[id]
		if not (unit and spell) then
			return nil
		end
		local hostile = unit.hostile or false
		if (hostile and not spell.hostile) or (not hostile and not spell.friendly) then
			return nil
		end
		local dx, dy, dz = unit.x - player.x, unit.y - player.y, unit.z - player.z
		local distance = sqrt(dx * dx + dy * dy + dz * dz)
		if spell.min and distance < spell.min then
			return false
		end
		return dx * dx + dy * dy + dz * dz <= spell.max * spell.max
	end,
}
_G.C_Item = {
	GetItemCount = function(id)
		return carried[id] or 0
	end,
	IsItemInRange = function(id, token)
		itemAsked[#itemAsked + 1] = id
		if restricted then
			return SECRET
		end
		local unit, entry = units[token], ns.BandItems[id]
		if not (unit and entry) then
			return nil
		end
		local hostile = unit.hostile or false
		if (hostile and not entry.hostile) or (not hostile and not entry.friendly) then
			return nil
		end
		local dx, dy, dz = unit.x - player.x, unit.y - player.y, unit.z - player.z
		return dx * dx + dy * dy + dz * dz <= entry.range * entry.range
	end,
}
_G.InCombatLockdown = function()
	return combat == true
end
_G.UnitClass = function()
	return "Mage", "MAGE"
end
_G.UnitLevel = function()
	return 60
end
_G.UnitExists = function(token)
	return units[token] ~= nil
end
_G.UnitIsUnit = function(a, b)
	return a == b
end
_G.UnitIsPlayer = function(token)
	return (units[token] and units[token].player) or false
end
_G.UnitIsDeadOrGhost = function(token)
	return (units[token] and units[token].dead) or false
end
_G.UnitCanAttack = function(_, token)
	return (units[token] and units[token].hostile) or false
end
_G.UnitGUID = function(token)
	local unit = units[token]
	if not unit then
		return nil
	end
	if unit.secret then
		return SECRET
	end
	return unit.guid
end
_G.UnitPosition = function()
	error("UnitPosition answers only for the player's group: it must not be read for an NPC")
end
_G.UnitInRange = function()
	error("UnitInRange returns secrets and is for party members: it must not be called")
end

-- A GUID as the client writes one: its fifth field is the creature ID.
local function GUID(npc)
	return string.format("Creature-0-0-0-0-%d-0000000001", npc)
end

-- The band maths: each NPC the client names, with one idle spawn on the map, bounds |player z - npc z| by
-- sqrt(R^2 - d^2), and the bounds intersect. HERE is over Stormwind Keep: surfaces at 106, 112 and 152 yd.
local HERE = { x = -9020, y = 870 }
local shipped = ns.IdleSpawns[0][5694]

-- A stationary NPC at (HERE.x + dx, HERE.y + dy), with the one spawn Data/IdleSpawns.lua would hold for it.
local function placed(npc, dx, dy, z, hostile)
	local x, y = HERE.x + dx, HERE.y + dy
	ns.IdleSpawns[0][npc] = string.format("%d %d %d", x, y, z)
	return { x = x, y = y, z = z, guid = GUID(npc), hostile = hostile }
end

local function reset()
	asked, itemAsked, restricted, combat = {}, {}, nil, false
	carried = {}
end

ns.IdleSpawns[0][5694] = string.format("%d %d 100", HERE.x, HERE.y + 29)
ns.IdleSpawns[0][5695] = string.format("%d %d 100", HERE.x - 9, HERE.y)
player.map, player.x, player.y, player.z = 0, HERE.x, HERE.y, 100
units = {
	target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694) }, -- 29 yd off: the 30 yd check bounds 8.2 yd
	mouseover = { x = HERE.x - 9, y = HERE.y, z = 100, guid = GUID(5695) }, -- 9 yd off: the 10 yd check bounds 4.9
}
reset()
do
	assert(ns.SpellTargets[ALLY] and ns.SpellTargets[ANY], "an ally-target and an any-target spell are kept")
	assert(not ns.SpellTargets[HOSTILE], "an enemy-only spell is not in the friendly table")
	assert(ns.HostileSpells[ANY] and ns.HostileSpells[HOSTILE], "an any-target and an enemy-target spell are kept")
	assert(not ns.HostileSpells[ALLY], "an ally-only spell is not in the hostile table")
	assert(
		not ns.SpellTargets[PET] and not ns.SpellTargets[CASTER],
		"a pet-target and a caster-target spell are excluded"
	)
	assert(ns.BandItems[LINEN] and ns.BandItems[LINEN].range == 15, "a bandage carries its on-use spell's range")
	assert(ns.BandItems[LINEN].friendly and not ns.BandItems[LINEN].hostile, "a bandage heals an ally")
	assert(ns.BandItems[ENEMY_ITEM] and ns.BandItems[ENEMY_ITEM].hostile, "an enemy item is kept")
	local band = assert(Band.Measure(0, HERE.x, HERE.y), "both NPCs are in range, so there is a band")
	near(band.lo, 100 - sqrt(100 - 81) - 0.5, "the tighter 10 yd check bounds the bottom")
	near(band.hi, 100 + sqrt(100 - 81) + 0.5, "and the top")
	assert(Band.Holds(band, 100), "the player's own height is in the band")
	assert(Band.Holds(band, 97), "a surface a yard under the player is in the band")
	assert(not Band.Holds(band, 74), "the floor under the Keep is not")
	assert(not Band.Holds(band, 106), "nor the one above the bound")
	assert(asked[1] == ANY and asked[2] == ALLY, "the tightest range is the only one that has to answer")
	for _, id in ipairs(asked) do
		assert(id ~= PET and id ~= CASTER and id ~= HOSTILE, "a pet, caster or enemy spell is never asked of a friend")
	end
	assert(#itemAsked == 0, "no item is carried, so no item check is asked")
end

-- A carried item adds its on-use spell's range to the ladder: a Linen Bandage's 15 yd bound answers before the 25
-- and 30 yd spells, and a bandage the player does not carry is never asked.
do
	reset()
	carried = { [LINEN] = 1 }
	units = { target = placed(5698, 12, 0, 100) }
	local band = assert(Band.Measure(0, HERE.x, HERE.y), "the carried bandage answers")
	near(band.hi, 100 + sqrt(225 - 144) + 0.5, "the 15 yd item bounds the height")
	assert(Band.Holds(band, 100) and not Band.Holds(band, 110), "the band is the item's own bound")
	assert(itemAsked[1] == LINEN, "the carried bandage is asked")
	assert(#itemAsked == 1, "only the carried item is asked")
	assert(itemAsked[1] ~= RUNECLOTH, "a bandage the player does not carry is not asked")
	assert(#asked == 0, "the item answers before any spell")
end

-- A spell with a minimum range is not skipped: a true answer still bounds the distance from above by its maximum.
do
	reset()
	units = { target = placed(5698, 12, 0, 100) }
	local band = assert(Band.Measure(0, HERE.x, HERE.y), "the 8-25 yd spell answers")
	assert(asked[1] == MIN, "the minimum-range spell is asked, not skipped")
	near(band.hi, 100 + sqrt(625 - 144) + 0.5, "a true answer bounds by the maximum, not the minimum")
	assert(Band.Holds(band, 100) and Band.Holds(band, 120), "the band reaches above the NPC")
	assert(not Band.Holds(band, 123), "and stops at the maximum range")
end

-- A stationary hostile NPC with one idle spawn counts too, and answers the any-target and enemy-target spells that a
-- friendly NPC cannot.
do
	reset()
	units = { target = placed(5697, 9, 0, 100, true) }
	local band = assert(Band.Measure(0, HERE.x, HERE.y), "a hostile NPC answers an any-target spell")
	assert(asked[1] == ANY, "the 30 yd any-target spell answers")
	for _, id in ipairs(asked) do
		assert(id ~= ALLY and id ~= MIN and id ~= WIDE, "a friendly-only spell is not asked of a hostile NPC")
	end
	near(band.hi, 100 + sqrt(900 - 81) + 0.5, "the hostile NPC bounds the height too")
end
do
	reset()
	units = { target = placed(5697, 32, 0, 100, true) }
	local band = assert(Band.Measure(0, HERE.x, HERE.y), "a hostile NPC answers an enemy-target spell")
	assert(asked[1] == HOSTILE, "the 30 yd any-target spell is out of range, so the 35 yd enemy spell answers")
	near(band.hi, 100 + sqrt(1225 - 1024) + 0.5, "the enemy spell bounds by its own range")
end

-- An item whose use spell targets an enemy is asked of a hostile NPC and never of a friendly one.
do
	reset()
	carried = { [ENEMY_ITEM] = 1 }
	units = { target = placed(5697, 12, 0, 100, true) }
	local band = assert(Band.Measure(0, HERE.x, HERE.y), "a hostile NPC answers a hostile item")
	assert(itemAsked[1] == ENEMY_ITEM, "the 20 yd hostile item answers before the 30 yd spell")
	assert(#asked == 0, "the item answers first")
	near(band.hi, 100 + sqrt(400 - 144) + 0.5, "the item bounds by its own range")
end
do
	reset()
	carried = { [ENEMY_ITEM] = 1 }
	units = { target = placed(5698, 12, 0, 100) }
	assert(Band.Measure(0, HERE.x, HERE.y), "the friendly NPC is measured by a spell")
	assert(itemAsked[1] ~= ENEMY_ITEM, "a friendly NPC is not asked about a hostile-only item")
end

-- A friendly unit's item check is the legacy #nocombat call: it waits for combat to end, while an enemy's is asked.
do
	reset()
	carried = { [LINEN] = 1 }
	combat = true
	units = { target = placed(5698, 12, 0, 100) }
	assert(Band.Measure(0, HERE.x, HERE.y), "the 25 yd spell answers while the item waits")
	assert(#itemAsked == 0, "a friendly item check is skipped in combat")
	assert(asked[1] == MIN, "so the next spell answers")
end
do
	reset()
	carried = { [ENEMY_ITEM] = 1 }
	combat = true
	units = { target = placed(5697, 12, 0, 100, true) }
	assert(Band.Measure(0, HERE.x, HERE.y), "an enemy item check is asked in combat")
	assert(itemAsked[1] == ENEMY_ITEM, "and the hostile item answers")
end

-- No NPC in range is no measurement at all, and the walk keeps today's behaviour.
do
	reset()
	units = {}
	Band.Forget()
	assert(Band.Measure(0, HERE.x, HERE.y) == nil, "no unit answers, so no band")
	assert(Band.At(0, HERE.x, HERE.y) == nil, "and nothing is kept")
end

-- A creature with two idle spawns on the map is not measured: which spawn the client's answer is about is unknown.
-- The row the generator writes holds one triple per spawn.
do
	reset()
	ns.IdleSpawns[0][5696] = string.format("%d %d 100 %d %d 100", HERE.x, HERE.y + 29, HERE.x - 9, HERE.y)
	units = { target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5696) } }
	Band.Forget()
	assert(Band.Measure(0, HERE.x, HERE.y) == nil, "two spawns leave no single height to bound")
	ns.IdleSpawns[0][5696] = nil
end

-- A creature with no idle spawn on this map is not measured, and neither is one whose GUID the client withholds.
do
	reset()
	units = {
		target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(999999) },
		mouseover = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694), secret = true },
	}
	Band.Forget()
	assert(Band.Measure(0, HERE.x, HERE.y) == nil, "an unknown creature and a secret GUID measure nothing")
	assert(asked[1] == nil and itemAsked[1] == nil, "and no range check is asked")
end

-- A unit the client names as a player or a corpse is not measured. A hostile creature now is, which the earlier
-- hostile cases cover.
do
	reset()
	units = {
		target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694), player = true },
		mouseover = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694), dead = true },
	}
	Band.Forget()
	assert(Band.Measure(0, HERE.x, HERE.y) == nil, "a player and a corpse are not stationary NPCs")
end

-- A restricted answer is not read: the band is no measurement rather than a guess, and nothing else is called.
do
	reset()
	carried = { [LINEN] = 1 }
	units = { target = placed(5698, 12, 0, 100) }
	restricted = true
	Band.Forget()
	assert(Band.Measure(0, HERE.x, HERE.y) == nil, "a secret answer measures nothing")
	assert(itemAsked[1] == LINEN, "the item check was asked and its secret answer refused")
	restricted = nil
end

-- The measured band is kept while the player stays in range of the spawns it came from, and dropped when they walk
-- away from one: no clock is involved.
do
	reset()
	units = { target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694) } }
	Band.Forget()
	local first = assert(Band.At(0, HERE.x, HERE.y), "measured at the Keep")
	assert(Band.At(0, HERE.x + 5, HERE.y) == first, "still the same band five yards on")
	player.x = HERE.x + 40
	assert(Band.At(0, player.x, HERE.y) == nil, "away from the spawn, the band is gone")
	player.x = HERE.x
end

-- The shipped Stormwind data, keyed by the Keep guard's creature ID: its idle spawn at (-9011, 877, 148) is 11.4 yd
-- from the courtyard point, so a 25 yd check bounds the player's height to 125.2..170.8 yd: the Keep's own floor
-- fits and the ground at 106 does not.
ns.IdleSpawns[0][5694] = shipped
ns.IdleSpawns[0][5695] = nil
do
	reset()
	local NPC = { x = -9011, y = 877, z = 148 }
	player.map, player.x, player.y, player.z = 0, HERE.x, HERE.y, 152
	units = { target = { x = NPC.x, y = NPC.y, z = NPC.z, guid = GUID(5694) } }
	Band.Forget()
	local band = assert(Band.Measure(0, HERE.x, HERE.y), "the Keep's spawn answers the 25 yd check")
	assert(asked[1] == MIN, "the 10 yd check is skipped: the spawn is 11.4 yd off")
	assert(Band.Holds(band, 152) and Band.Holds(band, 150), "the Keep's floor is in the band")
	assert(not Band.Holds(band, 106) and not Band.Holds(band, 112), "the ground under it is not")

	-- Walked from the Keep's floor, the walk starts on a surface inside that band; without a band it starts 46 yd
	-- below, on the cheapest surface at the same spot, which is the shape of #602's walks under the city.
	local GOAL = { x = -8832.77, y = 478.623 } -- the flight master
	local heard = assert(Band.At(0, HERE.x, HERE.y), "the kept band is the measured one")
	local banded = assert(Path.FindSync(0, { x = HERE.x, y = HERE.y, band = heard }, GOAL))
	local today = assert(Path.FindSync(0, { x = HERE.x, y = HERE.y }, GOAL))
	assert(today[2].z == 106, "with no measurement the walk starts on the ground, as before: " .. tostring(today[2].z))
	assert(Band.Holds(heard, banded[2].z), "with the band it starts inside it: " .. tostring(banded[2].z))
	assert(banded[2].z > today[2].z, "and above the ground, not on it")

	-- A band that holds one floor only starts the walk on that floor.
	local tight = assert(Path.FindSync(0, { x = HERE.x, y = HERE.y, band = { lo = 148, hi = 156 } }, GOAL))
	assert(tight[2].z == 152, "the Keep's floor within it: " .. tostring(tight[2].z))

	-- A band that fits no surface is no measurement: the surfaces are all still there to start from.
	local other = assert(Path.FindSync(0, { x = HERE.x, y = HERE.y, band = { lo = 10, hi = 20 } }, GOAL))
	assert(other[2].z == 106, "a band with no surface in it leaves today's start: " .. tostring(other[2].z))
end

print("band: the creature ID in UnitGUID bounds the player's height, and a walk starts on the floor inside it: ok")

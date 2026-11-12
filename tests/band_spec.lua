-- Routing/Band.lua bounds the player's height from the client's own range checks to NPCs that stand still at a spawn
-- whose height Data/IdleSpawns.lua holds, so a walk from where they stand starts on the floor they are on: on
-- Stormwind Keep's upper floor, not on the ground 46 yards under it that today's search starts from and runs along
-- (#602's shape). An NPC is named by the creature ID in its GUID, because UnitPosition answers only for the player's
-- group (#737).
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
	"Data/IdleSpawns.lua",
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
-- refuses it.
local SECRET = {}
local spells = {
	[1] = { max = 10, friendly = true },
	[2] = { max = 30, friendly = true },
	[3] = { max = 40, friendly = true },
	[4] = { max = 30, friendly = false },
}
local player = { map = 0, x = 0, y = 0, z = 0 }
local units = {}
local asked -- every call the addon made, so a spec can check what it does not call
local restricted -- when set, the range check answers a value an addon may not read

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
		return { itemIndexOffset = 0, numSpellBookItems = #spells }
	end,
	GetSpellBookItemInfo = function(slot)
		return { spellID = slot }
	end,
}
_G.C_Spell = {
	GetSpellInfo = function(id)
		return { minRange = 0, maxRange = spells[id] and spells[id].max }
	end,
	IsSpellInRange = function(id, token)
		asked[#asked + 1] = id
		if restricted then
			return SECRET
		end
		local unit, spell = units[token], spells[id]
		if not (unit and spell and spell.friendly) then
			return nil
		end
		local dx, dy, dz = unit.x - player.x, unit.y - player.y, unit.z - player.z
		return dx * dx + dy * dy + dz * dz <= spell.max * spell.max
	end,
}
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
-- sqrt(R^2 - d^2), and the bounds intersect. The two spawns are planted over the Keep's cluster for the starter and
-- restored to the shipped data before the shipped-spawn cases below.
local HERE = { x = -9020, y = 870 } -- Stormwind Keep: surfaces at 106, 112 and 152 yd
local shipped = ns.IdleSpawns[0][5694]
ns.IdleSpawns[0][5694] = string.format("%d %d 100", HERE.x, HERE.y + 29)
ns.IdleSpawns[0][5695] = string.format("%d %d 100", HERE.x - 9, HERE.y)
player.map, player.x, player.y, player.z = 0, HERE.x, HERE.y, 100
units = {
	target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694) }, -- 29 yd off: the 30 yd check bounds 8.2 yd
	mouseover = { x = HERE.x - 9, y = HERE.y, z = 100, guid = GUID(5695) }, -- 9 yd off: the 10 yd check bounds 4.9
}
asked = {}
do
	local band = assert(Band.Measure(0, HERE.x, HERE.y), "both NPCs are in range, so there is a band")
	near(band.lo, 100 - sqrt(100 - 81) - 0.5, "the tighter 10 yd check bounds the bottom")
	near(band.hi, 100 + sqrt(100 - 81) + 0.5, "and the top")
	assert(Band.Holds(band, 100), "the player's own height is in the band")
	assert(Band.Holds(band, 97), "a surface a yard under the player is in the band")
	assert(not Band.Holds(band, 74), "the floor under the Keep is not")
	assert(not Band.Holds(band, 106), "nor the one above the bound")
	assert(asked[1] == 2 and asked[2] == 1, "the tightest range is the only one that has to answer")
end

-- No NPC in range is no measurement at all, and the walk keeps today's behaviour.
do
	units = {}
	Band.Forget()
	assert(Band.Measure(0, HERE.x, HERE.y) == nil, "no unit answers, so no band")
	assert(Band.At(0, HERE.x, HERE.y) == nil, "and nothing is kept")
end

-- A creature with two idle spawns on the map is not measured: which spawn the client's answer is about is unknown.
-- The row the generator writes holds one triple per spawn.
do
	ns.IdleSpawns[0][5696] = string.format("%d %d 100 %d %d 100", HERE.x, HERE.y + 29, HERE.x - 9, HERE.y)
	units = { target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5696) } }
	Band.Forget()
	assert(Band.Measure(0, HERE.x, HERE.y) == nil, "two spawns leave no single height to bound")
	ns.IdleSpawns[0][5696] = nil
end

-- A creature with no idle spawn on this map is not measured, and neither is one whose GUID the client withholds.
do
	units = {
		target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(999999) },
		mouseover = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694), secret = true },
	}
	asked = {}
	Band.Forget()
	assert(Band.Measure(0, HERE.x, HERE.y) == nil, "an unknown creature and a secret GUID measure nothing")
	assert(asked[1] == nil, "and no range check is asked")
end

-- A unit the client names as a player, a corpse and a hostile creature are not measured.
do
	units = {
		target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694), player = true },
		mouseover = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694), dead = true },
		nameplate1 = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694), hostile = true },
	}
	Band.Forget()
	assert(Band.Measure(0, HERE.x, HERE.y) == nil, "a player, a corpse and a hostile creature are not stationary NPCs")
end

-- A restricted answer is not read: the band is no measurement rather than a guess, and nothing else is called.
do
	units = { target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694) } }
	restricted = true
	Band.Forget()
	assert(Band.Measure(0, HERE.x, HERE.y) == nil, "a secret answer measures nothing")
	restricted = nil
end

-- The measured band is kept while the player stays in range of the spawns it came from, and dropped when they walk
-- away from one: no clock is involved.
do
	units = { target = { x = HERE.x, y = HERE.y + 29, z = 100, guid = GUID(5694) } }
	Band.Forget()
	local first = assert(Band.At(0, HERE.x, HERE.y), "measured at the Keep")
	assert(Band.At(0, HERE.x + 5, HERE.y) == first, "still the same band five yards on")
	player.x = HERE.x + 40
	assert(Band.At(0, player.x, HERE.y) == nil, "away from the spawn, the band is gone")
	player.x = HERE.x
end

-- The shipped Stormwind data, keyed by the Keep guard's creature ID: its idle spawn at (-9011, 877, 148) is 11.4 yd
-- from the courtyard point, so a 30 yd check bounds the player's height to 119.7..176.3 yd: the Keep's own floor fits
-- and the ground at 106 does not.
ns.IdleSpawns[0][5694] = shipped
ns.IdleSpawns[0][5695] = nil
do
	local NPC = { x = -9011, y = 877, z = 148 }
	player.map, player.x, player.y, player.z = 0, HERE.x, HERE.y, 152
	units = { target = { x = NPC.x, y = NPC.y, z = NPC.z, guid = GUID(5694) } }
	asked = {}
	Band.Forget()
	local band = assert(Band.Measure(0, HERE.x, HERE.y), "the Keep's spawn answers the 30 yd check")
	assert(asked[1] == 2, "the 10 yd check is skipped: the spawn is 11.4 yd off")
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

-- A party mage's capital portals, declared by the player because the client cannot read another player's spellbook.
-- Off by default, absent without another mage, and offered only when the portal shortens the journey.
local ns = { db = {}, charDB = {} }
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)
assert(loadfile("Data/Teleports.lua"))("ShortestPathForever", ns)
assert(loadfile("Data/Zones.lua"))("ShortestPathForever", ns)

local here = { map = 0, x = 0, y = 0 }
local group = { party = true, raid = false, size = 2, units = {} }
local names = {
	[1453] = "Stormwind",
	[1454] = "Orgrimmar",
	[1455] = "Ironforge",
	[1456] = "Thunder Bluff",
	[1457] = "Darnassus",
	[1458] = "Undercity",
}
local env = setmetatable({
	canaccessvalue = function()
		return true
	end,
	UnitClass = function(unit)
		local member = group.units[unit]
		return member and member.class, member and member.class
	end,
	UnitName = function(unit)
		local member = group.units[unit]
		return member and member.name
	end,
	UnitIsUnit = function(unit, other)
		return unit == other
	end,
	IsInGroup = function()
		return group.party
	end,
	IsInRaid = function()
		return group.raid
	end,
	GetNumGroupMembers = function()
		return group.size
	end,
	UnitFactionGroup = function()
		return ns.faction or "Alliance"
	end,
	C_Map = {
		GetMapInfo = function(uiMap)
			return names[uiMap] and { name = names[uiMap] }
		end,
	},
	C_Spell = {
		GetSpellName = function(spell)
			return "Teleport: " .. tostring(spell)
		end,
	},
	UNKNOWN = "Unknown",
}, { __index = _G })
env._G = env
setfenv(assert(loadfile("Transport/PartyPortals.lua")), env)("ShortestPathForever", ns)
assert(loadfile("Journey/JourneySteps.lua"))("ShortestPathForever", ns)
ns.JourneyPosition = function()
	return here.x, here.y, nil, here.map
end

local function point(map, x, y)
	return { map = map, x = x, y = y }
end

local function mage(name)
	group.units = { party1 = { name = name, class = "MAGE" } }
end

local function warrior()
	group.units = { party1 = { name = "Warrior", class = "WARRIOR" } }
end

-- The setting starts off: no portals, even with a mage in the group.
ns.db = {
	partyMagePortals = false,
	partyMageStormwind = true,
	partyMageIronforge = true,
	partyMageDarnassus = true,
	partyMageUndercity = true,
	partyMageThunderBluff = true,
	partyMageOrgrimmar = true,
}
mage("Magey")
assert(#ns.PartyPortalPlaces(here) == 0, "party mage portals are off by default")

-- On, but no mage: still nothing.
ns.db.partyMagePortals = true
warrior()
assert(#ns.PartyPortalPlaces(here) == 0, "no mage in the group, no party portal")

-- On with a mage: the Alliance capitals from the shipped mage teleports, never typed in here.
mage("Magey")
local places = ns.PartyPortalPlaces(here)
assert(#places == 3, #places)
local bySpell = {}
for _, place in ipairs(places) do
	assert(place.partyMage == "Magey", "the hop names the mage")
	assert(place.cast == 13000, "the ask and the cast are a fixed wait")
	bySpell[place.spell] = place
end
assert(bySpell[3561] and bySpell[3561].destination == "Stormwind")
assert(bySpell[3562] and bySpell[3562].destination == "Ironforge")
assert(bySpell[3565] and bySpell[3565].destination == "Darnassus")
assert(not bySpell[3563] and not bySpell[3566] and not bySpell[3567], "the other faction's capitals are not offered")

-- The player can say which portals the mage knows.
ns.db.partyMageIronforge = false
places = ns.PartyPortalPlaces(here)
local offered = {}
for _, place in ipairs(places) do
	offered[place.spell] = true
end
assert(#places == 2 and not offered[3562], "an unticked capital is not offered")
ns.db.partyMageIronforge = true

-- A far destination takes the portal and walks the last few yards; the step names the mage and the capital.
local stormwind = bySpell[3561]
local goal = point(stormwind.map, stormwind.x + 70, stormwind.y)
local plan = ns.Planner.Plan({
	from = here,
	to = goal,
	now = 0,
	walkSpeed = 7,
	faction = "Alliance",
	partyPortals = ns.PartyPortalPlaces(here),
})
assert(plan and #plan.legs == 2, "the portal wins over the long walk")
assert(plan.legs[1].mode == "teleport" and plan.legs[1].partyPortal, "the first leg is the party portal")
assert(plan.legs[1].partyPortal.partyMage == "Magey" and plan.legs[1].partyPortal.destination == "Stormwind")
assert(plan.arrive == 28000, "the fixed ask, the loading screen and the last 70 yards")
local step = ns.LegStep(plan.legs[1])
assert(step:find("Magey", 1, true) and step:find("Stormwind", 1, true), step)

-- A near destination is still a walk: the portal only joins when it shortens the journey.
plan = ns.Planner.Plan({
	from = here,
	to = point(0, 70, 0),
	now = 0,
	walkSpeed = 7,
	faction = "Alliance",
	partyPortals = ns.PartyPortalPlaces(here),
})
assert(plan and #plan.legs == 1 and plan.legs[1].mode == "walk", "a portal that does not help is left out")

-- Off again: the next plan has no hop.
ns.db.partyMagePortals = false
assert(#ns.PartyPortalPlaces(here) == 0, "the setting off drops the hop")
plan = ns.Planner.Plan({
	from = here,
	to = goal,
	now = 0,
	walkSpeed = 7,
	faction = "Alliance",
	partyPortals = ns.PartyPortalPlaces(here),
})
assert(plan and plan.legs[1].mode == "walk", "without the setting the journey walks")

-- The mage leaving the group drops it on the next plan too.
ns.db.partyMagePortals = true
warrior()
assert(#ns.PartyPortalPlaces(here) == 0, "the mage leaving drops the hop")
plan = ns.Planner.Plan({
	from = here,
	to = goal,
	now = 0,
	walkSpeed = 7,
	faction = "Alliance",
	partyPortals = ns.PartyPortalPlaces(here),
})
assert(plan and plan.legs[1].mode == "walk", "without the mage the journey walks")

-- A plan from somewhere else cannot ask the mage to come to it.
mage("Magey")
here = point(0, 1000, 1000)
assert(#ns.PartyPortalPlaces(point(0, 0, 0)) == 0, "only a plan from where the player stands asks the mage")

print("party portals: ok")

-- A Horde druid who knows only Zoram'gar and Orgrimmar casts Teleport: Moonglade. On the shipped flight network
-- Moonglade's flight master reaches Orgrimmar only through Everlook (and Azshara or Bloodvenom Post), and the client
-- routes connecting flights only through flight points you know, so no plan may fly on from Moonglade.
-- Reported on CurseForge by alex21xx (2026-10-10 and 2026-10-15) against the rule 1.15.0 replaced.
local ns = {}
for _, file in ipairs({
	"Transport/Model.lua",
	"Routing/Planner.lua",
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
	"Data/Teleports.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end

local MOONGLADE, EVERLOOK, BLOODVENOM, VALORMOK = 69, 53, 48, 44
local ORGRIMMAR, ZORAMGAR, THUNDER_BLUFF, CROSSROADS = 23, 58, 22, 25
for id, name in pairs({
	[MOONGLADE] = "Moonglade",
	[EVERLOOK] = "Everlook, Winterspring",
	[BLOODVENOM] = "Bloodvenom Post, Felwood",
	[VALORMOK] = "Valormok, Azshara",
	[ORGRIMMAR] = "Orgrimmar, Durotar",
	[ZORAMGAR] = "Zoram'gar Outpost, Ashenvale",
	[THUNDER_BLUFF] = "Thunder Bluff, Mulgore",
	[CROSSROADS] = "Crossroads, The Barrens",
}) do
	local node = ns.TaxiNodes[id]
	assert(node and node.name == name and node.faction == "Horde", "flight point " .. id .. " is Horde " .. name)
end

local spell
for _, teleport in ipairs(ns.Teleports) do
	if teleport.spell == 18960 then
		spell = teleport
	end
end
assert(spell and spell.to, "Teleport: Moonglade has a sourced landing")
local moonglade = {
	map = spell.to.map,
	x = spell.to.x,
	y = spell.to.y,
	z = spell.to.z,
	spell = spell.spell,
	cast = spell.cast,
}

local function Plan(from, to, known)
	return ns.Planner.Plan({
		from = from,
		to = to,
		now = 0,
		docks = ns.Docks,
		routes = ns.Routes,
		taxiNodes = ns.TaxiNodes,
		taxiPaths = ns.TaxiPaths,
		portals = ns.Portals,
		landmasses = ns.Landmasses,
		baked = ns.Walks,
		faction = "Horde",
		otherFaction = false,
		walkSpeed = 7,
		taxiKnown = known,
		anchors = {},
		teleports = { moonglade },
		teleportReady = { 0 },
	})
end

-- The flights a plan takes, each as its hops "from>to", and whether it leaves Moonglade.
local function Flights(plan)
	local flights, fromMoonglade = {}, false
	for _, leg in ipairs(plan.legs) do
		if leg.mode == "flight" then
			local hops = {}
			for _, hop in ipairs(leg.hops) do
				hops[#hops + 1] = { from = hop.from, to = hop.to }
			end
			flights[#flights + 1] = hops
			fromMoonglade = fromMoonglade or leg.from.id == MOONGLADE
		end
	end
	return flights, fromMoonglade
end

-- A flight may leave an unknown point only from the ground (walking there learns it, and a zero-length walk may be
-- dropped from the legs), never as a connection: every stop after the first, and the landing, must be known.
local function KnownConnections(plan, known)
	for _, hops in ipairs((Flights(plan))) do
		for index, hop in ipairs(hops) do
			assert(index == 1 or known[hop.from], "no flight connects through unknown point " .. hop.from)
			assert(known[hop.to], "no flight lands on unknown point " .. hop.to)
		end
	end
end

local starts = {
	{ map = 0, x = -9000, y = 0 }, -- Elwynn: the teleport is the way to Kalimdor's north
	{ map = 1, x = -4400, y = 200 }, -- Feralas
	{ map = 1, x = -7100, y = -3700 }, -- Tanaris
	{ map = 1, x = 6000, y = 500 }, -- Darkshore
}
for _, start in ipairs(starts) do
	assert(ns.Planner.Landmass(start, ns.Landmasses) == nil, "each start is on a mainland, not an island")
end
local goals = { ORGRIMMAR, ZORAMGAR, THUNDER_BLUFF, CROSSROADS, EVERLOOK, VALORMOK }

-- Moonglade unknown (the teleport lands beside it, so walking there learns it), and known: either way both its
-- flights land at points this character has not found, so nothing flies out of it.
local teleported = 0
for _, moongladeKnown in ipairs({ false, true }) do
	local known = { [ORGRIMMAR] = true, [ZORAMGAR] = true, [MOONGLADE] = moongladeKnown or nil }
	for _, start in ipairs(starts) do
		for _, goal in ipairs(goals) do
			local plan = assert(Plan(start, ns.TaxiNodes[goal], known))
			local _, fromMoonglade = Flights(plan)
			assert(not fromMoonglade, "no flight out of Moonglade to " .. goal)
			KnownConnections(plan, known)
			if plan.legs[1].mode == "teleport" then
				teleported = teleported + 1
			end
		end
	end
end
assert(teleported > 0, "the teleport is still taken where it is quickest")

-- From Elwynn, Orgrimmar is the zeppelin's, not a flight through Everlook and Azshara you cannot take.
local zeppelin = false
for _, leg in ipairs(Plan(starts[1], ns.TaxiNodes[ORGRIMMAR], { [ORGRIMMAR] = true, [ZORAMGAR] = true }).legs) do
	assert(leg.mode ~= "teleport", "no Moonglade detour to Orgrimmar")
	zeppelin = zeppelin or leg.mode == "zeppelin"
end
assert(zeppelin, "Elwynn to Orgrimmar takes the zeppelin")

-- Once Everlook and Valormok are known, the teleport, the walk that learns Moonglade's flight master and the
-- connecting flight from there are the quick way, so the refusal above is the unknown points' doing.
local known = { [ORGRIMMAR] = true, [ZORAMGAR] = true, [EVERLOOK] = true, [VALORMOK] = true }
local plan = Plan(starts[1], ns.TaxiNodes[ORGRIMMAR], known)
assert(plan.legs[1].mode == "teleport", "known connections make the Moonglade flight the quick way")
local _, fromMoonglade = Flights(plan)
assert(fromMoonglade, "the flight leaves Moonglade's flight master after walking there")
KnownConnections(plan, known)
print("known flights: no Moonglade flight through unknown points: ok")

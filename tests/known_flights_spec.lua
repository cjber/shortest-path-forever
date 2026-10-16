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
assert(ns.TaxiNodes[MOONGLADE].name == "Moonglade" and ns.TaxiNodes[MOONGLADE].faction == "Horde")
assert(ns.TaxiNodes[EVERLOOK].name == "Everlook, Winterspring" and ns.TaxiNodes[ORGRIMMAR].faction == "Horde")

local landing
for _, teleport in ipairs(ns.Teleports) do
	if teleport.spell == 18960 then
		landing = teleport.to
	end
end
assert(landing, "Teleport: Moonglade has a sourced landing")
local moonglade = { map = landing.map, x = landing.x, y = landing.y, z = landing.z, spell = 18960, cast = 10000 }

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

-- Every flight leaves from a point you know or are standing at (walking there learns it), and every stop it makes
-- on the way, and the one it lands at, is known.
local function Flies(plan)
	local flown = {}
	for index, leg in ipairs(plan.legs) do
		if leg.mode == "flight" then
			local previous = plan.legs[index - 1]
			assert(
				ns.known[leg.from.id] or (previous and previous.mode == "walk" and previous.to.id == leg.from.id),
				"a flight leaves only from a known point or one just walked to"
			)
			for _, hop in ipairs(leg.hops) do
				assert(ns.known[hop.to], "no flight stops at or lands on an unknown point: " .. hop.to)
				flown[#flown + 1] = hop.from .. ">" .. hop.to
			end
		end
	end
	return table.concat(flown, " ")
end

local froms = {
	{ map = 0, x = -9000, y = 0 }, -- Elwynn: the teleport is the way to Kalimdor's north
	{ map = 1, x = -4400, y = 200 }, -- Feralas
	{ map = 1, x = -7100, y = -3700 }, -- Tanaris
	{ map = 1, x = 6000, y = 500 }, -- Darkshore
}
local goals = { ORGRIMMAR, ZORAMGAR, THUNDER_BLUFF, CROSSROADS, EVERLOOK, VALORMOK }
ns.known = { [ORGRIMMAR] = true, [ZORAMGAR] = true }
local teleported = 0
for _, from in ipairs(froms) do
	for _, goal in ipairs(goals) do
		local plan = assert(Plan(from, ns.TaxiNodes[goal], ns.known))
		local flown = Flies(plan)
		if plan.legs[1].mode == "teleport" then
			teleported = teleported + 1
			assert(not flown:find(MOONGLADE .. ">", 1, true), "no flight out of Moonglade: " .. flown)
		end
		for _, unknown in ipairs({ EVERLOOK, BLOODVENOM, VALORMOK }) do
			assert(not (flown .. " "):find(">" .. unknown .. " ", 1, true), "no flight through " .. unknown)
		end
	end
end
assert(teleported > 0, "the teleport is still taken where it is quickest")

-- From Elwynn, Orgrimmar is the zeppelin's, not a flight through Everlook and Azshara you cannot take.
local plan = Plan(froms[1], ns.TaxiNodes[ORGRIMMAR], ns.known)
assert(plan.legs[1].mode ~= "teleport", "no Moonglade detour to Orgrimmar")

-- Once Everlook and Valormok are known, the same teleport and connecting flight is the quick way, so the refusal
-- above is the unknown points' doing, not a lost route.
ns.known = { [ORGRIMMAR] = true, [ZORAMGAR] = true, [MOONGLADE] = true, [EVERLOOK] = true, [VALORMOK] = true }
plan = Plan(froms[1], ns.TaxiNodes[ORGRIMMAR], ns.known)
assert(plan.legs[1].mode == "teleport", "known points make the Moonglade flight the quick way")
local flown = Flies(plan)
assert(flown:find(MOONGLADE .. ">", 1, true) == 1, "the flight leaves Moonglade: " .. flown)

-- Known Moonglade alone still flies nowhere: both its flights land at points this character has not found.
ns.known = { [ORGRIMMAR] = true, [ZORAMGAR] = true, [MOONGLADE] = true }
for _, goal in ipairs(goals) do
	Flies(assert(Plan(froms[1], ns.TaxiNodes[goal], ns.known)))
end
print("known flights: no Moonglade flight through unknown points: ok")

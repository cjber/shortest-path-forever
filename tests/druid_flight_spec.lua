-- Nighthaven's druid flight masters fly a druid, by gossip, to Rut'theran Village (Alliance) or Thunder Bluff (Horde),
-- with no flight point to discover and whether or not the landing is known. Reported for an Alliance druid whose plans
-- out of Moonglade ignored the flight to Rut'theran (#1010).
local ns = {}
for _, file in ipairs({
	"Transport/Model.lua",
	"Routing/Savings.lua",
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

local SILVA, BUNTHEN, RUTTHERAN, THUNDER_BLUFF, MOONGLADE = 62, 63, 27, 22, 49
assert(
	ns.TaxiNodes[SILVA].class == "DRUID" and ns.TaxiNodes[SILVA].faction == "Alliance",
	"Silva serves Alliance druids"
)
assert(
	ns.TaxiNodes[BUNTHEN].class == "DRUID" and ns.TaxiNodes[BUNTHEN].faction == "Horde",
	"Bunthen serves Horde druids"
)

local spell
for _, teleport in ipairs(ns.Teleports) do
	if teleport.spell == 18960 then
		spell = teleport
	end
end
local landing = assert(spell and spell.to, "Teleport: Moonglade has a sourced landing")

local function Plan(from, to, faction, class, known, teleports)
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
		faction = faction,
		class = class,
		otherFaction = false,
		walkSpeed = 7,
		taxiKnown = known,
		anchors = {},
		teleports = teleports or {},
		teleportReady = teleports and { 0 } or {},
	})
end

local function Flights(plan)
	local flights = {}
	for _, leg in ipairs(plan.legs) do
		if leg.mode == "flight" then
			local hops = {}
			for _, hop in ipairs(leg.hops) do
				hops[#hops + 1] = hop.from .. ">" .. hop.to
			end
			flights[#flights + 1] = table.concat(hops, ",") .. (leg.gossip and " gossip" or "")
		end
	end
	return table.concat(flights, " ")
end

local here = { map = landing.map, x = landing.x, y = landing.y, z = landing.z }
-- No flight point known at all, as in the report: the druid flight needs none.
for _, case in ipairs({
	{ "Alliance", RUTTHERAN, "62>27 gossip" },
	{ "Horde", THUNDER_BLUFF, "63>22 gossip" },
}) do
	local faction, goal, expected = case[1], case[2], case[3]
	local plan = assert(Plan(here, ns.TaxiNodes[goal], faction, "DRUID", {}), faction .. " druid plans")
	assert(Flights(plan) == expected, faction .. " druid flies " .. expected .. ", got " .. Flights(plan))
	local other = assert(Plan(here, ns.TaxiNodes[goal], faction, "HUNTER", {}), faction .. " hunter plans")
	assert(Flights(other) == "", faction .. " hunter never takes the druid flight, got " .. Flights(other))
	local unset = assert(Plan(here, ns.TaxiNodes[goal], faction, nil, {}))
	assert(Flights(unset) == "", "a plan that names no class never takes a class flight")
end

-- From far away the druid casts Teleport: Moonglade, walks to Silva and flies home.
local teleport =
	{ map = landing.map, x = landing.x, y = landing.y, z = landing.z, spell = spell.spell, cast = spell.cast }
local plan = assert(Plan(ns.TaxiNodes[MOONGLADE], ns.TaxiNodes[RUTTHERAN], "Alliance", "DRUID", {}, { teleport }))
assert(
	Flights(plan):find("62>27 gossip", 1, true),
	"the Moonglade teleport leads to the druid flight: " .. Flights(plan)
)

-- The gossip flight lands on the ground: it never continues as a connecting hop of a flight-map journey.
for _, goal in ipairs({ 26, 28, 41, 456 }) do
	if ns.TaxiNodes[goal] then
		local onward =
			assert(Plan(here, ns.TaxiNodes[goal], "Alliance", "DRUID", { [RUTTHERAN] = true, [goal] = true }))
		assert(not Flights(onward):find("62>27,", 1, true), "a gossip flight is its own leg: " .. Flights(onward))
	end
end

-- Landing at a flight master the druid has never visited is standing beside it: they may fly on from there, as
-- they would after walking up to it.
local CROSSROADS = 25
local onward = assert(Plan(here, ns.TaxiNodes[CROSSROADS], "Horde", "DRUID", { [CROSSROADS] = true }))
assert(
	Flights(onward) == "63>22 gossip 22>25",
	"the druid flies on from an unknown gossip landing: " .. Flights(onward)
)

print("druid flight: Nighthaven flies druids home with no flight point known: ok")

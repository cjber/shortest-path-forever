-- The reported Stormwind to Wailing Caverns journey (#465): a flight point the client has reported, Booty Bay,
-- makes the route walk to Stormwind's unknown flight master, learn it there, and fly and sail instead of running
-- the whole way. With no flight point known, the same journey walks to the boat, and the plan says an unknown
-- flight point would have shortened it.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
for _, file in ipairs({
	"Transport/Model.lua",
	"Routing/Savings.lua",
	"Routing/Planner.lua",
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Teleports.lua",
	"Data/Walks.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end

local function Plan(from, to, known, faction, teleport)
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
		faction = faction or "Alliance",
		otherFaction = false,
		walkSpeed = 7,
		taxiKnown = known,
		anchors = {},
		teleports = { teleport },
		teleportReady = { teleport and teleport.ready },
		teleportMinimumSavings = teleport and teleport.minimum,
		unknownFlightNotice = true,
	})
end

local function Has(plan, mode)
	for _, leg in ipairs(plan.legs) do
		if leg.mode == mode then
			return true
		end
	end
	return false
end

local STORMWIND, BOOTY_BAY = 2, 19
local entrance = assert(ns.Entrances[43], "Wailing Caverns has a door")
assert(entrance.name == "Wailing Caverns" and entrance.map == 1, "the door is on Kalimdor")
local from = { map = 0, x = -8800, y = 800, label = "Stormwind" }

-- No flight point is known: the run to Booty Bay's boat is the route, and the plan reports the unknown flight
-- point that would have shortened it.
local walked = assert(Plan(from, entrance, {}))
assert(not Has(walked, "flight"), "no known flight point means no flight")
assert(walked.unknownFlight == true, "the plan explains the flight point it could not use")
assert(walked.unknownFlightMaps and walked.unknownFlightMaps[0], "the faster flight is in the Eastern Kingdoms")
local first = walked.legs[1]
assert(
	first.mode == "walk" and first.to.kind == "dock" and first.yards > 5000,
	"with no flight point the whole way to the boat is walked"
)

-- A class teleport dropped for saving less than its minimum stays dropped when looking for the unknown flight
-- point: it lands at the door 800 s in, before the flight would, yet the walk still reports the flight.
local rune = { map = 1, x = entrance.x, y = entrance.y, spell = 3565, cast = 10000, ready = 800000, minimum = 600 }
local kept = assert(Plan(from, entrance, {}, nil, rune))
assert(not Has(kept, "teleport"), "the teleport saves less than its minimum")
assert(kept.unknownFlightMaps and kept.unknownFlightMaps[0], "the dropped teleport does not hide the faster flight")

-- Knowing only Booty Bay is enough for the feature (#868): the route walks to Stormwind's undiscovered flight
-- master, learns it there, then flies to the known Booty Bay. Only the departure point is learned in person; the
-- landing is known, so the flight is one the client will let the character take.
local booty = assert(Plan(from, entrance, { [BOOTY_BAY] = true }))
assert(Has(booty, "flight"), "walking to the unknown departure learns it and flies")
assert(
	booty.legs[1].mode == "walk"
		and booty.legs[1].to.kind == "taxi"
		and booty.legs[1].to.id == STORMWIND
		and booty.legs[1].to.undiscovered,
	"the route first walks to Stormwind's undiscovered flight master"
)
assert(booty.legs[2].mode == "flight" and booty.legs[2].to.id == BOOTY_BAY, "then flies from the learned point")
assert(not booty.unknownFlight, "a plan that flies needs no unknown-flight notice")
assert(booty.arrive < walked.arrive, "learning Stormwind beats walking the whole way")

-- With Stormwind also known the same journey walks to its flight master and flies to Booty Bay, so the long run
-- to the boat is gone. Learning the unknown point on the way costs no time.
local known = assert(Plan(from, entrance, { [STORMWIND] = true, [BOOTY_BAY] = true }))
assert(Has(known, "flight"), "both known flight points fly")
assert(known.legs[1].to.kind == "taxi" and known.legs[1].to.id == STORMWIND, "the flight starts at Stormwind")
assert(known.arrive == booty.arrive, "the learned departure takes the same route as a known one")
assert(known.arrive < walked.arrive, "a known taxi node beats the walked leg")

local gromgol = { map = 0, x = -12414, y = 146, label = "Grom'gol" }
local lochModan = { map = 0, x = -5400, y = -2900, label = "Loch Modan" }
local hordeWalk = assert(Plan(gromgol, lochModan, {}, "Horde"))
assert(not Has(hordeWalk, "flight"), "with nothing known the Horde route to Loch Modan has no flight")
assert(
	hordeWalk.unknownFlightMaps and hordeWalk.unknownFlightMaps[0] and not hordeWalk.unknownFlightMaps[1],
	"a faster Eastern Kingdoms flight is reported, Kalimdor is not"
)
local stroll = assert(Plan(gromgol, { map = 0, x = -12300, y = 200, label = "Grom'gol" }, {}, "Horde"))
assert(not stroll.unknownFlightMaps, "a short walk no flight would beat reports no continent")

print("known taxi walk: a known flight point flies instead of walking: ok")

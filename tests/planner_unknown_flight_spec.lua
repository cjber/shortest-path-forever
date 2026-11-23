-- Issue #868: walk to an undiscovered flight master, learn it there, then fly from it when that is quicker. Only
-- the departure walked to becomes usable; a landing or connecting point still has to be known (#857). The
-- fixtures are hand-made offline plans, so they need no client and no walking maps.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Savings.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/PlanBounds.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/LegPoints.lua"))("ShortestPathForever", ns)

local function point(x)
	return { map = 1, x = x, y = 0 }
end

local function Plan(fixture)
	return ns.Planner.Plan(fixture)
end

local function Flight(plan)
	for _, leg in ipairs(plan.legs) do
		if leg.mode == "flight" then
			return leg
		end
	end
end

-- Start --walk--> unknown 1 --flight--> known 2 --walk--> goal. The same walk without the flight is much longer.
local function Faster(flightSeconds)
	return {
		from = point(0),
		to = point(10100),
		now = 0,
		walkSpeed = 7,
		faction = "Alliance",
		taxiNodes = { [1] = point(1000), [2] = point(10000) },
		taxiPaths = { { from = 1, to = 2, seconds = flightSeconds } },
		taxiKnown = { [2] = true },
		exactMaps = { [1] = true },
		walks = {
			{ from = point(0), to = point(1000), cost = 1000 },
			{ from = point(0), to = point(10000), cost = 10000 },
			{ from = point(0), to = point(10100), cost = 10100 },
			{ from = point(10000), to = point(10100), cost = 100 },
		},
		unknownFlightNotice = true,
	}
end

-- The fixture's flight leaves the flight master the route walks to. Its landing is known, so it is allowed.
local quick = assert(Plan(Faster(100)))
local approach = quick.legs[1]
assert(
	approach.mode == "walk" and approach.to.id == 1 and approach.to.undiscovered,
	"the route walks to the undiscovered departure and learns it there"
)
local flight = assert(Flight(quick))
assert(flight.from.id == 1 and flight.to.id == 2, "the flight leaves the learned point for the known one")
assert(not quick.unknownFlight, "a route that flies needs no unknown-flight notice")

-- The same unknown master is not worth a detour when its flight is slower than walking straight there.
local slow = assert(Plan(Faster(10000)))
assert(#slow.legs == 1 and slow.legs[1].mode == "walk", "a slower flight leaves the walk alone")
assert(slow.legs[1].yards == 10100, "the plan walks the whole way")
assert(not Flight(slow), "no flight is planned when it is not faster")

-- Start --walk--> unknown 1 --flight--> unknown 2 --flight--> known 3 --walk--> goal. Only unknown 1 was walked
-- to, so its flights cannot continue through unknown 2: the route walks all the way and says a flight would help.
local function Chain(secondKnown)
	return {
		from = point(0),
		to = point(10100),
		now = 0,
		walkSpeed = 7,
		faction = "Alliance",
		taxiNodes = { [1] = point(1000), [2] = point(2000), [3] = point(10000) },
		taxiPaths = {
			{ from = 1, to = 2, seconds = 10 },
			{ from = 2, to = 3, seconds = 10 },
		},
		taxiKnown = { [2] = secondKnown or nil, [3] = true },
		exactMaps = { [1] = true },
		walks = {
			{ from = point(0), to = point(1000), cost = 1000 },
			{ from = point(1000), to = point(2000), cost = 1000 },
			{ from = point(2000), to = point(10000), cost = 8000 },
			{ from = point(0), to = point(10000), cost = 10000 },
			{ from = point(0), to = point(10100), cost = 10100 },
			{ from = point(10000), to = point(10100), cost = 100 },
		},
		unknownFlightNotice = true,
	}
end

local guarded = assert(Plan(Chain(false)))
assert(not Flight(guarded), "a flight cannot connect through an undiscovered point")
assert(#guarded.legs == 1 and guarded.legs[1].yards == 10100, "the route walks all the way instead")
assert(guarded.unknownFlight == true and guarded.unknownFlightMaps[1], "the plan reports the flight it could not use")
for _, leg in ipairs(guarded.legs) do
	assert(leg.mode ~= "flight", "no unknown point may be landed at or crossed")
end

-- With that connecting point known, the same walked-to departure flies: the refusal above is the unknown point's.
local connected = assert(Plan(Chain(true)))
local connecting = assert(Flight(connected))
assert(connecting.from.id == 1 and connecting.to.id == 3, "the learned departure reaches the known destination")
assert(#connecting.hops == 2, "the flight connects through the point that is known")
assert(
	connected.legs[1].mode == "walk" and connected.legs[1].to.id == 1 and connected.legs[1].to.undiscovered,
	"the departure is still the one walked to"
)

print("planner unknown flight: walk to learn the departure, never land on an unknown point: ok")

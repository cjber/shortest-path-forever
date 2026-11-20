-- Issue #537 with #868: a flight lands only at flight points the character knows, and a departure must be known
-- too unless the route walks up to that flight master and learns it there. A known arrival alone still must not
-- produce a flight from an unknown point the route never reaches on foot.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Savings.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/LegPoints.lua"))("ShortestPathForever", ns)

local function point(x)
	return { map = 1, x = x or 0, y = 0 }
end

-- One directed path between two flight points that both sit on the journey's endpoints.
local function Plan(known, fromX)
	return ns.Planner.Plan({
		from = point(fromX or 0),
		to = point(7000),
		now = 0,
		walkSpeed = 7,
		faction = "Alliance",
		taxiNodes = { point(0), point(7000) },
		taxiPaths = { { from = 1, to = 2, seconds = 10 } },
		taxiKnown = known,
	})
end

local function Has(plan, mode)
	for _, leg in ipairs(plan.legs) do
		if leg.mode == mode then
			return leg
		end
	end
end

-- (a) Nothing known: the journey walks, and plans no flight at all.
local empty = assert(Plan({}))
assert(not Has(empty, "flight"), "an empty known set plans no flight")
assert(Has(empty, "walk"), "the journey falls back to walking")

-- (b) A known arrival with an unknown departure walks to that master, learns it there and flies. A known
-- departure with an unknown arrival still walks: a landing point is never learned on the way.
local arrival = assert(Plan({ [2] = true }, -70))
local learned = Has(arrival, "flight")
assert(learned and learned.from.id == 1, "the walked-to departure flies to the known arrival")
local approach = arrival.legs[1]
assert(
	approach.mode == "walk" and approach.to.id == 1 and approach.to.undiscovered,
	"the route walks to the undiscovered departure first"
)
local departure = assert(Plan({ [1] = true }, -70))
assert(not Has(departure, "flight"), "a known departure cannot land at an unknown point")
assert(Has(departure, "walk"), "the route walks to the unknown arrival")

-- (c) Both endpoints known: the flight is planned, and it runs between the two known points.
local both = assert(Plan({ [1] = true, [2] = true }))
local flight = Has(both, "flight")
assert(flight and flight.from.id == 1 and flight.to.id == 2, "both known endpoints fly")
assert(not flight.from.undiscovered and not flight.to.undiscovered, "the flown endpoints are known")

print("flight endpoints: a flight lands on a known point and leaves a known or walked-to one: ok")

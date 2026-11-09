-- Issue #537: a flight can only be taken between flight points the character knows. Walking up to an unknown
-- flight master does not learn it, so a known arrival alone must never produce a flight leg.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)

local function point(x)
	return { map = 1, x = x or 0, y = 0 }
end

-- One directed path between two flight points that both sit on the journey's endpoints.
local function Plan(known)
	return ns.Planner.Plan({
		from = point(0),
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

-- (b) Only one endpoint known, in either direction: still no flight.
for _, known in ipairs({ { [1] = true }, { [2] = true } }) do
	local one = assert(Plan(known))
	assert(not Has(one, "flight"), "one known endpoint is not enough to fly")
	assert(Has(one, "walk"), "one known endpoint still walks")
end

-- (c) Both endpoints known: the flight is planned, and it runs between the two known points.
local both = assert(Plan({ [1] = true, [2] = true }))
local flight = Has(both, "flight")
assert(flight and flight.from.id == 1 and flight.to.id == 2, "both known endpoints fly")
assert(not flight.from.undiscovered and not flight.to.undiscovered, "the flown endpoints are known")

print("flight endpoints: a flight needs both points known: ok")

-- A journey's end releases the walking maps (Path.ClearCaches), but keeps each endpoint's connection to its cluster:
-- a flight master's entrance costs are the same for the next journey, and connecting one searches its whole cluster
-- (#1080). The kept costs give the same answer as fresh ones.
local ns = {}
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
assert(loadfile("Data/Taxi.lua"))("ShortestPathForever", ns)
assert(loadfile("tools/load_nav.lua"))(0)
local Path = ns.Path

local frame
Path.after = function(fn)
	frame = fn
end
Path.budget = 3
local function probe(from, to)
	local answer
	local job = Path.FindCost(0, from, to, function(c)
		answer = c
	end)
	while frame do
		local fn = frame
		frame = nil
		fn()
	end
	return answer, job.expansions
end

-- Stormwind's flight master to Goldshire, then to Sentinel Hill's.
local stormwind, sentinel = ns.TaxiNodes[2], ns.TaxiNodes[4]
local goldshire = { x = -9464, y = 62, z = 56 }
local first, cold = probe(stormwind, goldshire)
Path.ClearCaches()
local again, warm = probe(stormwind, goldshire)
assert(
	first and again == first,
	"a kept connection changed the walk: " .. tostring(first) .. " then " .. tostring(again)
)
assert(warm < cold, string.format("the next journey connected both ends again: %d then %d expansions", cold, warm))
-- A kept connection is only costs: a walk drawn from it searches its cluster again and still finds the same walk.
local points, cost = Path.FindSync(0, stormwind, goldshire)
assert(points and #points > 1 and math.abs(cost - first) < 1e-6, "the drawn walk disagrees with the kept cost")
Path.ClearCaches()
local farther = probe(stormwind, sentinel)
Path.ClearCaches()
local _, fresh = Path.FindSync(0, stormwind, sentinel)
assert(farther and math.abs(farther - fresh) < 1e-6, "kept and fresh connections disagree on the walk to Sentinel Hill")
print(string.format("path_kept_ends_spec: %d expansions cold, %d with kept connections", cold, warm))

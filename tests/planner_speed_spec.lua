local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)
local Plan = ns.Planner.Plan

local function point(map, x, y)
	return { map = map, x = x or 0, y = y or 0 }
end

local docks = { { map = 1, x = 100, y = 0 }, { map = 1, x = 6000, y = 0 } }
local baked = { [1] = { ["dock1 dock2"] = { 5000 } } }

local function options(from, to, speed, cache)
	return {
		from = from,
		to = to,
		now = 0,
		walkSpeed = speed,
		faction = "Alliance",
		docks = docks,
		baked = baked,
		cache = cache,
	}
end

local function bakedEdge(topology)
	for _, adjacent in ipairs(topology.edges) do
		for _, edge in ipairs(adjacent) do
			if edge.yards == 5000 then
				return edge
			end
		end
	end
end

local function sameRoute(a, b)
	if #a.legs ~= #b.legs or a.arrive ~= b.arrive or a.now ~= b.now then
		return false
	end
	for index, leg in ipairs(a.legs) do
		local other = b.legs[index]
		if
			leg.mode ~= other.mode
			or leg.depart ~= other.depart
			or leg.arrive ~= other.arrive
			or leg.yards ~= other.yards
			or leg.from.kind ~= other.from.kind
			or leg.to.kind ~= other.to.kind
		then
			return false
		end
	end
	return true
end

local from, to = point(1, 0, 0), point(1, 7000, 0)
local cache = {}
local slow = assert(Plan(options(from, to, 7, cache)), "speed 7 plans")
local topology = assert(cache.topology, "the first plan builds a topology")
local edge = assert(bakedEdge(topology), "the baked walk is in the graph")
assert(math.abs(edge.duration - 5000 / 7 * 1000) < 1e-6, "the baked walk scales at its build speed")

-- Every run speed reuses the one graph and still plans what a rebuilt graph plans.
for _, speed in ipairs({ 4, 7, 14, 25 }) do
	local warm = assert(Plan(options(from, to, speed, cache)), "speed " .. speed .. " plans on the shared graph")
	assert(cache.topology == topology, "a run speed change reuses the graph")
	assert(bakedEdge(topology) == edge, "the graph keeps its own edge objects")
	assert(math.abs(edge.duration - 5000 / speed * 1000) < 1e-6, "the baked walk rescaled to " .. speed .. " yd/s")
	local fresh = assert(Plan(options(from, to, speed, {})), "speed " .. speed .. " plans on a fresh graph")
	assert(sameRoute(warm, fresh), "speed " .. speed .. " matches a rebuilt plan")
end
assert(slow.arrive > Plan(options(from, to, 14, cache)).arrive, "faster running arrives sooner")

local water = options(from, to, 14, cache)
water.waterWalking = true
assert(Plan(water), "the water walk plans")
assert(cache.topology ~= topology, "a walk mode change rebuilds the graph")
print("planner_speed_spec: ok")

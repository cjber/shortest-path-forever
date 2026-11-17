-- Partial paint remains a weight in the decoder and exact endpoint line costs.
local F = assert(loadfile("tests/nav_fixture.lua"))()
local ns = { RoadCells = { [49893] = { [1] = "AKAAEBAB/" } } }
-- Ten unpainted cells, four at 1/63, then one fully painted cell.
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
local G = ns.PathGrid
F.install(
	49893,
	F.format2({
		nx = 1,
		ny = 1,
		cell = {
			[0] = { [10] = { z = 20 }, [11] = { z = 20 }, [12] = { z = 20 }, [13] = { z = 20 }, [14] = { z = 20 } },
		},
		node = { { 0, 10, 1 } },
	})
)
local st = G.State(49893)
local road = assert(G.roads(st, 0))
assert(road[10] == 1 / 63, "faint paint must decode as coverage, not boolean road")
assert(road[14] == 1 and road[9] == nil and road[15] == nil, "run boundaries preserve unpainted ground")
assert(G.grid(st, 0))
for _, coverage in ipairs({ 0, 0.1, 0.25, 0.5, 1 }) do
	st.road[0] = { [10] = coverage > 0 and coverage or nil }
	local _, _, cost = G.toward(st, { roadFactor = 3 }, 0, 10, 0.5, 10.1, 0.5, 10.9, false, nil, nil, true)
	-- real=true deliberately removes preference; the budgeted call measures weighted cost.
	assert(cost and math.abs(cost - 0.8 * st.cs) < 1e-8)
	local _, _, weighted = G.toward(st, { roadFactor = 3 }, 0, 10, 0.5, 10.1, 0.5, 10.9, false, nil, 100)
	assert(
		weighted and math.abs(weighted - 0.8 * st.cs * (1 + 2 * (1 - coverage))) < 1e-8,
		"connector uses fractional coverage"
	)
end

-- Baked crossing ratios charge the destination's fractional paint in both modes.
assert(loadfile("Routing/Path.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/PathJobs.lua"))("ShortestPathForever", ns)
local MAP = 49894
F.install(
	MAP,
	F.format2({
		nx = 2,
		ny = 1,
		cell = {
			[66] = { [10] = { z = 20 } },
			[67] = { [10] = { z = 20 } },
		},
		node = {
			{ 66, 10, 1, out = { { 67, 10, 16, 16 } } },
			{ 67, 10, 1, out = { { 66, 10, 16, 16 } } },
		},
	})
)
local crossing = G.State(MAP)
crossing.road[0] = { [66 * 67 + 10] = 1 }
crossing.road[1] = { [10] = 16 / 63 }
local baked = ns.Path.BakeRoadEdges(MAP)
assert(baked[0] == "vAvA", "crossing into partial paint has 47/63 off-road cost")
assert(baked[1] == "AAAA", "reverse crossing enters fully painted ground")

print("road_coverage_spec: ok")

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

-- Trail records are matched to one surface and combined with the cell's painted coverage.
local TRAILS = 49896
ns.RoadCells[TRAILS] = { [1] = "AKAADB" }
-- Upper floor, base, exactly the same-layer limit above the upper floor, then two levels in one unpainted cell.
local records = { [1] = "AAKgHjAALgFCAAMgITAANgHhAANgFD" }
F.install(
	TRAILS,
	F.format2({
		nx = 1,
		ny = 1,
		cell = {
			[0] = { [10] = { z = 20 }, [11] = { z = 20 }, [12] = { z = 20 }, [13] = { z = 20 } },
		},
		floor = {
			{ 0, 10, 30, 1, 0 },
			{ 0, 11, 30, 1, 0 },
			{ 0, 12, 30, 1, 0 },
			{ 0, 13, 30, 1, 0 },
			{ 0, 13, 40, 1, 0 },
		},
	})
)
-- The baked node records decode without opening the cluster's walking grid.
-- Base trail at cell 11, explicit zero on its sibling, and strong trail on cell 10's upper floor.
local BAKED = 49897
F.install(BAKED, F.format2({ nx = 1, ny = 1, cell = {} }))
ns.RoadNodeCoverage = { [BAKED] = { [1] = "AALqBGJ/BGKA" } }
local precomputed = G.State(BAKED)
local coverage = assert(G.roads(precomputed, 0), "the runtime must read baked coverage")
assert(coverage[11] == 2 / 3 and coverage[4490] == 0 and coverage[4489] == 1)
assert(precomputed.val[0] == nil, "baked coverage needs no decoded surfaces")

local match = assert(loadfile("tools/bake_road_coverage.lua"))()
ns.RoadNodeCoverage[TRAILS] = match(G, TRAILS, records)
local layered = G.State(TRAILS)
assert(G.grid(layered, 0))
local function cover(cell, layer)
	return G.roadNode(layered, 0, assert(G.surface(layered, 0, cell, layer)))
end
assert(cover(10, 0) == 1 / 63 and cover(10, 1) == 1, "upper trail must preserve the base's paint")
assert(cover(11, 0) == 2 / 3 and cover(11, 1) == 1 / 63, "base trail must preserve the upper floor's paint")
assert(cover(12, 0) == 1 / 63 and cover(12, 1) == 1 / 63, "distant trail gives neither floor a discount")
assert(cover(13, 0) == 1 and cover(13, 1) == 1 / 3, "recorded weights stay separate on unpainted floors")
assert(cover(13, 2) == 0, "an unmatched floor must not inherit the base trail")

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

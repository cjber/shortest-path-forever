-- Endpoint budgets measure the actual directed connector, including its selected terminal layer and bare tail.
local F = assert(loadfile("tests/nav_fixture.lua"))()
local ns = {}
for _, name in ipairs({ "PathGrid", "Path", "PathJobs" }) do
	assert(loadfile("Routing/" .. name .. ".lua"))("ShortestPathForever", ns)
end
local G, Path = ns.PathGrid, ns.Path
local C, CS = 67, (1600 / 3) / 67
local id = 49200
local function install(cells, floors, links)
	id = id + 1
	F.install(id, F.format2({ nx = 1, ny = 1, cell = cells, floor = floors, link = links, node = { { 10, 10, 1 } } }))
	local st = G.State(id)
	assert(G.grid(st, 0))
	return st, id
end
local function near(a, b)
	assert(a and math.abs(a - b) < 1e-9, tostring(a) .. " vs " .. b)
end
local function point(x, y, z)
	return { x = x * CS, y = y * CS, z = z or 20 }
end

-- A dry floor over water and a wet floor over land charge the selected layer in both directions.
for _, wet in ipairs({ false, true }) do
	local st = install({ [10] = { [10] = { z = 0, water = not wet } } }, { { 10, 10, 30, wet and 2 or 1, 0 } })
	local floorNode = C * C
	st.road[0] = { [10 * C + 10] = 1 }
	assert(G.roads(st, 0)[G.cellOf(st, 0, floorNode)], "selected floor uses its cluster-0 road cell")
	for _, x in ipairs({ 10.1, 10.9 }) do
		local exact = 0.4 * CS * (wet and 3 or 1)
		local k, n, time =
			G.toward(st, { swim = 3, roadFactor = 3 }, 0, floorNode, x, 10.5, 10.5, 10.5, true, nil, nil, true)
		assert(k == 0 and n == floorNode)
		near(time, exact)
		local rk, rn, reverseTime =
			G.toward(st, { swim = 3, roadFactor = 3 }, 0, floorNode, 10.5, 10.5, x, 10.5, true, nil, nil, true)
		assert(rk == 0 and rn == floorNode)
		near(reverseTime, exact)
		assert(G.toward(st, { swim = 3, roadFactor = 3 }, 0, floorNode, x, 10.5, 10.5, 10.5, true, nil, exact + 1e-10))
		assert(not G.toward(st, { swim = 3 }, 0, floorNode, x, 10.5, 10.5, 10.5, true, nil, exact / 2))
	end
	local _, _, walking = G.toward(st, { swim = 1 }, 0, floorNode, 10.1, 10.5, 10.5, 10.5, true, nil, nil, true)
	near(walking, 0.4 * CS)
end

-- Destination-surface intervals differ by direction at a land/water boundary. The terminal tail is charged too.
local st = install({ [10] = { [10] = { z = 20 } }, [11] = { [10] = { z = 20, water = true } } })
local land, water = 10 * C + 10, 11 * C + 10
local k, n, forward = G.toward(st, { swim = 3 }, 0, land, 10.2, 10.5, 11.5, 10.5, true, nil, nil, true)
assert(k == 0 and n == water)
near(forward, 1.3 * CS * 3)
local _, _, backward = G.toward(st, { swim = 3 }, 0, water, 11.5, 10.5, 10.2, 10.5, true, nil, nil, true)
near(backward, 1.3 * CS)
local _, _, walking = G.toward(st, { swim = 1 }, 0, land, 10.2, 10.5, 11.5, 10.5, true, nil, nil, true)
near(walking, 1.3 * CS)
assert(not G.toward(st, { swim = 3 }, 0, land, 10.2, 10.5, 11.5, 10.5, false, nil, nil, true))
assert(not G.toward(st, {
	factor = function()
		return 4
	end,
}, 0, land, 10.2, 10.5, 11.5, 10.5, true, 1, nil, true))
st.road[0] = { [land] = 1 }
assert(not G.toward(st, { swim = 3, roadFactor = 3 }, 0, land, 10.2, 10.5, 11.5, 10.5, true, nil, forward + 1e-10))
local _, _, reference =
	G.toward(st, { swim = 3, roadFactor = 3 }, 0, land, 10.2, 10.5, 11.5, 10.5, true, nil, nil, true)
near(reference, forward)

-- Multi-cell floor traversal follows its links and charges the reached wet layer, not the dry base below it.
local layered = install({ [10] = { [10] = { z = 0 } }, [11] = { [10] = { z = 0 } } }, {
	{ 10, 10, 30, 1, 1 },
	{ 11, 10, 30, 2, 2 },
})
local lk, ln, elapsed = G.toward(layered, { swim = 3 }, 0, C * C, 10.2, 10.5, 11.5, 10.5, true, nil, nil, true)
assert(lk == 0 and ln == C * C + 1)
near(elapsed, 1.3 * CS * 3)

-- A one-way connector cannot become a reverse reference, even when a surface exists at each end.
local directed = install(
	{ [10] = { [10] = { z = 32, flags = 1 } }, [11] = { [10] = { z = 20 } } },
	nil,
	{ { 10, 10, 1, 0, 16 } }
)
assert(G.toward(directed, {}, 0, land, 10.5, 10.5, 11.5, 10.5, false, nil, nil, true))
local dk, dn, dt = G.toward(directed, {}, 0, water, 11.5, 10.5, 10.5, 10.5, false, nil, nil, true)
assert(dk == nil and dn == false and dt == nil)

-- Bare continuation is dry and off-road, including its final interval. A closed cell with any surface is blocked.
local bare, bareMap = install({ [10] = { [10] = { z = 20 } } })
bare.road[0] = { [land] = 1 }
local bk, bn, bt = G.toward(bare, { roadFactor = 3 }, 0, land, 10.5, 10.5, 12.2, 10.5, false, nil, nil, true)
assert(bk == nil and bn == true)
near(bt, 1.7 * CS)
local _, accepted = G.toward(bare, { roadFactor = 3 }, 0, land, 10.5, 10.5, 12.2, 10.5, false, nil, bt + 1e-10)
assert(accepted == false, "bare cells must not borrow the last road surface")
local _, _, charged = G.toward(bare, { roadFactor = 3 }, 0, land, 10.5, 10.5, 12.2, 10.5, false, nil, bt * 3 + 1e-10)
near(charged, bt * 3)
local blocked = install({ [10] = { [10] = { z = 20, flags = 1 } }, [11] = { [10] = { z = 40 } } })
local ck, cn, ct = G.toward(blocked, {}, 0, land, 10.5, 10.5, 11.5, 10.5, false, nil, nil, true)
assert(ck == nil and cn == false and ct == nil)

-- Whole Path n=1: measured endpoint connectors permit the direct chord without adding centres.
local _, singleMap = install({ [10] = { [10] = { z = 20 } } })
local pts, cost = Path.FindSync(singleMap, point(10.1, 10.5), point(10.9, 10.5))
assert(pts and #pts == 2, "one-node path keeps its direct chord")
near(cost, 0.8 * CS)
-- A snapped bare start has no directed on-mesh reference. Keep the selected centre and the valid fallback.
local snapped, snappedCost = Path.FindSync(bareMap, point(11.1, 10.5), point(10.1, 10.5))
assert(snapped and #snapped == 3)
near(snappedCost, CS)
near(snapped[2].x, 10.5 * CS)
local reverse, reverseCost = Path.FindSync(bareMap, point(10.1, 10.5), point(11.1, 10.5))
assert(reverse)
near(reverseCost, CS)
print("path_connector_spec: ok")

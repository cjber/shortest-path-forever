-- Trade District vendors stand on the street, z 94 to 102, over the sealed ground under Stormwind (z 60 to 76). The
-- walking map must give each of their cells the street as a surface: a cell holding only the ground under the city
-- makes Floor settle the player there, and the walk to the flight master starts under the street and loops round
-- the city (#1046).
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Grid = ns.PathGrid
local state = Grid.State(0)

local function surfaces(x, y)
	local k, lc = Grid.locate(state, x, y)
	ns.Path.FindSync(0, { x = x, y = y }, { x = x + 1, y = y + 1 }) -- decodes the cluster
	local val, z, at = state.val[k], state.z[k], state.at[k]
	local out = {}
	if val and val[lc + 1] ~= 0 then
		out[#out + 1] = z[lc + 1]
	end
	local n = at and at[-(lc + 1)]
	while n and at[n + 1] == lc do
		out[#out + 1] = z[n + 1]
		n = n + 1
	end
	return out
end

-- Idle spawns from Data, with their heights.
local spawns = {
	{ -8935, 613, 100 },
	{ -8894, 611, 95 },
	{ -8885, 676, 100 },
	{ -8868, 674, 98 },
	{ -8851, 589, 94 },
	{ -8815, 660, 96 },
	{ -8814, 654, 96 },
}
local missing = {}
for _, s in ipairs(spawns) do
	local found = false
	for _, h in ipairs(surfaces(s[1], s[2])) do
		found = found or math.abs(h - s[3]) <= 5
	end
	if not found then
		missing[#missing + 1] = ("%d,%d z%d (%s)"):format(s[1], s[2], s[3], table.concat(surfaces(s[1], s[2]), ", "))
	end
end
assert(#missing == 0, "Trade District cells without the street: " .. table.concat(missing, "; "))

-- The reported walk: from the street by the bank's east side to the flight master, straight up the roost ramp.
local _, len = ns.Path.FindSync(0, { x = -8783, y = 593, z = 98 }, { x = -8832.77, y = 478.623, z = 109.616 })
assert(len and len < 250, len)
print("trade_district_floor_spec: ok")

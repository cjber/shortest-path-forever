-- A single underground cell must survive simplification between two uncovered endpoints.
local F = assert(loadfile("tests/nav_fixture.lua"))()
local ns = {}
for _, file in ipairs({ "PathCeiling", "PathGrid", "Path", "PathJobs" }) do
	assert(loadfile("Routing/" .. file .. ".lua"))("ShortestPathForever", ns)
end
local cells = {}
for x = 10, 14 do
	cells[x] = { [10] = { z = 20 } }
end
local map = F.format2({ nx = 1, ny = 1, cell = cells, node = { { 10, 10, 1 } } })
local symbols = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function varint(value)
	local out = ""
	repeat
		local digit = value % 32
		value = math.floor(value / 32)
		local symbol = digit + (value > 0 and 32 or 0) + 1
		out = out .. symbols:sub(symbol, symbol)
	until value == 0
	return out
end
local key = (12 * 67 + 10) * 64
map.ceiling = { varint(key + 1) .. varint(60 * 8 * 4) }
F.install(44, map)
local cs = ns.PathGrid.State(44).cs
local from = { x = 10.5 * cs, y = 10.5 * cs, z = 20 }
local to = { x = 14.5 * cs, y = 10.5 * cs, z = 20 }
local points, cost = ns.Path.FindSync(44, from, to)
assert(points and math.abs(cost - 4 * cs) < 1e-9, tostring(cost))
assert(not points[1].depth and not points[#points].depth)
for _, point in ipairs(points) do
	if point.depth == 40 then
		return
	end
end
error("the short cave was lost when the walk was simplified")

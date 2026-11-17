-- Exact candidate runtime; no replaced runtime functions. Analytical segment integration splits at every grid boundary.
local F = assert(loadfile("tests/nav_fixture.lua"))()
local ns = {}
for _, f in ipairs({ "PathGrid", "Path", "PathJobs" }) do
	assert(loadfile("Routing/" .. f .. ".lua"))("SPF", ns)
end
local C, CS = 67, (1600 / 3) / 67
local failures = 0
local function check(ok, msg)
	print((ok and "PASS " or "RED  ") .. msg)
	if not ok then
		failures = failures + 1
	end
end
local function point(x, y)
	return { x = x * CS, y = y * CS, z = 20 }
end
local function length(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
local function offLength(a, b, road)
	local ax, ay, bx, by = a.x / CS, a.y / CS, b.x / CS, b.y / CS
	local ts = { 0, 1 }
	for _, v in ipairs({ { ax, bx }, { ay, by } }) do
		if v[1] ~= v[2] then
			for n = math.floor(math.min(v[1], v[2])) + 1, math.floor(math.max(v[1], v[2])) do
				local t = (n - v[1]) / (v[2] - v[1])
				if t > 0 and t < 1 then
					ts[#ts + 1] = t
				end
			end
		end
	end
	table.sort(ts)
	local off = 0
	for i = 2, #ts do
		local t = (ts[i] + ts[i - 1]) / 2
		local x, y = math.floor(ax + (bx - ax) * t), math.floor(ay + (by - ay) * t)
		if not road[x * C + y] then
			off = off + (ts[i] - ts[i - 1]) * length(a, b)
		end
	end
	return off
end
for scenario, mode in ipairs({ "road", "water", "hazard", "chord" }) do
	local road = {}
	for x = 10, 20 do
		road[x * C + x] = 1
	end
	for x = 21, 30 do
		road[x * C + (mode == "chord" and x or 40 - x)] = 1
	end
	local cells = {}
	for x = 5, 40 do
		cells[x] = {}
		for y = 5, 40 do
			cells[x][y] = { z = 20, water = mode == "water" and not road[x * C + y] }
		end
	end
	local map = 45100 + scenario
	F.install(map, F.format2({ nx = 1, ny = 1, cell = cells, node = { { 5, 5, 1 } } }))
	local st = ns.PathGrid.State(map)
	st.road[0] = road
	local hz = {
		key = mode,
		roads = true,
		roadFactor = 3,
		Point = function(_, x, y)
			return mode == "hazard" and not road[math.floor(x / CS) * C + math.floor(y / CS)] and 10 or 1
		end,
		Chord = function()
			return 1
		end,
		Near = function()
			return mode == "hazard"
		end,
		Charged = function()
			return mode == "hazard"
		end,
	}
	local a, b = point(10.9, 10.1), point(30.9, mode == "chord" and 30.1 or 10.9)
	for direction = 1, 2 do
		local from, to = direction == 1 and a or b, direction == 1 and b or a
		local pts, cost = ns.Path.FindSync(map, from, to, false, hz)
		assert(pts, cost)
		local expected = 20 * math.sqrt(2) * CS
		check(
			math.abs(cost - expected) < 1e-8,
			mode .. " direction " .. direction .. " reported real travel cost " .. cost
		)
		if mode == "road" or mode == "chord" then
			for _, i in ipairs(mode == "chord" and { 2 } or { 2, #pts }) do
				local p, q = pts[i - 1], pts[i]
				local weighted = length(p, q) + 2 * offLength(p, q, road)
				-- Legal reference: endpoint -> own road-cell centre -> selected diagonal road -> next rendered centre.
				local reference
				if mode == "chord" then
					reference = expected
						+ length(from, point(math.floor(from.x / CS) + 0.5, math.floor(from.y / CS) + 0.5))
						+ length(to, point(math.floor(to.x / CS) + 0.5, math.floor(to.y / CS) + 0.5))
				else
					local endpoint = i == 2 and from or to
					local centre = point(math.floor(endpoint.x / CS) + 0.5, math.floor(endpoint.y / CS) + 0.5)
					local inner = i == 2 and q or p
					reference = length(endpoint, centre) + length(centre, inner)
				end
				check(
					weighted <= reference + 1e-8,
					("%s direction %d segment %d weighted %.6f within legal road reference %.6f"):format(
						mode,
						direction,
						i - 1,
						weighted,
						reference
					)
				)
			end
			if mode == "chord" then
				local weighted = 0
				for i = 2, #pts do
					weighted = weighted + length(pts[i - 1], pts[i]) + 2 * offLength(pts[i - 1], pts[i], road)
				end
				local reference = expected
					+ length(from, point(math.floor(from.x / CS) + 0.5, math.floor(from.y / CS) + 0.5))
					+ length(to, point(math.floor(to.x / CS) + 0.5, math.floor(to.y / CS) + 0.5))
				check(
					weighted <= reference + 1e-8,
					"whole drawn chord fallback stays within its complete real reference"
				)
			end
		else
			local off = 0
			for i = 2, #pts do
				off = off + offLength(pts[i - 1], pts[i], road)
			end
			check(off < 1e-8, mode .. " direction " .. direction .. " no illegal field crossing, offroad yards " .. off)
		end
	end
end
assert(failures == 0, "#891 whole Path.FindSync endpoint/chord road tradeoff failures: " .. failures)

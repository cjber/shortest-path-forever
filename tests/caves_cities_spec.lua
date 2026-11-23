-- Caves and cities (#1015): the hardest places to walk. Every ground spawn classic-db places on the two continents
-- stands on the walking map, and every capital service walks to and from the capital's hubs on a walk the router's
-- own search can follow, costing what the raw navmesh's shortest walk does (tests/fixtures/caves_cities.lua, from
-- tools/gen_caves_cities.py). Known failures are listed in tests/fixtures/caves_cities_known.lua; one that passes must
-- leave that list, so the list only shrinks.
--
-- CAVES_CITIES_RECORD=1 rewrites the known list from this run; CAVES_CITIES_DUMP=<file> writes every walk (cost,
-- reference, points) for a before and after diff. CAVES_CITIES_ROADS=1 dumps a second walk with Follow roads on;
-- the failure column and known list still describe the plain shortest walk.
local ns = {}
for _, file in ipairs({
	"Data/RoadCells.lua",
	"Data/RoadEdges.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
for _, map in ipairs({ 0, 1 }) do
	assert(loadfile("tools/load_nav.lua"))(map)
end
local Path, Grid = ns.Path, ns.PathGrid
Path.cacheKB = math.huge
local follow = assert(loadfile("tests/walk_follow.lua"))().new(ns)
local fixture = assert(loadfile("tests/fixtures/caves_cities.lua"))()
local known = assert(loadfile("tests/fixtures/caves_cities_known.lua"))()
local floor, sqrt, format = math.floor, math.sqrt, string.format

-- The grid walks eight directions, so a walk may be up to 1 / cos 22.5 degrees longer than the straight path, and
-- each end may stand its distance from its cell's centre off the grid.
local OCTILE = 1 / math.cos(math.pi / 8)
local function offset(st, x, y)
	local cx = st.x0 + (floor((x - st.x0) / st.cs) + 0.5) * st.cs
	local cy = st.y0 + (floor((y - st.y0) / st.cs) + 0.5) * st.cs
	return sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
end

-- A marked drop can cost fewer running yards than the distance between its drawn cell centers.
-- Credit that measured difference when checking the horizontal lower bound. Interior points name exact nodes.
local function dropCredit(st, points)
	local credit = 0
	local ks, nodes, costs = {}, {}, {}
	for i = 2, #points - 2 do
		local a, b = points[i], points[i + 1]
		if a.jump then
			local ak, ac = Grid.locate(st, a.x, a.y)
			local bk, bc = Grid.locate(st, b.x, b.y)
			local an = Grid.standing(st, ak, ac, a.z)
			local bn = Grid.standing(st, bk, bc, b.z)
			local gx, gy = floor((a.x - st.x0) / st.cs), floor((a.y - st.y0) / st.cs)
			local dx, dy = floor((b.x - st.x0) / st.cs) - gx, floor((b.y - st.y0) / st.cs) - gy
			local charge = math.huge
			for j = 1, Grid.neighbours(st, ak, an, gx, gy, dx, dy, true, ks, nodes, costs) do
				if ks[j] == bk and nodes[j] == bn and costs[j] > 0 then
					charge = math.min(charge, costs[j])
				end
			end
			assert(charge < math.huge, "marked drop has no matching link")
			credit = credit + math.max(0, sqrt(dx * dx + dy * dy) * st.cs - charge)
		end
	end
	return credit
end

local failed = {} -- key -> kind
local function key(...)
	return table.concat({ ... }, " ")
end

-- On build 1.60.1.71037 these three upper lift centers have no static navmesh within the fixture's interaction
-- range. The grid can still walk to the boarding lip. Check that approach even without a raw route reference.
local offMeshLiftCenter = {
	[key(0, 1596.2, 291.8, 55.7)] = true, -- west
	[key(0, 1595.3, 188.6, 55.7)] = true, -- east
	[key(0, 1544.2, 240.8, 55.7)] = true, -- south
}

for map, flat in pairs(fixture.spawns) do
	for i = 1, #flat, 3 do
		local x, y, z = flat[i], flat[i + 1], flat[i + 2]
		if not follow.stands(map, x, y, z) then
			failed[key("spawn", map, x, y, z)] = "off-surface"
		end
	end
end

local roadDump = os.getenv("CAVES_CITIES_ROADS") == "1"
local roadProfile = {
	roads = true,
	key = "caves-cities-roads",
	Point = function()
		return 1
	end,
	Chord = function()
		return 1
	end,
	Near = function()
		return false
	end,
	Charged = function()
		return false
	end,
}
local dump = os.getenv("CAVES_CITIES_DUMP")
dump = dump and assert(io.open(dump, "w"))
for _, w in ipairs(fixture.walks) do
	local name, map, reference = w[1], w[2], w[9]
	local from, to = { x = w[3], y = w[4], z = w[5] }, { x = w[6], y = w[7], z = w[8] }
	local points, cost = Path.FindSync(map, from, to)
	local kind
	if not points then
		kind = reference and "no-walk" or nil
	elseif
		not reference
		and not (offMeshLiftCenter[key(map, w[3], w[4], w[5])] or offMeshLiftCenter[key(map, w[6], w[7], w[8])])
	then
		kind = "no-reference"
	else
		local f = follow.check(map, points, from.z, to.z)
		if f then
			kind = f.kind
		elseif reference then
			local st = Grid.State(map)
			local slack = offset(st, from.x, from.y) + offset(st, to.x, to.y) + w[10]
			if cost + dropCredit(st, points) < reference - slack or cost > reference * OCTILE + slack then
				kind = "cost"
			end
		end
	end
	if kind then
		failed[key("walk", name)] = kind
	end
	if dump then
		if roadDump then
			points, cost = Path.FindSync(map, from, to, false, roadProfile --[[@as SPFHazards]])
		end
		local p = {}
		for _, q in ipairs(points or {}) do
			p[#p + 1] = format("%.2f,%.2f,%.2f", q.x, q.y, q.z or 0)
		end
		dump:write(
			format(
				"%s\t%s\t%s\t%s\t%s\n",
				name,
				kind or "ok",
				points and format("%.1f", cost) or "-",
				reference or "-",
				table.concat(p, " ")
			)
		)
	end
end
if dump then
	dump:close()
end

if os.getenv("CAVES_CITIES_RECORD") then
	local keys = {}
	for k in pairs(failed) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local out = assert(io.open("tests/fixtures/caves_cities_known.lua", "w"))
	out:write("-- Known caves and cities failures (tests/caves_cities_spec.lua): key -> kind. The list only shrinks.\n")
	out:write("-- rule-ignore: file-size-no-growth - generated by the spec, one row per failure\n")
	out:write("-- stylua: ignore\nreturn {\n")
	for _, k in ipairs(keys) do
		out:write(format("\t[%q] = %q,\n", k, failed[k]))
	end
	out:write("}\n")
	out:close()
	return
end

local new, fixed = {}, {}
for k, kind in pairs(failed) do
	if known[k] ~= kind then
		new[#new + 1] = format("%s: %s (known: %s)", k, kind, tostring(known[k]))
	end
end
for k, kind in pairs(known) do
	if not failed[k] then
		fixed[#fixed + 1] = format("%s: was %s, now passes: remove it from the known list", k, kind)
	end
end
table.sort(new)
table.sort(fixed)
assert(#new == 0, #new .. " new caves and cities failures:\n" .. table.concat(new, "\n", 1, math.min(#new, 40)))
assert(#fixed == 0, table.concat(fixed, "\n", 1, math.min(#fixed, 40)))

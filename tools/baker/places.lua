-- Prints, as JSON, the fixed places on one map where a player stands at a known height: flight masters, boat docks
-- and lift ends, portal ends and class teleport landings. gen_nav.py keeps the walking ground that holds one of them.
-- With "hops", prints the map's hops instead (ns.Hops) as [trigger x, y, z, radius, landing x, y, z].
-- With "lifts", prints only lift stop positions.
-- usage (from the repository root): luajit tools/baker/places.lua <map> [hops|lifts]
local map = assert(tonumber(arg[1]), "usage: luajit tools/baker/places.lua <map> [hops|lifts]")
local ns = {}
for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Teleports.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local out = {}
if arg[2] == "hops" then
	for _, hop in ipairs(ns.Hops) do
		local from, to = hop.from, hop.to
		if from.map == map then
			out[#out + 1] = ("[%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g]"):format(
				from.x,
				from.y,
				from.z,
				hop.radius,
				to.x,
				to.y,
				to.z
			)
		end
	end
	print("[" .. table.concat(out, ",") .. "]")
	return
end
local function Add(point)
	-- A place without a height cannot say which of the floors at its spot it stands on.
	if point and point.map == map and point.z then
		out[#out + 1] = ("[%.17g,%.17g,%.17g]"):format(point.x, point.y, point.z)
	end
end
if arg[2] == "lifts" then
	local liftDocks = {}
	for _, route in pairs(ns.Routes) do
		if route.kind == "lift" then
			for _, stop in ipairs(route.stops) do
				liftDocks[stop.dock] = true
			end
		end
	end
	for id in pairs(liftDocks) do
		local dock = ns.Docks[id]
		Add(dock.walk or dock)
	end
else
	for _, dock in pairs(ns.Docks) do
		Add(dock.walk or dock)
	end
	for _, node in pairs(ns.TaxiNodes) do
		Add(node)
	end
	for _, portal in ipairs(ns.Portals) do
		Add(portal.from)
		Add(portal.to)
	end
	for _, teleport in ipairs(ns.Teleports) do
		Add(teleport.to)
	end
end
table.sort(out)
print("[" .. table.concat(out, ",") .. "]")

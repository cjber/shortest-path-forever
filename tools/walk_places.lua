-- The fixed places the baked walks join (docks, flight masters, portal ends, class teleports' landings), per map, as
-- { key, point } in key order: shared by tools/bake_walks.lua and tools/bake_walk_zones.lua.
-- Use: local places = assert(loadfile("tools/walk_places.lua"))(ns)
local ns = ...
local places = {}
local function Add(key, point)
	places[point.map] = places[point.map] or {}
	table.insert(places[point.map], { key = key, point = point })
end
for id, dock in pairs(ns.Docks) do
	Add("dock" .. id, dock.walk or dock)
end
for id, node in pairs(ns.TaxiNodes) do
	Add("taxi" .. id, node)
end
for id, portal in ipairs(ns.Portals) do
	Add("portal" .. (id * 2 - 1), portal.from)
	Add("portal" .. id * 2, portal.to)
end
-- Where a class teleport lands; the bind point moves, so Journey measures its walks in game.
for _, teleport in ipairs(ns.Teleports) do
	if teleport.to then
		Add("teleport" .. teleport.spell, teleport.to)
	end
end
for _, list in pairs(places) do
	table.sort(list, function(a, b)
		return a.key < b.key
	end)
end
return places

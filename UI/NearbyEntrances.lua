---@type string, SPFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- Dungeons and raids in the Nearby services list (#688). Each instance whose door the client places outdoors is a
-- group of its own whose single place is the door, so the list's shortlist, ranking and menu read it exactly as they
-- read a vendor's spawn. Picking one starts the door stop JourneyInput.lua builds, which ends when the player goes in,
-- the same journey a quest inside the dungeon gets.

-- The client tracker's dungeon mark (UI/Art.lua's passage art), drawn through UI/Art.lua at its native size.
local ICON = "questlog-questtypeicon-dungeon"

-- The door of each instance by group key, and the groups, built once: the entrance data is fixed for the session.
local places = {}
---@type SPFNearbyGroup[]?
local groups

-- The door as a place: the door itself on its continent, and the outdoor zone map and position the client gives it,
-- which the ranking and the zone line read. nil where the client cannot place the door outdoors.
---@param instance integer
---@return SPFNearbyPlace?
local function Place(instance)
	local entrance = ns.Entrances and ns.Entrances[instance]
	if not entrance then
		return nil
	end
	local door = { map = entrance.map, x = entrance.x, y = entrance.y }
	local location = ns.Locate and ns.Locate(door)
	if not location then
		return nil
	end
	local name = GetRealZoneText and GetRealZoneText(instance)
	return {
		id = instance,
		name = name and name ~= "" and name or entrance.name,
		title = location.zone,
		map = location.uiMap,
		x = location.x,
		y = location.y,
		world = door,
		entrance = instance,
	}
end

local function Build()
	if groups then
		return groups
	end
	groups, places = {}, {}
	local instances = {}
	for instance in pairs(ns.Entrances or {}) do
		instances[#instances + 1] = instance
	end
	table.sort(instances)
	for _, instance in ipairs(instances) do
		local place = Place(instance)
		if place then
			local key = "entrance:" .. instance
			places[key] = place
			groups[#groups + 1] = {
				section = "entrances",
				key = key,
				label = place.name,
				icon = ICON,
				npcs = {},
				entrance = instance,
			}
		end
	end
	return groups
end

---@class SPFNearbyEntrancesAPI
---@field Add fun(index: table<string, SPFNearbyPlace[]>, Add: fun(group: SPFNearbyGroup))
---@field Sort fun(list: SPFNearbyGroup[], world: SPFPoint?)
---@field Order fun(section: string, rows: SPFNearbyRow[], world: SPFPoint, seconds: table<string, number>?)
---@field Detail fun(place: SPFNearbyPlace): string
---@field Navigate fun(place: SPFNearbyPlace): boolean
local Entrances = {}
ns.NearbyEntrances = Entrances

-- Adds the dungeon and raid groups to the nearby index and group list as UI/Nearby.lua assembles them.
---@param index table<string, SPFNearbyPlace[]>
---@param Add fun(group: SPFNearbyGroup)
function Entrances.Add(index, Add)
	for _, group in ipairs(Build()) do
		index[group.key] = { places[group.key] }
		Add(group)
	end
end

-- Reorders the dungeon and raid groups nearest door first, dropping those on another continent: a menu is built in
-- one pass and has no travel estimates, so the straight line stands in for them.
---@param list SPFNearbyGroup[]
---@param world? SPFPoint
function Entrances.Sort(list, world)
	local near = {}
	for _, group in ipairs(list) do
		if group.section == "entrances" then
			local place = places[group.key]
			if place and world and place.world.map == world.map then
				near[#near + 1] = {
					group = group,
					gap = (place.world.x - world.x) ^ 2 + (place.world.y - world.y) ^ 2,
				}
			end
		end
	end
	table.sort(near, function(a, b)
		if a.gap == b.gap then
			return a.group.key < b.group.key
		end
		return a.gap < b.gap
	end)
	for position = #list, 1, -1 do
		if list[position].section == "entrances" then
			table.remove(list, position)
		end
	end
	for _, entry in ipairs(near) do
		list[#list + 1] = entry.group
	end
end

-- The panel's rows by travel time once every one has an estimate, and by the straight line to the door until then.
-- Every row is on the player's continent, so the distances compare.
---@param section string
---@param rows SPFNearbyRow[]
---@param world SPFPoint
---@param seconds? table<string, number>
function Entrances.Order(section, rows, world, seconds)
	if section ~= "entrances" or #rows < 2 then
		return
	end
	local times = seconds or {}
	local timed = seconds ~= nil
	if timed then
		for _, row in ipairs(rows) do
			if times[row.id] == nil then
				timed = false
				break
			end
		end
	end
	local function Key(row)
		if timed then
			return times[row.id]
		end
		local door = row.npc.world
		return (door.x - world.x) ^ 2 + (door.y - world.y) ^ 2
	end
	table.sort(rows, function(a, b)
		local keyA, keyB = Key(a), Key(b)
		if keyA == keyB then
			return a.id < b.id
		end
		return keyA < keyB
	end)
end

-- A row's detail: the outdoor zone, since the row's label is already the instance.
---@param place SPFNearbyPlace
---@return string
function Entrances.Detail(place)
	return place.title or place.name
end

-- Starts the journey: the door stop JourneyInput.lua builds, so the journey arrives on going in. A Nearby row has no
-- goal inside the instance, so the stop it stands for is a bare point on the instance map, read only for identity.
---@param place SPFNearbyPlace
---@return boolean
function Entrances.Navigate(place)
	local stop = place.entrance
		and ns.EntranceStop
		and ns.EntranceStop(place.entrance, { map = place.entrance, x = 0, y = 0 })
	if not stop then
		return false
	end
	return ns.StartJourney(stop) == true
end

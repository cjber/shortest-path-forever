---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- "Only my professions": the shop rule both Nearby services and the world map's town services follow. A profession
-- trainer shows only for a profession this character has learned. A vendor is judged row by row: in a group it shows
-- only when the goods it sells in that group supply one of those professions, so a food seller that also stocks a
-- cooking reagent keeps its Food row for a character without Cooking. A vendor whose goods in the group supply no
-- profession always shows, as does the option off.
--
-- Which professions an item supplies comes from Data/Services.lua's ItemProfessions, generated from the client's
-- item, spell and skill-line tables and classic-db's vendor inventories. The game's titles are never read: they are
-- text, and a supplier called Trade Supplies names no profession at all.
--
-- The rule lives here rather than in UI/Nearby.lua because the world map's layer reads the same one.

---@class SPFNearbyProfessionsAPI
---@field Learned fun(): table<integer, boolean> the professions this character has learned
---@field Shown fun(group: SPFNearbyGroup?, place: SPFNearbyPlace|SPFTownService?, items?: integer[]): boolean
local Professions = {}
ns.NearbyProfessions = Professions

-- The skill line of each profession slot given, as a set.
---@param set table<integer, boolean>
---@return table<integer, boolean>
local function Collect(set, ...)
	for slot = 1, select("#", ...) do
		local book = select(slot, ...)
		local skill = book and select(7, GetProfessionInfo(book)) -- multi-value: the skill line is seventh
		if type(skill) == "number" then
			set[skill] = true
		end
	end
	return set
end

-- The professions this character has learned, as a set of skill lines, read from the client's own profession slots.
---@return table<integer, boolean>
function Professions.Learned()
	if not (GetProfessions and GetProfessionInfo) then
		return {}
	end
	return Collect({}, GetProfessions())
end

-- The goods a vendor sells in the group being judged, looked up from the list that indexed them.
---@param group SPFNearbyGroup
---@param place SPFNearbyPlace|SPFTownService
---@return integer[]?
local function GroupItems(group, place)
	local services = ns.NearbyServices
	return services and services.Items and services.Items(group.key, place.id)
end

-- Whether a place shows under the filter: a profession trainer only for a profession this character has learned, and
-- a vendor only when the goods it sells in the group supply a learned profession. Every other service shows, and the
-- option off shows everything.
---@param group SPFNearbyGroup?
---@param place SPFNearbyPlace|SPFTownService?
---@param items? integer[] the goods the place sells in the group, which a vendor is judged by
---@return boolean
function Professions.Shown(group, place, items)
	if not (ns.db and ns.db.onlyMyProfessions) then
		return true
	end
	local learned = Professions.Learned()
	if group and group.skill then
		return learned[group.skill] == true
	end
	if not (group and group.section == "vendors" and place) then
		return true
	end
	local supplied = ns.ItemProfessions
	if not supplied then
		return true
	end
	items = items or GroupItems(group, place)
	local any = false
	for _, itemID in ipairs(items or {}) do
		for _, skill in ipairs(supplied[itemID] or {}) do
			any = true
			if learned[skill] then
				return true
			end
		end
	end
	return not any
end

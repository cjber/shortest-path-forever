---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- "Only my professions": the shop rule both Nearby services and the world map's town services follow. A profession
-- trainer shows only for a profession this character has learned. A vendor shows only when its goods supply one of
-- those professions: the recipes it sells name a profession's skill line as their required skill, and the materials
-- it sells are reagents or tools of that profession's spells. A vendor supplying nothing from a profession always
-- shows, as does the option off.
--
-- Which professions a vendor supplies comes from Data/Services.lua's VendorProfessions, generated from the client's
-- item, spell and skill-line tables and classic-db's vendor inventories. The game's titles are never read: they are
-- text, and a supplier called Trade Supplies names no profession at all.
--
-- The rule lives here rather than in UI/Nearby.lua because the world map's layer reads the same one.

---@class SPFNearbyProfessionsAPI
---@field Learned fun(): table<integer, boolean> the professions this character has learned
---@field Shown fun(group: SPFNearbyGroup?, place: SPFNearbyPlace|SPFTownService?): boolean whether a service shows with the filter on
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

-- Whether a place shows under the filter: a profession trainer only for a profession this character has learned, and
-- a vendor only when one of the professions its goods supply is learned. Every other service shows, and the option
-- off shows everything.
---@param group SPFNearbyGroup?
---@param place SPFNearbyPlace|SPFTownService?
---@return boolean
function Professions.Shown(group, place)
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
	local supplied = ns.VendorProfessions and ns.VendorProfessions[place.id]
	if not supplied then
		return true
	end
	for _, skill in ipairs(supplied) do
		if learned[skill] then
			return true
		end
	end
	return false
end

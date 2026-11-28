---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- Which continents have no flight points synced yet: Settings' counts, the tracker's warning rows and the notice.
local CONTINENTS = {
	{ map = 0, uiMap = 1415, name = L["Eastern Kingdoms"] },
	{ map = 1, uiMap = 1414, name = L["Kalimdor"] },
}
local continentsNamed = false
local NONE = {}

local function Continents()
	if not continentsNamed then
		continentsNamed = true
		for _, continent in ipairs(CONTINENTS) do
			local info = C_Map.GetMapInfo(continent.uiMap)
			if info and info.name and info.name ~= "" then
				continent.name = info.name
			end
		end
	end
	return CONTINENTS
end

local function KnownCounts()
	local counts = {}
	for nodeID in pairs(ns.KnownTaxiNodes()) do
		local node = ns.TaxiNodes[nodeID]
		if node then
			counts[node.map] = (counts[node.map] or 0) + 1
		end
	end
	return counts
end

---@return {map: number, name: string, known: integer}[]
function ns.KnownFlightPointsByContinent()
	local counts, continents = KnownCounts(), {}
	for _, continent in ipairs(Continents()) do
		continents[#continents + 1] = { map = continent.map, name = continent.name, known = counts[continent.map] or 0 }
	end
	return continents
end

---@param plan SPFPlan
---@return {map: number, name: string}[]
local function UnsyncedContinents(plan)
	local maps = plan.unknownFlightMaps
	if not maps then
		return NONE
	end
	local counts, unsynced = KnownCounts(), NONE
	for _, continent in ipairs(Continents()) do
		if maps[continent.map] and not counts[continent.map] then
			unsynced = unsynced == NONE and {} or unsynced
			unsynced[#unsynced + 1] = continent
		end
	end
	return unsynced
end

---@param plan SPFPlan
---@return SPFRow[]
function ns.UnsyncedFlightPointRows(plan)
	local unsynced = UnsyncedContinents(plan)
	if unsynced == NONE then
		return NONE
	end
	local rows = {}
	for _, continent in ipairs(unsynced) do
		rows[#rows + 1] = {
			key = "no-flight-points-" .. continent.map,
			text = string.format(
				L["No flight points learned in %s: open a flight master's map once to sync them."],
				continent.name
			),
			warning = true,
		}
	end
	return rows
end

local announcedGoal, announced = nil, {}

-- Says once for each journey and continent that learning its flight points would find a quicker way.
---@param result SPFPlan?
---@param goal SPFPoint?
function ns.AnnounceUnsyncedFlightPoints(result, goal)
	if not (result and result.unknownFlightMaps and goal and ns.db.flightPathReminder) then
		return
	end
	if announcedGoal ~= goal then
		announcedGoal, announced = goal, {}
	end
	for _, continent in ipairs(UnsyncedContinents(result)) do
		if not announced[continent.map] then
			announced[continent.map] = true
			ns.Notice(
				L["A flight would be quicker. Open a flight master's map in %s once to sync your flight points."]:format(
					continent.name
				)
			)
		end
	end
end

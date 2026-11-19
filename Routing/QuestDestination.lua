---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L
---@class SPFPlanner
local Planner = ns.Planner

local function QuestPointValid(point)
	return point
		and type(point.uiMapID) == "number"
		and point.uiMapID > 0
		and type(point.x) == "number"
		and point.x >= 0
		and point.x <= 1
		and type(point.y) == "number"
		and point.y >= 0
		and point.y <= 1
end

-- Native POIs already describe the quest's current state. A completed quest prefers its
-- destination POI (turn-in) over a next waypoint that may still describe the last objective.
---@param questID number
---@param title string?
---@param complete boolean
---@param uiMapID number?
---@param pois QuestPOIMapInfo[]?
---@param waypoint {uiMapID: number?, x: number?, y: number?}?
function Planner.QuestDestination(questID, title, complete, uiMapID, pois, waypoint)
	local destination, start
	for _, poi in ipairs(pois or {}) do
		if poi.questID == questID then
			-- As in QuestDataProvider, x/y belong to the queried map, even for child-map POIs.
			local point = { uiMapID = uiMapID, x = poi.x, y = poi.y }
			if QuestPointValid(point) then
				if not poi.isQuestStart then
					destination = point
					break
				end
				-- Some quests start and end with one NPC and have no objective area, so the client reports only
				-- that start pin. It is still the only place it names, and better than no journey at all.
				start = start or point
			end
		end
	end
	if waypoint and QuestPointValid(waypoint) and (not complete or not destination) then
		destination = { uiMapID = waypoint.uiMapID, x = waypoint.x, y = waypoint.y }
	end
	destination = destination or start
	if destination and title and title ~= "" then
		destination.label = complete and string.format(L["%s (turn in)"], title) or title
		return destination
	end
end

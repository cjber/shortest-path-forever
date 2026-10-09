---@class SPFNamespace
local ns = select(2, ...)
local L = ns.L

---@param uiMapID integer
---@param x number
---@param y number
---@return SPFPoint?
function ns.WorldPoint(uiMapID, x, y)
	local continent, world = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(x, y))
	if continent and world then
		local worldX, worldY = world:GetXY()
		return { map = continent, x = worldX, y = worldY }
	end
end

local function PlanQuest(questID, clickedMap, isWaypoint)
	if not ns.db.journey then
		return
	end
	-- Forever takes questID and ignoreWaypoint; Ketho's Wiki stub incorrectly has zero parameters.
	---@diagnostic disable-next-line: redundant-parameter
	local uiMapID = clickedMap or GetQuestUiMapID(questID, true)
	local waypoint
	if not clickedMap or isWaypoint then
		local mapID, x, y
		if clickedMap then
			mapID = clickedMap
			x, y = C_QuestLog.GetNextWaypointForMap(questID, mapID)
		else
			mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
		end
		waypoint = { uiMapID = mapID, x = x, y = y }
	end
	local pois = not isWaypoint and uiMapID and uiMapID > 0 and C_QuestLog.GetQuestsOnMap(uiMapID) or nil
	local location = ns.Planner.QuestDestination(
		questID,
		C_QuestLog.GetTitleForQuestID(questID),
		C_QuestLog.IsComplete(questID),
		uiMapID,
		pois,
		waypoint
	)
	local point = location and ns.WorldPoint(location.uiMapID, location.x, location.y)
	if not point then
		-- Questie.API exposes icons and update notifications, but no public coordinate lookup.
		ns.Print(L["No location for that quest yet."])
		return
	end
	point.label, point.questID, point.pinBadge = location.label, questID, clickedMap ~= nil
	ns.StartJourney(point)
end

-- The World map between its continents and a continent's open sea still give a world position, on no zone: the
-- client answers with a spot off the map it names, or with the continent and no zone under the spot.
---@param point SPFPoint
---@return boolean
local function OnZone(point)
	local location = ns.Locate(point)
	if not location or location.x < 0 or location.x > 1 or location.y < 0 or location.y > 1 then
		return false
	end
	local info = C_Map.GetMapInfo(location.uiMap)
	return not info or info.mapType > Enum.UIMapType.Continent
end

local function OnCanvasClick(map, button)
	if not ns.db.journey or button ~= "LeftButton" or not IsShiftKeyDown() then
		return false
	end
	local point = ns.WorldPoint(map:GetMapID(), map:GetNormalizedCursorPosition())
	if point and OnZone(point) then
		ns.StartJourney(point)
	else
		ns.Print(L["no journey can be planned to that spot."])
	end
	return true
end

local function OnMinimapClick(_, button)
	if not ns.db.journey or button ~= "LeftButton" or not IsShiftKeyDown() then
		return
	end
	local point = ns.MinimapPoint()
	if point then
		ns.StartJourney(point)
	else
		ns.Print(L["no journey can be planned to that spot."])
	end
end

local function OnPinClick(map, action, button)
	if
		not ns.db.journey
		or action ~= MapCanvasMixin.MouseAction.Click
		or button ~= "LeftButton"
		or not IsShiftKeyDown()
	then
		return false
	end
	-- MapCanvas calls these handlers before POIButton.OnClick. Canvas click handlers do not run over pins.
	for _, focus in ipairs(GetMouseFoci()) do
		local pin = focus
		---@cast pin SPFQuestPin
		if pin.pinTemplate == "QuestPinTemplate" and pin:GetMap() == map and pin:GetQuestID() then
			PlanQuest(pin:GetQuestID(), map:GetMapID(), pin:GetStyle() == POIButtonUtil.Style.Waypoint)
			return true
		end
		---@cast pin SPFFlightPin
		if
			pin.pinTemplate
			and pin.pinTemplate ~= "ShortestPathForeverGoalPinTemplate"
			and pin.pinTemplate ~= "QuestPinTemplate"
			and pin.GetMap
			and pin:GetMap() == map
		then
			local info = pin.poiInfo
			local flight = pin.pinTemplate == "FlightPointPinTemplate"
				or pin.pinTemplate == "ShortestPathForeverFlightPinTemplate"
			local node = flight and info and ns.TaxiNodes[info.nodeID]
			local point
			if node then
				point = { map = node.map, x = node.x, y = node.y, z = node.z }
			elseif pin.GetGlobalPosition then
				local x, y = pin:GetGlobalPosition()
				if x and y then
					point = ns.WorldPoint(map:GetMapID(), x, y)
				end
			end
			if point and OnZone(point) then
				point.label = info and info.name
				point.pinBadge = true
				ns.StartJourney(point)
				return true
			end
		end
	end
	return false
end

local function AddQuestMenuEntry(root, questID)
	if ns.db.journey and questID then
		root:CreateButton(L["Plan journey"], function()
			PlanQuest(questID)
		end)
	end
end

ns.Init(function()
	-- Questie owns Shift-click on its icons. Alt-click observes the map cursor
	-- through our own event frame, including icons that swallow canvas clicks.
	local clicks = CreateFrame("Frame")
	clicks:RegisterEvent("GLOBAL_MOUSE_DOWN")
	clicks:SetScript("OnEvent", function(_, _, button)
		if
			not ns.db.journey
			or button ~= "LeftButton"
			or not IsAltKeyDown()
			or not WorldMapFrame:IsShown()
			or not WorldMapFrame.ScrollContainer:IsMouseOver()
		then
			return
		end
		local point = ns.WorldPoint(WorldMapFrame:GetMapID(), WorldMapFrame:GetNormalizedCursorPosition())
		if point and OnZone(point) then
			ns.StartJourney(point)
		end
	end)
	WorldMapFrame:AddCanvasClickHandler(OnCanvasClick)
	WorldMapFrame:AddGlobalPinMouseActionHandler(OnPinClick)
	-- The stock handler still pings the spot, which marks where the journey goes for your group too.
	Minimap:HookScript("OnMouseUp", OnMinimapClick)
	Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", function(owner, root)
		-- The native menu owner is the tracker container, with no quest ID/context data.
		-- Resolve the right-clicked HeaderButton's block; never reuse a previous hover's quest.
		for _, header in ipairs(GetMouseFoci()) do
			local block = header:GetParent()
			---@cast block SPFTrackerBlock
			if
				block
				and block.HeaderButton == header
				and block.parentModule
				and block.parentModule:GetContextMenuParent() == owner
			then
				AddQuestMenuEntry(root, block.id)
				return
			end
		end
	end)
	Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", function(owner, root)
		---@cast owner SPFQuestMenuOwner
		-- Waypoint menus share this tag, but have no questID.
		AddQuestMenuEntry(root, owner.questID)
	end)
end)

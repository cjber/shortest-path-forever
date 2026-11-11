---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- The bindings UI reads these names from the global namespace. They are set here from L so each locale translates
-- them with the rest of the addon; Bindings.xml lists the hidden buttons they click.
_G.BINDING_HEADER_SHORTESTPATHFOREVER = L["Shortest Path Forever"]
_G["BINDING_NAME_CLICK ShortestPathForeverTravelToPinButton:LeftButton"] = L["Travel to my map pin"]
_G["BINDING_NAME_CLICK ShortestPathForeverTravelToTrackedQuestButton:LeftButton"] = L["Travel to my tracked quest"]
_G["BINDING_NAME_CLICK ShortestPathForeverClearJourneyButton:LeftButton"] = L["Clear journey"]

-- A place inside a dungeon or raid has no walking map: from outside, a journey there goes to the instance's door
-- (Data/Portals.lua ns.Entrances) and arrives when you go in. The door keeps the stop it stands for (`stop`), its
-- name, quest and title; areas and holds drawn inside the instance stay behind. Inside, the point stays as it is.
---@param point SPFPoint
---@return SPFPoint
function ns.InstanceEntrance(point)
	local entrance = ns.Entrances and ns.Entrances[point.map]
	if not entrance or select(8, GetInstanceInfo()) == point.map then
		return point
	end
	local name = GetRealZoneText(point.map)
	if not name or name == "" then
		name = entrance.name
	end
	return {
		map = entrance.map,
		x = entrance.x,
		y = entrance.y,
		z = entrance.z,
		label = point.label or L["Enter %s"]:format(name),
		questID = point.questID,
		questIDs = point.questIDs,
		routeTitle = point.routeTitle,
		details = point.details,
		entrance = point.map,
		stop = point,
	}
end

-- A map of a place under another one you can walk on, and the height of its floor. A spot gives no height, and a walk
-- ends on the cheapest surface there: a spot picked on the Undercity's map ended on the Ruins of Lordaeron overhead.
-- With this height the walk ends on the floor nearest it (Path.lua's snap), in the city; a spot with no city under it
-- keeps the ruins. The Tirisfal Glades map names the same spots on the surface and gets no height. Ironforge's
-- mountain top cannot be walked to, so its city is already the cheapest.
local UNDERGROUND = {
	[1458] = -43.1, -- Undercity: the flight master's floor (Data/Taxi.lua node 11)
}

-- The height of the NPC or quest object spawn nearest (x, y) on map, within radius yards, when it stands over or
-- under another walkable surface (Data/Heights.lua). QuestieDB's spawns have no height, so a journey to one ended on
-- the cheapest surface there: the hill over Azurelode Mine rather than the miners inside it. With this height the walk
-- ends on the spawn's own floor (Path.lua's snap); a spawn with one surface around it is not listed and needs none.
---@param map number
---@param x number
---@param y number
---@param radius number
---@return number?
function ns.SpawnHeight(map, x, y, radius)
	local heights = ns.SpawnHeights and ns.SpawnHeights[map]
	local st = heights and ns.PathGrid.State(map)
	if not st then
		return nil
	end
	-- A list is one Nav cluster's; the box's corners name every cluster it reaches, a radius being far below a tile.
	local best, gap, seen = nil, radius * radius, {}
	for _, dx in ipairs({ -radius, radius }) do
		for _, dy in ipairs({ -radius, radius }) do
			local k = ns.PathGrid.locate(st, x + dx, y + dy)
			if k and not seen[k] then
				seen[k] = true
				for sx, sy, sz in (heights[k + 1] or ""):gmatch("(%S+) (%S+) (%S+)") do
					local d = (tonumber(sx) - x) ^ 2 + (tonumber(sy) - y) ^ 2
					if d <= gap then
						best, gap = tonumber(sz), d
					end
				end
			end
		end
	end
	return best
end

---@param uiMapID integer
---@param x number
---@param y number
---@return SPFPoint?
function ns.WorldPoint(uiMapID, x, y)
	local continent, world = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(x, y))
	if continent and world then
		local worldX, worldY = world:GetXY()
		return { map = continent, x = worldX, y = worldY, z = UNDERGROUND[uiMapID] }
	end
end

-- The map whose quest pins include this quest, and those pins. A quest whose only pin is its start can name no map
-- of its own (Dragonmaw Shinbones, 1846, whose objective is an item drop), so the map under the player is asked too.
---@param questID number
---@param uiMapID number?
---@param here boolean? ask the map under the player when the first map has no pin
---@return number? mapID, QuestPOIMapInfo[]? pois
local function QuestPOIs(questID, uiMapID, here)
	local seen = {}
	local function Ask(mapID)
		if not mapID or mapID <= 0 or seen[mapID] then
			return nil
		end
		seen[mapID] = true
		local pois = C_QuestLog.GetQuestsOnMap(mapID)
		for _, poi in ipairs(pois or {}) do
			if poi.questID == questID then
				return mapID, pois
			end
		end
	end
	local mapID, pois = Ask(uiMapID)
	if not pois and here then
		local current = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		mapID, pois = Ask(current)
	end
	return mapID, pois
end

local function PlanQuest(questID, clickedMap, isWaypoint)
	if not ns.db.journey then
		ns.Print(L["Journeys are off. Turn on Shift-click to plan journeys in settings."])
		return false
	end
	-- Forever takes questID and ignoreWaypoint; Ketho's Wiki stub incorrectly has zero parameters.
	---@diagnostic disable-next-line: redundant-parameter
	local uiMapID = clickedMap or GetQuestUiMapID(questID, true)
	if not clickedMap and (not uiMapID or uiMapID <= 0) then
		-- No map for the quest's own pins: the game's map for the quest may still be its waypoint's.
		---@diagnostic disable-next-line: redundant-parameter
		uiMapID = GetQuestUiMapID(questID, false)
	end
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
	local pois
	if not isWaypoint then
		local poiMap
		poiMap, pois = QuestPOIs(questID, uiMapID, not clickedMap)
		uiMapID = poiMap or uiMapID
	end
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
		return false
	end
	point.label, point.questID, point.pinBadge = location.label, questID, clickedMap ~= nil
	-- The goal's live objectives: the arrow and any pin read them from the client's quest log.
	point.questIDs = { questID }
	ns.StartJourney(point)
	return true
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

-- Shift+click inserts a link into an open chat box; leave that click to Blizzard's own handlers.
-- Both globals may be absent (older builds, the headless harness); guard the call so a missing
-- one never errors inside a click handler.
local function ChatBoxOpen()
	local active = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
	return active ~= nil and active() ~= nil
end

-- A spot on a map, as a Shift-click on the world map or /way names it, with what to call it if anything.
---@param uiMapID integer
---@param x number
---@param y number
---@param label? string
---@return boolean
function ns.JourneyToMapPoint(uiMapID, x, y, label)
	local point = ns.WorldPoint(uiMapID, x, y)
	if not (point and OnZone(ns.InstanceEntrance(point))) then
		ns.Print(L["no journey can be planned to that spot."])
		return false
	end
	point.label = label
	ns.StartJourney(point)
	return true
end

-- The client's own map pin (the user waypoint a player drops from the map) as a journey, for the key binding a
-- controller player has instead of Shift-click.
---@return boolean
function ns.JourneyToUserWaypoint()
	if not ns.db.journey then
		ns.Print(L["Journeys are off. Turn on Shift-click to plan journeys in settings."])
		return false
	end
	local waypoint = C_Map.GetUserWaypoint()
	local position = waypoint and waypoint.position
	if not (position and waypoint.uiMapID) then
		ns.Print(L["no map pin is set."])
		return false
	end
	return ns.JourneyToMapPoint(waypoint.uiMapID, position.x, position.y)
end

-- The quest the player is tracking. The client's super-tracked quest is the ordinary answer, but a quest shown in the
-- objective tracker is merely watched: the native menu only offers "Super Track Quest" for it. Falling back to the
-- watch list, in tracker order, is what makes the tracked-quest binding reach the block the player sees.
---@return number?
local function TrackedQuestID()
	local questID = C_SuperTrack.GetSuperTrackedQuestID()
	if questID and questID > 0 then
		return questID
	end
	local count = C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() or 0
	for index = 1, count do
		local getWatch = C_QuestLog.GetQuestIDForQuestWatchIndex
		questID = getWatch and getWatch(index)
		if questID and questID > 0 then
			return questID
		end
	end
end

-- The quest the client is super-tracking, or the top tracked quest when none is, as the Shift-click on its tracker
-- block would plan it.
---@return boolean
function ns.JourneyToTrackedQuest()
	local questID = TrackedQuestID()
	if not questID then
		ns.Print(L["no quest is tracked."])
		return false
	end
	return PlanQuest(questID)
end

local function OnCanvasClick(map, button)
	if not ns.db.journey or button ~= "LeftButton" or not IsShiftKeyDown() or ChatBoxOpen() then
		return false
	end
	ns.JourneyToMapPoint(map:GetMapID(), map:GetNormalizedCursorPosition())
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

-- A journey to a Shift-clicked pin, labelled by its name if it has one: a flight point by its node, anything else by
-- where it stands on the map. False when there is nowhere to plan to.
---@param mapID number
---@param info? {nodeID?: number, name?: string}
---@param flight boolean
---@param x? number
---@param y? number
---@return boolean
local function JourneyToPin(mapID, info, flight, x, y)
	local node = flight and info and ns.TaxiNodes[info.nodeID]
	local point
	if node then
		point = { map = node.map, x = node.x, y = node.y, z = node.z }
	elseif x and y then
		point = ns.WorldPoint(mapID, x, y)
	end
	if not (point and OnZone(ns.InstanceEntrance(point))) then
		return false
	end
	point.label = info and info.name
	point.pinBadge = true
	ns.StartJourney(point)
	return true
end

-- The quest a pin marks, when it is the map's own quest pin on `map` (QuestDataProvider's QuestPinTemplate); nil for
-- any other pin. UI/QuestPins.lua uses the same lookup to hide the game's pin under one of our stops.
---@param pin SPFMapPin
---@param map SPFMapCanvas
---@return number?
function ns.QuestPinID(pin, map)
	---@cast pin SPFQuestPin
	if pin.pinTemplate == "QuestPinTemplate" and pin.GetMap and pin:GetMap() == map and pin.GetQuestID then
		return pin:GetQuestID()
	end
end

local function OnPinClick(map, action, button)
	if
		not ns.db.journey
		or action ~= MapCanvasMixin.MouseAction.Click
		or button ~= "LeftButton"
		or not IsShiftKeyDown()
		or ChatBoxOpen()
	then
		return false
	end
	-- MapCanvas calls these handlers before POIButton.OnClick. Canvas click handlers do not run over pins.
	for _, focus in ipairs(GetMouseFoci()) do
		local pin = focus
		---@cast pin SPFQuestPin
		local questID = ns.QuestPinID(pin, map)
		if questID then
			PlanQuest(questID, map:GetMapID(), pin:GetStyle() == POIButtonUtil.Style.Waypoint)
			return true
		end
		---@cast pin SPFFlightPin
		if pin.pinTemplate and pin.pinTemplate ~= "QuestPinTemplate" and pin.GetMap and pin:GetMap() == map then
			local x, y
			if pin.GetGlobalPosition then
				x, y = pin:GetGlobalPosition()
			end
			if JourneyToPin(map:GetMapID(), pin.poiInfo, pin.pinTemplate == "FlightPointPinTemplate", x, y) then
				return true
			end
		end
	end
	return false
end

-- Shift-click on one of the addon's own map pins (UI/Canvas.lua), as OnPinClick does for the map's. The stop
-- buttons keep their own click.
---@param pin SPFCanvasPin
---@param button string
---@return boolean
local function OnOwnPinClick(pin, button)
	if not ns.db.journey or button ~= "LeftButton" or not IsShiftKeyDown() or ChatBoxOpen() then
		return false
	end
	local marker = pin.marker
	if marker ~= "flight" and marker ~= "dock" and marker ~= "portal" then
		return false
	end
	local x, y = pin:GetPosition()
	local info = marker == "flight" and (pin --[[@as SPFAddonFlightPin]]).poiInfo or nil
	return JourneyToPin(pin:GetMap():GetMapID() --[[@as number]], info, marker == "flight", x, y)
end

local function AddQuestMenuEntry(root, questID)
	if ns.db.journey and questID then
		root:CreateButton(L["Plan journey"], function()
			PlanQuest(questID)
		end)
		ns.FamilyHints.AddQuestMenu(root)
	end
end

-- A tracker replacement (EQOT, the guide column) can leave a block under ObjectiveTrackerFrame without the native
-- parentModule/GetContextMenuParent chain. Walk a bounded number of parents so a block from another frame is never
-- accepted as the right-clicked one.
local TRACKER_DEPTH = 8

---@param block Frame
---@return boolean
local function UnderObjectiveTracker(block)
	for _ = 1, TRACKER_DEPTH do
		local parent = block:GetParent()
		if not parent then
			return false
		end
		if parent == ObjectiveTrackerFrame then
			return true
		end
		block = parent
	end
	return false
end

---@param block Frame
---@param ancestor Frame?
---@return boolean
local function Under(block, ancestor)
	if not ancestor then
		return false
	end
	for _ = 1, TRACKER_DEPTH do
		if block == ancestor then
			return true
		end
		local parent = block:GetParent()
		if not parent then
			return false
		end
		block = parent
	end
	return false
end

---@param block SPFTrackerBlock
---@param owner Frame
---@return boolean
local function BlockBelongsTo(block, owner)
	local module = block.parentModule
	local getContextMenuParent = module and module.GetContextMenuParent
	if getContextMenuParent and getContextMenuParent(module) == owner then
		return true
	end
	-- A replacement tracker such as EQOT draws its blocks under a frame of its own, not ObjectiveTrackerFrame, so the
	-- menu's owner is the only ancestry left to check before the native fallback.
	return Under(block, owner) or UnderObjectiveTracker(block)
end

-- The right-clicked header's block, never a previous hover's: the header test keeps a stale focus from being used.
---@param owner Frame
---@return number|string?
local function QuestIDFromTrackerFocus(owner)
	for _, header in ipairs(GetMouseFoci()) do
		---@cast header SPFTrackerBlockHeader
		local block = header:GetParent()
		---@cast block SPFTrackerBlock
		if block and block.HeaderButton == header and BlockBelongsTo(block, owner) then
			local questID = block.id or block.questID or header.questID
			if questID then
				return questID
			end
		end
	end
end

-- Bindings.xml's CLICK bindings name these hidden buttons, so a key or a controller button reaches the same actions
-- the map's Shift-click does. A hidden button takes a CLICK binding without drawing anything.
---@param name string
---@param onClick fun()
local function Binding(name, onClick)
	local button = CreateFrame("Button", name, UIParent)
	button:SetSize(1, 1)
	button:Hide()
	button:SetScript("OnClick", onClick)
end

-- Yards from a Questie icon to the spawn it marks. Questie keeps a spawn's spot to a hundredth of a percent of its zone
-- map, a yard or less. Data/Heights.lua lists only spawns with another floor near them, so a wider reach would hand an
-- unlisted spawn a listed neighbour's floor: at 25 yd 0.7% of single-floor spawns ended on the wrong one, at 8 yd two
-- in 61,641. A zoomed-out icon standing for a group of spawns, at the group's centre, may find none and keeps the
-- cheapest surface.
local QUESTIE_ICON_REACH = 8

-- The spot of the Questie map icon under the cursor: its zone map and the spawn's place on it. Questie draws each
-- world map icon as a QuestieFrame button holding them (Questie/Questie Modules/Map/QuestieMap.lua, DrawWorldIcon:
-- x and y in percent, UiMapID, miniMapIcon false). Read only, never written.
---@return integer?, number?, number?
local function QuestieIconSpot()
	if not rawget(_G, "Questie") then
		return nil
	end
	for _, frame in ipairs(GetMouseFoci()) do
		if not (frame.IsForbidden and frame:IsForbidden()) then
			---@cast frame SPFQuestieIcon
			local map, x, y = frame.UiMapID, frame.x, frame.y
			if
				frame.miniMapIcon == false
				and type(frame.data) == "table"
				and type(map) == "number"
				and type(x) == "number"
				and type(y) == "number"
			then
				return map, x / 100, y / 100
			end
		end
	end
end

ns.Init(function()
	Binding("ShortestPathForeverTravelToPinButton", ns.JourneyToUserWaypoint)
	Binding("ShortestPathForeverTravelToTrackedQuestButton", ns.JourneyToTrackedQuest)
	Binding("ShortestPathForeverClearJourneyButton", ns.ClearJourney)
	-- Questie owns Shift-click on its icons. Alt-click observes the map cursor
	-- through our own event frame, including icons that swallow canvas clicks.
	-- TomTom's map overlay passes LeftButton through; its waypoint gesture uses RightButton.
	local clicks = CreateFrame("Frame")
	clicks:RegisterEvent("GLOBAL_MOUSE_DOWN")
	clicks:SetScript("OnEvent", function(_, _, button)
		if
			not ns.db.journey
			or button ~= "LeftButton"
			or not IsAltKeyDown()
			or IsShiftKeyDown()
			or not WorldMapFrame:IsShown()
			or not WorldMapFrame.ScrollContainer:IsMouseOver()
		then
			return
		end
		-- Over a Questie icon the journey goes to the spawn it marks, on that spawn's floor.
		local iconMap, iconX, iconY = QuestieIconSpot()
		local point
		if iconMap and iconX and iconY then
			point = ns.WorldPoint(iconMap, iconX, iconY)
			if point and point.z == nil then
				point.z = ns.SpawnHeight(point.map, point.x, point.y, QUESTIE_ICON_REACH)
			end
		else
			point =
				ns.WorldPoint(WorldMapFrame:GetMapID() --[[@as number]], WorldMapFrame:GetNormalizedCursorPosition())
		end
		if point and OnZone(ns.InstanceEntrance(point)) then
			ns.StartJourney(point)
		end
	end)
	-- The map's click registries are Blizzard's own for addons (MapCanvasSecureUtil.CreateHandlerRegistry): it keeps
	-- them outside the map's fields and calls each handler through securecallfunction, so the map's code never runs
	-- the addon's. The addon's own pins take their clicks through UI/Canvas.lua instead.
	WorldMapFrame:AddCanvasClickHandler(OnCanvasClick)
	WorldMapFrame:AddGlobalPinMouseActionHandler(OnPinClick)
	ns.Canvas.OnClick(OnOwnPinClick)
	-- The stock handler still pings the spot, which marks where the journey goes for your group too.
	Minimap:HookScript("OnMouseUp", OnMinimapClick)
	Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", function(owner, root)
		---@cast owner Frame
		-- The native menu owner is the tracker container, with no quest ID/context data.
		-- Resolve the right-clicked HeaderButton's block; never reuse a previous hover's quest.
		AddQuestMenuEntry(root, QuestIDFromTrackerFocus(owner))
	end)
	Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", function(owner, root)
		---@cast owner SPFQuestMenuOwner
		-- Waypoint menus share this tag, but have no questID; the client also spells it questId.
		AddQuestMenuEntry(root, owner.questID or owner.questId)
	end)
end)

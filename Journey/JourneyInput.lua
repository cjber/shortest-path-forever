---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- The keys a journey click can wait for, in the order the settings list them. Shift has always planned a journey;
-- Alt is for players whose other addons take Shift, Questie's untrack among them.
ns.JourneyKeys = { "shift", "alt" }

-- What each key is called in the settings row. English stands in when a locale has no translation, as every
-- phrase does.
local KEY_NAMES = {
	shift = L["Shift"],
	alt = L["Alt"],
}

-- The saved key, and never an unknown one: an older or hand-edited setting plans journeys with Shift.
---@return string
local function JourneyKey()
	local key = ns.db and ns.db.journeyKey
	if key == "alt" then
		return key
	end
	return "shift"
end

-- Whether the key chosen in Guidance is held: the one gesture behind every map click that plans a journey.
---@return boolean
function ns.JourneyKeyDown()
	if JourneyKey() == "alt" then
		return IsAltKeyDown() == true
	end
	return IsShiftKeyDown() == true
end

-- What the chosen key is called, for the settings row.
---@param key? string
---@return string
function ns.JourneyKeyName(key)
	return KEY_NAMES[key or JourneyKey()] or KEY_NAMES.shift
end

-- The line a tooltip ends with on every map pin the journey key plans a journey to (#1078): the addon's flight
-- points, docks and portals, and the map's own pins OnPinClick takes. One producer, so the wording and the key match
-- everywhere.
-- Nothing while journeys are off, or under the gamepad interface, whose map cursor has no key to hold.
---@return string?
function ns.JourneyClickHint()
	if not (ns.db and ns.db.journey) or ns.GamepadUI() then
		return nil
	end
	return string.format(L["%s-click to plan a journey here"], ns.JourneyKeyName())
end

---@param tooltip GameTooltip
function ns.AddJourneyClickHint(tooltip)
	local hint = ns.JourneyClickHint()
	if hint then
		GameTooltip_AddInstructionLine(tooltip, hint)
	end
end

-- The bindings UI reads these names from the global namespace. They are set here from L so each locale translates
-- them with the rest of the addon; Bindings.xml lists the hidden buttons they click.
_G.BINDING_HEADER_SHORTESTPATHFOREVER = L["Shortest Path Forever"]
_G["BINDING_NAME_CLICK ShortestPathForeverTravelToPinButton:LeftButton"] = L["Travel to my map pin"]
_G["BINDING_NAME_CLICK ShortestPathForeverTravelToTrackedQuestButton:LeftButton"] = L["Travel to my tracked quest"]
_G["BINDING_NAME_CLICK ShortestPathForeverClearJourneyButton:LeftButton"] = L["Clear journey"]

-- A place inside a dungeon or raid has no walking map: from outside, a journey there goes to the instance's door
-- (Data/Portals.lua ns.Entrances) and arrives when you go in. The door keeps the stop it stands for (`stop`), its
-- name, quest and title; areas and holds drawn inside the instance stay behind. Inside, the point stays as it is.
---
-- The door stop on its own, shared with the Nearby services list: the door's continent and position, the "Enter %s"
-- label (the client's name for the instance, else the data's), and `entrance`, which completes it on going in.
---@param instance integer the instance map ID
---@param point SPFPoint the goal inside the instance whose name, quests and title the door keeps
---@return SPFPoint?
function ns.EntranceStop(instance, point)
	local entrance = ns.Entrances and ns.Entrances[instance]
	if not entrance then
		return nil
	end
	local name = GetRealZoneText(instance)
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
		entrance = instance,
		stop = point,
	}
end

---@param point SPFPoint
---@return SPFPoint
function ns.InstanceEntrance(point)
	if not (ns.Entrances and ns.Entrances[point.map]) or select(8, GetInstanceInfo()) == point.map then
		return point
	end
	return ns.EntranceStop(point.map, point) or point
end

-- A map of a place under another one you can walk on: the height of its floor, and the height of the surface above
-- it. A click on the city's own map names the floor, because its spots are rooms under the ground; a click on a map
-- that lies over it names the surface above, since the same 2D spot there holds both floors (#923). The Undercity's
-- floor is its flight master's (Data/Taxi.lua node 11), and the surface above is the Ruins of Lordaeron, at the height
-- of the three lift tops (Data/Transports.lua docks 1009, 1011 and 1013). Ironforge is not listed: a click on its own
-- map already ends on its city floor.
---@class SPFUnderground
---@field floor number
---@field surface number
---@type table<number, SPFUnderground>
local UNDERGROUND = {
	[1458] = { floor = -43.1, surface = 55.718 },
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

-- The stack whose map covers a world position: the client puts the position on that map in [0, 1] when it does.
---@param continent number
---@param world Vector2DMixin
---@return SPFUnderground?
local function StackOver(continent, world)
	for id, stack in pairs(UNDERGROUND) do
		local map, position = C_Map.GetMapPosFromWorldPos(continent, world, id)
		if map == id and position then
			local x, y = position:GetXY()
			if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				return stack
			end
		end
	end
end

---@param uiMapID integer
---@param x number
---@param y number
---@return SPFPoint?
function ns.WorldPoint(uiMapID, x, y)
	local continent, world = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(x, y))
	if continent and world then
		local worldX, worldY = world:GetXY()
		local z
		local own = UNDERGROUND[uiMapID]
		if own then
			z = own.floor
		else
			local over = StackOver(continent, world)
			z = over and over.surface
		end
		return { map = continent, x = worldX, y = worldY, z = z }
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

-- A gesture that plans a journey says so on screen while journeys are off (#1076). A map click otherwise falls to
-- the map, which zooms, with nothing to say why. True when they are off; the click is still the game's.
---@return boolean
local function JourneysOff()
	if ns.db.journey then
		return false
	end
	ns.Notice(L["Journeys are off. Turn on Click the map to plan journeys in settings."])
	return true
end

local function PlanQuest(questID, clickedMap, isWaypoint)
	if JourneysOff() then
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
	point.label, point.questID = location.label, questID
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

-- A modified click inserts a link into an open chat box; leave that click to Blizzard's own handlers.
-- Both globals may be absent (older builds, the headless harness); guard the call so a missing
-- one never errors inside a click handler.
local function ChatBoxOpen()
	local active = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
	return active ~= nil and active() ~= nil
end

-- A spot on a map, as a map click with the journey key held or /way names it, with what to call it if anything.
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
-- controller player has instead of a map click.
---@return boolean
function ns.JourneyToUserWaypoint()
	if JourneysOff() then
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

-- The quest the client is super-tracking, or the top tracked quest when none is, as the journey key on its tracker
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

-- Route to the focused quest: an opt-in journey from the quest the client is super-tracking, or from the map pin
-- the player placed, so a controller needs no map click. A guide's own journey is left alone: its focus changes
-- are its steps, not the player's choice. Journey.lua calls these after Guide.TrackingChanged, so a guide the
-- player took over has already yielded.
---@type number?
local focusedQuest
---@type table?
local focusedWaypoint
-- The flight point a left click on the map super-tracks (UI/FlightPins.lua): the same choice of destination (#1079).
---@type number?
local focusedNode

---@return number?
local function SuperTrackedQuest()
	local get = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
	local questID = get and get()
	if type(questID) == "number" and questID > 0 then
		return questID
	end
end

---@return table?
local function UserWaypoint()
	local get = C_Map and C_Map.GetUserWaypoint
	return get and get() or nil
end

---@return number?
local function SuperTrackedNode()
	local get = C_SuperTrack and C_SuperTrack.GetSuperTrackedMapPin
	if not (get and Enum.SuperTrackingMapPinType) then
		return nil
	end
	local kind, id = get()
	if kind == Enum.SuperTrackingMapPinType.TaxiNode and type(id) == "number" then
		return id
	end
end

local function RememberFocused()
	focusedQuest, focusedWaypoint, focusedNode = SuperTrackedQuest(), UserWaypoint(), SuperTrackedNode()
end

-- A loading screen starts from the focus the player already has; only a later change is theirs to route.
function ns.FocusedTrackingReset()
	RememberFocused()
end

-- Whether another addon leads the journey. The player's own journeys start without an API owner, or under this
-- addon's name through Nearby services.
---@return boolean
local function GuideLeads()
	local owner = ns.JourneyOwner and ns.JourneyOwner()
	return owner ~= nil and owner ~= "Shortest Path Forever"
end

---@param questID number
---@return boolean
local function GoalIsQuest(questID)
	local goal = ns.JourneyGoal and ns.JourneyGoal()
	if not goal then
		return false
	end
	if goal.questID == questID then
		return true
	end
	for _, id in ipairs(goal.questIDs or {}) do
		if id == questID then
			return true
		end
	end
	return false
end

---@param waypoint table
---@return boolean
local function GoalIsWaypoint(waypoint)
	local goal = ns.JourneyGoal and ns.JourneyGoal()
	local position = waypoint.position
	if not (goal and position) then
		return false
	end
	local point = ns.WorldPoint(waypoint.uiMapID, position.x, position.y)
	return point ~= nil and goal.map == point.map and goal.x == point.x and goal.y == point.y
end

---@param node number
---@return boolean
local function GoalIsNode(node)
	local goal, at = ns.JourneyGoal and ns.JourneyGoal(), ns.TaxiNodes[node]
	return goal ~= nil and at ~= nil and goal.map == at.map and goal.x == at.x and goal.y == at.y
end

local JourneyToPin

---@param node number
local function JourneyToNode(node)
	JourneyToPin(nil, { nodeID = node, name = ns.TaxiName and ns.TaxiName(node) or nil }, true)
end

---@param event string
function ns.FocusedTrackingChanged(event)
	local guide = ns.JourneyGuide
	local owned = guide and guide.OwnsReported and guide.OwnsReported(event) or false
	if event == "SUPER_TRACKING_CHANGED" then
		local questID, node = SuperTrackedQuest(), SuperTrackedNode()
		local changed, nodeChanged = questID ~= focusedQuest, node ~= focusedNode
		focusedQuest, focusedNode = questID, node
		if
			nodeChanged
			and node
			and not owned
			and ns.db
			and ns.db.focusedQuest
			and ns.db.journey
			and not GuideLeads()
			and not GoalIsNode(node)
		then
			JourneyToNode(node)
			return
		end
		if
			owned
			or not changed
			or not questID
			or not (ns.db and ns.db.focusedQuest and ns.db.journey)
			or GuideLeads()
			or GoalIsQuest(questID)
		then
			return
		end
		ns.JourneyToTrackedQuest()
		return
	end
	local waypoint = UserWaypoint()
	local changed = not (guide and guide.SameWaypoint and guide.SameWaypoint(waypoint, focusedWaypoint))
	focusedWaypoint = waypoint
	if
		owned
		or not changed
		or not waypoint
		or not (ns.db and ns.db.focusedQuest and ns.db.journey)
		or GoalIsWaypoint(waypoint)
	then
		return
	end
	ns.JourneyToUserWaypoint()
end

-- The journey key is this addon's gesture, so its canvas handler asks first. Higher priorities run first, and
-- OpenMap takes every plain or Alt left click on its stitched map at 1000 to zoom in (#1076).
local CANVAS_CLICK_PRIORITY = 1001

local function OnCanvasClick(map, button)
	if button ~= "LeftButton" or not ns.JourneyKeyDown() or ChatBoxOpen() then
		return false
	end
	-- Past the shown map's edge (OpenMap's stitched view) the spot is on no map this addon can read. OpenMap's
	-- own handler plans a Shift-click there through API.Navigate, on the zone under the cursor.
	local x, y = map:GetNormalizedCursorPosition()
	if not (x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) or JourneysOff() then
		return false
	end
	ns.JourneyToMapPoint(map:GetMapID(), x, y)
	return true
end

local function OnMinimapClick(_, button)
	if button ~= "LeftButton" or not ns.JourneyKeyDown() or JourneysOff() then
		return
	end
	local point = ns.MinimapPoint()
	if point then
		ns.StartJourney(point)
	else
		ns.Print(L["no journey can be planned to that spot."])
	end
end

-- A journey to a pin clicked with the journey key, labelled by its name if it has one: a flight point by its node,
-- anything else by where it stands on the map. False when there is nowhere to plan to.
---@param mapID? number
---@param info? {nodeID?: number, name?: string}
---@param flight boolean
---@param x? number
---@param y? number
---@return boolean
function JourneyToPin(mapID, info, flight, x, y)
	local node = flight and info and ns.TaxiNodes[info.nodeID]
	local point
	if node then
		point = { map = node.map, x = node.x, y = node.y, z = node.z }
	elseif mapID and x and y then
		point = ns.WorldPoint(mapID, x, y)
	end
	if not (point and OnZone(ns.InstanceEntrance(point))) then
		return false
	end
	point.label = info and info.name
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
		action ~= MapCanvasMixin.MouseAction.Click
		or button ~= "LeftButton"
		or not ns.JourneyKeyDown()
		or ChatBoxOpen()
		or JourneysOff()
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

-- A click with the journey key on one of the addon's own map pins (UI/Canvas.lua), as OnPinClick does for the map's.
-- The stop buttons keep their own click.
---@param pin SPFCanvasPin
---@param button string
---@return boolean
local function OnOwnPinClick(pin, button)
	if button ~= "LeftButton" or not ns.JourneyKeyDown() or ChatBoxOpen() then
		return false
	end
	local marker = pin.marker
	if (marker ~= "flight" and marker ~= "dock" and marker ~= "portal") or JourneysOff() then
		return false
	end
	local x, y = pin:GetPosition()
	local info = marker == "flight" and (pin --[[@as SPFAddonFlightPin]]).poiInfo or nil
	return JourneyToPin(pin:GetMap():GetMapID() --[[@as number]], info, marker == "flight", x, y)
end

-- A quest menu's entry and Adventure Guide's suggestions under it, wherever the menu is described: the client's own
-- menus below, and Kaliel's Tracker's dropdown (Core/KalielsTracker.lua), which is filled through the same calls.
---@param root table a menu description with CreateButton and CreateTitle
---@param questID number|string?
function ns.AddQuestMenuEntry(root, questID)
	if ns.db.journey and questID then
		root:CreateButton(L["Plan journey"], function()
			PlanQuest(questID)
		end)
		ns.AdventureSuggestions.AddQuestMenu(root)
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
-- the map's journey click does. A hidden button takes a CLICK binding without drawing anything.
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
	RememberFocused()
	Binding("ShortestPathForeverTravelToPinButton", ns.JourneyToUserWaypoint)
	Binding("ShortestPathForeverTravelToTrackedQuestButton", ns.JourneyToTrackedQuest)
	Binding("ShortestPathForeverClearJourneyButton", ns.ClearJourney)
	-- Questie owns Shift-click on its icons. While Shift is the journey key, Alt-click over a Questie icon plans
	-- there through our own event frame, and Alt-click anywhere else is left alone. When Alt is chosen, that one key
	-- plans everywhere, Questie icons included, and Shift no longer plans a journey. TomTom's map overlay passes
	-- LeftButton through; its waypoint gesture uses RightButton.
	local clicks = CreateFrame("Frame")
	clicks:RegisterEvent("GLOBAL_MOUSE_DOWN")
	clicks:SetScript("OnEvent", function(_, _, button)
		if button ~= "LeftButton" or not WorldMapFrame:IsShown() or not WorldMapFrame.ScrollContainer:IsMouseOver() then
			return
		end
		-- Only a Questie icon, whose own frame swallows the click, needs this handler: everywhere else the canvas and
		-- pin handlers answer the chosen key, and any other modified click is left to other addons (OpenMap's
		-- Alt-click deletes its markers). Over the icon the journey goes to the spawn it marks, on that spawn's floor.
		local iconMap, iconX, iconY = QuestieIconSpot()
		if not (iconMap and iconX and iconY) then
			return
		end
		if JourneyKey() == "shift" then
			-- Questie keeps Shift-click to untrack its quest; Alt-click plans the journey there.
			if not IsAltKeyDown() or IsShiftKeyDown() then
				return
			end
		elseif not ns.JourneyKeyDown() then
			return
		end
		if JourneysOff() then
			return
		end
		local point = ns.WorldPoint(iconMap, iconX, iconY)
		if point and point.z == nil then
			point.z = ns.SpawnHeight(point.map, point.x, point.y, QUESTIE_ICON_REACH)
		end
		if point and OnZone(ns.InstanceEntrance(point)) then
			ns.StartJourney(point)
		end
	end)
	-- The map's click registries are Blizzard's own for addons (MapCanvasSecureUtil.CreateHandlerRegistry): it keeps
	-- them outside the map's fields and calls each handler through securecallfunction, so the map's code never runs
	-- the addon's. The addon's own pins take their clicks through UI/Canvas.lua instead.
	-- The map's own pins write their tooltips themselves. The hint joins one owned by a pin OnPinClick plans to, found
	-- from the pin's fields alone (MapCanvasPinMixin's owningMap and normalizedX, QuestPinMixin's questID): none of its
	-- methods is called and nothing is written to it (WFA-38).
	GameTooltip:HookScript("OnShow", function(tooltip)
		local pin = tooltip:GetOwner()
		---@cast pin SPFMapPin?
		if not (pin and ns.JourneyClickHint()) or pin:IsForbidden() then
			return
		end
		local template = rawget(pin, "pinTemplate")
		if
			not WorldMapFrame:IsShown()
			or rawget(pin, "owningMap") ~= WorldMapFrame
			or type(template) ~= "string"
			or (template == "QuestPinTemplate" and not rawget(pin, "questID"))
			or (template ~= "QuestPinTemplate" and rawget(pin, "normalizedX") == nil)
		then
			return
		end
		ns.AddJourneyClickHint(tooltip)
		tooltip:Show()
	end)
	-- The minimap's tooltip, over what it tracks, is owned by UIParent, not the minimap: Minimap_OnUpdate
	-- (Blizzard_Minimap/Mainline/Minimap.lua) anchors it there and fills it with SetMinimapMouseover. Its tooltip data
	-- type is what says it is the minimap's, so the hint joins it there; a click on that spot plans to it.
	local minimapTooltip = Enum and Enum.TooltipDataType and Enum.TooltipDataType.MinimapMouseover
	if minimapTooltip and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		TooltipDataProcessor.AddTooltipPostCall(minimapTooltip, function(tooltip)
			if tooltip ~= GameTooltip or tooltip:IsForbidden() or not ns.JourneyClickHint() then
				return
			end
			ns.AddJourneyClickHint(tooltip)
			tooltip:Show()
		end)
	end
	WorldMapFrame:AddCanvasClickHandler(OnCanvasClick, CANVAS_CLICK_PRIORITY)
	WorldMapFrame:AddGlobalPinMouseActionHandler(OnPinClick)
	ns.Canvas.OnClick(OnOwnPinClick)
	-- The stock handler still pings the spot, which marks where the journey goes for your group too.
	Minimap:HookScript("OnMouseUp", OnMinimapClick)
	-- Our entries in the game's quest menus go through ns.ModifyMenu like every other menu this addon adds to: under
	-- the gamepad interface the game builds these menus itself and takes them into its focus in the same call, and a
	-- menu an addon added to is tainted, so the quest list's More options action on Y did nothing (#788).
	ns.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", "quest tracker", function(owner, root)
		---@cast owner Frame
		-- The native menu owner is the tracker container, with no quest ID/context data.
		-- Resolve the right-clicked HeaderButton's block; never reuse a previous hover's quest.
		ns.AddQuestMenuEntry(root, QuestIDFromTrackerFocus(owner))
	end)
	ns.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", "quest log", function(owner, root)
		---@cast owner SPFQuestMenuOwner
		-- Waypoint menus share this tag, but have no questID; the client also spells it questId.
		ns.AddQuestMenuEntry(root, owner.questID or owner.questId)
	end)
end)

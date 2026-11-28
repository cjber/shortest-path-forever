---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Guide: the arrow and the native user waypoint that steer along the journey's current leg. It borrows the player's
-- waypoint and super tracking, and gives them back when it stops or the player takes them over.
---@class SPFJourneyGuide
local Guide = {}
ns.JourneyGuide = Guide

local guide

-- Waypoint UI (github.com/Adaptvx/Waypoint-UI) drives the same native user waypoint we borrow. It is detected at the
-- point of use, because it may load after us. Use its public API to publish the guide's waypoint.
---@return table? navigation
local function WaypointUINavigation()
	local api = rawget(_G, "WaypointUIAPI")
	local navigation = type(api) == "table" and api.Navigation
	if type(navigation) ~= "table" or type(navigation.IsUserNavigationTracked) ~= "function" then
		return nil
	end
	if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("WaypointUI") then
		return nil
	end
	return navigation
end

-- Waypoint UI is tracking a navigation of its own, so it owns the native marker and we must not write it.
---@param navigation table
---@return boolean tracking
local function WaypointUITracking(navigation)
	local ok, tracking = ns.core.SafeCall("Waypoint UI tracking", navigation.IsUserNavigationTracked)
	return ok and tracking == true
end

-- Waypoint UI holds the native waypoint right now, so a change to it is Waypoint UI's, not the player's.
local function WaypointUIHolding()
	local navigation = WaypointUINavigation()
	if not navigation or type(navigation.GetUserNavigation) ~= "function" then
		return false
	end
	local ok, waypoint = ns.core.SafeCall("Waypoint UI waypoint", navigation.GetUserNavigation)
	return ok and waypoint ~= nil
end

-- Whether Waypoint UI is tracking a navigation of its own: its pin is the one in the world then, and ours
-- (UI/DestinationPin.lua) stands down rather than drawing a second one over it.
---@return boolean
function ns.WaypointUIPinOwned()
	local navigation = WaypointUINavigation()
	return navigation ~= nil and WaypointUITracking(navigation)
end

-- The title the tracker and JourneyInfo use, so Waypoint UI names the destination the same way the guide does.
---@param goal table?
---@return string? title
local function DestinationTitle(goal)
	if not goal then
		return nil
	end
	if goal.routeTitle then
		return goal.routeTitle
	end
	local ok, label = pcall(ns.PlaceLabel, goal)
	if ok and label then
		return string.format(ns.L["Journey to %s"], label)
	end
	return goal.label
end

-- Waypoint UI expects coordinates as percentages. Suppress placement audio on guide updates.
---@param navigation table
---@param title string?
---@param waypoint table
---@return boolean
local function HandOverToWaypointUI(navigation, title, waypoint)
	if type(navigation.NewUserNavigation) ~= "function" then
		return false
	end
	local ok, marker = ns.core.SafeCall("Waypoint UI handover", navigation.NewUserNavigation, {
		name = title,
		mapID = waypoint.uiMapID,
		x = waypoint.position.x * 100,
		y = waypoint.position.y * 100,
		flags = "ShortestPathForever",
		suppressAudio = true,
	})
	return ok and type(marker) == "table"
end

local function RefreshTracker()
	ns.journeyVersion = (ns.journeyVersion or 0) + 1
	ns.RefreshTracker()
end

local function SameWaypoint(a, b)
	if a == b then
		return true
	end
	if not (a and b) then
		return false
	end
	-- C_Map.GetUserWaypoint's position is a plain { x, y } table, not a Vector2D (WaypointLocationDataProvider.lua:183).
	if a.uiMapID == b.uiMapID and a.position.x == b.position.x and a.position.y == b.position.y then
		return true
	end
	local aMap, aWorld = C_Map.GetWorldPosFromMapPos(a.uiMapID, CreateVector2D(a.position.x, a.position.y))
	local bMap, bWorld = C_Map.GetWorldPosFromMapPos(b.uiMapID, CreateVector2D(b.position.x, b.position.y))
	-- Map changes can reproject or round the read-back. One yard absorbs that without claiming a different pin.
	return aWorld and bWorld and aMap == bMap and (aWorld.x - bWorld.x) ^ 2 + (aWorld.y - bWorld.y) ^ 2 <= 1
end

-- Whether two points are the same place on the map.
---@param a table?
---@param b table?
---@return boolean
local function SamePoint(a, b)
	return a == b or (a ~= nil and b ~= nil and a.map == b.map and a.x == b.x and a.y == b.y)
end

-- The game's in-world navigation marker (Blizzard_QuestNavigation/SuperTrackedFrame.lua) picks Blizzard's atlas
-- whenever the super-tracked target changes. While it points at the waypoint this guide placed, our own child frame
-- draws the addon's pin over its icon; a quest, a corpse or the player's own pin keeps Blizzard's icon.
local MARKER_SIZE = 36

---@return boolean
local function MarkerIsOurs()
	if not guide or not guide.waypoint or not guide.expectedWaypoint then
		return false
	end
	if not C_SuperTrack.IsSuperTrackingUserWaypoint() then
		return false
	end
	return SameWaypoint(C_Map.GetUserWaypoint(), guide.expectedWaypoint)
end

-- Our own frame, parented to the marker, holds a pin texture: it inherits the marker's alpha fading and follows its
-- icon, and Blizzard's UpdateIcon never touches it. Built once for the one marker the client keeps.
local markerPin, markerPinParent
---@param parent SPFSuperTrackedFrame
---@return Frame
local function MarkerPin(parent)
	if markerPin and markerPinParent == parent then
		return markerPin
	end
	local pinFrame = CreateFrame("Frame", nil, parent)
	local pin = pinFrame:CreateTexture(nil, "ARTWORK")
	ns.Art.Icon(pin, ns.PIN_FILE, MARKER_SIZE)
	pin:SetPoint("CENTER", parent.Icon, "CENTER")
	pinFrame:Hide()
	markerPin, markerPinParent = pinFrame, parent
	return pinFrame
end

-- The marker's own icon and border never have their alpha set by Blizzard's UpdateIcon, so ours sticks across its
-- repaints. Hidden again the moment the marker points at anything but the guide's waypoint.
local function RefreshNativeMarker()
	local frame = SuperTrackedFrame
	if not (frame and frame.Icon) then
		return
	end
	local ours = MarkerIsOurs() and not ns.WaypointUIPinOwned()
	if ours then
		MarkerPin(frame):Show()
	elseif markerPin then
		markerPin:Hide()
	end
	local alpha = ours and 0 or 1
	frame.Icon:SetAlpha(alpha)
	if frame.IconBorder then
		frame.IconBorder:SetAlpha(alpha)
	end
end

local function MarkerFollowsArrow()
	return not ns.db.guideStops or ns.db.arrowDirect == true
end

-- What the tracker calls the current leg's destination, with the journey's goal under it while the leg is a hop.
-- Nil when the client's waypoint is not ours: a player's own pin and Waypoint UI's navigation keep their tooltip.
---@return string? title, string? goalTitle
local function WaypointNames()
	if not guide or guide.paused or not guide.waypoint or WaypointUIHolding() then
		return nil
	end
	if not SameWaypoint(C_Map.GetUserWaypoint(), guide.expectedWaypoint) then
		return nil
	end
	if not MarkerFollowsArrow() then
		return guide.title
	end
	local title
	if guide.leg then
		local ok, label = pcall(ns.LegLabel, guide.leg)
		if ok then
			title = label
		end
	end
	if not title and guide.target then
		local ok, label = pcall(ns.PlaceLabel, guide.target)
		if ok then
			title = label
		end
	end
	title = title or guide.title
	if not title then
		return nil
	end
	local goalTitle
	if guide.leg and guide.goal and not SamePoint(guide.leg.to, guide.goal) then
		goalTitle = guide.title
		if goalTitle == title then
			goalTitle = nil
		end
	end
	return title, goalTitle
end

-- A tooltip hook must not read or draw on a tooltip the client has marked forbidden; nil is not a tooltip either.
---@param tooltip GameTooltip?
---@return boolean
local function Usable(tooltip)
	return tooltip ~= nil and not tooltip:IsForbidden()
end

-- Name the client's user waypoint tooltip for the waypoint Guide holds, keeping the client's own instructions and
-- adding the journey's goal under a hop. The map's WaypointLocationPin is the waypoint by its own OnEnter, so its
-- title is never read; the minimap names whatever the pointer is over, and only its readable MAP_PIN title says it
-- is the waypoint. 1.60.1 hands that title back as a secret value, which addon code may keep but not compare, so a
-- secret title leaves the client's tooltip as it is rather than guess whose it is.
---@param tooltip GameTooltip
---@param fromWaypointPin boolean? the client waypoint pin's own OnEnter, which is the waypoint or nothing
local function NameWaypointTooltip(tooltip, fromWaypointPin)
	if not Usable(tooltip) then
		return
	end
	local titleLine = GameTooltipTextLeft1
	if not titleLine then
		return
	end
	if not fromWaypointPin then
		local clientTitle = titleLine.GetText and titleLine:GetText()
		if not canaccessvalue(clientTitle) or clientTitle ~= MAP_PIN then
			return
		end
	end
	local title, goalTitle = WaypointNames()
	if not title then
		return
	end
	titleLine:SetText(title)
	if goalTitle then
		GameTooltip_AddNormalLine(tooltip, goalTitle)
	end
	tooltip:Show()
end

-- Whether a saved map pin stands at the journey's destination: arriving there clears the pin rather than restoring it.
---@param waypoint table
---@param point SPFPoint?
---@return boolean
local function PinAtGoal(waypoint, point)
	local location = point and ns.Locate(point)
	if not (waypoint and location) then
		return false
	end
	return SameWaypoint(waypoint, UiMapPoint.CreateFromCoordinates(location.uiMap, location.x, location.y))
end

-- A player pin at the destination and the guide's current marker both represent the journey.
local function IsJourneyWaypoint()
	local goal = ns.JourneyGoal()
	if not goal then
		return false
	end
	local waypoint = C_Map.GetUserWaypoint()
	return waypoint ~= nil
		and ((guide and SameWaypoint(waypoint, guide.writingWaypoint or guide.waypoint)) or PinAtGoal(waypoint, goal))
end

local waypointProviders = {}
-- Pins the world map's provider recreates on refresh; each one gets the tooltip hook once.
local hookedPins = setmetatable({}, { __mode = "k" })

-- Guide's waypoint is the marker Shortest Path wrote. Our own pin is the one a player should see, so hide the
-- native pin wherever Guide owns the waypoint: at the goal the gold pin stands there, and at a bend the route line
-- and the tracker name it. The player's own waypoint keeps the client's pin.
local function HideGuideWaypointPin(provider)
	if provider.pin then
		if not hookedPins[provider.pin] then
			hookedPins[provider.pin] = true
			provider.pin:HookScript("OnEnter", function(pin)
				NameWaypointTooltip(GameTooltip, true)
				if Usable(GameTooltip) and GameTooltip:IsOwned(pin) and IsJourneyWaypoint() then
					GameTooltip_AddNormalLine(GameTooltip, ns.L["Right-click to clear"])
					GameTooltip:Show()
				end
			end)
		end
		local owned = guide and (guide.writingWaypoint or guide.waypoint)
		provider.pin:SetShown(not (owned and SameWaypoint(C_Map.GetUserWaypoint(), owned)))
	end
end

-- The stock waypoint passes right clicks through to the canvas.
function Guide.ClearHoveredWaypointJourney()
	for _, provider in ipairs(waypointProviders) do
		local pin = provider.pin
		if pin and pin:IsShown() and pin:IsMouseOver() and IsJourneyWaypoint() then
			ns.PlayerClear()
			return true
		end
	end
	return false
end

local refreshPending = false
local function RefreshWaypointPins()
	if refreshPending or #waypointProviders == 0 then
		return
	end
	refreshPending = true
	-- The native provider recreates its pin during the same event/map refresh.
	C_Timer.After(0, function()
		refreshPending = false
		for _, provider in ipairs(waypointProviders) do
			HideGuideWaypointPin(provider)
		end
	end)
end

-- Tracking Guide restored and the client has not reported yet; auto-routing skips it.
---@class SPFGuideSettledTracking
---@field quest number?
---@field tracked boolean?
---@field kind Enum.SuperTrackingType?

---@type SPFGuideSettledTracking?
local settledTracking
local stopping

---@param waypoint table?
---@return table?
local function CopyWaypoint(waypoint)
	if waypoint then
		local position = waypoint.position
		return { uiMapID = waypoint.uiMapID, position = { x = position.x, y = position.y }, z = waypoint.z }
	end
end

-- Record the final super-tracking state for the deferred tracking event.
local function SettleTracking()
	settledTracking = {
		quest = C_SuperTrack.GetSuperTrackedQuestID(),
		tracked = C_SuperTrack.IsSuperTrackingUserWaypoint(),
		kind = C_SuperTrack.GetHighestPrioritySuperTrackingType(),
	}
end

local function ClearOrphanWaypoint()
	local saved = ns.charDB.guideWaypoint
	if guide or not saved then
		return
	end
	-- The guide does not survive a reload (Resume.lua may start the journey again, with a new guide), but the client
	-- saves user waypoints independently of this addon.
	ns.charDB.guideWaypoint = nil
	local point = UiMapPoint.CreateFromCoordinates(saved.uiMapID, saved.x, saved.y)
	if SameWaypoint(C_Map.GetUserWaypoint(), point) then
		local borrowed = saved.borrowed
		stopping = true
		local restored = borrowed
			and C_Map.SetUserWaypoint(
				UiMapPoint.CreateFromCoordinates(borrowed.uiMapID, borrowed.position.x, borrowed.position.y, borrowed.z)
			)
		if not restored then
			C_Map.ClearUserWaypoint()
		end
		C_SuperTrack.SetSuperTrackedUserWaypoint(restored and saved.borrowedTracked == true or false)
		stopping = nil
		SettleTracking()
		RefreshWaypointPins()
	end
end

local function RememberTracking(state)
	state.expectedQuest = C_SuperTrack.GetSuperTrackedQuestID()
	state.expectedTrackedWaypoint = C_SuperTrack.IsSuperTrackingUserWaypoint()
	state.expectedTrackingType = C_SuperTrack.GetHighestPrioritySuperTrackingType()
end

local function SameTracking(state)
	local quest = C_SuperTrack.GetSuperTrackedQuestID()
	local waypoint = C_SuperTrack.IsSuperTrackingUserWaypoint()
	local kind = C_SuperTrack.GetHighestPrioritySuperTrackingType()
	-- Another addon may select the quest whose area the player walks into (Adventure Guide's focus, RestedXP pointing
	-- at a quest of its own now and then) while the guide's waypoint stays the super-tracked destination. The priority
	-- type only says which icon the client draws this moment, not who owns navigation, so a selection on top of our
	-- waypoint is not a takeover: our waypoint is still the one super-tracked and still leads.
	if state.expectedTrackedWaypoint and waypoint then
		return true
	end
	return state.expectedQuest == quest
		and state.expectedTrackedWaypoint == waypoint
		and state.expectedTrackingType == kind
end

-- Waypoint writes are reported inside the write. Super-tracking is reported after the tracking has settled.
---@param event string
---@return boolean
function Guide.OwnsReported(event)
	if stopping or (guide and guide.writing) then
		return true
	end
	if event == "SUPER_TRACKING_CHANGED" and settledTracking then
		local reported = settledTracking
		settledTracking = nil
		if
			C_SuperTrack.GetSuperTrackedQuestID() == reported.quest
			and C_SuperTrack.IsSuperTrackingUserWaypoint() == reported.tracked
			and C_SuperTrack.GetHighestPrioritySuperTrackingType() == reported.kind
		then
			return true
		end
	end
	if not guide then
		return false
	end
	if not guide.hasDriven and WaypointUIHolding() then
		return true
	end
	if event == "USER_WAYPOINT_UPDATED" then
		if SameWaypoint(C_Map.GetUserWaypoint(), guide.expectedWaypoint) then
			return true
		end
		-- The slot was replaced. Until ownership is resolved, even an empty slot or a return to this point is external.
		guide.expectedWaypoint, guide.waypoint = false, nil
		ns.charDB.guideWaypoint = nil
		return false
	end
	return SameTracking(guide)
end

-- End the guide. `reason` is Journey's end reason: on arrival, a pin that was the journey's own destination is
-- cleared (the player asked for it to go), while any other pin the player had is put back.
---@param reason? string
local function StopGuide(reason)
	local previous = guide
	guide = nil
	ns.PointGuideArrow(nil)
	if previous then
		ns.charDB.guideWaypoint = nil
		if ns.GuideChanged then
			ns.GuideChanged()
		end
	end
	if
		not previous
		or not previous.hasDriven
		or previous.leaveWaypoint
		or not SameWaypoint(C_Map.GetUserWaypoint(), previous.expectedWaypoint)
	then
		RefreshWaypointPins()
		RefreshNativeMarker()
		if ns.RefreshJourneyPin then
			ns.RefreshJourneyPin()
		end
		return
	end
	local ownsTracking = not previous.yielded and SameTracking(previous)
	if reason == "arrived" and PinAtGoal(previous.previousWaypoint, previous.goal) then
		previous.previousWaypoint = nil
	end
	stopping = true
	local restored = previous.previousWaypoint and C_Map.SetUserWaypoint(previous.previousWaypoint)
	-- A rejected restoration must still remove our waypoint to avoid leaving it without an ownership record.
	if not restored and previous.waypoint then
		C_Map.ClearUserWaypoint()
	end
	settledTracking = nil
	if ownsTracking then
		local tracked = restored and previous.previousTrackedWaypoint or false
		C_SuperTrack.SetSuperTrackedUserWaypoint(tracked)
		if not tracked then
			C_SuperTrack.SetSuperTrackedQuestID(previous.previousQuest or 0)
		end
		SettleTracking()
	elseif not restored and C_SuperTrack.IsSuperTrackingUserWaypoint() then
		C_SuperTrack.SetSuperTrackedUserWaypoint(false)
		SettleTracking()
	end
	stopping = nil
	RefreshWaypointPins()
	RefreshNativeMarker()
	if ns.RefreshJourneyPin then
		ns.RefreshJourneyPin()
	end
end

local function OwnsWaypoint()
	-- Before SPF publishes a waypoint, Waypoint UI may already have a tracked pin to hand over.
	return (not guide.hasDriven and WaypointUIHolding())
		or SameWaypoint(C_Map.GetUserWaypoint(), guide.expectedWaypoint)
end

local function ClearGuideWaypoint()
	-- Synchronous clear events must see an internal write, and deferred events must see the empty expected point.
	guide.writing = true
	C_Map.ClearUserWaypoint()
	C_SuperTrack.SetSuperTrackedUserWaypoint(false)
	guide.waypoint, guide.expectedWaypoint = nil, nil
	guide.waypointTarget, guide.uiMap, guide.fading, guide.waypointNavigation = nil, nil, nil, nil
	ns.charDB.guideWaypoint = nil
	RememberTracking(guide)
	guide.writing = nil
	RefreshWaypointPins()
	RefreshNativeMarker()
	if ns.RefreshJourneyPin then
		ns.RefreshJourneyPin()
	end
end

local function YieldGuide()
	-- A quest/map-pin click belongs to the player. Keep the route arrow, but never retake tracking.
	guide.yielded = true
	if guide.waypoint then
		ClearGuideWaypoint()
	end
	if ns.RefreshJourneyPin then
		ns.RefreshJourneyPin()
	end
end

-- Whether the marker leads, which stands the screen arrow down. With "Mark only where steps end" the arrow leads,
-- and the waypoint marks the step destination.
local function MarkerLeads()
	return MarkerFollowsArrow() and guide.waypoint ~= nil and C_SuperTrack.IsSuperTrackingUserWaypoint()
end

local function GuideWaypoint(point, fading)
	if not guide or (ns.TomTomArrowActive and ns.TomTomArrowActive()) then
		return false
	end
	-- Leave an external pin in place while the waypoint event's ownership is being resolved.
	if not OwnsWaypoint() then
		RefreshTracker()
		return false
	end
	if not guide.yielded and not SameTracking(guide) then
		YieldGuide()
	end
	if guide.yielded then
		return false
	end
	local followsArrow = MarkerFollowsArrow()
	local uiMap
	if followsArrow then
		uiMap = C_Map.GetBestMapForUnit("player")
		-- Keep the current marker across frames where the player has no readable map (#826).
		if not uiMap then
			return MarkerLeads()
		end
	else
		-- The route arrow advances through bends and travel legs independently of the step waypoint.
		local goal = guide.goal
		if not (goal and goal.map and goal.x and goal.y) then
			return false
		end
		point, fading = goal, false
	end
	local navigation = WaypointUINavigation()
	local changed = not SamePoint(point, guide.waypointTarget) or uiMap ~= guide.uiMap or fading ~= guide.fading
	if changed or (guide.waypoint and navigation and navigation ~= guide.waypointNavigation) then
		guide.waypointTarget, guide.uiMap = { map = point.map, x = point.x, y = point.y }, uiMap
		guide.fading, guide.waypointNavigation = fading, navigation
		local waypoint
		if not followsArrow then
			local location = ns.Locate(point)
			if
				location
				and C_Map.CanSetUserWaypointOnMap(location.uiMap)
				and location.x >= 0
				and location.x <= 1
				and location.y >= 0
				and location.y <= 1
			then
				waypoint = UiMapPoint.CreateFromCoordinates(location.uiMap, location.x, location.y)
			end
		-- The native waypoint has no per-pin alpha; near the goal, use the fading fallback instead of stacking icons.
		elseif not fading and uiMap and C_Map.CanSetUserWaypointOnMap(uiMap) then
			local projectedMap, position =
				C_Map.GetMapPosFromWorldPos(point.map, CreateVector2D(point.x, point.y), uiMap)
			if projectedMap == uiMap and position then
				local x, y = position:GetXY()
				if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
					waypoint = UiMapPoint.CreateFromVector2D(uiMap, position)
				end
			end
		end
		-- These APIs may dispatch events synchronously. Only our own writes bypass ownership checks.
		guide.writing = true
		guide.writingWaypoint = waypoint
		local waypointUITracking = navigation ~= nil and WaypointUITracking(navigation)
		local expected
		if waypoint and navigation and HandOverToWaypointUI(navigation, guide.title, waypoint) then
			local current = C_Map.GetUserWaypoint()
			if SameWaypoint(current, waypoint) then
				expected = current
			end
		end
		local handedOver = expected ~= nil
		if not handedOver and changed and waypoint and not waypointUITracking and C_Map.SetUserWaypoint(waypoint) then
			local current = C_Map.GetUserWaypoint()
			if SameWaypoint(current, waypoint) then
				expected = current
			end
		end
		if expected then
			guide.waypoint, guide.expectedWaypoint = expected, CopyWaypoint(expected)
			ns.charDB.guideWaypoint = {
				uiMapID = expected.uiMapID,
				x = expected.position.x,
				y = expected.position.y,
				borrowed = CopyWaypoint(guide.previousWaypoint),
				borrowedTracked = guide.previousTrackedWaypoint,
			}
			guide.hasDriven = true
			if not handedOver then
				C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			end
		elseif changed and guide.waypoint then
			-- Never leave a stale native marker pointing at the previous target when placement fails.
			ClearGuideWaypoint()
		end
		-- Deferred events from our own writes must also agree with the expected tracking state.
		RememberTracking(guide)
		guide.writing, guide.writingWaypoint = nil, nil
		for _, provider in ipairs(waypointProviders) do
			HideGuideWaypointPin(provider)
		end
		RefreshNativeMarker()
		if ns.RefreshJourneyPin then
			ns.RefreshJourneyPin()
		end
	end
	return MarkerLeads()
end

-- The title Guide shows, built only when the goal or the strings it is named from change: Guide.To runs on the
-- journey's tick, and rebuilding a formatted title there would allocate every tick (#784).
---@param goal table?
---@return string?
local function GuideTitle(goal)
	local source = goal and (goal.routeTitleFormat or goal.routeTitle or goal.label)
	if goal ~= guide.titleGoal or source ~= guide.titleSource then
		guide.titleGoal, guide.titleSource = goal, source
		guide.title = DestinationTitle(goal)
	end
	return guide.title
end

-- Whether the guide still owns this walk's output. A restart, cast or explicit retarget
-- clears it even when the player and route have not changed.
---@param node SPFPoint|SPFPlace
---@param points? SPFWalkPoints
---@return boolean
function Guide.PointsTo(node, points)
	return guide ~= nil and guide.target == node and guide.points == points
end

---@param node table
---@param points table?
---@param goal table?
---@param leg? SPFLeg
function Guide.To(node, points, goal, leg)
	if not guide then
		return
	end
	local sameGoal = SamePoint(guide.goal, goal)
	guide.leg, guide.goal = leg, goal
	if guide.target == node and guide.points == points and sameGoal then
		GuideTitle(goal)
		return
	end
	if guide.paused then
		guide.paused = nil
		guide.pausedGoal = nil
		RefreshTracker()
	end
	guide.points = points
	guide.target = node
	GuideTitle(goal)
	local point = node.kind == "dock" and ns.DockPoint(node.id) or node
	ns.PointGuideArrow(points or { point }, GuideWaypoint, node, goal)
	if (ns.db.arrow == false or (ns.TomTomArrowActive and ns.TomTomArrowActive())) and guide and guide.waypoint then
		if OwnsWaypoint() then
			ClearGuideWaypoint()
		end
	end
end

-- Keep the owner's stop while it waits for quest progress, without directions to a place already reached. The arrow
-- becomes the arrival pin over the stop's own area (#627), and leaves it to the guide when the stop changes.
---@param goal SPFPoint?
function Guide.Pause(goal)
	if not guide then
		return
	end
	-- The route can pause before To() has populated the display target.
	goal = goal or guide.goal or guide.pausedGoal
	if guide.paused then
		guide.pausedGoal = goal
		-- The driver asks every tick while the player stands in the area: only the arrival pin may need putting back,
		-- for a setting turned on again, and a waypoint combat kept until it ended still has to go.
		if not InCombatLockdown() and guide.waypoint and OwnsWaypoint() then
			ClearGuideWaypoint()
		end
		if ns.PointArrivalPin then
			ns.PointArrivalPin(goal)
		end
		return
	end
	local changed = true
	guide.paused = true
	guide.pausedGoal = goal
	guide.points, guide.target, guide.waypointTarget, guide.leg, guide.goal = nil, nil, nil, nil, nil
	ns.PointGuideArrow(nil)
	if ns.PointArrivalPin then
		ns.PointArrivalPin(goal)
	end
	if not InCombatLockdown() and guide.waypoint and OwnsWaypoint() then
		ClearGuideWaypoint()
	end
	if changed then
		RefreshTracker()
		if ns.RefreshJourneyPin then
			ns.RefreshJourneyPin()
		end
	end
end

function Guide.Paused()
	return guide ~= nil and guide.paused == true
end

-- The leg under way is a teleport, cast where you stand: there is no walking point to read. Guide.Cast clears the
-- arrow's points and keeps the leg as its target, which is what this distinguishes from a paused or stopped guide.
---@return boolean
function Guide.Casting()
	return guide ~= nil and guide.points == nil and guide.target ~= nil and guide.target.teleport ~= nil
end

-- A teleport is cast where you stand: show the item or spell to use, with no walking arrow.
---@param leg SPFLeg
---@param goal SPFPoint?
function Guide.Cast(leg, goal)
	if not guide or (guide.target == leg and SamePoint(guide.goal, goal)) then
		return
	end
	local casting = guide
	local keepWaypoint = goal and not MarkerFollowsArrow() and SamePoint(guide.waypointTarget, goal)
	guide.points, guide.target, guide.goal = nil, leg, goal
	ns.PointGuideArrow(nil)
	if guide ~= casting or guide.target ~= leg then
		return
	end
	ns.PointCastPrompt(leg.teleport)
	if guide == casting and guide.waypoint and not keepWaypoint and OwnsWaypoint() then
		ClearGuideWaypoint()
	end
end

-- The next Guide.To re-points the arrow even at the same target.
function Guide.Retarget()
	ns.PointCastPrompt(nil)
	if guide then
		guide.target, guide.leg, guide.goal = nil, nil, nil
	end
end

-- The arrow switch changes a cast's visibility without resetting its canonical guidance phase.
function Guide.ArrowChanged()
	local teleport = guide and guide.target and guide.target.teleport
	if teleport and Guide.Casting() then
		ns.PointCastPrompt(teleport)
	else
		Guide.Retarget()
	end
end

---@return boolean
function Guide.Active()
	return guide ~= nil
end

-- Whether the player took native navigation over: the route arrow still leads, the client's marker is theirs.
---@return boolean
function Guide.Yielded()
	return guide ~= nil and guide.yielded == true
end

-- Whether the journey's goal is guided right now, and so wears the gold pin. With step-end marks the arrow
-- leads independently of the waypoint. The goal pin is gold only
-- then; a paused, yielded or stopped guide is the bronze untracked state, and a planned route with no guide is too.
---@return boolean
function ns.JourneyPinTracked()
	return guide ~= nil
		and not guide.paused
		and not guide.yielded
		and (ns.db.guideStops or (guide.waypoint ~= nil and C_SuperTrack.IsSuperTrackingUserWaypoint()))
end

-- The current waypoint covers a stop only when it marks that stop's world point. A waypoint on an
-- earlier bend still needs the separate destination pin.
---@param stop SPFPoint
---@return boolean
function Guide.HasWaypointAtStop(stop)
	return guide ~= nil
		and guide.waypoint ~= nil
		and SamePoint(guide.waypointTarget, stop)
		and SameWaypoint(C_Map.GetUserWaypoint(), guide.waypoint)
end

function Guide.Start()
	ClearOrphanWaypoint()
	settledTracking = nil
	local previous = C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint()
	local saved = previous
		and UiMapPoint.CreateFromCoordinates(previous.uiMapID, previous.position.x, previous.position.y, previous.z)
	guide = {
		previousQuest = C_SuperTrack.GetSuperTrackedQuestID(),
		previousWaypoint = saved,
		expectedWaypoint = previous or nil,
		previousTrackedWaypoint = saved ~= nil and C_SuperTrack.IsSuperTrackingUserWaypoint(),
	}
	RememberTracking(guide)
	if ns.GuideChanged then
		ns.GuideChanged()
	end
end

-- A quest the player tracked before the journey is gone; never restore its tracking.
function Guide.QuestGone(questID)
	if guide and guide.previousQuest == questID then
		guide.previousQuest = nil
	end
end

---@param event string
---@param waypointOwner? "guide"|"RestedXP"|"stops"
function Guide.TrackingChanged(event, waypointOwner)
	RefreshWaypointPins()
	if not guide or guide.writing or (not guide.hasDriven and WaypointUIHolding()) then
		return
	end
	local waypoint = C_Map.GetUserWaypoint()
	if SameWaypoint(waypoint, guide.expectedWaypoint) then
		if event == "SUPER_TRACKING_CHANGED" and not SameTracking(guide) then
			YieldGuide()
		end
		return
	end
	-- Removing the pin a guide stepped aside for gives it nothing new to yield to.
	if waypointOwner == "RestedXP" or waypointOwner == "stops" or (guide.leaveWaypoint and not waypoint) then
		-- The native slot changed hands while the guide keeps leading the same route.
		guide.expectedWaypoint = waypoint
		guide.waypointTarget, guide.uiMap, guide.fading, guide.waypointNavigation = nil, nil, nil, nil
		RememberTracking(guide)
		if waypointOwner == "stops" then
			guide.leaveWaypoint = true
			YieldGuide()
		end
		-- Standing still redraws nothing, so an emptied slot asks the arrow to mark it again.
		if not waypoint and ns.RedrawGuideMarker then
			ns.RedrawGuideMarker()
		end
		RefreshTracker()
		return
	end
	local clearPlayerJourney = event == "USER_WAYPOINT_UPDATED"
		and guide.hasDriven
		and not guide.yielded
		and guide.goal
		and (guide.goal.questID ~= nil or #(guide.goal.questIDs or {}) > 0)
		and waypoint == nil
		and (not ns.JourneyOwner or ns.JourneyOwner() == nil)
	StopGuide()
	if clearPlayerJourney and ns.ClearJourney then
		ns.ClearJourney()
	else
		RefreshTracker()
	end
end

Guide.Stop = StopGuide
Guide.ClearOrphan = ClearOrphanWaypoint
Guide.SameWaypoint = SameWaypoint
Guide.RefreshWaypointPins = RefreshWaypointPins
Guide.RefreshTracker = RefreshTracker
Guide.WaypointNames = WaypointNames
Guide.NameWaypointTooltip = NameWaypointTooltip

-- Blizzard_QuestNavigation loads on demand, so the marker may arrive after this addon's own load; every tracking or
-- waypoint change is ours to answer too, and none of it goes through Blizzard's own frame methods.
local markerEvents = CreateFrame("Frame")
markerEvents:RegisterEvent("SUPER_TRACKING_CHANGED")
markerEvents:RegisterEvent("USER_WAYPOINT_UPDATED")

ns.Init(function()
	markerEvents:RegisterEvent("ADDON_LOADED")
	RefreshNativeMarker()
	markerEvents:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if
				name == "WaypointUI"
				and guide
				and guide.waypointTarget
				and guide.waypoint
				and not InCombatLockdown()
			then
				GuideWaypoint(guide.waypointTarget, guide.fading)
			elseif name ~= "Blizzard_QuestNavigation" then
				return
			end
		end
		RefreshNativeMarker()
	end)
	for provider in pairs(WorldMapFrame.dataProviders) do
		if provider.RefreshAllData == WaypointLocationDataProviderMixin.RefreshAllData then
			waypointProviders[#waypointProviders + 1] = provider
		end
	end
	-- Minimap_OnUpdate (Blizzard_Minimap/Mainline/Minimap.lua) rebuilds its tooltip from
	-- C_TooltipInfo.GetMinimapMouseover on every mouseover update; TooltipDataHandler.lua runs these callbacks after
	-- the client's lines are in place.
	local minimap = Enum and Enum.TooltipDataType and Enum.TooltipDataType.MinimapMouseover
	if minimap and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
		TooltipDataProcessor.AddTooltipPostCall(minimap, function(tooltip)
			if not Usable(tooltip) then
				return
			end
			NameWaypointTooltip(tooltip)
		end)
	end
end)

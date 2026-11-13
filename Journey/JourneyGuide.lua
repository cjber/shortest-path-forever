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
-- point of use, because it may load after us. While it is tracking a navigation it owns the marker: we hand our
-- destination over through its public API instead of writing the waypoint and clearing each other's pin.
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

-- Hand our destination to Waypoint UI rather than writing the waypoint it is already tracking. Wrapped in
-- ns.core.SafeCall so a renamed or absent member can never raise into the guide. Waypoint UI's public API takes
-- coordinates as percent,
-- while our bend coordinates are normalized 0-1, so we scale them by 100 here.
---@param navigation table
---@param title string?
---@param uiMap number
---@param x number
---@param y number
local function HandOverToWaypointUI(navigation, title, uiMap, x, y)
	if type(navigation.NewUserNavigation) ~= "function" then
		return
	end
	ns.core.SafeCall("Waypoint UI handover", navigation.NewUserNavigation, {
		name = title,
		mapID = uiMap,
		x = x * 100,
		y = y * 100,
	})
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
	local ours = MarkerIsOurs()
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
			provider.pin:HookScript("OnEnter", function()
				NameWaypointTooltip(GameTooltip, true)
			end)
		end
		local owned = guide and (guide.writingWaypoint or guide.waypoint)
		provider.pin:SetShown(not (owned and SameWaypoint(C_Map.GetUserWaypoint(), owned)))
	end
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
		C_Map.ClearUserWaypoint()
		C_SuperTrack.SetSuperTrackedUserWaypoint(false)
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

-- Tracking Guide itself wrote and the client has not reported yet: the pin it restored when it stopped, and the
-- quest and waypoint it handed back. Auto-routing (JourneyInput.lua) reads these so none of them counts as the
-- player focusing a quest or placing a pin.
---@class SPFGuideSettled
---@field waypoint table?
---@field waypointPending boolean?
---@field quest number?
---@field tracked boolean?
---@field kind Enum.SuperTrackingType?
---@field trackingPending boolean?

---@type SPFGuideSettled?
local settled
local stopping

---@param waypoint table?
---@return table?
local function CopyWaypoint(waypoint)
	if not waypoint then
		return nil
	end
	local position = waypoint.position
	return { uiMapID = waypoint.uiMapID, position = { x = position.x, y = position.y }, z = waypoint.z }
end

-- Record what Guide left behind after its final writes, for the deferred events those writes raise.
---@param waypoint boolean whether it wrote the user waypoint
---@param tracking boolean whether it wrote the super-tracked state
local function Settled(waypoint, tracking)
	settled = {
		waypoint = waypoint and CopyWaypoint(C_Map.GetUserWaypoint()) or nil,
		waypointPending = waypoint or nil,
		quest = C_SuperTrack.GetSuperTrackedQuestID(),
		tracked = C_SuperTrack.IsSuperTrackingUserWaypoint(),
		kind = C_SuperTrack.GetHighestPrioritySuperTrackingType(),
		trackingPending = tracking or nil,
	}
	if not (settled.waypointPending or settled.trackingPending) then
		settled = nil
	end
end

local function SettledChanged(event)
	if not settled then
		return false
	end
	if event == "USER_WAYPOINT_UPDATED" and settled.waypointPending then
		local wasOurs = SameWaypoint(C_Map.GetUserWaypoint(), settled.waypoint)
		settled.waypointPending = nil
		if not settled.trackingPending then
			settled = nil
		end
		return wasOurs
	end
	if event == "SUPER_TRACKING_CHANGED" and settled.trackingPending then
		local wasOurs = C_SuperTrack.GetSuperTrackedQuestID() == settled.quest
			and C_SuperTrack.IsSuperTrackingUserWaypoint() == settled.tracked
			and C_SuperTrack.GetHighestPrioritySuperTrackingType() == settled.kind
		settled.trackingPending = nil
		if not settled.waypointPending then
			settled = nil
		end
		return wasOurs
	end
	return false
end

-- Whether the client's report is Guide's own write rather than the player's choice. Called after
-- Guide.TrackingChanged, so a guide the player just took over has already yielded or stopped.
---@param event string
---@return boolean
function Guide.OwnsReported(event)
	if stopping or (guide and guide.writing) or SettledChanged(event) then
		return true
	end
	if not guide then
		return false
	end
	if WaypointUIHolding() then
		return true
	end
	if event == "USER_WAYPOINT_UPDATED" then
		return SameWaypoint(C_Map.GetUserWaypoint(), guide.expectedWaypoint)
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
	-- A rejected restoration must still remove our bend, rather than leave it behind without an ownership record.
	if not restored and previous.waypoint then
		C_Map.ClearUserWaypoint()
	end
	local wroteWaypoint = previous.previousWaypoint ~= nil or previous.waypoint ~= nil
	local wroteTracking = false
	if ownsTracking then
		local tracked = restored and previous.previousTrackedWaypoint or false
		C_SuperTrack.SetSuperTrackedUserWaypoint(tracked)
		if not tracked then
			C_SuperTrack.SetSuperTrackedQuestID(previous.previousQuest or 0)
		end
		wroteTracking = true
	elseif not restored and C_SuperTrack.IsSuperTrackingUserWaypoint() then
		C_SuperTrack.SetSuperTrackedUserWaypoint(false)
		wroteTracking = true
	end
	stopping = nil
	Settled(wroteWaypoint, wroteTracking)
	RefreshWaypointPins()
	RefreshNativeMarker()
	if ns.RefreshJourneyPin then
		ns.RefreshJourneyPin()
	end
end

local function OwnsWaypoint()
	-- Waypoint UI holds the native waypoint while it navigates; a change to it is not the player taking over.
	if WaypointUIHolding() then
		return true
	end
	if not SameWaypoint(C_Map.GetUserWaypoint(), guide.expectedWaypoint) then
		-- A manual replacement or removal ends guidance; never reclaim the player's waypoint.
		StopGuide()
		return false
	end
	return true
end

local function ClearGuideWaypoint()
	-- Synchronous clear events must see an internal write, and deferred events must see the empty expected point.
	guide.writing = true
	C_Map.ClearUserWaypoint()
	C_SuperTrack.SetSuperTrackedUserWaypoint(false)
	guide.waypoint, guide.expectedWaypoint = nil, nil
	guide.bend, guide.uiMap, guide.fading = nil, nil, nil
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

local function GuideWaypoint(point, fading)
	if not guide then
		return false
	end
	-- The bend callback can run before deferred notifications of a player's waypoint or tracking change.
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
	local uiMap = C_Map.GetBestMapForUnit("player")
	-- A frame with no map for the player is no place to move the marker, or to take it away: the waypoint Guide
	-- already placed is still the guidance the player has, and the client draws it on the map it names next. Taking it
	-- away drops the game's own pin and writes it back on the next readable frame, so guidance blinks while the
	-- journey scans (#826).
	if not uiMap then
		return guide.waypoint ~= nil and C_SuperTrack.IsSuperTrackingUserWaypoint()
	end
	local bend = guide.bend
	if
		not bend
		or point.map ~= bend.map
		or point.x ~= bend.x
		or point.y ~= bend.y
		or uiMap ~= guide.uiMap
		or fading ~= guide.fading
	then
		guide.bend, guide.uiMap = { map = point.map, x = point.x, y = point.y }, uiMap
		guide.fading = fading
		local waypoint
		local navigation = WaypointUINavigation()
		local yielding = navigation ~= nil and WaypointUITracking(navigation)
		-- The native waypoint has no per-pin alpha; near the goal, use the fading fallback instead of stacking icons.
		if not fading and uiMap and C_Map.CanSetUserWaypointOnMap(uiMap) then
			local projectedMap, position =
				C_Map.GetMapPosFromWorldPos(point.map, CreateVector2D(point.x, point.y), uiMap)
			if projectedMap == uiMap and position then
				local x, y = position:GetXY()
				if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
					if yielding and navigation then
						-- Waypoint UI owns the native marker: hand the bend over and never write the waypoint ourselves.
						-- The second test narrows `navigation` to non-nil for LuaLS: `yielding` already implies it, and nil can
						-- never reach here because a nil navigation makes it false.
						HandOverToWaypointUI(navigation, guide.title, uiMap, x, y)
						guide.waypoint, guide.expectedWaypoint = nil, nil
						ns.charDB.guideWaypoint = nil
					else
						waypoint = UiMapPoint.CreateFromVector2D(uiMap, position)
					end
				end
			end
		end
		-- These APIs may dispatch events synchronously. Only our own writes bypass ownership checks.
		guide.writing = true
		guide.writingWaypoint = waypoint
		if waypoint and C_Map.SetUserWaypoint(waypoint) then
			guide.waypoint, guide.expectedWaypoint = waypoint, waypoint
			ns.charDB.guideWaypoint = { uiMapID = waypoint.uiMapID, x = waypoint.position.x, y = waypoint.position.y }
			guide.hasDriven = true
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		elseif guide.waypoint then
			-- Never leave a stale native marker pointing at the preceding bend when projection fails.
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
	return guide.waypoint ~= nil and C_SuperTrack.IsSuperTrackingUserWaypoint()
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

---@param node table
---@param points table?
---@param goal table?
---@param leg? SPFLeg
function Guide.To(node, points, goal, leg)
	if not guide then
		return
	end
	guide.leg, guide.goal = leg, goal
	if guide.target == node and guide.points == points then
		GuideTitle(goal)
		return
	end
	if guide.paused then
		guide.paused = nil
		guide.pausedGoal = nil
		RefreshTracker()
	end
	if ns.db.arrow == false and guide.waypoint then
		if not OwnsWaypoint() then
			return
		end
		ClearGuideWaypoint()
	end
	guide.points = points
	guide.target = node
	GuideTitle(goal)
	local point = node.kind == "dock" and ns.DockPoint(node.id) or node
	ns.PointGuideArrow(points or { point }, GuideWaypoint, node, goal)
end

-- Keep the owner's stop while it waits for quest progress, without directions to a place already reached. The arrow
-- becomes the arrival pin over the stop's own area (#627), and leaves it to the guide when the stop changes.
function Guide.Pause()
	if not guide then
		return
	end
	if guide.paused then
		-- The driver asks every tick while the player stands in the area: only the arrival pin may need putting back,
		-- for a setting turned on again, and a waypoint combat kept until it ended still has to go.
		if not InCombatLockdown() and guide.waypoint and OwnsWaypoint() then
			ClearGuideWaypoint()
		end
		if ns.PointArrivalPin then
			ns.PointArrivalPin(guide.pausedGoal)
		end
		return
	end
	local goal = guide.goal
	local changed = true
	guide.paused = true
	guide.pausedGoal = goal
	guide.points, guide.target, guide.bend, guide.leg, guide.goal = nil, nil, nil, nil, nil
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

-- A teleport is cast where you stand: show the item or spell to use, with no walking arrow.
---@param leg SPFLeg
function Guide.Cast(leg)
	if not guide or guide.target == leg then
		return
	end
	local casting = guide
	guide.points, guide.target = nil, leg
	ns.PointGuideArrow(nil)
	if guide ~= casting or guide.target ~= leg then
		return
	end
	ns.PointCastPrompt(leg.teleport)
	if guide.waypoint then
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

---@return boolean
function Guide.Active()
	return guide ~= nil
end

-- Whether the player took native navigation over: the route arrow still leads, the client's marker is theirs.
---@return boolean
function Guide.Yielded()
	return guide ~= nil and guide.yielded == true
end

-- Whether the journey's goal is tracked as the client's waypoint right now. The goal pin is gold only then; a
-- paused, yielded or stopped guide is the bronze untracked state, and a planned route with no guide is too.
---@return boolean
function ns.JourneyPinTracked()
	return guide ~= nil
		and not guide.paused
		and not guide.yielded
		and guide.waypoint ~= nil
		and C_SuperTrack.IsSuperTrackingUserWaypoint()
end

function Guide.Start()
	ClearOrphanWaypoint()
	settled = nil
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

function Guide.TrackingChanged(event)
	RefreshWaypointPins()
	if not guide or guide.writing then
		return
	end
	if WaypointUIHolding() then
		-- Waypoint UI's own write or tracking change: keep steering and never treat it as the player taking over.
		return
	end
	if not OwnsWaypoint() then
		RefreshTracker()
	elseif event == "SUPER_TRACKING_CHANGED" and not SameTracking(guide) then
		YieldGuide()
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
	if SuperTrackedFrame and SuperTrackedFrame.Icon then
		RefreshNativeMarker()
	else
		markerEvents:RegisterEvent("ADDON_LOADED")
	end
	markerEvents:SetScript("OnEvent", function(self, event, name)
		if event == "ADDON_LOADED" then
			if name ~= "Blizzard_QuestNavigation" then
				return
			end
			self:UnregisterEvent("ADDON_LOADED")
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

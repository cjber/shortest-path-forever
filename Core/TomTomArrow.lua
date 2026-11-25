---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- With TomTom installed and "Use TomTom's arrow" on, Shortest Path drives TomTom's Crazy Arrow to the current
-- guide step instead of drawing its own arrow or placing Blizzard's navigation marker. Waypoints we add are
-- tagged by table identity so Core/TomTom.lua's tomtomFollow ignores them and never loops, and foreign waypoints
-- set by the player or another addon are never overwritten or removed.

-- Weak keys: a waypoint nobody holds any more takes its ownership tag with it.
---@type table<table, boolean>
local ownWaypoints = setmetatable({}, { __mode = "k" })
local adding = false
local repointing = false
local removing = false
local suppressingReplacement = false
local notifyingArrow = false
local syncedFromArrow = false
-- True only while TomTom actually holds our active step target (either our own waypoint or a repointed foreign one).
local driven = false
---@type TomTomWaypoint?
local currentUid
---@type TomTomWaypoint?
local drivenForeign
-- When a TomTom implementation lacks ClearCrazyArrowPoint and leaves our removed waypoint on its arrow until the next
-- ArrowUpdate, that exact removed table identifies the one automatic replacement to suppress.
---@type TomTomWaypoint?
local replacedArrowUid
local currentMap, currentX, currentY, currentTitle
---@type SPFWalkPoints?
local activePoints
---@type SPFPlace?
local activeStop
---@type SPFPoint?
local activeGoal

---@param value any
---@return boolean
local function FiniteNumber(value)
	return canaccessvalue(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

---@param a SPFPoint?
---@param b SPFPoint?
---@return boolean
local function SamePoint(a, b)
	return a == b or (a ~= nil and b ~= nil and a.map == b.map and a.x == b.x and a.y == b.y)
end

-- Whether settings and TomTom allow driving TomTom's arrow (real TomTom loaded, opt-in on, arrow not off).
---@return boolean
local function TomTomArrowEnabled()
	return ns.db ~= nil
		and ns.db.tomtomArrow == true
		and ns.db.arrow ~= false
		and ns.RealTomTom ~= nil
		and ns.RealTomTom() ~= nil
end

-- Whether Shortest Path actually owns TomTom's arrow right now. Returns false if projecting or adding the waypoint
-- failed, so UI/Arrow.lua and JourneyGuide.lua fall back to our own arrow and native marker.
---@return boolean
function ns.TomTomArrowActive()
	return driven and TomTomArrowEnabled()
end

-- Recognised strictly by the waypoint table we created, or while suppressing TomTom's automatic arrow update caused
-- by our own waypoint removal or repointing.
---@param uid any
---@return boolean
function ns.IsOwnTomTomWaypoint(uid)
	return removing or repointing or suppressingReplacement or (type(uid) == "table" and ownWaypoints[uid] == true)
end

local function NotifyDrivenChanged()
	if ns.SyncTomTomArrow then
		ns.SyncTomTomArrow()
	end
	if not notifyingArrow and ns.ArrowBearingChanged then
		notifyingArrow = true
		ns.ArrowBearingChanged()
		notifyingArrow = false
	end
end

-- TomTom calls SetCrazyArrow synchronously inside AddWaypoint before returning the waypoint table, and may also
-- replace a removed own waypoint with the closest remaining foreign waypoint on its next update.
---@param uid any
function ns.OnTomTomCrazyArrow(uid)
	if adding and type(uid) == "table" then
		ownWaypoints[uid] = true
		return
	end
	if replacedArrowUid ~= nil then
		local previousArrow = ns.TomTomArrowWaypoint and ns.TomTomArrowWaypoint()
		local tomtom = ns.RealTomTom and ns.RealTomTom()
		local existing = type(uid) == "table"
			and tomtom ~= nil
			and (type(tomtom.IsValidWaypoint) ~= "function" or tomtom:IsValidWaypoint(uid))
		if previousArrow == replacedArrowUid and existing then
			suppressingReplacement = true
		end
		replacedArrowUid = nil
	end
end

function ns.AfterTomTomCrazyArrow()
	suppressingReplacement = false
end

---@param uid any
function ns.OnTomTomWaypointRemoved(uid)
	if uid == nil then
		return
	end
	if uid == currentUid or uid == drivenForeign then
		if uid == currentUid then
			currentUid = nil
		end
		if uid == drivenForeign then
			drivenForeign = nil
		end
		currentMap, currentX, currentY, currentTitle = nil, nil, nil, nil
		local wasDriven = driven
		driven = false
		if wasDriven and not removing then
			NotifyDrivenChanged()
		end
	end
end

---@param tomtom TomTom?
---@param uid TomTomWaypoint?
---@param clearArrow boolean
local function RemoveOwnWaypoint(tomtom, uid, clearArrow)
	if not (tomtom and uid and type(tomtom.RemoveWaypoint) == "function") then
		return
	end
	local wasOnArrow = clearArrow and ns.TomTomArrowWaypoint ~= nil and ns.TomTomArrowWaypoint() == uid
	removing = true
	ns.core.SafeCall("TomTom arrow remove", tomtom.RemoveWaypoint, tomtom, uid)
	if wasOnArrow and ns.TomTomArrowWaypoint() == uid and type(tomtom.ClearCrazyArrowPoint) == "function" then
		ns.core.SafeCall("TomTom arrow clear", tomtom.ClearCrazyArrowPoint, tomtom, false)
	end
	removing = false
	if wasOnArrow and ns.TomTomArrowWaypoint() == uid then
		replacedArrowUid = uid
	end
end

local function ClearDriven()
	local uid = currentUid
	currentUid = nil
	drivenForeign = nil
	driven = false
	currentMap, currentX, currentY, currentTitle = nil, nil, nil, nil
	if not uid then
		return
	end
	RemoveOwnWaypoint(ns.RealTomTom and ns.RealTomTom() or nil, uid, true)
end

---@param point SPFPoint?
---@return integer? uiMap, number? x, number? y
local function ProjectPoint(point)
	if not (point and FiniteNumber(point.map) and FiniteNumber(point.x) and FiniteNumber(point.y)) then
		return nil
	end
	local uiMap, position
	if ns.ZoneMap then
		uiMap, position = ns.ZoneMap(point.map, point.x, point.y)
	end
	if not (uiMap and position) then
		uiMap, position = C_Map.GetMapPosFromWorldPos(point.map, CreateVector2D(point.x, point.y))
	end
	if not (uiMap and position and FiniteNumber(uiMap) and uiMap > 0 and uiMap % 1 == 0) then
		return nil
	end
	local x, y = position:GetXY()
	if not (FiniteNumber(x) and FiniteNumber(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
		return nil
	end
	return uiMap, x, y
end

---@param stop SPFPlace?
---@param goal SPFPoint?
---@return string
local function StepTitle(stop, goal)
	if stop and (not goal or not SamePoint(stop, goal)) then
		if ns.PlaceLabel then
			local ok, label = pcall(ns.PlaceLabel, stop)
			if ok and type(label) == "string" and label ~= "" then
				return label
			end
		end
		if type(stop.label) == "string" and stop.label ~= "" then
			return stop.label
		end
	end
	if goal then
		if type(goal.routeTitle) == "string" and goal.routeTitle ~= "" then
			return goal.routeTitle
		end
		if type(goal.label) == "string" and goal.label ~= "" then
			return goal.label
		end
		if ns.PlaceLabel then
			local ok, label = pcall(ns.PlaceLabel, goal)
			if ok and type(label) == "string" and label ~= "" then
				return label
			end
		end
	end
	return ns.L["Journey"]
end

---@return SPFPoint? point, SPFPlace? stop, SPFPoint? goal
local function CurrentTarget()
	if not activePoints or #activePoints == 0 then
		return nil
	end
	local stop, goal = activeStop, activeGoal
	local point
	if ns.db and ns.db.arrowDirect == true then
		local _, _, _, map = ns.JourneyPosition()
		point = (goal and goal.map == map and goal) or activePoints[#activePoints]
	elseif ns.GuideState then
		local target, _, _, stateStop, stateGoal = ns.GuideState()
		point = target or activePoints[#activePoints]
		stop = stateStop or stop
		goal = stateGoal or goal
	else
		point = activePoints[#activePoints]
	end
	return point, stop, goal
end

---@param notifyArrow? boolean
local function SyncDriven(notifyArrow)
	local wasDriven = driven
	if not TomTomArrowEnabled() then
		ClearDriven()
		if notifyArrow and wasDriven ~= driven then
			NotifyDrivenChanged()
		end
		return
	end
	local point, stop, goal = CurrentTarget()
	if not point then
		ClearDriven()
		if notifyArrow and wasDriven ~= driven then
			NotifyDrivenChanged()
		end
		return
	end
	local uiMap, x, y = ProjectPoint(point)
	if not (uiMap and x and y) then
		ClearDriven()
		if notifyArrow and wasDriven ~= driven then
			NotifyDrivenChanged()
		end
		return
	end
	local title = StepTitle(stop, goal)
	local tomtom = ns.RealTomTom()
	if not tomtom then
		ClearDriven()
		if notifyArrow and wasDriven ~= driven then
			NotifyDrivenChanged()
		end
		return
	end
	if
		driven
		and currentMap == uiMap
		and currentX == x
		and currentY == y
		and currentTitle == title
		and (not currentUid or type(tomtom.IsValidWaypoint) ~= "function" or tomtom:IsValidWaypoint(currentUid))
		and (not drivenForeign or type(tomtom.IsValidWaypoint) ~= "function" or tomtom:IsValidWaypoint(drivenForeign))
	then
		return
	end
	local preexisting = ns.TomTomWaypointAt and ns.TomTomWaypointAt(tomtom, uiMap, x, y, title)
	if preexisting and not ownWaypoints[preexisting] then
		-- A foreign waypoint already sits at this exact map, point and title: point at it without claiming or
		-- overwriting it, so clearing our journey never removes the player's or another addon's waypoint.
		ClearDriven()
		if type(tomtom.SetCrazyArrow) == "function" then
			repointing = true
			local ok =
				ns.core.SafeCall("TomTom arrow point", tomtom.SetCrazyArrow, tomtom, preexisting, 15, preexisting.title)
			repointing = false
			if ok then
				driven = true
				drivenForeign = preexisting
				currentMap, currentX, currentY, currentTitle = uiMap, x, y, title
			end
		end
		if notifyArrow and wasDriven ~= driven then
			NotifyDrivenChanged()
		end
		return
	end
	if preexisting and preexisting == currentUid then
		driven = true
		drivenForeign = nil
		currentMap, currentX, currentY, currentTitle = uiMap, x, y, title
		if notifyArrow and wasDriven ~= driven then
			NotifyDrivenChanged()
		end
		return
	end
	local previous = currentUid
	adding = true
	local ok, uid = ns.core.SafeCall("TomTom arrow add", tomtom.AddWaypoint, tomtom, uiMap, x, y, {
		title = title,
		from = "ShortestPathForever",
		persistent = false,
		minimap = false,
		world = false,
		silent = true,
		crazy = true,
		cleardistance = 0,
	})
	adding = false
	if ok and type(uid) == "table" and uid ~= preexisting then
		ownWaypoints[uid] = true
		currentUid = uid
		drivenForeign = nil
		driven = true
		replacedArrowUid = nil
		currentMap, currentX, currentY, currentTitle = uiMap, x, y, title
		if previous and previous ~= uid then
			RemoveOwnWaypoint(tomtom, previous, false)
			if
				ns.TomTomArrowWaypoint
				and ns.TomTomArrowWaypoint() ~= uid
				and type(tomtom.SetCrazyArrow) == "function"
			then
				repointing = true
				ns.core.SafeCall("TomTom arrow point", tomtom.SetCrazyArrow, tomtom, uid, 15, title)
				repointing = false
			end
		end
	else
		ClearDriven()
	end
	if notifyArrow and wasDriven ~= driven then
		NotifyDrivenChanged()
	end
end

-- Called by UI/Arrow.lua inside PointGuideArrow before checking ArrowShown, so actual TomTom ownership is settled
-- before our native arrow or Blizzard's marker is shown or hidden.
---@param points SPFWalkPoints?
---@param stop SPFPlace?
---@param goal SPFPoint?
function ns.SyncTomTomGuide(points, stop, goal)
	syncedFromArrow = true
	if points and #points > 0 then
		activePoints, activeStop, activeGoal = points, stop, goal
	else
		activePoints, activeStop, activeGoal = nil, nil, nil
	end
	SyncDriven(false)
end

-- Settings checkbox and late TomTom load both call this.
function ns.RefreshTomTomArrow()
	if ns.RealTomTom and ns.RealTomTom() and ns.RefreshTomTomFollow then
		ns.RefreshTomTomFollow()
	end
	if TomTomArrowEnabled() then
		SyncDriven(false)
	else
		ClearDriven()
	end
	if ns.SyncTomTomArrow then
		ns.SyncTomTomArrow()
	end
	if not notifyingArrow and ns.ArrowBearingChanged then
		notifyingArrow = true
		ns.ArrowBearingChanged()
		notifyingArrow = false
	end
	if ns.JourneyGuide and ns.JourneyGuide.Active and ns.JourneyGuide.Active() then
		if ns.JourneyGuide.ArrowChanged then
			ns.JourneyGuide.ArrowChanged()
		end
		if ns.WakeTravel then
			ns.WakeTravel()
		end
	end
end

ns.Init(function()
	hooksecurefunc(
		ns,
		"PointGuideArrow",
		function(points, _, stop, goal) -- taint-ok: Shortest Path owns this addon table.
			if syncedFromArrow then
				syncedFromArrow = false
				return
			end
			if points and #points > 0 then
				activePoints, activeStop, activeGoal = points, stop, goal
			else
				activePoints, activeStop, activeGoal = nil, nil, nil
			end
			SyncDriven(false)
		end
	)
	if type(ns.GuideGuidanceChanged) == "function" then
		hooksecurefunc(ns, "GuideGuidanceChanged", function() -- taint-ok: Shortest Path owns this addon table.
			if activePoints and ns.GuideState then
				local _, source = ns.GuideState()
				if source == activePoints then
					SyncDriven(true)
				end
			end
		end)
	end
	if type(ns.ArrowBearingChanged) == "function" then
		hooksecurefunc(ns, "ArrowBearingChanged", function() -- taint-ok: Shortest Path owns this addon table.
			if not notifyingArrow then
				SyncDriven(true)
			end
		end)
	end
	if ns.JourneyGuide and type(ns.JourneyGuide.ArrowChanged) == "function" then
		hooksecurefunc(ns.JourneyGuide, "ArrowChanged", function() -- taint-ok: Shortest Path owns this addon table.
			SyncDriven(true)
			if ns.SyncTomTomArrow then
				ns.SyncTomTomArrow()
			end
		end)
	end
	if type(ns.JourneyChanged) == "function" then
		hooksecurefunc(ns, "JourneyChanged", function() -- taint-ok: Shortest Path owns this addon table.
			if not (ns.HasJourney and ns.HasJourney()) then
				activePoints, activeStop, activeGoal = nil, nil, nil
				ClearDriven()
			end
		end)
	end
end)

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
---@type TomTomWaypoint?
local currentUid
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

-- Whether Shortest Path is driving TomTom's arrow right now: real TomTom loaded, opt-in setting on, and our
-- direction arrow setting is not off (#1301).
---@return boolean
function ns.TomTomArrowActive()
	return ns.db ~= nil
		and ns.db.tomtomArrow == true
		and ns.db.arrow ~= false
		and ns.RealTomTom ~= nil
		and ns.RealTomTom() ~= nil
end

-- Recognised strictly by the waypoint table we created (or while repointing at an existing foreign waypoint).
---@param uid any
---@return boolean
function ns.IsOwnTomTomWaypoint(uid)
	return repointing or (type(uid) == "table" and ownWaypoints[uid] == true)
end

-- TomTom calls SetCrazyArrow synchronously inside AddWaypoint before returning the waypoint table.
---@param uid any
function ns.OnTomTomCrazyArrow(uid)
	if adding and type(uid) == "table" then
		ownWaypoints[uid] = true
	end
end

---@param uid any
function ns.OnTomTomWaypointRemoved(uid)
	if uid ~= nil and uid == currentUid then
		currentUid = nil
		currentMap, currentX, currentY, currentTitle = nil, nil, nil, nil
	end
end

local function ClearDriven()
	local uid = currentUid
	currentUid = nil
	currentMap, currentX, currentY, currentTitle = nil, nil, nil, nil
	if not uid then
		return
	end
	local tomtom = ns.RealTomTom and ns.RealTomTom()
	if tomtom and type(tomtom.RemoveWaypoint) == "function" then
		ns.core.SafeCall("TomTom arrow remove", tomtom.RemoveWaypoint, tomtom, uid)
	end
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

local function SyncDriven()
	if not ns.TomTomArrowActive() then
		ClearDriven()
		return
	end
	local point, stop, goal = CurrentTarget()
	if not point then
		ClearDriven()
		return
	end
	local uiMap, x, y = ProjectPoint(point)
	if not (uiMap and x and y) then
		ClearDriven()
		return
	end
	local title = StepTitle(stop, goal)
	local tomtom = ns.RealTomTom()
	if not tomtom then
		ClearDriven()
		return
	end
	if
		currentMap == uiMap
		and currentX == x
		and currentY == y
		and currentTitle == title
		and (not currentUid or type(tomtom.IsValidWaypoint) ~= "function" or tomtom:IsValidWaypoint(currentUid))
	then
		return
	end
	local preexisting = ns.TomTomWaypointAt and ns.TomTomWaypointAt(tomtom, uiMap, x, y, title)
	if preexisting and not ownWaypoints[preexisting] then
		-- A foreign waypoint already sits at this exact map, point and title: point at it without claiming or
		-- overwriting it, so clearing our journey never removes the player's or another addon's waypoint.
		ClearDriven()
		currentMap, currentX, currentY, currentTitle = uiMap, x, y, title
		if type(tomtom.SetCrazyArrow) == "function" then
			repointing = true
			ns.core.SafeCall("TomTom arrow point", tomtom.SetCrazyArrow, tomtom, preexisting, 15, preexisting.title)
			repointing = false
		end
		return
	end
	if preexisting and preexisting == currentUid then
		currentMap, currentX, currentY, currentTitle = uiMap, x, y, title
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
		currentMap, currentX, currentY, currentTitle = uiMap, x, y, title
		if previous and previous ~= uid then
			ns.core.SafeCall("TomTom arrow remove", tomtom.RemoveWaypoint, tomtom, previous)
		end
	elseif previous then
		ClearDriven()
	end
end

-- Settings checkbox and late TomTom load both call this.
function ns.RefreshTomTomArrow()
	if ns.RealTomTom and ns.RealTomTom() and ns.RefreshTomTomFollow then
		ns.RefreshTomTomFollow()
	end
	if ns.TomTomArrowActive() then
		SyncDriven()
	else
		ClearDriven()
	end
	if ns.SyncTomTomArrow then
		ns.SyncTomTomArrow()
	end
	if ns.ArrowBearingChanged then
		ns.ArrowBearingChanged()
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
			if points and #points > 0 then
				activePoints, activeStop, activeGoal = points, stop, goal
			else
				activePoints, activeStop, activeGoal = nil, nil, nil
			end
			SyncDriven()
		end
	)
	if type(ns.GuideGuidanceChanged) == "function" then
		hooksecurefunc(ns, "GuideGuidanceChanged", function() -- taint-ok: Shortest Path owns this addon table.
			if activePoints and ns.GuideState then
				local _, source = ns.GuideState()
				if source == activePoints then
					SyncDriven()
				end
			end
		end)
	end
	if type(ns.ArrowBearingChanged) == "function" then
		hooksecurefunc(ns, "ArrowBearingChanged", SyncDriven) -- taint-ok: Shortest Path owns this addon table.
	end
	if ns.JourneyGuide and type(ns.JourneyGuide.ArrowChanged) == "function" then
		hooksecurefunc(ns.JourneyGuide, "ArrowChanged", function() -- taint-ok: Shortest Path owns this addon table.
			SyncDriven()
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

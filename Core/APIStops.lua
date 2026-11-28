---@type string, SPFNamespace
local _, ns = ...

if ns.broken then
	return
end
local L = ns.L
local Input = assert(ns.APIInput, "Core/APIInput.lua loads first")
local Number, Point, ID = Input.Number, Input.Point, Input.ID
local DetailLines, Shapes, Quests = Input.DetailLines, Input.Shapes, Input.Quests
-- Yards from a stop to the spawn it stands for: QuestieDB keeps a spawn's spot to a hundredth of a percent of its zone
-- map, a yard or less, and the server's spawn sits within 2 yd of Questie's for five spawns in six.
local SPAWN_REACH = 8

-- What a consumer driving its own route reads (API.JourneyState) and hears (API.ObserveStops): the planner's status and
-- plan copied fresh, and the owner-scoped per-stop channel Journey.lua feeds. API.lua owns the route and passes it in.
---@class SPFAPIStops
local Stops = {}
ns.APIStops = Stops

---@class SPFAPIRoute
---@field owner string
---@field points SPFPoint[]
---@field index integer
---@field policy SPFRoutePolicy
---@field loop? true the last stop leads back to the first
---@field walked integer stops moved on from since this itinerary started
---@alias SPFStopObserver fun(phase: "arrived"|"settled", i: integer, stop: SPFAPIObservedStop, s: SPFAPIJourneyState)

-- What a consumer driving a route needs to tell busy, still working, failed and blocked apart, copied fresh:
-- the planner's own status and legs read in one place, so the state call and the stop observers answer the same.
---@param route SPFAPIRoute?
---@return SPFAPIJourneyState
function Stops.State(route)
	local pending, _, costError, settling, _, replanning = ns.JourneyStatus()
	local plan, index = ns.JourneyPlan()
	local legs, failure = {}, costError
	for legIndex, leg in ipairs(plan and plan.legs or {}) do
		legs[legIndex] = { mode = leg.mode, measured = leg.measured == true, walkError = leg.walkError }
		failure = failure or leg.walkError
	end
	local blocked
	if InCombatLockdown() then
		blocked = "combat" -- the standard reason (forever-core#961)
	elseif ns.Corpse and ns.Corpse.Active() then
		blocked = "corpse"
	end
	local goal, distance = ns.JourneyGoal(), nil
	if goal then
		local x, y, _, map = ns.JourneyPosition()
		if x and y and map == goal.map then
			distance = math.sqrt((x - goal.x) ^ 2 + (y - goal.y) ^ 2)
		end
	end
	return {
		owner = route and route.owner,
		policy = route and route.policy or "normal",
		busy = ns.HasJourney() or route ~= nil,
		pending = pending or replanning == true,
		settling = settling == true,
		failure = failure,
		blocked = blocked,
		preview = plan ~= nil and plan.preview == true,
		index = plan and index or nil,
		legs = legs,
		distance = distance,
		reach = ns.db.arrivalDistance or 15,
	}
end

-- A stop naming the NPC it reaches (Nearby services) takes the height of that NPC's QuestieDB spawn when it stands over
-- or under another surface, keeping the walk on its floor. Nearby measures its walks to the same point.
---@param point SPFPoint
---@return SPFPoint
function ns.OnSpawnFloor(point)
	if point.z == nil then
		point.z = ns.SpawnHeight(point.map, point.x, point.y, SPAWN_REACH)
	end
	return point
end

-- A caller's stops, checked and copied into the journey's own points. nil when any stop is not one.
---@param stops table
---@param options SPFRouteSwitches
---@return SPFPoint[]?
function Stops.Points(stops, options)
	local count = #stops
	for key in pairs(stops) do
		if not Number(key) or key % 1 ~= 0 or key < 1 or key > count then
			return nil
		end
	end
	local points = {}
	for index = 1, count do
		local stop = stops[index]
		if
			type(stop) ~= "table"
			or (stop.title ~= nil and not (canaccessvalue(stop.title) and type(stop.title) == "string"))
			or (stop.tooltip ~= nil and not (canaccessvalue(stop.tooltip) and type(stop.tooltip) == "string"))
			or (stop.hold ~= nil and not (canaccessvalue(stop.hold) and type(stop.hold) == "boolean"))
			or (stop.radius ~= nil and (not Number(stop.radius) or stop.radius < 0))
			or (stop.z ~= nil and not Number(stop.z))
			or (stop.questID ~= nil and not ID(stop.questID))
			or (stop.questIDs ~= nil and (type(stop.questIDs) ~= "table" or not Quests(stop.questIDs)))
			or (stop.handins ~= nil and (type(stop.handins) ~= "table" or not Quests(stop.handins)))
			or (stop.npc ~= nil and not ID(stop.npc))
			or (stop.shapes ~= nil and (type(stop.shapes) ~= "table" or not Shapes(stop.shapes)))
		then
			return nil
		end
		local point = Point(stop.map, stop.x, stop.y)
		if not point then
			return nil
		end
		point.label = stop.title
		-- The place as submitted: what a stop observer hears even where the world cannot be projected back to it.
		point.submitted = { map = stop.map, x = stop.x, y = stop.y, z = stop.z }
		point.details = DetailLines(stop.tooltip)
		-- A caller's world height lets the stop pin compare its surface with the terrain under that spot.
		if stop.z ~= nil then
			point.z = stop.z
		elseif stop.npc ~= nil then
			-- A stop naming no NPC (a TomTom or guide waypoint) may be any spot, so it keeps the cheapest surface.
			ns.OnSpawnFloor(point)
		end
		-- A caller such as Adventure Guide may need the route to remain visible while the
		-- player completes an interaction at this location. It resubmits the route after
		-- that state changes; ordinary API stops retain automatic arrival.
		point.hold = stop.hold == true
		point.radius = stop.radius
		point.questID = stop.questID
		-- The NPC whose service this stop reaches: Shortest Path marks that NPC's nameplate while the stop is
		-- current. Another addon's route passes no npc, so its own highlight is the only one.
		point.npc = stop.npc
		-- The quests whose client blobs the stop stands for, copied; StopInside prefers the client's own answer for them.
		if stop.questID or stop.questIDs then
			point.questIDs = { stop.questID }
			for _, questID in ipairs(stop.questIDs or {}) do
				if questID ~= stop.questID then
					point.questIDs[#point.questIDs + 1] = questID
				end
			end
		end
		-- The quests handed in at the stop, copied: they hide the game's own pins there (UI/QuestPins.lua) and never
		-- decide arrival or the stop's area, which are the quests above alone.
		if stop.handins then
			point.handins = {}
			for _, questID in ipairs(stop.handins) do
				point.handins[#point.handins + 1] = questID
			end
		end
		-- The areas are copied to world points too: the caller cannot redirect a journey they no longer own.
		if stop.shapes then
			point.shapes = {}
			for _, shape in ipairs(stop.shapes) do
				local at = Point(shape.map, shape.x, shape.y) --[[@as SPFAreaShape]]
				at.radius = shape.radius
				point.shapes[#point.shapes + 1] = at
			end
		end
		-- An unknown kind is dropped, not refused: a caller written for a later vocabulary still gets its route.
		point.look = ns.StopKind(stop.kind)
		point.number = index
		-- A caller drawing its own places asks for the line alone: no stop pin on the world map (UI/Route.lua).
		point.unmarked = not options.stopMarkers or nil
		point.unfaded = not options.fadeLaterLegs or nil
		point.tourLine = options.tourLine or nil
		if count > 1 then
			local location = not point.label and ns.Locate(point)
			-- What to do there, apart from the count the tooltip gives its own line (UI/StopPin.lua).
			point.stopLabel = point.label or location and location.zone or UNKNOWN
			-- Keep the locale format beside the built title, so the tracker can colour the place inside it.
			point.routeTitleFormat = L["Stop %d of %d: %s"]
			point.routeCount = count
			point.routeTitle = string.format(point.routeTitleFormat, index, count, point.stopLabel)
		end
		points[index] = point
	end
	return points
end

---@type table<{owner: string, callback: SPFStopObserver}, true>
local observers = {}

-- Subscribes callback to owner's own route; the returned function unsubscribes and is safe to call twice.
---@param owner string
---@param callback SPFStopObserver
---@return fun()
function Stops.Observe(owner, callback)
	local entry = { owner = owner, callback = callback }
	observers[entry] = true
	return function()
		observers[entry] = nil
	end
end

-- Tells the route owner's observers about the stop under way, inside the call that reached or settled it. current
-- reads the route again after each callback: one that replaced or ended it stops the rest, and the caller (false)
-- must not carry on with the old arrival.
---@param phase "arrived"|"settled"
---@param point SPFPoint
---@param current fun(): SPFAPIRoute?
---@return boolean? alive
function Stops.Dispatch(phase, point, current)
	-- A door stands in for the stop inside its instance (JourneyInput.lua).
	point = point.stop or point
	local watched = current()
	if not watched or watched.points[watched.index] ~= point or next(observers) == nil then
		return
	end
	local watchedIndex, heard = watched.index, {}
	for entry in pairs(observers) do
		if entry.owner == watched.owner then
			heard[#heard + 1] = entry
		end
	end
	if #heard == 0 then
		return
	end
	local projected = ns.JourneyGoalDetails(Input.Place, point)
	local stop = projected or point.submitted
	if not stop then
		return
	end
	local title = point.label or (projected and projected.title) or ns.JourneyTitle(point)
	for _, entry in ipairs(heard) do
		if observers[entry] then
			-- Each observer gets its own copy: one cannot change what the next one sees.
			local seen = { map = stop.map, x = stop.x, y = stop.y, z = stop.z, title = title }
			ns.core.SafeCall("stop observer", entry.callback, phase, watchedIndex, seen, Stops.State(current()))
			local now = current()
			if not now or now ~= watched or now.index ~= watchedIndex or now.points[watchedIndex] ~= point then
				return false
			end
		end
	end
end

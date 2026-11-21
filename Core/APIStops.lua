---@type string, SPFNamespace
local _, ns = ...

if ns.broken then
	return
end
local Input = assert(ns.APIInput, "Core/APIInput.lua loads first")

-- What a consumer driving its own route reads (API.JourneyState) and hears (API.ObserveStops): the planner's status and
-- plan copied fresh, and the owner-scoped per-stop channel Journey.lua feeds. API.lua owns the route and passes it in.
---@class SPFAPIStops
local Stops = {}
ns.APIStops = Stops

---@alias SPFAPIRoute {owner: string, points: SPFPoint[], index: integer, policy: SPFRoutePolicy}
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

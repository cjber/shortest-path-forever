---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- The walks a journey's search has measured, kept behind JourneySearch.lua: the drawn path of each walking leg,
-- searched once and shared by every plan that walks it, and the walks on from a bind point.
local WALK_CACHE_LIMIT = 64

---@class SPFJourneyWalks
local Walks = ns.JourneySearch.Walks
local SamePlace = ns.JourneySearch.SamePlace
local Context = ns.PlanContext

-- A finished leg search: the path it found (or the one it failed to replace), why it failed, its running yards.
---@class SPFMeasuredWalk
---@field points? SPFWalkPoints
---@field reason? string
---@field cost? number
---@field notes? string[]

---@type table<string, SPFMeasuredWalk>
local walkCache = {}
local walkOrder, walkPending, walkJobs = {}, {}, {}
local pathJobs, pathVersion = {}, 0
local pendingWalks = 0
-- What every walk here is searched to keep away from (Hazards.lua), and the walks on from bind points.
---@type SPFHazards?
local hazards
local landings

-- The same journey replanned from a few yards on: every leg goes the same way to the same place.
function Walks.SameJourney(a, b, start, here)
	if not (a and b) or a.waterMode ~= b.waterMode or #a.legs ~= #b.legs - start + 1 then
		return false
	end
	for index, leg in ipairs(a.legs) do
		local other = b.legs[index + start - 1]
		if
			leg.mode ~= other.mode
			or leg.route ~= other.route
			or not SamePlace(leg.to, other.to)
			or (index > 1 and not SamePlace(leg.from, other.from))
		then
			return false
		end
	end
	-- A walk you have strayed from is searched again from where you are.
	local walk = b.legs[start]
	if walk and walk.walkError then
		return here and SamePlace(walk.from, here)
	end
	return not (walk and walk.mode == "walk" and walk.measured) or ns.OnWalk(walk.walkPoints, here) ~= nil
end

local function WalkKey(from, to)
	return table.concat({ from.map, from.x, from.y, from.z or "", to.x, to.y, to.z or "" }, ":")
end

local function CacheWalk(key, entry)
	if not walkCache[key] then
		walkOrder[#walkOrder + 1] = key
		if #walkOrder > WALK_CACHE_LIMIT then
			walkCache[table.remove(walkOrder, 1)] = nil
		end
	end
	walkCache[key] = entry
end

local function FindWalk(planned, leg, key, water, done)
	local version, previous = pathVersion, leg.walkPoints
	-- A straight placeholder is not a drawn walk: only points an earlier search measured are kept through this one.
	local measuredBefore = previous ~= nil and not leg.walkPlaceholder
	if not previous then
		previous = ns.Planner.WalkPoints(leg.from, leg.to)
		leg.walkPoints, leg.walkPlaceholder = previous, true
	end
	leg.walkDrawn = measuredBefore
	local function apply(points, cost)
		leg.walkError = not points and cost or nil
		if points then
			leg.walkPoints, leg.walkPlaceholder = points, nil
			leg.measured, leg.walkDrawn, leg.wet, leg.walkCost = true, true, points.wet, cost
			leg.hazardNotes = hazards and ns.Hazards.Notes(hazards, leg, points) or nil
			if planned.preview then
				leg.yards = cost
			end
		else
			-- A failed search drops its straight placeholder: what is left is not a walk to draw or keep (#894).
			leg.walkPoints = measuredBefore and previous or {}
			leg.walkDrawn, leg.walkPlaceholder = measuredBefore, not measuredBefore
		end
	end
	if walkPending[key] then
		walkPending[key][#walkPending[key] + 1] = { plan = planned, apply = apply }
		return
	end
	local waiting = { { plan = planned, apply = apply } }
	walkPending[key] = waiting
	pendingWalks = pendingWalks + 1
	local job = ns.Path.Find(leg.from.map, leg.from, leg.to, function(points, cost, finished)
		pathJobs[finished] = nil
		if version ~= pathVersion or finished.cancelled then
			return
		end
		pendingWalks = pendingWalks - 1
		walkPending[key], walkJobs[key] = nil, nil
		for _, entry in ipairs(waiting) do
			entry.apply(points, cost)
		end
		CacheWalk(key, {
			-- A failed search never stores its straight placeholder as a measured walk (#894).
			points = points or (measuredBefore and previous or nil),
			reason = not points and cost or nil,
			cost = points and cost,
			notes = points and leg.hazardNotes,
		})
		if ns.db.debug and ns.Planner.WalkContradicts(leg, points and cost) then
			ns.Print(string.format("walking cost mismatch: planned %.1f, found %s", leg.yards, tostring(cost)))
		end
		done()
	end, water, hazards)
	pathJobs[job], walkJobs[key], job.onError = true, job, ns.JourneySearch.JobFailed
end

-- A plan that will not be followed: the searches only it waited for stop.
---@param planned SPFPlan
function Walks.Drop(planned)
	for key, waiting in pairs(walkPending) do
		for at = #waiting, 1, -1 do
			if waiting[at].plan == planned then
				table.remove(waiting, at)
			end
		end
		if #waiting == 0 then
			local job = walkJobs[key]
			pathJobs[job], walkPending[key], walkJobs[key] = nil, nil, nil
			pendingWalks = pendingWalks - 1
			ns.Path.Cancel(job)
		end
	end
end

-- The walk to draw now: the first one at or after the leg being followed. Costs prove every other walk, and its
-- drawing waits until it is the next one on foot.
---@param planned SPFPlan
---@param index integer?
---@return integer?
local function ActiveWalk(planned, index)
	for at = index or 1, #planned.legs do
		if planned.legs[at].mode == "walk" then
			return at
		end
	end
end

-- Whether the walk to draw now was put off until you could reach it.
---@param planned SPFPlan?
---@param index integer? the leg being followed
---@return boolean
function Walks.NeedsPrepare(planned, index)
	local _, _, _, map = ns.JourneyPosition()
	local at = planned and ActiveWalk(planned, index)
	local leg = planned and at and planned.legs[at]
	return leg ~= nil and leg.walkDeferred == true and leg.from.map == map
end

-- Gives each of a plan's walking legs its path: the measured one, or the best drawing there is while a search for
-- it runs. Only the walk being followed (or next) is searched; a later walk with a known cost, like one on a
-- continent not yet loaded, is put off until it is that walk. drawn are the legs on show, whose paths stand in for
-- the walks that replace them. done runs after each search lands, once its legs are updated.
---@param planned SPFPlan?
---@param drawn SPFLeg[]?
---@param water boolean? whether walks may cross water
---@param done fun()
---@param index integer? the leg being followed
function Walks.Prepare(planned, drawn, water, done, index)
	if not planned or (planned.prepared and not Walks.NeedsPrepare(planned, index)) then
		return
	end
	local resume = planned.prepared
	planned.prepared = true
	local _, _, _, map = ns.JourneyPosition()
	local active = ActiveWalk(planned, index)
	for at, leg in ipairs(planned.legs) do
		if leg.mode == "walk" and (not resume or at == active and leg.walkDeferred and leg.from.map == map) then
			leg.walkDeferred = nil
			local key = WalkKey(leg.from, leg.to)
			local entry = walkCache[key]
			leg.measured, leg.walkError, leg.walkCost = false, nil, leg.yards
			if entry then
				leg.walkPoints, leg.measured = entry.points or {}, entry.reason == nil
				leg.walkDrawn = entry.points ~= nil
				leg.walkPlaceholder = entry.reason ~= nil and entry.points == nil or nil
				leg.wet, leg.walkError = entry.points and entry.points.wet, entry.reason
				leg.hazardNotes = entry.notes
				if entry.cost then
					leg.walkCost = entry.cost
					if planned.preview then
						leg.yards = entry.cost
					end
				end
			elseif
				not leg.estimated
				and (at ~= active or map and leg.from.map ~= map and not ns.Path.IsLoaded(leg.from.map))
			then
				-- Exact costs already prove this leg; draw it once it is the walk to follow, or its continent loads.
				leg.walkDeferred = true
				leg.walkPoints, leg.walkDrawn, leg.walkPlaceholder =
					ns.Planner.WalkPoints(leg.from, leg.to), false, true
			elseif leg.from.map == leg.to.map and ns.Path.HasData(leg.from.map) then
				-- A replacement may itself still be pending while drawing an older result; preserve that too.
				for _, previous in ipairs(drawn or {}) do
					if
						previous.mode == "walk"
						and SamePlace(previous.to, leg.to)
						and previous.walkDrawn
						and not previous.walkPlaceholder
					then
						leg.walkPoints = previous.walkPoints
						break
					end
				end
				FindWalk(planned, leg, key, water, done)
			else
				leg.walkPoints, leg.walkError = {}, "nodata"
			end
		end
	end
end

-- What the search for a leg's walk found, once it has landed.
---@param leg SPFLeg
---@return SPFMeasuredWalk?
function Walks.Measured(leg)
	return walkCache[WalkKey(leg.from, leg.to)]
end

-- Leg searches still running.
---@return number
function Walks.Pending()
	return pendingWalks
end

-- Stops the leg searches in flight; their legs keep what they drew.
function Walks.Cancel()
	pathVersion = pathVersion + 1
	for job in pairs(pathJobs) do
		ns.Path.Cancel(job)
	end
	pathJobs, walkPending, walkJobs, pendingWalks = {}, {}, {}, 0
end

-- Measured in another water mode, or for a journey that is over.
function Walks.Clear()
	walkCache, walkOrder = {}, {}
end

-- Walks from now on keep away from these hazards; walks and landings measured with others are forgotten.
---@param profile SPFHazards?
function Walks.SetHazards(profile)
	hazards = profile
	Walks.Clear()
	Walks.ClearLandings()
end

function Walks.ClearLandings()
	for _, entry in pairs(landings) do
		if entry.job then
			ns.Path.Cancel(entry.job)
		end
	end
	landings = {}
end

-- The bind point moves, so its walks on to the fixed places cannot be baked like a class teleport's: each is searched
-- once per bind point and water mode, alongside the journey's own endpoint searches.
landings = {}

---@class SPFLanding
---@field targets SPFPlace[]
---@field costs? (number|false)[]
---@field waiting? fun()[]
---@field beyond? table<fun(), number>
---@field job SPFPathJob

---@param place SPFTeleportPlace
---@param water boolean?
---@return SPFLanding?
local function Landing(place, water)
	if not (place.bind and ns.Path.HasData(place.map)) then
		return nil
	end
	local key = string.format("%d:%.17g:%.17g:%s", place.map, place.x, place.y, tostring(water))
	local entry = landings[key]
	if not entry then
		local mass, targets = Context.Landmass(place), {}
		-- Without the teleports' own destinations: a landing walks on to docks, flight points and portals.
		for _, target in ipairs((Context.Places())) do
			if target.map == place.map and Context.Landmass(target) == mass then
				targets[#targets + 1] = target
			end
		end
		-- waiting: called when the search ends; beyond: called once its frontier passes their radius, or it ends.
		entry = { targets = targets, waiting = {}, beyond = {} }
		landings[key] = entry
		local function wake(radius)
			local due = {}
			for callback, reach in pairs(entry.beyond or {}) do
				if radius >= reach then
					due[#due + 1] = callback
				end
			end
			for _, callback in ipairs(due) do
				entry.beyond[callback] = nil
				callback()
			end
		end
		entry.job = ns.Path.FindMany(
			place.map,
			place,
			targets,
			function(costs)
				local waiting = entry.waiting or {}
				entry.costs, entry.waiting = costs, nil
				for _, callback in ipairs(waiting) do
					callback()
				end
				wake(math.huge)
				entry.beyond = nil
			end,
			water,
			nil,
			function(_, _, job)
				wake(job.radius)
			end,
			hazards
		)
		entry.job.onError = ns.JourneySearch.JobFailed
	end
	return entry
end

-- Whether a bind point's walks are still being searched for a teleport that could still beat a route arriving at
-- `before`. A walk the search has not settled is at least its frontier (job.radius) long, so a way on from the landing
-- arrives no sooner than the teleport is ready, cast and that walk at speed: past that the landing cannot win and the
-- journey need not wait for its walks to every flight point on the continent (#1154). callback, when given, runs once
-- the search ends, or with speed once its frontier passes the walk that would tie `before`.
---@param teleports SPFTeleportPlace[]?
---@param water boolean?
---@param callback? fun()
---@param ready? table<number, number>
---@param before? number
---@param speed? number yards a second a walk is timed at
---@return boolean
function Walks.LandingPending(teleports, water, callback, ready, before, speed)
	local pending = false
	for index, place in ipairs(teleports or {}) do
		local entry = Landing(place, water)
		local reach = math.huge
		if ready and speed then
			reach = ready[index] and (before - ready[index] - (place.cast or 0)) * speed / 1000 or -math.huge
		elseif ready then
			reach = ready[index] and ready[index] < before and math.huge or -math.huge
		end
		if entry and entry.waiting and entry.job.radius < reach then
			pending = true
			if callback and reach < math.huge then
				entry.beyond[callback] = reach
			elseif callback then
				entry.waiting[#entry.waiting + 1] = callback
			end
		end
	end
	return pending
end

-- The measured walks on from each usable bind point. While its search runs, a walk it has settled is exact and one it
-- has not is at least the frontier's radius: LandingPending lets a plan go on once that bound rules the landing out,
-- and the plan still sees the near walks that let a hearth win.
---@param teleports SPFTeleportPlace[]?
---@param water boolean?
---@return SPFWalkCost[]
function Walks.Landings(teleports, water)
	local walks = {}
	for _, place in ipairs(teleports or {}) do
		local entry = Landing(place, water)
		local costs = entry and (entry.costs or entry.job.costs)
		local radius = entry and not entry.costs and entry.job.radius or 0
		for i, target in ipairs(entry and entry.targets or {}) do
			local cost = costs and costs[i]
			if cost ~= nil then
				walks[#walks + 1] = { from = place, to = target, cost = cost }
			elseif radius > math.sqrt((target.x - place.x) ^ 2 + (target.y - place.y) ^ 2) then
				walks[#walks + 1] = { from = place, to = target, cost = radius, estimated = true }
			end
		end
	end
	return walks
end

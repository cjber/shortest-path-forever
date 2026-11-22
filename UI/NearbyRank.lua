---@type string, SPFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- One row's shortlist ranked by the planner's own journey cost, at most one Estimate per Step. The panel, the tracking
-- menu and /spfnear drain it inside a path job, whose estimates pause at the frame budget. The best starts as the
-- straight-line nearest, so a row always has an NPC, and stays so when no estimate can be made. A walk still being
-- measured is estimated on its lower bound, so the ranking is decided (exact) once its cheapest place is not one of
-- them: every other place is then exact or no faster.
---@class SPFNearbyRank
---@field key? string
---@field candidates SPFNearbyPlace[]
---@field estimate SPFEstimate
---@field fromMap integer
---@field fromX number
---@field fromY number
---@field at integer
---@field order SPFNearbyPlace[] the candidates, cheapest lower bound first once each is estimated
---@field least table<SPFNearbyPlace, number> each candidate's lower bound
---@field best? SPFNearbyPlace
---@field seconds? number
---@field walks table<SPFNearbyPlace, number|false>
---@field pending? SPFWalksPending
---@field exact? boolean
local Rank = {}
Rank.__index = Rank

function Rank:Step()
	local count = #self.candidates
	local at = self.at
	if at > 2 * count then
		return self.best or self.candidates[1], self.seconds, false
	end
	self.at = at + 1
	-- First each place's lower bound, in the shortlist's order, then the places cheapest bound first, so a ride's endpoint
	-- walks are measured only while it could still win. One estimate per step either way.
	local least = self.least
	if at <= count then
		local place = self.candidates[at]
		local walk = self.pending and self.pending[place] or self.walks[place]
		least[place] =
			self.estimate(self.fromMap, self.fromX, self.fromY, place.map, place.x, place.y, walk, true, place)
		if at == count then
			table.sort(self.order, function(a, b)
				return (least[a] or math.huge) < (least[b] or math.huge)
			end)
		end
		return self.best or self.candidates[1], self.seconds, true
	end
	local place = self.order[at - count]
	if self.seconds and (least[place] or math.huge) > self.seconds then
		-- Every remaining bound is slower. A pending winner will rank again once its walk lands.
		self.at = 2 * count + 1
		return self.best, self.seconds, false
	end
	-- Read before the estimate, which may pause while the measure settles this walk: the estimate is on the walk read.
	-- A walk still searched counts at its lower bound, so a pending place is never cheaper than it could be.
	local bound = self.pending and self.pending[place]
	-- Only a settled best sets a ceiling. On a tie the candidate may still decide the row.
	local ceiling = self.exact and self.seconds or nil
	-- Keep the lower-bound result while the walk is pending. A preference such as saving a Hearthstone cooldown
	-- can change which route wins once the walk is measured, so it only applies to a settled estimate.
	local seconds
	if bound then
		seconds = least[place]
	else
		seconds = self.estimate(
			self.fromMap,
			self.fromX,
			self.fromY,
			place.map,
			place.x,
			place.y,
			self.walks[place],
			nil,
			place,
			ceiling
		)
	end
	local exact = not bound
	if seconds and (not self.seconds or seconds < self.seconds or seconds == self.seconds and exact) then
		self.best, self.seconds, self.exact = place, seconds, exact
	end
	return self.best or self.candidates[1], self.seconds, at < 2 * count
end

---@param walks? SPFWalks MeasureWalks' answer
---@param pending? SPFWalksPending the places whose walks it is still measuring
local function NewRank(candidates, estimate, fromMap, fromX, fromY, walks, pending)
	return setmetatable({
		candidates = candidates,
		walks = walks or {},
		pending = pending,
		estimate = estimate,
		fromMap = fromMap,
		fromX = fromX,
		fromY = fromY,
		at = 1,
		order = { unpack(candidates) },
		least = {},
	}, Rank)
end

-- Each place's walking end, on the NPC's own floor. Spawns do not move, and the height scan is the costly part of a
-- measure, so each place's is found once.
local spawns = setmetatable({}, { __mode = "k" })

---@param place SPFNearbyPlace
---@return SPFPoint|false
local function Spawn(place)
	local point = spawns[place]
	if point == nil then
		local world = ns.WorldPoint(place.map, place.x, place.y)
		-- A map that cannot project yet is asked again on the next measure; only a spawn with no floor is final.
		if not world then
			return false
		end
		point = ns.OnSpawnFloor(world) or false
		spawns[place] = point
	end
	return point
end

---@class SPFNearbyEndpointCosts
---@field key string
---@field water boolean?
---@field walks SPFWalkCost[]

-- Landing costs depend on the NPC's floor and hazard profile, so they can be reused as the player moves.
---@type table<SPFNearbyPlace, SPFNearbyEndpointCosts>
local landings = setmetatable({}, { __mode = "k" })
local departures = {}
local previousHere
---@type table<SPFPathJob, table<SPFPoint, SPFHazards>>
local profiles = setmetatable({}, { __mode = "k" })

local function Profile(job, here, goal)
	local byGoal = profiles[job]
	if not byGoal then
		byGoal = {}
		profiles[job] = byGoal
	end
	local hazards = byGoal[goal] or ns.Hazards.Profile(here, goal, here)
	byGoal[goal] = hazards
	return hazards
end

local function DepartureCache(here)
	local band, previous = here.band, previousHere and previousHere.band
	local sameBand = band == previous or band and previous and band.lo == previous.lo and band.hi == previous.hi
	if not (previousHere and sameBand and ns.JourneySearch.SamePlace(previousHere, here)) then
		departures = {}
		previousHere = here
	end
	return departures
end

local function CostCache(cache, key, hazards, water)
	local entry = cache[key]
	if not entry or entry.key ~= hazards.key or entry.water ~= water then
		entry = { key = hazards.key, water = water, walks = {} }
		cache[key] = entry
	end
	return entry.walks
end

-- The planner identifies the endpoints to price. Probe just that directed walk, as the journey does.
local function EndpointCost(job, cached, from, to, options)
	local path = ns.Path
	if not path.HasData(from.map) then
		return nil
	end
	for _, walk in ipairs(cached) do
		if ns.JourneySearch.SamePlace(walk.from, from) and ns.JourneySearch.SamePlace(walk.to, to) then
			return walk.cost
		end
	end
	local cost
	local probe = path.FindCost(from.map, from, to, function(yards, reason, searched)
		if job.cancelled then
			return
		end
		if yards or reason == "unreachable" or reason == "offmesh" or reason == "outside" then
			cost = yards or false
			cached[#cached + 1] = { from = from, to = to, cost = cost }
		end
		job.walking[searched] = nil
		path.Resume(job)
	end, options.waterWalking, options.hazards)
	job.walking = job.walking or {}
	job.walking[probe] = true
	path.Wait()
	return cost
end

local function Earliest(job, options)
	local hazards = options.hazards
	if hazards and hazards.goalZone then
		-- The direct walk's zone charge can hide a quicker arrival that would win once a ride gets longer.
		options.hazards = setmetatable({ goalZone = false }, { __index = hazards })
	end
	local bound = options.lowerBound
	options.lowerBound = true
	local plan = ns.Planner.Plan(options, job)
	options.lowerBound, options.hazards = bound, hazards
	return plan
end

-- Replan on the winning candidate's measured legs. Another ride can become cheaper when a walk grows or is ruled
-- out, so keep the lower-bound alternatives in the graph until a plan needs no further searches.
---@param job SPFPathJob
---@param options SPFContextOptions
---@param place SPFNearbyPlace
---@param walk? number|false
---@param bound? boolean
---@param ceiling? number an arrival the ranking has already beaten: a plan past it is returned unmeasured, as partial
---@return SPFPlan?, boolean? partial
local function Plan(job, options, place, walk, bound, ceiling)
	job.nearbyHere = job.nearbyHere or ns.JourneySearch.Here()
	local here, goal = job.nearbyHere, Spawn(place)
	local walks, starts, ends = {}, nil, nil
	if here and goal then
		options.from, options.to = here, goal
		local hazards = Profile(job, here, goal)
		options.hazards = hazards
		options.endpointBounds = true
		local water = options.waterWalking
		starts = CostCache(DepartureCache(here), hazards.key, hazards, water)
		ends = CostCache(landings, place, hazards, water)
		for _, measured in ipairs(starts) do
			walks[#walks + 1] = measured
		end
		for _, measured in ipairs(ends) do
			walks[#walks + 1] = measured
		end
	end
	if walk ~= nil then
		walks[#walks + 1] = { from = options.from, to = options.to, cost = walk }
	elseif here and goal and here.map == goal.map and ns.Path.HasData(here.map) then
		walks[#walks + 1] =
			{ from = here, to = goal, cost = ns.Path.LowerBound(here.map, here, goal), estimated = true, apart = true }
	end
	options.walks, options.lowerBound = walks, bound
	if bound then
		return Earliest(job, options)
	end
	local plan = ns.Planner.Plan(options, job)
	if not (here and goal and plan) then
		return plan
	end
	while plan do
		-- Preferences can pick a slower route. Only the earliest possible arrival proves a loss.
		if ceiling and plan.arrive > ceiling and #plan.pendingWalks > 0 then
			local earliest = Earliest(job, options)
			if earliest and earliest.arrive > ceiling then
				return earliest, true
			end
		end
		local changed = false
		-- The planner collects walks from goal to start. Price departures first since their costs are shared.
		for i = #plan.pendingWalks, 1, -1 do
			local leg = plan.pendingWalks[i]
			local cache = leg.from.kind == "start" and starts or ends
			local cost = EndpointCost(job, cache, leg.from, leg.to, options)
			if cost ~= nil then
				walks[#walks + 1] = { from = leg.from, to = leg.to, cost = cost }
				changed = true
				break -- Replan before starting another endpoint search.
			end
		end
		if not changed then
			return plan
		end
		plan = ns.Planner.Plan(options, job)
	end
end

---@class SPFNearbyWalkBatch
---@field job SPFPathJob
---@field key string
---@field water boolean
---@field index table<SPFNearbyPlace, integer>
---@field costs (number|false)[]
---@field done? boolean
---@field reason? string
---@field publish? fun()

-- Finished walks can also answer a later measure after the panel was closed.
---@type table<string, SPFNearbyWalkBatch>
local measured = {}

-- Group direct walks by the journey's hazard profile. A longer direct walk cannot beat a ride that wins on the
-- bound. This gives up #1034's exactness only when a planner preference would choose a walk longer than the bound
-- over a faster ride.
---@param job SPFPathJob
---@param here SPFPoint
---@param places SPFNearbyPlace[]
---@param map integer
---@param x number
---@param y number
---@return table<string, { hazards: SPFHazards, targets: SPFPoint[], of: SPFNearbyPlace[] }>, SPFWalksPending
local function Groups(job, here, places, map, x, y)
	local mass = ns.PlanContext.Landmass(here)
	local groups, seen, bounds = {}, {}, {}
	for _, place in ipairs(places) do
		local point = not seen[place] and Spawn(place)
		seen[place] = true
		if point and point.map == here.map and ns.PlanContext.Landmass(point) == mass then
			local bound = ns.Path.LowerBound(here.map, here, point)
			local _, _, legs = ns.EstimateIn(job, map, x, y, place.map, place.x, place.y, bound, true, place)
			local leg = legs and legs[1]
			if leg and #legs == 1 and leg.mode == "walk" and leg.from.kind == "start" and leg.to.kind == "goal" then
				local hazards = Profile(job, here, point)
				local group = groups[hazards.key]
				if not group then
					group = { hazards = hazards, targets = {}, of = {} }
					groups[hazards.key] = group
				end
				group.targets[#group.targets + 1] = point
				group.of[#group.targets] = place
				bounds[place] = bound
			end
		end
		ns.Path.Checkpoint()
	end
	return groups, bounds
end

---@param batch SPFNearbyWalkBatch
local function PauseBatch(batch)
	batch.publish = nil
	if not (batch.done or batch.job.done) then
		ns.Path.Pause(batch.job)
	end
end

-- Publish the direct walks as they settle under the frame budget. Other places use the planner's own estimate.
-- A requeue can borrow the previous measure's batches, including frontiers paused before all costs were settled.
---@type SPFMeasureWalks
local function MeasureWalks(places, callback, map, x, y, kept)
	local here = ns.JourneySearch.Here()
	if not (here and ns.Path.HasData(here.map)) then
		callback({})
		return nil
	end
	local water = ns.JourneyWaterWalking()
	local batches = kept and kept.nearbyWalks or {}
	if kept then
		kept.nearbyWalks = nil -- transfer ownership before the previous handle is cancelled
	end
	local handle = ns.Path.Run(function(job)
		return Groups(job, here, places, map, x, y)
	end, function(groups, bounds)
		if not groups then
			callback({})
			return
		end
		local lastMeasured, saved = measured, {}
		measured = saved
		local reusable = {}
		for batch in pairs(batches) do
			PauseBatch(batch)
			if batch.water == water and not batch.job.reason and ns.Path.ReuseMany(batch.job, here) then
				reusable[batch] = true
			else
				ns.Path.Cancel(batch.job)
				batches[batch] = nil
			end
		end
		local walks, pending = {}, {}
		local function Publish()
			callback(walks, next(pending) and pending or nil)
		end
		---@param batch SPFNearbyWalkBatch
		---@param selected SPFNearbyPlace[]
		local function Attach(batch, selected)
			local function Read()
				local job = batch.job
				local costs = job.costs or batch.costs
				local done = job.done or batch.done
				local failed = job.reason or batch.reason
				local changed = false
				for _, place in ipairs(selected) do
					local cost = costs[batch.index[place]]
					if done or cost ~= nil then
						if not failed then
							walks[place] = cost or false
						end
						changed = changed or pending[place] ~= nil
						pending[place] = nil
					else
						pending[place] = bounds[place]
					end
				end
				return changed
			end
			Read()
			for _, place in ipairs(selected) do
				if pending[place] then
					batch.publish = function()
						if Read() then
							Publish()
						end
					end
					if batch.job.paused then
						ns.Path.Resume(batch.job)
					end
					break
				end
			end
		end
		for key, group in pairs(groups) do
			local last = lastMeasured[key]
			if last and not reusable[last] and last.water == water and ns.Path.ReuseMany(last.job, here) then
				reusable[last] = true
			end
			local covered = {}
			for batch in pairs(reusable) do
				if batch.key == key then
					local selected = {}
					for _, place in ipairs(group.of) do
						if batch.index[place] and not covered[place] then
							selected[#selected + 1], covered[place] = place, true
						end
					end
					if #selected > 0 then
						batches[batch] = true
						if batch.done or batch.job.done then
							saved[key] = batch
						end
						Attach(batch, selected)
					end
				end
			end
			local targets, selected, index = {}, {}, {}
			for at, place in ipairs(group.of) do
				if not covered[place] then
					targets[#targets + 1] = group.targets[at]
					selected[#targets], index[place] = place, #targets
				end
			end
			if #targets > 0 then
				local batch = { key = key, water = water, index = index, costs = {} }
				batch.job = ns.Path.FindMany(
					here.map,
					here,
					targets,
					function(costs, reason, job)
						batch.costs, batch.done, batch.reason = costs, true, reason
						if not reason and job then
							saved[key] = batch
						end
						if batch.publish then
							batch.publish()
						end
						batch.publish = nil
					end,
					water,
					false,
					function(costs)
						batch.costs = costs
						if batch.publish then
							batch.publish()
						end
					end,
					group.hazards
				)
				batches[batch] = true
				Attach(batch, selected)
			end
		end
		Publish()
	end)
	handle.nearbyWalks, handle.nearbyOrigin = batches, here
	return handle
end

-- A measure answers for its source node even after its searches finish or pause.
---@param handle SPFPathJob
local function Holds(handle)
	local here, origin = ns.JourneySearch.Here(), handle.nearbyOrigin
	if not (here and origin) then
		return false
	end
	for batch in pairs(handle.nearbyWalks or {}) do
		if batch.job.sourceNode and ns.Path.ReuseMany(batch.job, here) then
			return true
		end
	end
	local band, originalBand = here.band, origin.band
	return here.map == origin.map
		and here.x == origin.x
		and here.y == origin.y
		and here.z == origin.z
		and (
			band == originalBand
			or band ~= nil and originalBand ~= nil and band.lo == originalBand.lo and band.hi == originalBand.hi
		)
end

---@param handle SPFPathJob
local function Pause(handle)
	for batch in pairs(handle.nearbyWalks or {}) do
		PauseBatch(batch)
	end
end

---@param job SPFPathJob
local function Cancel(job)
	ns.Path.Cancel(job)
	for walking in pairs(job.walking or {}) do
		ns.Path.Cancel(walking)
	end
	job.walking = nil
	for batch in pairs(job.nearbyWalks or {}) do
		PauseBatch(batch)
		if not (batch.done or batch.job.done) then
			ns.Path.Cancel(batch.job)
		end
	end
end

-- The cheapest of one shortlist by the journey's cost, on its walks as they land: callback(place) once the ranking is
-- decided, and the walks to the places left then stop. Returns the function that stops it all.
---@param candidates SPFNearbyPlace[]
---@param map integer
---@param x number
---@param y number
---@param callback SPFChosen
---@return fun()
local function Choose(candidates, map, x, y, callback)
	local measure, ranking, latest, again, done
	local function Stop()
		done = true
		for _, job in ipairs({ measure or false, ranking or false }) do
			if job then
				Cancel(job)
			end
		end
	end
	local function Decide()
		if ranking then
			again = true
			return
		end
		local walks, pending = latest.walks, latest.pending
		local this
		this = ns.Path.Run(function(job)
			local rank = NewRank(candidates, function(...)
				return ns.EstimateIn(job, ...)
			end, map, x, y, walks, pending)
			repeat
				local _, _, more = rank:Step()
			until not more
			return rank.best or candidates[1], rank.exact or not pending
		end, function(place, decided)
			if ranking ~= this or done then
				return
			end
			ranking = nil
			if decided then
				Stop()
				callback(place)
			elseif again then
				again = false
				Decide()
			end
		end)
		ranking = this
	end
	measure = MeasureWalks(candidates, function(walks, pending)
		if done then
			return
		end
		latest = { walks = walks, pending = pending }
		Decide()
	end, map, x, y)
	return Stop
end

---@alias SPFWalks table<SPFNearbyPlace, number|false> each place's measured walk; false where none was found
---@alias SPFWalksPending table<SPFNearbyPlace, number> each place still searched, with a lower bound on its walk
---@alias SPFWalksSettled fun(walks: SPFWalks, pending: SPFWalksPending?)
---@alias SPFChosen fun(place: SPFNearbyPlace)
---@alias SPFChoose fun(candidates: SPFNearbyPlace[], map: integer, x: number, y: number, callback: SPFChosen): fun()
---@alias SPFMeasureWalks
---| fun(list: SPFNearbyPlace[], cb: SPFWalksSettled, m: integer, x: number, y: number, kept?: SPFPathJob): SPFPathJob?
---@class SPFNearbyRankAPI
---@field New SPFRank
---@field MeasureWalks SPFMeasureWalks
---@field Cancel fun(job: SPFPathJob)
---@field Holds fun(job: SPFPathJob): boolean
---@field Pause fun(job: SPFPathJob)
---@field Choose SPFChoose
---@field Plan fun(job: SPFPathJob, options: SPFContextOptions, ...: any): SPFPlan?, boolean?
ns.NearbyRank = {
	New = NewRank,
	MeasureWalks = MeasureWalks,
	Cancel = Cancel,
	Holds = Holds,
	Pause = Pause,
	Choose = Choose,
	Plan = Plan,
}

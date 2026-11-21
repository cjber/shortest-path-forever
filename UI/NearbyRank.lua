---@type string, SPFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- One row's shortlist ranked by the planner's own journey cost, one Estimate per Step. The panel, the tracking menu and
-- /spfnear drain it inside a path job, whose estimates pause at the frame budget. The best starts as the straight-line
-- nearest, so a row always has an NPC, and stays so when no estimate can be made. A place whose walk is still being
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
---@field best? SPFNearbyPlace
---@field seconds? number
---@field walks table<SPFNearbyPlace, number|false>
---@field pending? SPFWalksPending
---@field exact? boolean
local Rank = {}
Rank.__index = Rank

function Rank:Step()
	local place = self.candidates[self.at]
	if not place then
		return self.best or self.candidates[1], self.seconds, false
	end
	self.at = self.at + 1
	-- Read before the estimate, which may pause while the measure settles this walk: the estimate is on the walk read.
	-- A walk still searched counts at its lower bound, so a pending place is never cheaper than it could be.
	local bound = self.pending and self.pending[place]
	local walk = self.walks[place]
	if bound then
		walk = bound
	end
	-- On a bound the estimate skips the planner's preferences: a Hearthstone dropped for saving too little on the bound
	-- may save enough on the longer walk measured, so the preferred route is no lower bound (#1034 review).
	local seconds =
		self.estimate(self.fromMap, self.fromX, self.fromY, place.map, place.x, place.y, walk, bound and true, place)
	local exact = not bound
	if seconds and (not self.seconds or seconds < self.seconds or seconds == self.seconds and exact) then
		self.best, self.seconds, self.exact = place, seconds, exact
	end
	return self.best or self.candidates[1], self.seconds, self.at <= #self.candidates
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

-- Retain settled costs without retaining Dijkstra frontiers. Departures share a batch across goals with identical
-- hazards. A reverse batch belongs to its NPC, since it must start on that NPC's own floor.
---@class SPFNearbyTransitCosts
---@field here SPFPoint
---@field anchor? SPFPathJob
---@field departures table<string, SPFPathJob>
---@field landings table<SPFNearbyPlace, SPFPathJob>
---@type SPFNearbyTransitCosts?
local transit

local function TransitCosts(here)
	local last = transit
	local band, previous = here.band, last and last.here.band
	local sameBand = band == previous or band and previous and band.lo == previous.lo and band.hi == previous.hi
	if
		not last
		or not (sameBand and ns.JourneySearch.SamePlace(last.here, here) or ns.Path.ReuseMany(last.anchor, here, true))
	then
		last = { here = here, departures = {}, landings = {} }
		transit = last
	end
	return last
end

local function TargetIndex(targets, target)
	for i, point in ipairs(targets) do
		if ns.JourneySearch.SamePlace(point, target) then
			return i
		end
	end
end

local function EndpointCost(job, source, target, reverse, options, places, kept, key)
	local path = ns.Path
	if not path.HasData(source.map) then
		return nil
	end
	local cache = reverse and kept.landings or kept.departures
	local batch = cache[key]
	local index
	local hazards, water = options.hazards, options.waterWalking
	if
		batch
		and batch.waterWalking == water
		and batch.hazards.key == hazards.key
		and (reverse or path.ReuseMany(batch, source, true))
	then
		index = TargetIndex(batch.targets, target)
		if index and batch.costs[index] ~= nil then
			return batch.costs[index]
		end
	end

	local cost
	local function Update(costs, reason, searched)
		if job.cancelled or (not searched.done and (not costs or costs[index] == nil)) then
			return
		end
		if reason ~= "nodata" and reason ~= "error" then
			cost = costs and costs[index]
			if cost == nil then
				cost = false
			end
			if searched.valid then
				cache[key] = searched
				if not reverse then
					kept.anchor = searched
				end
			end
		end
		path.ReleaseMany(searched)
		job.walking[searched] = nil
		path.Resume(job)
	end

	-- A second ranking can use another batch while this one owns its callbacks.
	cache[key] = nil
	if index then
		batch.callback, batch.progress = Update, Update
		path.Resume(batch)
	else
		local targets = ns.JourneySearch.EndpointTargets(source, places)
		index = TargetIndex(targets, target)
		if not index then
			return nil
		end
		batch = path.FindMany(source.map, source, targets, Update, water, reverse, Update, hazards)
	end
	job.walking = job.walking or {}
	job.walking[batch] = true
	path.Wait()
	return cost
end

-- Replan on the winning candidate's measured legs. Another ride can become cheaper when a walk grows or is ruled
-- out, so keep the lower-bound alternatives in the graph until a plan needs no further searches.
---@param job SPFPathJob
---@param options SPFContextOptions
---@param place SPFNearbyPlace
---@param walk? number|false
---@param bound? boolean
local function Plan(job, options, place, walk, bound)
	job.nearbyHere = job.nearbyHere or ns.JourneySearch.Here()
	local here, goal = job.nearbyHere, Spawn(place)
	if here and goal then
		options.from, options.to = here, goal
		options.hazards = ns.Hazards.Profile(here, goal, here)
		options.endpointBounds = true
	end
	local walks = {}
	if walk ~= nil then
		walks[1] = { from = options.from, to = options.to, cost = walk }
	end
	options.walks, options.lowerBound = walks, bound
	local plan = ns.Planner.Plan(options, job)
	if bound or not (here and goal and plan) then
		return plan
	end
	local rides = false
	for _, leg in ipairs(plan.legs) do
		rides = rides or leg.mode ~= "walk"
	end
	if not rides then
		return plan
	end
	local kept, places = TransitCosts(here), ns.Planner.Places(options)
	while plan do
		local changed = false
		for _, leg in ipairs(plan.pendingWalks) do
			local reverse = leg.from.kind ~= "start"
			local cost
			if reverse then
				cost = EndpointCost(job, goal, leg.from, true, options, places, kept, place)
			elseif leg.to.kind ~= "goal" then
				cost = EndpointCost(job, here, leg.to, false, options, places, kept, options.hazards.key)
			end
			if cost ~= nil then
				walks[#walks + 1] = { from = leg.from, to = leg.to, cost = cost }
				changed = true
			end
		end
		if not changed then
			return plan
		end
		plan = ns.Planner.Plan(options, job)
	end
end

-- The last finished measures, one per hazard profile: the panel asks again every tick, and while you stand on the
-- same node with the same settings their walks hold.
---@type table<string, { job: SPFPathJob, water: boolean, walks: SPFWalks }>
local measured = {}

-- The places that walk under one hazard profile: the journey's own, which never charges the zone or town you start or
-- end in (Hazards.Profile), so each place has its own and places share a search only where theirs match.
---@param here SPFPoint
---@param places SPFNearbyPlace[]
---@return table<string, { hazards: SPFHazards, targets: SPFPoint[], of: SPFNearbyPlace[] }>
local function Groups(here, places)
	local Context = ns.PlanContext
	local mass = Context.Landmass(here)
	local groups, seen = {}, {}
	for _, place in ipairs(places) do
		-- A place on another landmass is no walk: the journey crosses by boat or flight, as its own batches assume.
		local point = not seen[place] and Spawn(place)
		seen[place] = true
		if point and point.map == here.map and Context.Landmass(point) == mass then
			local hazards = ns.Hazards.Profile(here, point, here)
			local group = groups[hazards.key]
			if not group then
				group = { hazards = hazards, targets = {}, of = {} }
				groups[hazards.key] = group
			end
			group.targets[#group.targets + 1] = point
			group.of[#group.targets] = place
		end
		ns.Path.Checkpoint()
	end
	return groups
end

-- The walks the journey would take from where you stand to each place: its own search, from its own start (your floor,
-- or your height band) to the spot it walks to (the NPC's own floor), under its own hazards. An estimate built on them
-- prices the direct walk as the journey does, including detours around walls (#1032). Transit endpoint walks settle
-- inside the ranking job when it finds a ride. Calls back as direct walks settle, nearest first, with running yards
-- (false where no walk was found) and, for each place still searched, a lower bound on its walk (Path.LowerBound);
-- then once more with pending nil when done. A place it cannot search is never pending, and its estimate stays the
-- planner's own. The work runs under the frame budget; Cancel stops it, as a caller does once its rankings are decided
-- rather than walk to every far place.
---@param places SPFNearbyPlace[]
---@param callback SPFWalksSettled
---@return SPFPathJob?
local function MeasureWalks(places, callback)
	local here = ns.JourneySearch.Here()
	if not (here and ns.Path.HasData(here.map)) then
		callback({})
		return nil
	end
	local water = ns.JourneyWaterWalking()
	local handle
	handle = ns.Path.Run(function()
		return Groups(here, places)
	end, function(groups)
		-- A grouping that failed measures nothing: every estimate stays the planner's own, and the callers decide.
		if not groups then
			callback({})
			return
		end
		local walks, pending, open, last = {}, {}, 1, measured
		measured = {}
		-- Each change goes out at once: while other groups search, what is known so far, and when the last ends, done.
		local function Publish()
			callback(walks, open > 0 and pending or nil)
		end
		for key, group in pairs(groups) do
			local kept = last[key]
			local known = kept and kept.water == water and ns.Path.ReuseMany(kept.job, here)
			for _, place in ipairs(known and group.of or {}) do
				known = known and kept.walks[place] ~= nil
			end
			if known then
				measured[key] = kept
				for _, place in ipairs(group.of) do
					walks[place] = kept.walks[place]
				end
			else
				open = open + 1
				for at, place in ipairs(group.of) do
					pending[place] = ns.Path.LowerBound(here.map, here, group.targets[at])
				end
				local job, finished
				job = ns.Path.FindMany(
					here.map,
					here,
					group.targets,
					function(costs, reason)
						finished = true
						if job then
							handle.walking[job] = nil
						end
						local found = {}
						for at, place in ipairs(group.of) do
							-- false where no walk was found; on a failed search the planner's own estimate stands.
							if not reason then
								found[place] = costs[at] or false
							end
							walks[place], pending[place] = found[place], nil
						end
						if not reason then
							measured[key] = { job = job, water = water, walks = found }
						end
						open = open - 1
						Publish()
					end,
					water,
					false,
					function(costs)
						local settled = false
						for at, place in ipairs(group.of) do
							if pending[place] and costs[at] ~= nil then
								walks[place], pending[place], settled = costs[at], nil, true
							end
						end
						if settled then
							Publish()
						end
					end,
					group.hazards
				)
				-- A search that answered at once is already settled.
				if not finished then
					handle.walking[job] = true
				end
			end
		end
		open = open - 1
		-- What the reused measures know goes out now; with nothing known yet, the first settled walk publishes.
		if open == 0 or next(walks) then
			Publish()
		end
	end)
	handle.walking = {}
	return handle
end

-- Whether a measure still running answers for where you stand: its searches start from your walking-map node, as
-- Path.ReuseMany tells. A measure not yet searching, or done searching, holds.
---@param handle SPFPathJob
---@return boolean
local function Holds(handle)
	local here = ns.JourneySearch.Here()
	for job in pairs(handle.walking or {}) do
		if job.sourceNode then
			return here ~= nil and ns.Path.ReuseMany(job, here)
		end
	end
	return true
end

-- Stops a measure, with the walking searches it started, or a ranking.
---@param job SPFPathJob
local function Cancel(job)
	ns.Path.Cancel(job)
	for walking in pairs(job.walking or {}) do
		ns.Path.Cancel(walking)
	end
	job.walking = nil
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
	end)
	return Stop
end

---@alias SPFWalks table<SPFNearbyPlace, number|false> each place's measured walk; false where none was found
---@alias SPFWalksPending table<SPFNearbyPlace, number> each place still searched, with a lower bound on its walk
---@alias SPFWalksSettled fun(walks: SPFWalks, pending: SPFWalksPending?)
---@alias SPFChosen fun(place: SPFNearbyPlace)
---@alias SPFChoose fun(candidates: SPFNearbyPlace[], map: integer, x: number, y: number, callback: SPFChosen): fun()
---@alias SPFMeasureWalks fun(places: SPFNearbyPlace[], callback: SPFWalksSettled): SPFPathJob?
---@class SPFNearbyRankAPI
---@field New SPFRank
---@field MeasureWalks SPFMeasureWalks
---@field Cancel fun(job: SPFPathJob)
---@field Holds fun(job: SPFPathJob): boolean
---@field Choose SPFChoose
---@field Plan fun(job: SPFPathJob, options: SPFContextOptions, ...: any): SPFPlan?
ns.NearbyRank =
	{ New = NewRank, MeasureWalks = MeasureWalks, Cancel = Cancel, Holds = Holds, Choose = Choose, Plan = Plan }

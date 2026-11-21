-- rule-ignore: file-size-no-growth - the journey search, its leg policy and the zone exemptions it builds stay together
---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- The search for a journey's fastest way: one bounded FindMany from where you stand and one back from the goal,
-- short A* probes for the candidate's own walks, the plan they settle, that plan's walking geometry (JourneyWalks.lua)
-- and whether it replaces the route you are following. A first search draws its estimate, then follows a measured
-- route while the proof runs.
-- Journey.lua starts, steps and cancels the search and follows what it publishes.
local PROBE_BUDGET = 60 -- ms before switching from candidate costs to shared endpoint searches
local REFRESH_EVERY = 60
-- Timed replans replace the followed route only for a worthwhile gain; endpoint costs stay unchanged between
-- the infrequent batches, except for Remaining() along the walk you are following.
local SWITCH_GAIN, SWITCH_SHARE = 30000, 0.1

-- A followed route yields to a challenger for a gain worth the change: a tenth of the trip left, or 30 seconds,
-- whichever is the smaller. The floor alone is unreachable on a trip under half a minute, so there the share decides.
local function Worthwhile(gain, remaining)
	return gain >= SWITCH_GAIN or gain >= remaining * SWITCH_SHARE
end

local Context = ns.PlanContext
---@class SPFJourneySearch
---@field timing {at: number, frames: integer, cpu: number, first: table?, last: table?}? the last search's timings
local Search = {}
ns.JourneySearch = Search
-- JourneyWalks.lua fills this in; nothing outside the search uses it.
---@class SPFJourneyWalks
local Walks = {}
Search.Walks = Walks

---@alias SPFSearchNews
---| "searching" a first search began: nothing to follow yet
---| "rough" a first search's estimate, drawn until a followable route replaces it
---| "route" this route replaces the followed one (nil: no way there)
---| "walks" the followed route was retimed and its walks redrawn
---| "times" the followed route was retimed

-- The journey being searched for, as Start received it, or the nearest ground a player can walk to when nobody can
-- walk onto it (grounded, #1113). followed is the route Journey is on: the one Start passed or the last one published
-- as "route". progress is Journey's own record, read here and never written.
local goal, followed
---@type {from: SPFPoint, to: SPFPoint}?
local grounded
---@type {index: integer, departed?: boolean}
local progress
---@type fun(route: SPFPlan?, news: SPFSearchNews)
local publish
-- One search from its first batch to its proof: its provisional offer and the candidate it must still prove.
local search
local FinishSearch
-- The mode this journey's walks were searched in, and the hazards they keep away from (Hazards.lua).
local waterMode
---@type SPFRoutePolicy
local routePolicy = "normal"
---@type SPFHazards?
local hazards
local lastRunSpeed = 7
local plannerCache = {}
local probeJobs, pathVersion = {}, 0
-- The timed replan's path job while it plans.
local replanning
local startBatch, goalBatch, startAt
local refreshedAt = 0
local startCosts, goalCosts = {}, {}
local pendingCosts, settleRound = 0, 0
local costError
local costsWaiting

local function SamePlace(a, b)
	return a.map == b.map and a.x == b.x and a.y == b.y and a.z == b.z
end
Search.SamePlace = SamePlace

-- Where you stand, with the height of your floor when Floor.lua knows it: the walks then start on that floor rather
-- than the cheapest surface near you. Where the floor is not known, the range checks to the NPCs around you bound the
-- height instead, and the walks start on the surfaces inside that band (Band.lua, #737).
local function Here()
	local x, y, _, map = ns.JourneyPosition()
	if not (x and y and map) then
		return nil
	end
	local z = ns.Floor and ns.Floor.Height(map, x, y) or nil
	return { map = map, x = x, y = y, z = z, band = z == nil and ns.Band and ns.Band.At(map, x, y) or nil }
end
Search.Here = Here

-- Both directions only search fixed places on the endpoint's own landmass.
function Search.EndpointTargets(point, places)
	local list, mass = {}, Context.Landmass(point)
	for _, place in ipairs(places) do
		if place.map == point.map and Context.Landmass(place) == mass then
			list[#list + 1] = place
		end
	end
	return list, mass
end

-- Cancelled searches leave both batches paused with their settled costs.
local function CancelPaths()
	pathVersion = pathVersion + 1
	for job in pairs(probeJobs) do
		ns.Path.Cancel(job)
	end
	Walks.Cancel()
	for _, batch in pairs({ start = startBatch, goal = goalBatch }) do
		if batch.job then
			ns.Path.Pause(batch.job)
		end
	end
	pendingCosts = 0
	probeJobs, replanning = {}, nil
end

-- How much of the chosen walk is still ahead of here, from 0 to 1, or nil when here is off it.
local function RemainingShare(leg, here)
	local found, _, after, total = ns.OnWalk(leg.walkPoints, here)
	if found and total > 0 then
		return after / total
	end
end

-- The rest of the chosen walk in its own running yards, so water keeps its search weight.
local function Remaining(leg, here)
	local share = RemainingShare(leg, here)
	return share and (leg.walkCost or leg.yards) * share
end

-- The measured walks from where the batch started, moved to here, and back from the goal, with the rest of the walk
-- you are on.
---@param here SPFPoint
---@return SPFWalkCost[]
local function MeasuredWalks(here)
	local walks = {}
	for _, walk in ipairs(goalCosts) do
		walks[#walks + 1] = walk
	end
	if startAt and startAt.map == here.map then
		for _, walk in ipairs(startCosts) do
			walks[#walks + 1] =
				{ from = here, to = walk.to, cost = walk.cost, estimated = walk.estimated, apart = walk.apart }
		end
	end
	-- Drawing an offer must not supply a new cost to the proof that produced it.
	local leg = followed and followed.legs[progress.index]
	local rest = leg
		and not followed.provisional
		and followed.waterMode == waterMode
		and followed.hazards == (hazards and hazards.key)
		and leg.mode == "walk"
		and leg.measured
		and Remaining(leg, here)
	if rest then
		walks[#walks + 1] = { from = here, to = leg.to, cost = rest }
	end
	return walks
end

-- A plan being followed draws from the leg you are on; any other starts at its first.
local function PrepareWalks(planned)
	Walks.Prepare(
		planned,
		followed and followed.legs,
		waterMode,
		FinishSearch,
		planned == followed and progress.index or 1
	)
end

-- Only the timings move, so the drawn route, Guide and any walk still being searched carry on undisturbed.
local function Retime(planned)
	followed.now, followed.arrive = planned.now, planned.arrive
	for index, leg in ipairs(planned.legs) do
		local kept = followed.legs[index + progress.index - 1]
		kept.depart, kept.arrive, kept.wait, kept.estimated = leg.depart, leg.arrive, leg.wait, leg.estimated
		kept.aboard, kept.yards, kept.ready = leg.aboard, leg.yards, leg.ready
	end
end

-- Compare against this route's own measured legs, at the same departure time as the challenger.
-- Reusing an earlier arrival would make the first offered route unfairly hard to replace.
local function EstimateKept(now)
	if not followed then
		return nil
	end
	local here = Here()
	local estimate = { now = now, arrive = now, legs = {} }
	for index = progress.index, #followed.legs do
		local leg = followed.legs[index]
		if
			index == progress.index
			and leg.route
			and not progress.departed
			and (leg.mode == "boat" and (not here or not SamePlace(leg.from, here)) or leg.depart < now)
		then
			-- An unboarded boat still needs an approach from here. This estimate starts at the boat and has
			-- no measured approach, so only a fresh plan can price the walk back to its dock.
			return nil
		end
		local duration, wait = leg.arrive - leg.depart, leg.wait or 0
		local yards = leg.yards or duration / 1000 * lastRunSpeed
		if leg.walkError then
			return nil
		end
		if leg.mode == "walk" then
			local entry = Walks.Measured(leg)
			if entry and entry.reason then
				return nil
			end
			local basis = entry and entry.cost or leg.walkCost or yards
			if index == progress.index and leg.measured then
				-- A share of the basis, never divided by the walk's own cost, which a measured walk may put at 0.
				local share = RemainingShare(leg, here)
				if not share then
					return nil
				end
				yards = basis * share
			else
				yards = basis
			end
			duration, wait = yards / lastRunSpeed * 1000, 0
		elseif leg.route and not leg.aboard then
			wait = ns.Routes[leg.route].period / 2
			if leg.boarding then
				local _, _, departIn = ns.Timetable.Visit(leg.route, leg.boarding, estimate.arrive)
				wait = departIn or wait
			end
		elseif index == progress.index and leg.aboard then
			duration, wait = math.max(0, leg.arrive - now), 0
		elseif leg.ready then
			wait = math.max(0, leg.ready - estimate.arrive)
		end
		local depart = estimate.arrive + wait
		estimate.arrive = depart + duration
		estimate.legs[#estimate.legs + 1] = {
			depart = depart,
			arrive = estimate.arrive,
			wait = wait,
			yards = yards,
			estimated = leg.estimated,
			aboard = leg.aboard,
		}
	end
	return estimate
end

-- The drawn route's own timings from where you stand: what a timed tick owes the player, without a search, a plan or
-- new geometry. False when a sailing the route waits for has moved to its next visit, or nothing can be estimated.
---@return boolean
local function RetimeKept()
	local estimate = followed and EstimateKept(ns.NowMs())
	if not estimate then
		return false
	end
	for index, leg in ipairs(estimate.legs) do
		local kept = followed.legs[index + progress.index - 1]
		-- An untimed route has no sailing to count; it waits out a guess of half its round trip.
		local sighted = kept.route and kept.boarding and not kept.aboard and ns.Timetable.Anchor(kept.route) ~= nil
		if sighted and math.abs(leg.depart - kept.depart) > 0.5 then
			return false
		end
	end
	Retime(estimate)
	publish(followed, "times")
	return true
end

-- Since the journey's search started: wall milliseconds, frames that ran path work, their milliseconds and the
-- frame rate, for the report.
local function Elapsed(timing)
	local work = ns.Path.work
	return {
		ms = ns.Path.clock() - timing.at,
		frames = work.frames - timing.frames,
		cpu = work.cpu - timing.cpu,
		fps = GetFramerate and GetFramerate() or nil,
	}
end

-- The displayed plan has its own legs, so drawing geometry cannot change the proof's candidate.
---@param planned SPFPlan
---@return SPFPlan
local function CopyPlan(planned)
	local copy = {}
	for key, value in pairs(planned) do
		copy[key] = value
	end
	copy.legs = {}
	for index, leg in ipairs(planned.legs) do
		local legCopy = {}
		for key, value in pairs(leg) do
			legCopy[key] = value
		end
		copy.legs[index] = legCopy
	end
	return copy
end

local function Rough(planned)
	local rough = CopyPlan(planned)
	for _, leg in ipairs(rough.legs) do
		if leg.mode == "walk" and not leg.measured then
			leg.walkPlaceholder = true
		end
	end
	rough.preview, rough.rough = nil, true
	return rough
end

---@param planned SPFPlan?
local function Commit(planned)
	followed = planned
	local timing = Search.timing
	if timing then
		timing.last = Elapsed(timing)
		timing.first = timing.first or timing.last
	end
	return publish(planned, "route")
end

-- A proved journey keeps exact endpoint vectors and their lower bounds, never suspended search stacks.
local function ReleaseCosts()
	for _, batch in pairs({ start = startBatch, goal = goalBatch }) do
		if batch.job then
			ns.Path.ReleaseMany(batch.job)
		end
	end
end

-- Follow the settled walks once the first leg can guide the player.
local function Offer()
	local offer = search.offer
	local first = offer.legs[1]
	if first.measured then
		offer.provisional = true
		Commit(offer)
	end
end

FinishSearch = function()
	if not search then
		return
	end
	if pendingCosts > 0 then
		if search.offer and not followed then
			Offer()
		end
		return
	end
	if search.offer and not followed then
		Walks.Drop(search.offer)
		search.offer = nil
	end
	if Walks.Pending() > 0 then
		return
	end
	local planned, forced = search.candidate, search.forced
	local estimate = EstimateKept(planned and planned.now or ns.NowMs())
	local same = Walks.SameJourney(planned, followed, progress.index, Here())
	local gain = estimate and planned and estimate.arrive - planned.arrive
	-- A ride the planner preferred to a long walk, or to a walk through the goal's high-level zone, is later than that
	-- walk by design, so its gain cannot argue for it against the walk already shown.
	local overWalk = planned
		and (planned.preferred or planned.rideNote)
		and followed
		and #followed.legs == 1
		and followed.legs[1].mode == "walk"
	-- A teleport not yet cast commits you to nothing: any quicker way that leaves it unspent replaces it.
	local current = followed and followed.legs[progress.index]
	local first = planned and planned.legs[1]
	local uncast = current
		and current.mode == "teleport"
		and first
		and (first.mode ~= "teleport" or first.teleport.spell ~= current.teleport.spell)
	local better = estimate
		and planned
		and gain
		and (overWalk or uncast and gain > 0 or Worthwhile(gain, estimate.arrive - planned.now))
	local valid = true
	for _, leg in ipairs(planned and planned.legs or {}) do
		if leg.walkError then
			valid = false
		end
	end
	local provisional = followed and followed.provisional
	local refine = search.refine or search.initial and not provisional
	-- A provisional route yields to the proof even for a small gain. Ordinary replans keep their switching threshold.
	local keep
	if provisional then
		-- On a taxi Plan returns the followed route itself, including any legs already passed.
		keep = planned == followed or not forced and same
	else
		keep = followed and planned and estimate and (not valid or (not forced and (same or not better)))
	end
	if search.replace then
		keep = false
	end
	if not keep and planned and not planned.prepared then
		PrepareWalks(planned)
		if Walks.Pending() > 0 then
			return
		end
	end
	search = nil
	ReleaseCosts()
	if keep then
		followed.provisional = nil
		if same then
			followed.unknownFlight, followed.unknownFlightMaps = planned.unknownFlight, planned.unknownFlightMaps
			followed.rideNote = planned.rideNote
		end
		local retimed = same and planned or estimate
		if retimed then
			Retime(retimed)
		end
		if provisional and Search.timing then
			Search.timing.last = Elapsed(Search.timing)
		end
		local changedWater = followed.waterMode ~= waterMode
		followed.waterMode = waterMode
		if refine or changedWater then
			for _, leg in ipairs(followed.legs) do
				if leg.mode == "walk" then
					local entry = Walks.Measured(leg)
					if entry then
						if refine then
							leg.walkPoints = entry.points or {}
						end
						leg.walkError, leg.wet = entry.reason, entry.points and entry.points.wet
						leg.measured, leg.walkCost = entry.reason == nil, entry.cost or leg.walkCost
					end
				end
			end
			followed.prepared = true
		end
		return publish(followed, refine and "walks" or "times")
	end
	return Commit(planned)
end

local function Render(planned, forced)
	search = search or { initial = not followed }
	search.candidate, search.forced = planned, forced
	local resume = Walks.NeedsPrepare(followed, progress.index)
	search.refine = followed and (not followed.prepared or resume)
	if resume then
		PrepareWalks(followed)
	end
	if followed and followed.waterMode ~= waterMode then
		local kept = { legs = {}, preview = true }
		for index = progress.index, #followed.legs do
			local copy = {}
			for key, value in pairs(followed.legs[index]) do
				copy[key] = value
			end
			kept.legs[#kept.legs + 1] = copy
		end
		PrepareWalks(kept)
	end
	local estimate = not search.initial and not forced and EstimateKept(planned and planned.now or ns.NowMs())
	if estimate and planned and Walks.Pending() == 0 and not search.refine and not followed.provisional then
		local gain = estimate.arrive - planned.arrive
		if not Worthwhile(gain, estimate.arrive - planned.now) then
			FinishSearch()
			return
		end
	end
	-- Reusing the followed walk needs no new geometry and preserves Guide's passed bends.
	if search.refine or not Walks.SameJourney(planned, followed, progress.index, Here()) then
		PrepareWalks(planned)
	end
	FinishSearch()
end

-- Feasible plans use known walks; the incumbent bounds the exact search while preserving journey preferences.
---@param feasible boolean?
---@param incumbent SPFPlan?
---@param job SPFPathJob the path job planning, which pauses at the frame budget
---@return SPFPlan?
local function Plan(feasible, incumbent, job)
	local here = Here()
	if not (here and goal) then
		return nil
	end
	-- Taxi paths cannot be interrupted; retain their chosen destination until landing.
	if followed and UnitOnTaxi("player") then
		lastRunSpeed, followed.now = Context.RunSpeed(), ns.NowMs()
		return followed
	end
	-- Where you stand, the context and the walks below each read the client; the budget is checked between them.
	ns.Path.Checkpoint()
	local options = Context.Options(here, goal, routePolicy)
	-- This is a manual refusal for the active journey only. Keep it out of Context.Options so
	-- public estimates and nearby-service planning retain the normal Hearthstone policy.
	options.withoutHearth = ns.JourneyWithoutHearth and ns.JourneyWithoutHearth() or false
	local now = options.now
	lastRunSpeed = options.walkSpeed
	ns.Path.Checkpoint()
	local walks = MeasuredWalks(here)
	for _, walk in ipairs(Walks.Landings(options.teleports, waterMode)) do
		walks[#walks + 1] = walk
	end
	ns.Path.Checkpoint()
	options.cache, options.walks, options.waterWalking, options.hazards = plannerCache, walks, waterMode, hazards
	options.feasibleOnly = feasible
	-- A walk through the goal's high-level zone shows its real arrival but was chosen on its charged one (#1007).
	options.incumbent, options.incumbentPlan = incumbent and (incumbent.charged or incumbent.arrive), incumbent
	options.ride = Context.Ride(options)
	options.unknownFlightNotice = true
	local planned = ns.Planner.Plan(options, job)
	if planned then
		planned.now, planned.preview, planned.waterMode = now, nil, waterMode
		planned.hazards = hazards and hazards.key
	end
	return planned
end

-- Reuse only the last two endpoint searches, with starts confirmed by the pathfinder as the same snapped node.
-- One search owns the callbacks' shared revision, preview and probe budget across resumes
---@param includeGoal boolean?
---@param forced boolean?
---@param replace boolean? the destination moved, so the plan under way leads somewhere else
local function RefreshCosts(includeGoal, forced, replace)
	local here = Here()
	if not (here and goal) then
		return
	end
	CancelPaths()
	search = { initial = not followed, forced = forced, replace = replace }
	local owner = search
	local version = pathVersion
	local options = Context.Options(here, goal, routePolicy)
	local teleports, partyPortals = options.teleports, options.partyPortals
	local places, faction = Context.Places(teleports, partyPortals, routePolicy)
	local function targets(point, withGoal)
		local list, mass = Search.EndpointTargets(point, places)
		if withGoal and goal.map == point.map and Context.Landmass(goal) == mass then
			list[#list + 1] = goal
		end
		return list
	end
	local hazardKey = hazards and hazards.key
	local function reuse(batch, point, reverse)
		if
			not batch
			or batch.policy ~= routePolicy
			or batch.water ~= waterMode
			or batch.faction ~= faction
			or batch.teleports ~= teleports
			or batch.partyPortals ~= partyPortals
			or batch.hazards ~= hazardKey
		then
			return false
		end
		if not reverse and not SamePlace(batch.goal, goal) then
			return false
		end
		return SamePlace(batch.point, point) or (not reverse and ns.Path.ReuseMany(batch.job, point))
	end
	local function create(previous, point, reverse)
		if reuse(previous, point, reverse) then
			return previous
		end
		if previous and previous.job then
			ns.Path.Cancel(previous.job)
		end
		return {
			point = point,
			goal = goal,
			targets = targets(point, not reverse),
			reverse = reverse,
			policy = routePolicy,
			water = waterMode,
			faction = faction,
			teleports = teleports,
			partyPortals = partyPortals,
			hazards = hazardKey,
			costs = {},
		}
	end
	startBatch = create(startBatch, here, false)
	if includeGoal then
		goalBatch = create(goalBatch, goal, true)
	end
	startAt, refreshedAt = here, GetTime()
	pendingCosts, costError = 2, nil
	if search.initial then
		publish(nil, "searching")
	end
	local slices, lastRevision, probeCPU = 0, -1, 0
	local function fixedPlace(batch)
		if batch.fixedChecked or not (batch.job and batch.job.valid) then
			return
		end
		batch.fixedChecked = true
		for _, place in ipairs(places) do
			if
				place.map == batch.point.map
				and math.abs(place.x - batch.point.x) < 0.00001
				and math.abs(place.y - batch.point.y) < 0.00001
				and ns.Path.ReuseMany(batch.job, place, true)
			then
				batch.fixedKey = place.kind .. place.id
				return
			end
		end
	end
	local function bakedBound(batch, target)
		local first = batch.fixedKey
		local last = target.kind and target.kind .. target.id or target == goal and goalBatch.fixedKey
		local baked = first and last and ns.Walks[batch.point.map]
		if not baked then
			return 0
		end
		if first == last then
			return 0
		end
		if batch.reverse then
			first, last = last, first
		end
		local pair = baked[first < last and first .. " " .. last or last .. " " .. first]
		local cost = pair and pair[(waterMode and 2 or 1) + (first > last and pair[3] ~= nil and 2 or 0)]
		-- Baked costs round to whole yards. They strengthen the bound but never stand in for exact endpoint costs.
		return cost and math.max(0, cost - 0.5) or 0
	end
	local function walks(batch)
		local list = {}
		if not ns.Path.HasData(batch.point.map) then
			return list
		end
		local radius = batch.job and batch.job.radius or 0
		for i, target in ipairs(batch.reason ~= "nodata" and batch.targets or {}) do
			local cost = batch.probes and batch.probes[i]
			if cost == nil then
				cost = batch.costs[i]
			end
			local estimated = cost == nil
			if estimated then
				local lower = ns.Path.LowerBound(batch.point.map, batch.point, target)
				cost = math.max(lower, radius, bakedBound(batch, target))
			end
			list[#list + 1] = {
				from = batch.reverse and target or batch.point,
				to = batch.reverse and batch.point or target,
				cost = cost,
				estimated = estimated,
				-- Once the batch has settled every target on its own node, an unmeasured one is a real walk away.
				apart = estimated and batch.job and batch.job.snapped or nil,
			}
		end
		return list
	end
	local function active(batch, needed)
		if needed then
			ns.Path.Resume(batch.job)
		else
			ns.Path.Pause(batch.job)
		end
	end
	local preview
	local wantPreview = not followed
	if wantPreview then
		startCosts, goalCosts = walks(startBatch), walks(goalBatch)
	end
	-- A search that has published (FinishSearch forgets it) or was replaced is never heard from again.
	local function stale()
		return version ~= pathVersion or search ~= owner or not goal
	end
	-- Does the walk from here reach the goal itself? true when it does (a cost or a successful probe), false once
	-- the start batch or the goal batch has ruled it out or never measured the goal (another landmass), nil while it
	-- may still.
	local function Direct()
		for i, point in ipairs(startBatch.targets) do
			if SamePlace(point, goal) then
				if startBatch.costs[i] or (startBatch.probes and startBatch.probes[i]) then
					return true
				end
				-- A goal batch that spent its frontier holds every entrance that walks to the goal, so whether here
				-- leaves through one is known without waiting for the start batch to search the whole landmass.
				if startBatch.done or ns.Path.WalksInto(goalBatch.job, startBatch.point) == false then
					return false
				end
				return nil
			end
		end
		return false
	end
	-- An offer starts with a walk the player can retrace, the walk the best route the bounds still allow starts with
	-- too: a transport-first fallback, or a walk to a ride that an unmeasured walk may beat, can send the player away
	-- while the proof would choose otherwise (#1032).
	local function offerFeasible(feasible, planned)
		local first = feasible and feasible.legs[1]
		local lead = planned and planned.legs[1]
		if
			pendingCosts > 0
			and search.initial
			and not search.offer
			and not followed
			and first
			and first.mode == "walk"
			and lead
			and lead.mode == "walk"
			and SamePlace(lead.to, first.to)
		then
			search.offer = CopyPlan(feasible)
			PrepareWalks(search.offer)
			Offer()
		end
	end
	local consider, request
	-- Asks again once a bind point's walks have gone far enough that it cannot beat the plan (LandingPending). One
	-- function per search, so each consider moves its radius rather than adding a listener.
	local function landed()
		request(true)
	end
	-- Bounded search callback; splitting adds calls and upvalues on every frontier update. It runs only in the
	-- search's own path job (request), where each plan pauses at the frame budget; anything a pause let change is
	-- checked again after it.
	consider = function(final, job)
		if stale() then
			return
		end
		if not ns.JourneyPosition() then
			costsWaiting = true
			return
		end
		if
			(not startBatch.done and not (startBatch.job and startBatch.job.valid))
			or (not goalBatch.done and not (goalBatch.job and goalBatch.job.valid))
		then
			return
		end
		local hadFixed = startBatch.fixedKey or goalBatch.fixedKey
		fixedPlace(startBatch)
		fixedPlace(goalBatch)
		if stale() then
			return
		end
		if not hadFixed and (startBatch.fixedKey or goalBatch.fixedKey) then
			preview = nil
		end
		slices = slices + 1
		local revision = (startBatch.job and startBatch.job.revision or 0)
			+ (goalBatch.job and goalBatch.job.revision or 0)
		if not final and revision == lastRevision and slices < 16 then
			return
		end
		slices, lastRevision = 0, revision
		startCosts, goalCosts = walks(startBatch), walks(goalBatch)
		local goalError = goalBatch.reason
		-- Why an endpoint has no walk at all, a failed search first. A missing map is not one: its walks are estimated.
		local startError = startBatch.reason ~= "nodata" and startBatch.reason or nil
		costError = (startError == "error" or goalError == "error") and "error"
			or startError
			or goalError ~= "nodata" and goalError
			or nil
		-- An invalid goal also rules out the direct start -> goal edge without searching toward it.
		if goalError and goalError ~= "nodata" then
			startCosts[#startCosts + 1] = { from = here, to = goal, cost = false }
		end
		-- What the settled walks alone give: the arrival every other route must beat, and a route to follow if the
		-- proof still has far to go.
		local feasible = Plan(true, nil, job)
		if stale() then
			return
		end
		local bound = feasible and feasible.arrive
		local function best()
			return Plan(false, feasible, job)
		end
		-- Reuse the bounded preview once for probes; commit only after planning with current exact costs.
		local previewed = preview
			and not startBatch.reason
			and not goalBatch.reason
			and not (bound and preview.arrive >= bound)
		local planned = previewed and preview or best()
		preview = nil
		if stale() then
			return
		end
		-- Publishing starts in a frame of its own when the plans spent this one's budget.
		ns.Path.Checkpoint()
		if stale() then
			return
		end
		-- A batch that has not yet settled the targets on its own node may still find a zero, a transfer, for a walk
		-- this candidate needs: it learns that sooner than a probe would, so it runs first.
		-- A zero joined into a transfer leaves no pending walk behind, so every batch the plan used is checked.
		local unsnapped = {}
		if planned then
			for _, batch in ipairs({ startBatch, goalBatch }) do
				if batch.job and not batch.job.snapped and not batch.done then
					unsnapped[batch] = true
				end
			end
		end
		if next(unsnapped) then
			active(startBatch, unsnapped[startBatch] or false)
			active(goalBatch, unsnapped[goalBatch] or false)
			return
		end
		-- Short A* cost probes let easy routes prove themselves before expanding a wide frontier. Bound
		-- their total work, then let shared Dijkstras settle harder alternatives. Finish an active probe:
		-- abandoning it near completion would make the batch repeat its work.
		if probeCPU < PROBE_BUDGET then
			local probes = {}
			for _, leg in ipairs(planned and planned.pendingWalks or {}) do
				local batch = leg.from.kind == "start" and startBatch or goalBatch
				local target = batch.reverse and leg.from or leg.to
				for i, point in ipairs(batch.targets) do
					if
						SamePlace(point, target)
						and batch.costs[i] == nil
						and (not batch.probes or batch.probes[i] == nil)
					then
						probes[#probes + 1] = { batch = batch, index = i, leg = leg }
						break
					end
				end
			end
			if #probes > 0 then
				offerFeasible(feasible, planned)
				if stale() then
					return
				end
				planned.preview, search.candidate = true, planned
				active(startBatch, false)
				active(goalBatch, false)
				local left = #probes
				for _, probe in ipairs(probes) do
					local leg, batch = probe.leg, probe.batch
					local probeJob = ns.Path.FindCost(leg.from.map, leg.from, leg.to, function(cost, reason, finished)
						probeJobs[finished] = nil
						if version ~= pathVersion then
							return
						end
						if cost or reason == "unreachable" or reason == "offmesh" or reason == "outside" then
							batch.probes = batch.probes or {}
							batch.probes[probe.index] = cost or false
						end
						probeCPU = probeCPU + finished.cpu
						left = left - 1
						if left == 0 then
							request(true)
						end
					end, waterMode, hazards)
					probeJobs[probeJob] = true
				end
				return
			end
		end
		if previewed then
			planned = best()
			if stale() then
				return
			end
		end
		local needStart = planned and planned.needsStart and ns.Path.HasData(here.map)
		local needGoal = planned and planned.needsGoal and ns.Path.HasData(goal.map)
		-- Missing-map estimates remain the existing terminal fallback, never an endless search.
		needStart = needStart and not startBatch.done
		-- A goal no place walks to waits on the walk from here before it moves (Ground).
		needStart = (needStart or goalBatch.done and goalBatch.job.moved and Direct() == nil) and not startBatch.done
		-- A goal batch whose frontier is spent is finishing, and one that no place walked to still moves its goal to the
		-- ground they reach (Ground): it runs to its end rather than leaving the goal where nobody can stand.
		needGoal = (needGoal or goalBatch.job.radius == math.huge) and not goalBatch.done
		-- Nor does here (Direct): no route ends at this goal, so the walks from here wait for the ground it moves to.
		-- A goal with no ground to move to, or moved once already (Ground), keeps them: they still answer the search.
		local moves = goalBatch.job.moved and not (grounded and SamePlace(goal, grounded.to))
		if goalBatch.job.into and moves and Direct() == false then
			needStart = false
		end
		active(startBatch, needStart)
		active(goalBatch, needGoal)
		-- A bind point's walks still being searched, for a teleport that could be faster: settle when they end.
		local landing = not needStart
			and not needGoal
			and Walks.LandingPending(
				teleports,
				waterMode,
				landed,
				select(2, ns.UsableTeleports(ns.NowMs())),
				planned and planned.arrive or math.huge,
				lastRunSpeed
			)
		if not needStart and not needGoal and not landing then
			ns.Path.Checkpoint()
			if stale() then
				return
			end
			-- A walk callback can run at the checkpoint. Keep the proof pending until Render owns its result.
			pendingCosts, settleRound = 0, settleRound + 1
			Render(planned, forced)
		else
			offerFeasible(feasible, planned)
			if stale() then
				return
			end
			if planned and planned ~= followed then
				planned.preview = true
			end
			search.candidate = planned
		end
	end
	-- The search's own path job: the preview a first search shows, then consider again for as long as new costs
	-- arrived while it ran. Callbacks only ask for it, so none of them plans in its own frame.
	local considering, again, againFinal = nil, false, false
	local function work(job)
		if wantPreview then
			wantPreview = false
			preview = Plan(nil, nil, job)
			if stale() then
				return
			end
			if preview then
				preview.preview, search.candidate = true, preview
				-- A first search draws this estimate at once, before it has a measured route to follow.
				-- An estimate whose zero walks left no legs would read as arrival, so it waits for the proof.
				if not followed and search.initial and not search.rough and #preview.legs > 0 then
					search.rough = true
					publish(Rough(preview), "rough")
					if stale() then
						return
					end
				end
			end
		end
		while again do
			local final = againFinal
			again, againFinal = false, false
			consider(final, job)
		end
		considering = nil
	end
	local function schedule()
		if not considering and not stale() then
			considering = ns.Path.Run(work)
			probeJobs[considering] = true
		end
	end
	request = function(final)
		again, againFinal = true, againFinal or final == true
		schedule()
	end
	-- A finished batch's answer: its costs, why it found none, and false for each target it never reached.
	local function settle(batch, costs, reason, job)
		batch.costs, batch.reason, batch.job = costs or {}, reason, job
		if job.done then
			batch.done = true
			for i = 1, #batch.targets do
				if batch.costs[i] == nil then
					batch.costs[i] = false
				end
			end
		end
	end
	-- No place on the goal's landmass walks to it: a plateau ringed by faces past the player's slope and step limits
	-- (#1113). The route ends instead at the nearest ground those places reach, the closest a player can stand, unless
	-- the walk from here reaches the goal itself (a player already on the plateau), so the move waits until that walk
	-- is ruled out. The search starts again toward that ground.
	local function Ground()
		local moved = goalBatch.done and goalBatch.job and goalBatch.job.moved
		-- A goal moved once is not moved again: it has no route, and moving it onto itself restarted the search forever
		-- (#1141).
		if not moved or Direct() ~= false or (grounded and SamePlace(goal, grounded.to)) then
			return false
		end
		local point = {}
		for key, value in pairs(goal) do
			point[key] = value
		end
		point.x, point.y, point.z = moved.x, moved.y, moved.z
		grounded, goal = { from = goal, to = point }, point
		-- The rough route already drawn stays until the proved route replaces it, so a journey draws one estimate.
		local drew = search and search.rough
		RefreshCosts(true, true, search and search.replace)
		if search then
			search.rough = drew
		end
		return true
	end
	local function attach(batch)
		local function update(costs, reason, job)
			if version ~= pathVersion or not goal then
				return
			end
			settle(batch, costs, reason, job)
			if Ground() then
				return
			end
			request(batch.done)
		end
		local job = batch.job
		if job then
			job.callback, job.progress = update, update
			-- Reused from the search this one replaces, which paused it (CancelPaths). One that finished meanwhile
			-- lost its queued answer to the pause, so it is taken from the job; one never yet valid runs again, or
			-- nothing would ever answer. A valid one waits for consider, which resumes it only if it is needed.
			if job.done and not batch.done then
				settle(batch, job.costs, job.reason, job)
			elseif not job.valid and not batch.done then
				ns.Path.Resume(job)
			end
		else
			batch.job = ns.Path.FindMany(
				batch.point.map,
				batch.point,
				batch.targets,
				update,
				waterMode,
				batch.reverse,
				update,
				hazards
			)
		end
	end
	attach(startBatch)
	attach(goalBatch)
	-- Both batches may have finished while no search listened (a replan drops queued answers): attach took their
	-- results from the jobs, so the move a callback would have made is made here.
	if Ground() then
		return
	end
	Walks.LandingPending(teleports, waterMode, function()
		request(true)
	end)
	-- Existing settled costs can prove a repeated journey without advancing either frontier.
	if (startBatch.job.valid or startBatch.done) and (goalBatch.job.valid or goalBatch.done) then
		request(true)
	elseif wantPreview then
		schedule()
	end
end

-- Stops the work in flight and forgets the search; the walks, costs and batches stay for the journey to resume with.
function Search.Cancel()
	CancelPaths()
	search = nil
end

-- A goal is about to start: stops the work in flight and forgets the measured costs, keeping the batches a repeated
-- journey may reuse. Walks drawn for the same goal in the same water mode are kept too, and only then is the journey
-- a repeat whose route and progress carry on.
---@param same boolean? the new goal is the place the last one was
---@param policy? SPFRoutePolicy
---@return boolean? repeated
function Search.Clear(same, policy)
	policy = policy or "normal"
	local repeated = same and policy == routePolicy and (ns.JourneyWaterWalking()) == waterMode
	CancelPaths()
	costsWaiting = nil
	settleRound, costError = 0, nil
	startCosts, goalCosts, startAt = {}, {}, nil
	if not repeated then
		Walks.Clear()
	end
	return repeated
end

-- The journey is over: nothing of its search is kept.
function Search.Reset()
	Search.Clear(false)
	for _, batch in pairs({ start = startBatch, goal = goalBatch }) do
		if batch.job then
			ns.Path.Cancel(batch.job)
		end
	end
	startBatch, goalBatch = nil, nil
	search = nil
	-- A goal moved for this journey is not moved for the next: the player may stand on it by then.
	grounded = nil
	-- plannerCache is kept: Planner.Plan rebuilds the graph itself whenever an input it was built from differs (its
	-- CACHE_KEYS, waterWalking and hazards among them) and rewrites the two endpoints for the new journey, so a
	-- journey started after this one plans against a warm graph instead of paying the whole build on its first
	-- click. The decoded walking grids are still released here.
	ns.Path.ClearCaches()
	goal, followed = nil, nil
end

-- The hazards a journey keeps away from, exempting where it started (the first readable position), its goal, the
-- zone the character is standing in now and the zone the walk being followed starts in; walks searched with others
-- no longer apply. A boat can leave the character in a zone the origin never named, and the walk after it starts
-- there: neither may be charged for the character to escape (#895).
local origin, hereZone, landingZone
local avoided
local function WalkLanding()
	local leg = followed and progress and followed.legs[progress.index]
	if leg and leg.mode ~= "walk" then
		local nextLeg = followed.legs[progress.index + 1]
		if nextLeg and nextLeg.mode == "walk" then
			return nextLeg.from
		end
	end
end
local function Avoid()
	local here = Here()
	avoided = here ~= nil
	origin = origin or here
	hereZone = here and ns.Hazards.ZoneAt(here.map, here.x, here.y)
	local landing = WalkLanding()
	landingZone = landing and ns.Hazards.ZoneAt(landing.map, landing.x, landing.y)
	local profile = origin and goal and ns.Hazards.Profile(origin, goal, here, landing) or nil
	if (profile and profile.key) ~= (hazards and hazards.key) then
		hazards = profile
		Walks.SetHazards(profile)
		startCosts, goalCosts = {}, {}
	end
end

-- Searches for the fastest way to point from where you stand. route is what Journey follows meanwhile (a repeated
-- journey's, or one whose destination just moved) and state its progress along it. listener hears every change to what
-- Journey should follow, possibly before Start returns. A replacing search is one whose route leads to a place the
-- destination no longer is, so its first plan takes over whatever it costs.
---@param point SPFPoint
---@param route SPFPlan?
---@param state {index: integer, departed?: boolean}
---@param listener fun(route: SPFPlan?, news: SPFSearchNews)
---@param replace? boolean the route being replaced leads somewhere else, so the next plan takes over
---@param policy? SPFRoutePolicy
function Search.Start(point, route, state, listener, replace, policy)
	policy = policy or "normal"
	if policy ~= routePolicy then
		Search.Clear(false, policy)
		route = nil
	end
	routePolicy = policy
	if grounded and SamePlace(point, grounded.from) then
		point = grounded.to
	end
	goal, followed, progress, publish = point, route, state, listener
	search = nil
	waterMode = (ns.JourneyWaterWalking())
	origin = nil
	-- Timed only where the path jobs run: specs may stand in a bare Path.
	local work = ns.Path.work
	if not replace and work then
		Search.timing = { at = ns.Path.clock(), frames = work.frames, cpu = work.cpu }
	end
	Avoid()
	RefreshCosts(true, false, replace == true)
end

-- Once per driver frame with a readable position: restarts a search whose inputs changed or whose callbacks waited
-- for a position.
---@param changed? boolean the travel policy changed since the last frame
function Search.Poll(changed)
	local x, y, _, map = ns.JourneyPosition()
	local zone = x and y and map and ns.Hazards.ZoneAt(map, x, y)
	local landing = WalkLanding()
	local landZone = landing and ns.Hazards.ZoneAt(landing.map, landing.x, landing.y)
	if changed or zone ~= hereZone or landZone ~= landingZone then
		-- A setting, your level or a zone you stand in or land in changed what to avoid, from where you stand now.
		Avoid()
		RefreshCosts(true, true)
	end
	-- No batch has started, or a callback waited for a readable position.
	local stale = not startAt or costsWaiting
	costsWaiting = nil
	-- A journey started where no position could be read takes its hazards from the first one that can.
	if not avoided then
		Avoid()
	end
	-- Search callbacks may finish while position is unavailable; resume from readable endpoints.
	if stale then
		RefreshCosts(true, true)
	end
end

-- The timed replan, also due when the ride or run speed changes: searches again where the old costs no longer apply,
-- and otherwise plans in the frame with the costs it has. A tick with nothing new retimes the drawn route instead:
-- only a departure it waits for moving to its next visit gives a plan a different answer.
---@param riding number? the route you are aboard
---@param flying boolean? on a taxi
---@param changedRide boolean either changed since the last frame
---@param changedSpeed boolean the run speed changed since the last plan
function Search.Replan(riding, flying, changedRide, changedSpeed)
	local mode = ns.JourneyWaterWalking()
	local options = Context.Options(Here() or goal, goal, routePolicy)
	local partyPortals = options.partyPortals
	if mode ~= waterMode then
		-- Walks searched in another water mode no longer apply.
		waterMode = mode
		Walks.Clear()
		startCosts, goalCosts = {}, {}
		RefreshCosts(true, false)
	elseif
		goalBatch ~= nil and (goalBatch.teleports ~= options.teleports or goalBatch.partyPortals ~= partyPortals)
	then
		-- A new bind point, teleport or party mage: measure the walks on from where it lands.
		RefreshCosts(true, false)
	elseif pendingCosts == 0 and Walks.Pending() == 0 then
		local here = Here()
		local leg = followed and followed.legs[progress.index]
		local off = here and leg and leg.mode == "walk" and leg.measured and not ns.OnWalk(leg.walkPoints, here)
		local moved = here and startAt and not SamePlace(startAt, here)
		local retry = here
			and startAt
			and moved
			and (not followed or (leg and leg.walkError) or here.map ~= startAt.map)
		-- A teleport is cast where you stand, so its time holds wherever you go, while the walks searched from where
		-- you stood stop describing here: walked on before casting, they are searched again. An unboarded boat
		-- likewise needs the approach searched from here when the player leaves its dock.
		local walkedOn = moved and leg and (leg.mode == "teleport" or leg.mode == "boat" and not progress.departed)
		-- Exact endpoint costs do not expire at an unchanged position and floor.
		if
			not flying
			and not riding
			and (off or retry or walkedOn or moved and GetTime() - refreshedAt >= REFRESH_EVERY)
		then
			RefreshCosts(false, off or retry)
		elseif changedRide or changedSpeed or not RetimeKept() then
			-- Planned in a path job of its own; a newer tick's replan replaces one still running.
			if replanning then
				ns.Path.Cancel(replanning)
			end
			local version = pathVersion
			-- Held until it renders, so a newer tick cancels it at any pause.
			local this
			this = ns.Path.Run(function(job)
				local planned = Plan(nil, nil, job)
				if version ~= pathVersion or not goal then
					return
				end
				here = Here()
				if
					planned
					and (
						(planned.needsStart and here and ns.Path.HasData(here.map))
						or (planned.needsGoal and ns.Path.HasData(goal.map))
					)
				then
					-- A timed replan can expose an alternative left bounded by the previous proof.
					-- Resume its costs before letting it replace the route with settled geometry.
					RefreshCosts(false, changedRide)
				else
					ns.Path.Checkpoint()
					if version == pathVersion and goal then
						Render(planned, changedRide)
					end
				end
			end, function()
				if replanning == this then
					replanning = nil
				end
			end)
			replanning = this
			probeJobs[this] = true
		end
	end
end

-- The run speed the last plan assumed.
---@return number
function Search.Speed()
	return lastRunSpeed
end

-- A timed replan is running in a path job of its own, so the plan on show is about to be replaced.
---@return boolean
function Search.Replanning()
	return replanning ~= nil
end

-- loading: a first search is still running, with at most a measured route to follow.
---@return number pending, number round, string? error, boolean loading
function Search.Status()
	return pendingCosts + Walks.Pending(), settleRound, costError, search ~= nil and search.initial
end

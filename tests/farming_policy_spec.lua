-- The internal walking submission through the real journey, planner and estimate producers.
local checks = 0
local function check(value, label)
	checks = checks + 1
	assert(value, label)
end
local function harness()
	local d = assert(loadfile("tests/journey_driver.lua"))()
	d.load("UI/Looks.lua")
	d.load("Core/APIInput.lua")
	d.load("Core/API.lua")
	d.load("Journey/Itinerary.lua")
	return d, d.ns, d.env.ShortestPathForever.API
end
local function point(x)
	return { map = 1, x = x, y = 0 }
end
local function stop(x)
	return { map = 1, x = 0.5, y = 0.5 - x / 50000 }
end
local function allWalk(plan)
	if not plan or #plan.legs == 0 then
		return false
	end
	for _, leg in ipairs(plan.legs) do
		if leg.mode ~= "walk" then
			return false
		end
	end
	return true
end
local function portal(ns)
	ns.Portals = { { name = "Passage", kind = "portal", from = point(0), to = point(4990), seconds = 1 } }
end
-- Each transport is faster than the direct walk; the SAME retained topology must switch both ways.
for _, mode in ipairs({ "portal", "flight", "boat", "lift", "tram", "teleport", "party", "ride" }) do
	local _, ns, api = harness()
	local version, minor = api.version, api.minor
	local from, to = point(0), point(5000)
	if mode == "portal" then
		portal(ns)
	elseif mode == "flight" then
		ns.TaxiNodes = { point(0), point(4990) }
		ns.TaxiPaths = { { from = 1, to = 2, seconds = 1 } }
		ns.known = { true, true }
	elseif mode == "teleport" or mode == "party" then
		local places = { { map = 1, x = 4990, y = 0, spell = 123, cast = 1000 } }
		if mode == "party" then
			ns.PartyPortalPlaces = function()
				return places
			end
		else
			ns.teleports, ns.teleportReady = places, { 0 }
		end
	else
		ns.Docks = { point(0), point(4990) }
		ns.Routes = {
			[7] = {
				kind = mode == "ride" and "boat" or mode,
				period = 60000,
				stops = { { dock = 1, arrive = 0, depart = 1000 }, { dock = 2, arrive = 2000, depart = 3000 } },
			},
		}
		if mode == "ride" then
			ns.CurrentRide = function()
				return 7
			end
			ns.Timetable.NextStop = function()
				return 2, 1000
			end
		end
	end
	local cache = {}
	local function plan(policy)
		local o = ns.PlanContext.Options(from, to, policy)
		o.cache, o.ride = cache, ns.PlanContext.Ride(o)
		return ns.Planner.Plan(o), o
	end
	local normal = plan("normal")
	check(normal and not allWalk(normal), mode .. " is used in normal mode")
	local walking, o = plan("walking")
	check(allWalk(walking), mode .. " is excluded from walking mode")
	check(walking.arrive > normal.arrive, mode .. " restriction is effective even when transit is faster")
	local _, again = plan("walking")
	for _, key in ipairs({
		"taxiKnown",
		"anchors",
		"docks",
		"routes",
		"taxiNodes",
		"taxiPaths",
		"taxiTimes",
		"portals",
		"teleports",
		"teleportReady",
		"teleportState",
		"partyPortals",
	}) do
		check(next(o[key]) == nil and o[key] == again[key], key .. " is stably empty")
	end
	check(o.ride == nil, "already aboard cannot leak into walking")
	check(
		#ns.PlanContext.Places(ns.teleports, ns.PartyPortalPlaces and ns.PartyPortalPlaces(from), "walking") == 0,
		"transport endpoint places are excluded"
	)
	check(not allWalk(plan("normal")), mode .. " normal topology restored")
	check(
		ns.db.journey == true and o.baked == ns.Walks and o.landmasses == ns.Landmasses,
		"walking preserves terrain and preferences"
	)
	check(api.version == version and api.minor == minor, "internal policy preserves the public API version")
end
-- Route replacement, both same-owner resubmission and different-owner same-goal adoption.
do
	local d, ns, api = harness()
	portal(ns)
	local stops = { stop(5000) }
	check(api.NavigateRoute("public", stops), "normal submission")
	d.path.settle()
	check(not allWalk(d.shown()), "normal journey uses transit")
	local old = d.shown()
	check(ns.NavigateFarmingRoute("farm", stops), "walking submission")
	d.path.settle()
	check(
		ns.JourneyRoutePolicy() == "walking" and allWalk(d.shown()) and d.shown() ~= old,
		"different-owner adoption cannot keep transit"
	)
	check(api.Ended("public") == "replaced", "old owner replaced")
	check(api.Pause("farm") and api.Resume("farm"), "pause and resume accepted")
	check(ns.JourneyRoutePolicy() == "walking", "pause and resume retain walking")
	check(not ns.NavigateFarmingRoute("bad", { stop(100), { map = 0 } }), "invalid route refused")
	check(ns.JourneyOwner() == "farm" and ns.JourneyRoutePolicy() == "walking", "validation precedes replacement")
	check(api.NavigateRoute("farm", stops), "same-owner switch to normal")
	d.path.settle()
	check(ns.JourneyRoutePolicy() == "normal" and not allWalk(d.shown()), "resubmit cannot retain walking plan")
	check(ns.NavigateFarmingRoute("farm", stops), "same-owner switch back to walking")
	d.path.settle()
	check(allWalk(d.shown()), "same-owner walking recomputed")
	check(api.NavigateRoute("other", stops), "normal adoption after walking")
	d.path.settle()
	check(ns.JourneyRoutePolicy() == "normal" and not allWalk(d.shown()), "normal adoption cannot retain walking")
	check(ns.NavigateFarmingRoute("farm", stops), "walking before user replacement")
	d.path.settle()
	check(ns.StartJourney(point(5000)), "user chooses same destination")
	d.path.settle()
	check(ns.JourneyRoutePolicy() == "normal" and not allWalk(d.shown()), "user replacement defaults normal")
	check(ns.JourneyOwner() == nil and api.Ended("farm") == "replaced", "user replacement drops owner")
	check(ns.NavigateFarmingRoute("farm", stops) and api.Cancel("farm"), "owner cancels")
	check(ns.JourneyRoutePolicy() == "normal", "cancel resets policy")
end
-- Internal hop estimates cannot poison the public normal estimate cache.
do
	local _, ns, api = harness()
	portal(ns)
	local normal = assert(api.Estimate(1, 0.5, 0.5, 1, 0.5, 0.4))
	local legs = ns.EstimateLegs(point(0), point(5000), "walking")
	check(allWalk({ legs = legs }), "internal estimate walks")
	check(api.Estimate(1, 0.5, 0.5, 1, 0.5, 0.4) == normal, "public estimate remains normal after walking hop")
	local normalLegs = ns.EstimateLegs(point(0), point(5000), "normal")
	check(not allWalk({ legs = normalLegs }), "normal hop topology restored after walking estimate")
end
-- Multi-stop advancement, retarget, corpse suspension and queued replacement.
do
	local d, ns, api = harness()
	portal(ns)
	check(ns.NavigateFarmingRoute("farm", { stop(1000), stop(5000) }), "multi-stop walking")
	d.path.settle()
	d.move(point(1000))
	d.update(1)
	check(api.CurrentStop("farm") == 2 and ns.JourneyRoutePolicy() == "walking", "next stop retains policy")
	check(allWalk(d.shown()), "next stop still walks")
	check(ns.NavigateFarmingRoute("farm", { stop(1000), stop(4500) }), "retarget current stop")
	d.path.settle()
	check(ns.JourneyRoutePolicy() == "walking" and allWalk(d.shown()), "retarget retains walking")
	local corpse = true
	ns.Corpse = {
		Active = function()
			return corpse
		end,
		Point = function()
			return point(2000)
		end,
	}
	ns.SuspendJourney()
	check(ns.JourneyRoutePolicy() == "normal", "corpse guidance has normal effective policy")
	check(not api.Resume("farm"), "public resume refuses corpse guidance")
	corpse = false
	ns.ResumeJourney()
	d.path.settle()
	check(ns.JourneyRoutePolicy() == "walking" and allWalk(d.shown()), "resurrection restores walking")
	corpse = true
	ns.SuspendJourney()
	check(api.NavigateRoute("public", { stop(4500) }), "normal same-goal submission queues behind corpse")
	corpse = false
	ns.ResumeJourney()
	d.path.settle()
	check(ns.JourneyRoutePolicy() == "normal" and not allWalk(d.shown()), "queued normal replacement restores transit")
	ns.ClearJourney()
	check(ns.JourneyRoutePolicy() == "normal", "clear resets policy")
end
-- Policy changes invalidate endpoint callbacks and itinerary hops, including identical coordinates.
do
	local d, ns, api = harness()
	portal(ns)
	local queue = {}
	ns.RefreshJourneyPreview = function() end
	ns.Path.after = function(fn)
		queue[#queue + 1] = fn
	end
	local function frame()
		local due = queue
		queue = {}
		for _, fn in ipairs(due) do
			fn()
		end
	end
	d.path.auto = false
	check(api.NavigateRoute("normal", { stop(3000), stop(5000) }), "pending normal route")
	local old = d.path.waiting(d.path.batches)
	check(ns.NavigateFarmingRoute("farm", { stop(3000), stop(5000) }), "replace pending search")
	for _, batch in ipairs(old) do
		d.path.costs(batch, 0)
	end
	-- At most the new search's own walking estimate is drawn.
	local drawn = d.shown()
	check(drawn == nil or drawn.rough and allWalk(drawn), "late endpoint callbacks cannot publish old transit")
	for _, batch in ipairs(d.path.waiting(d.path.batches)) do
		check(#batch.targets <= 1, "walking endpoint searches contain no transport places")
	end
	d.path.auto = true
	d.path.settle()
	check(allWalk(d.shown()), "new policy settles walking")
	local before = #d.path.batches
	ns.teleports = { { map = 1, x = 2990, y = 0, spell = 123, cast = 1 } }
	ns.teleportReady = { 0 }
	ns.JourneySearch.Replan(nil, false, false, false)
	check(#d.path.batches == before, "excluded live teleport changes do not churn walking endpoints")
	ns.Portals = { { name = "Hop passage", kind = "portal", from = point(3000), to = point(4990), seconds = 1 } }
	ns.JourneyStatus = function()
		return false
	end
	ns.JourneyReplanning = function()
		return false
	end
	check(api.NavigateRoute("normal", { stop(3000), stop(5000) }), "normal itinerary")
	d.path.settle()
	frame()
	-- The hop plans in a path job on a later frame, then publishes on the next.
	d.path.runAll()
	frame()
	local preview = ns.JourneyPreview()
	local transit = false
	for _, path in ipairs(preview) do
		transit = transit or path.mode ~= "walk"
	end
	check(transit, "normal hop uses faster transport")
	check(ns.NavigateFarmingRoute("farm", { stop(3000), stop(5000) }), "walking same-geometry itinerary")
	d.path.settle()
	frame()
	d.path.runAll()
	frame()
	preview = ns.JourneyPreview()
	check(#preview > 0, "walking hop exists")
	for _, path in ipairs(preview) do
		check(path.mode == "walk", "hop transit invalidated")
	end
	frame() -- Flushes a due redraw before the walking geometry.
	frame() -- Starts the asynchronous walking geometry for the hop.
	local late = d.path.finds[#d.path.finds]
	check(late ~= nil and not late.done, "hop geometry queued")
	check(api.NavigateRoute("normal", { stop(3000), stop(5000) }), "normal itinerary restored")
	check(late.cancelled, "old hop search cancelled on policy change")
	d.path.settle()
	frame()
	frame()
	d.path.runAll()
	frame()
	local restored = ns.JourneyPreview()[1]
	d.path.finish(late, { point(3000), point(5000) }, 2000)
	check(ns.JourneyPreview()[1] == restored, "late walking hop cannot replace normal hop")
end
-- A walking route submitted while dead must discard its normal-policy hop on resurrection.
do
	local d, ns = harness()
	ns.Portals = { { name = "Hop passage", kind = "portal", from = point(3000), to = point(4990), seconds = 1 } }
	local queue = {}
	ns.Path.after = function(fn)
		queue[#queue + 1] = fn
	end
	ns.RefreshJourneyPreview = function() end
	ns.JourneyStatus = function()
		return false
	end
	ns.JourneyReplanning = function()
		return false
	end
	local function frame()
		local due = queue
		queue = {}
		for _, fn in ipairs(due) do
			fn()
		end
	end
	local corpse = true
	ns.Corpse = {
		Active = function()
			return corpse
		end,
		Point = function()
			return point(2000)
		end,
	}
	check(ns.NavigateFarmingRoute("farm", { stop(3000), stop(5000) }), "walking route queued behind corpse")
	frame()
	d.path.runAll()
	frame()
	local transit = false
	for _, path in ipairs(ns.JourneyPreview()) do
		transit = transit or path.mode ~= "walk"
	end
	check(transit and ns.JourneyRoutePolicy() == "normal", "queued hop uses effective corpse policy")
	corpse = false
	ns.ResumeJourney()
	d.path.settle()
	frame()
	frame()
	check(ns.JourneyRoutePolicy() == "walking", "queued route restores walking on resurrection")
	for _, path in ipairs(ns.JourneyPreview()) do
		check(path.mode == "walk", "queued normal hop invalidated on resurrection")
	end
end
-- Missing terrain and actual path errors remain explicit; policy alone never diagnoses reachability.
for _, reason in ipairs({ "nodata", "outside", "unreachable", "error" }) do
	local d, ns, api = harness()
	d.path.auto = false
	if reason == "nodata" then
		d.path.data = false
	end
	check(ns.NavigateFarmingRoute("farm", { stop(5000) }), "submission accepted before terrain answer")
	for _, batch in ipairs(d.path.waiting(d.path.batches)) do
		d.path.costs(batch, false, reason)
	end
	for _, job in ipairs(d.path.waiting(d.path.finds)) do
		d.path.finish(job, nil, reason)
	end
	local _, _, failure = ns.JourneySearch.Status()
	if reason == "nodata" then
		local plan = d.shown()
		check(
			failure == nil and plan and plan.legs[1].walkError == "nodata",
			"missing data remains unavailable terrain"
		)
	else
		check(failure == reason, "actual endpoint failure retained: " .. reason)
	end
	check(api.CurrentStop("farm") == 1 and api.Ended("farm") == nil, "failure never consumes a stop")
end
print("farming_policy_spec: " .. checks .. " checks passed")

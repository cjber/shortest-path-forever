local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
	"Data/TownAreas.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
}) do
	driver.load(file)
end
local throwInPath
local start = ns.PathSearch.start
ns.PathSearch.start = function(job)
	if throwInPath and job.targets then
		error("injected path throw")
	end
	return start(job)
end
driver.load("Routing/PathJobs.lua")
assert(loadfile("tools/load_nav.lua"))(0)
ns.faction, ns.level = "Alliance", 40

local nextFrame
ns.Path.after = function(fn, seconds)
	if not seconds then
		nextFrame = fn
	end
end
-- Keep driving after a reported Lua error, as the client does.
driver.env.geterrorhandler = function()
	return function() end
end

local from = { map = 0, x = -8833, y = 628, z = 94 }
local to = { map = 0, x = -9449, y = 64, z = 56 }
local function drain()
	for _ = 1, 2000 do
		if not nextFrame then
			return
		end
		local step = nextFrame
		nextFrame = nil
		step()
	end
	error("path queue did not drain")
end

local function checkFailure(label)
	driver.begin(from, to)
	drain()
	local pending, _, reason, loading = ns.JourneySearch.Status()
	assert(pending == 0 and not loading, "thrown " .. label .. " left the journey pending or loading")
	local _, rows = ns.JourneyInfo(tostring)
	assert(reason == "error" and rows[1].text == ns.WalkFailure.error, "journey did not publish a visible failure")
	for _, caught in ipairs(ns.core.CaughtErrors()) do
		if caught.message:find("injected " .. label .. " throw", 1, true) then
			return
		end
	end
	error(label .. " throw was not journaled")
end

local plan = ns.Planner.Plan
ns.Planner.Plan = function()
	error("injected planner throw")
end
checkFailure("planner")
ns.Planner.Plan = plan

throwInPath = true
checkFailure("path")
throwInPath = false

local find = ns.Path.Find
ns.Path.Find = function(map, a, b, _, ...)
	return find(map, a, b, function()
		error("injected walk callback throw")
	end, ...)
end
checkFailure("walk callback")
ns.Path.Find = find

local findMany = ns.Path.FindMany
ns.Path.FindMany = function()
	error("injected setup throw")
end
checkFailure("setup")
ns.Path.FindMany = findMany

driver.begin(from, to)
drain()
local _, _, route, _, stillLoading = ns.JourneyInfo(tostring)
assert(route and not stillLoading, "the next journey did not settle normally")

-- A failed replacement keeps the journey destination and lets a later input change retry it.
local retry = assert(loadfile("tests/journey_driver.lua"))()
local journey = retry.ns
local dock, destination = { map = 1, x = 0, y = 0 }, { map = 2, x = 0, y = 0 }
journey.Docks = { dock, destination }
journey.Routes = {
	[9] = {
		kind = "boat",
		period = 100000,
		stops = { { dock = 1, arrive = 0, depart = 20000 }, { dock = 2, arrive = 50000, depart = 70000 } },
	},
}
retry.env.geterrorhandler = driver.env.geterrorhandler
journey.zoneAt = function(_, x)
	return x < 64 and 1 or 2
end
retry.move(dock)
journey.StartJourney(destination)
retry.path.settle()
local crossing = assert(journey.JourneyPlan())
local crossingOptions = journey.PlanContext.Options
journey.AvoidJourneyTransport(crossing.legs[1])
local attempts = 0
journey.PlanContext.Options = function()
	attempts = attempts + 1
	error("injected avoid throw")
end
retry.update(0.1)
local _, failedRows = journey.JourneyInfo()
assert(failedRows[1].text == journey.WalkFailure.error, "avoid masked the thrown search error")
assert(journey.JourneyGoal() == destination, "the failed search keeps the journey destination")
local failedAttempts = attempts
retry.update(6)
assert(attempts == failedAttempts, "a failed search must stay stopped without changed inputs")

journey.PlanContext.Options = crossingOptions
journey.TravelPolicyChanged()
retry.update(0.1)
local _, avoidRows = journey.JourneyInfo()
assert(avoidRows[1].undoAvoid, "policy change retries the same journey with its avoid still applied")

journey.PlanContext.Options = function()
	error("injected second avoid throw")
end
journey.TravelPolicyChanged()
retry.update(0.1)
journey.PlanContext.Options = crossingOptions
journey.UndoAvoidedTransport(avoidRows[1].undoAvoid)
retry.update(0.1)
assert(journey.JourneyPlan().legs[1].route == 9, "Undo restarts a failed search for the same destination")
journey.PlanContext.Options = function()
	error("injected zone recovery throw")
end
journey.TravelPolicyChanged()
retry.update(0.1)
journey.PlanContext.Options = crossingOptions
retry.move({ map = 1, x = 100, y = 0 })
retry.update(0.1)
assert(journey.JourneyPlan(), "crossing into another zone restarts a failed search")
print("search throw: failure row, policy retry, Undo and zone recovery passed")

-- Prototype bench, not a spec. Run from the repository root:
--   luajit -joff tests/follow_bench.lua
--
-- What it measures: the cost of ONE follow refresh, i.e. asking the journey to plan to a
-- party member's newly-read position (Journey/Follow.lua's Refresh -> ns.StartJourney),
-- with the walking search settled the way a spec settles it. A follow refresh can only be
-- as cheap as the journey search it starts, so this is the number a throttle is chosen on:
--   refreshes/second x refresh cost = the share of the frame budget following takes.
--
-- The member is walked along a real road between two shipped taxi nodes, read back at the
-- granularity C_Map.GetPlayerMapPosition actually answers (a 0-1 fraction of a zone map),
-- and refreshed once per position rather than continuously, so no search is left running.
local root = arg[1] or "."

-- A member on foot, in yards per second.
local WALK = 7
-- Intervals a throttled follow target could plausibly use, in seconds.
local THROTTLES = { 0.2, 0.5, 1.0, 2.0 }
-- C_Map.GetPlayerMapPosition answers a fraction of a zone map: this is the step it reports
-- in, so a follow target must live with positions this coarse.
local MAP_STEP = 1 / 5000
local FRAME = 1 / 60
local SESSION = 60
-- Follow refreshes measured per case; each one stands a member at a new point along the road.
local SAMPLES = 10

local function quantise(value)
	return math.floor(value / MAP_STEP + 0.5) * MAP_STEP
end

local function length(from, to)
	return math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
end

local function along(from, to, yards)
	local total = length(from, to)
	local x = from.x + (to.x - from.x) / total * yards
	local y = from.y + (to.y - from.y) / total * yards
	return { map = from.map, x = quantise(x), y = quantise(y) }
end

local function run(case)
	local driver = assert(loadfile("tests/journey_driver.lua"))(root)
	local ns = driver.ns
	for _, file in ipairs({
		"Data/Routes.lua",
		"Data/Transports.lua",
		"Data/Taxi.lua",
		"Data/Portals.lua",
		"Data/Walks.lua",
		"Routing/PathGrid.lua",
		"Routing/Path.lua",
		"Routing/PathJobs.lua",
	}) do
		driver.load(file)
	end
	for _, map in ipairs({ 0, 1, 2991 }) do
		assert(loadfile("tools/load_nav.lua"))(map)
	end
	driver.load("Journey/Follow.lua")
	driver.env.UnitExists = function()
		return true
	end
	driver.env.UnitName = function()
		return "Wife"
	end
	driver.env.UnitIsUnit = function()
		return false
	end
	ns.faction, ns.db.debug = case.faction, true
	ns.Print = function(message)
		error(message)
	end

	-- The client's next-frame scheduling, pumped by this bench's own frame loop.
	local pending = {}
	ns.Path.after = function(fn)
		pending[#pending + 1] = fn
	end
	local jobs = {}
	for _, method in ipairs({ "Find", "FindMany" }) do
		local find = ns.Path[method]
		ns.Path[method] = function(...)
			local job = find(...)
			job.method = method
			jobs[#jobs + 1] = job
			return job
		end
	end
	local plan = ns.Planner.Plan
	local plannerCPU = 0
	ns.Planner.Plan = function(options)
		local started = os.clock()
		local planned = plan(options)
		plannerCPU = plannerCPU + (os.clock() - started) * 1000
		return planned
	end
	local startJourney = ns.StartJourney
	local refreshes = 0
	ns.StartJourney = function(point)
		refreshes = refreshes + 1
		return startJourney(point)
	end

	local function pump()
		local due = pending
		pending = {}
		for _, fn in ipairs(due) do
			fn()
		end
		driver.update(FRAME)
	end

	driver.move(case.player)
	ns.FollowPoint = function()
		return case.member
	end
	driver.begin(case.player, case.member)
	for _ = 1, 900 do
		if driver.shown() then
			break
		end
		pump()
	end
	assert(driver.shown(), "expected the follow journey to plan")

	-- One refresh: the member is somewhere new, and the journey is planned to them.
	local costs = {}
	local worst = 0
	for sample = 1, SAMPLES do
		local member = along(case.member, case.goal, WALK * sample * 3)
		ns.FollowPoint = function()
			return member
		end
		local before = #jobs
		local started = os.clock()
		ns.FollowTick(1)
		-- Settle the search this refresh started, as the game would over the next frames.
		for _ = 1, 900 do
			local shown = driver.shown()
			pump()
			if #jobs > before and shown and not ns.Path.Busy() then
				break
			end
		end
		local spent = (os.clock() - started) * 1000
		costs[#costs + 1] = spent
		if spent > worst then
			worst = spent
		end
	end
	local total = 0
	for _, cost in ipairs(costs) do
		total = total + cost
	end
	local searchCPU = 0
	for _, job in ipairs(jobs) do
		searchCPU = searchCPU + job.cpu
	end
	return {
		refreshes = refreshes,
		plannerCPU = plannerCPU,
		searchCPU = searchCPU,
		mean = total / #costs,
		worst = worst,
		searches = #jobs,
	}
end

local CASES = {
	{
		name = "Astranaar -> member in Ashenvale",
		faction = "Alliance",
		-- Astranaar, Ashenvale (taxi node 28) to Splintertree Post's road (node 61).
		player = { map = 1, x = 2827.34, y = -289.24 },
		member = { map = 1, x = 2500, y = -900 },
		goal = { map = 1, x = 2302.39, y = -2524.55 },
	},
	{
		name = "Auberdine -> member in Ashenvale",
		faction = "Alliance",
		-- Auberdine, Darkshore (taxi node 26) following a member walking in Ashenvale.
		player = { map = 1, x = 6341.38, y = 557.68 },
		member = { map = 1, x = 2827.34, y = -289.24 },
		goal = { map = 1, x = 2302.39, y = -2524.55 },
	},
}

print("case                                    refresh mean   worst  planner  search  searches")
for _, case in ipairs(CASES) do
	local r = run(case)
	print(
		string.format(
			"%-39s %5d %6.2fms %6.2fms %7.1fms %7.1fms %8d",
			case.name,
			r.refreshes,
			r.mean,
			r.worst,
			r.plannerCPU,
			r.searchCPU,
			r.searches
		)
	)
end

print("")
print(string.format("%-39s %8s %12s %12s %10s", "case", "throttle", "refreshes/min", "spent/frame", "% of frame"))
for _, case in ipairs(CASES) do
	local r = run(case)
	for _, throttle in ipairs(THROTTLES) do
		local perSession = SESSION / throttle
		-- One refresh's cost, paid on one frame of the interval it falls in.
		local spent = r.mean
		local share = spent / (1000 / 60) * 100 / (throttle * 60)
		print(string.format("%-39s %7.1fs %12d %11.2fms %9.2f%%", case.name, throttle, perSession, spent, share))
	end
end

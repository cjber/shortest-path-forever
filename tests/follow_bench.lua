-- Prototype bench, not a spec. Run from the repository root:
--   luajit -joff tests/follow_bench.lua
--
-- A follow session, as the game would run it: one 60 Hz frame at a time, the member walking
-- a real road between two shipped flight points, a follow tick every frame, and the replan
-- landing on its own frame (Journey/Follow.lua hands it to the next quiet one).
--
-- For each throttle it reports, over the 60 s session:
--   refreshes  replans a session causes
--   planner    planner CPU all of those spent
--   search     walking-search CPU they spent
--   worst      the worst single frame of the session, against AGENTS.md's 3 ms budget
--   overlap    frames where a replan ran in the same frame as a walking-search slice
--   % frame    planner + search CPU as a share of one 60 Hz frame, averaged
local root = arg[1] or "."

-- A member on foot, in yards per second.
local WALK = 7
-- The intervals a follow target could plausibly use, in seconds.
local THROTTLES = { 0.2, 0.5, 1.0, 2.0 }
-- C_Map.GetPlayerMapPosition answers a fraction of a zone map: this is its step, so a follow
-- target lives with positions this coarse.
local MAP_STEP = 1 / 5000
local FRAME = 1 / 60
local SESSION = 60
local ARRIVE = 40

local function quantise(value)
	return math.floor(value / MAP_STEP + 0.5) * MAP_STEP
end

local function along(from, to, yards)
	local dx, dy = to.x - from.x, to.y - from.y
	local total = math.sqrt(dx * dx + dy * dy)
	local step = math.min(yards, total - ARRIVE)
	return { map = from.map, x = quantise(from.x + dx / total * step), y = quantise(from.y + dy / total * step) }
end

local function run(case, throttle)
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
	ns.Print = function() end

	-- The client's next-frame scheduling, pumped by this bench's frame loop: every frame, the
	-- previous frame's callbacks run before the next tick, as C_Timer.After(0) does.
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
	local plannerCPU, plannerAt = 0, 0
	ns.Planner.Plan = function(options)
		local started = os.clock()
		local planned = plan(options)
		local spent = (os.clock() - started) * 1000
		plannerCPU = plannerCPU + spent
		if spent > plannerAt then
			plannerAt = spent
		end
		return planned
	end
	local startJourney = ns.StartJourney
	local refreshes = 0
	ns.StartJourney = function(point)
		refreshes = refreshes + 1
		return startJourney(point)
	end

	driver.move(case.player)
	local member = case.member
	ns.FollowPoint = function()
		return { map = member.map, x = member.x, y = member.y }
	end

	local function pump()
		local due = pending
		pending = {}
		for _, fn in ipairs(due) do
			fn()
		end
	end

	-- Start the journey the way a follow does, and let its first search settle.
	ns.StartFollowing("party1", throttle)
	for _ = 1, 900 do
		if driver.shown() then
			break
		end
		pump()
		driver.update(FRAME)
	end
	assert(driver.shown(), "expected the follow journey to plan")
	refreshes = 0

	local worst, overlap = 0, 0
	local seconds = 0
	while seconds < SESSION do
		local started = os.clock()
		member = along(case.member, case.goal, WALK * seconds)
		local searching = ns.Path.Busy()
		local before = refreshes
		ns.FollowTick(FRAME)
		pump()
		if refreshes > before and searching then
			overlap = overlap + 1
		end
		driver.update(FRAME)
		seconds = seconds + FRAME
		local cost = (os.clock() - started) * 1000
		if cost > worst then
			worst = cost
		end
	end
	local searchCPU = 0
	for _, job in ipairs(jobs) do
		searchCPU = searchCPU + job.cpu
	end
	local frames = math.floor(SESSION * 60)
	return {
		refreshes = refreshes,
		plannerCPU = plannerCPU,
		plannerAt = plannerAt,
		searchCPU = searchCPU,
		worst = worst,
		overlap = overlap,
		share = (plannerCPU + searchCPU) / frames / (1000 / 60) * 100,
	}
end

local CASES = {
	{
		name = "Astranaar -> Ashenvale road",
		faction = "Alliance",
		-- Astranaar (taxi node 28) following a member walking towards Splintertree (node 61).
		player = { map = 1, x = 2827.34, y = -289.24 },
		member = { map = 1, x = 2700, y = -600 },
		goal = { map = 1, x = 2302.39, y = -2524.55 },
	},
	{
		name = "Auberdine -> Ashenvale road",
		faction = "Alliance",
		-- Auberdine (node 26) following a member already walking in Ashenvale.
		player = { map = 1, x = 6341.38, y = 557.68 },
		member = { map = 1, x = 2827.34, y = -289.24 },
		goal = { map = 1, x = 2302.39, y = -2524.55 },
	},
}

print("case                              throttle refreshes  planner  worst  overlap  % frame")
for _, case in ipairs(CASES) do
	for _, throttle in ipairs(THROTTLES) do
		local r = run(case, throttle)
		print(
			string.format(
				"%-33s %7.1fs %9d %7.1fms %6.2fms %8d %8.2f%%",
				case.name,
				throttle,
				r.refreshes,
				r.plannerCPU,
				r.worst,
				r.overlap,
				r.share
			)
		)
	end
end

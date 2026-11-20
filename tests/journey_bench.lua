-- Real Journey + nav data, one pump per simulated 60 Hz frame. Optional args: a baseline source directory, then
-- "continent" for the continent-wide case alone (kept out of the default set speedpatrol times).
local root = arg[1] or "."
local cases = {
	{ "Auberdine -> Tanaris", 26, 39, "Alliance" },
	{ "Auberdine -> Eastern Plaguelands", 26, 67, "Alliance" },
	{ "Crossroads -> Thunder Bluff", 25, 22, "Horde" },
	{ "Ironforge -> Menethil", 6, 7, "Alliance" },
}
if arg[2] == "continent" then
	-- A goal search over most of Kalimdor: the Auberdine boat stays a contender until about 13.5k yards (#1074).
	cases = {
		{
			"Stormwind -> Feralas",
			{ map = 0, x = -8849, y = 647.9, z = 98 },
			{ map = 1, x = -4450, y = 1350, z = 0 },
			"Alliance",
		},
	}
end
for _, case in ipairs(cases) do
	local driver = assert(loadfile("tests/journey_driver.lua"))(root)
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
		"Routing/PathJobs.lua",
	}) do
		driver.load(file)
	end
	for _, map in ipairs({ 0, 1, 2991 }) do
		assert(loadfile("tools/load_nav.lua"))(map)
	end
	local fromName, toName = case[1]:match("^(.-) %-> (.+)$")
	local from, to = case[2], case[3]
	if type(from) == "number" then
		from, to = ns.TaxiNodes[from], ns.TaxiNodes[to]
		assert(from.name:find(fromName, 1, true), "wrong benchmark origin")
		assert(to.name:find(toName, 1, true), "wrong benchmark destination")
	end
	ns.faction, ns.db.debug = case[4], true
	ns.Print = function(message)
		error(message)
	end
	local jobs, nextFrame, rounds, resets, plannerCPU = {}, nil, 0, 0, 0
	local frames, usable, worst = 0, nil, 0
	local drawn = {}
	local draw = ns.SetJourneyRoute
	ns.SetJourneyRoute = function(g, r)
		local first = r and r.legs[1]
		if usable == nil and first and (first.mode ~= "walk" or first.measured) then
			usable = frames
		end
		for _, leg in ipairs(r and r.legs or {}) do
			if leg.mode == "walk" then
				local key = table.concat({ leg.from.map, leg.from.x, leg.from.y, leg.to.x, leg.to.y }, ":")
				if drawn[key] and #ns.Planner.LegPoints(leg, ns.Routes) == 2 then
					resets = resets + 1
				end
				if leg.measured and #leg.walkPoints > 2 then
					drawn[key] = true
				end
			end
		end
		draw(g, r)
	end
	local plan = ns.Planner.Plan
	ns.Planner.Plan = function(options, job)
		rounds = rounds + 1
		local started = os.clock()
		local planned = plan(options, job)
		plannerCPU = plannerCPU + (os.clock() - started) * 1000
		return planned
	end
	for _, method in ipairs({ "Find", "FindMany" }) do
		local find = ns.Path[method]
		ns.Path[method] = function(...)
			local job = find(...)
			job.method = method
			jobs[#jobs + 1] = job
			return job
		end
	end
	ns.Path.after = function(fn)
		nextFrame = fn
	end
	driver.begin(from, to)
	while nextFrame do
		local fn = nextFrame
		nextFrame = nil
		frames = frames + 1
		local started = os.clock()
		fn()
		driver.update(1 / 60)
		worst = math.max(worst, (os.clock() - started) * 1000)
		assert(frames < 20000, "journey did not settle")
	end
	local cpu, many, probes = 0, 0, 0
	for _, job in ipairs(jobs) do
		cpu = cpu + job.cpu
		if job.costOnly then
			probes = probes + 1
		end
		if job.method == "FindMany" then
			many = many + 1
			print(string.format("  FindMany map %d: %.1f ms, %d slices", job.map, job.cpu, job.frames))
		end
	end
	local settling, round = ns.JourneyStatus()
	assert(not settling)
	assert(driver.shown(), "expected reachable journey")
	print(
		string.format(
			"%s: %d searches (%d many, %d probes), %d planner calls, %d settle rounds, %d frames, "
				.. "%.1f ms search, %.1f ms planner, %d straight resets, usable frame %s, %.3f ms worst frame",
			case[1],
			#jobs,
			many,
			probes,
			rounds,
			round,
			frames,
			cpu,
			plannerCPU,
			resets,
			tostring(usable),
			worst
		)
	)
	assert(many == 2 and round == 1 and rounds >= 2, "one committed route")
	assert(resets == 0, "drawn walks cannot revert to straight lines")
	ns.ClearJourney()
end

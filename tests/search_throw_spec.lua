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

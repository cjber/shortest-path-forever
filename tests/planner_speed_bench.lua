-- A run-speed change must reuse the planner's graph instead of rebuilding it. Optional arg: a baseline source
-- directory, so the same bench measures an old Planner from there.
local root = arg[1] or "."
local driver = assert(loadfile("tests/journey_driver.lua"))(root)
local ns = driver.ns
for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Teleports.lua",
	"Data/Walks.lua",
}) do
	driver.load(file)
end
ns.faction, ns.speed = "Alliance", 7
local known = {}
for id in pairs(ns.TaxiNodes) do
	known[id] = true
end
ns.known = known
local function plan(from, to, speed, cache)
	local options = ns.PlanContext.Options(from, to)
	options.cache, options.walkSpeed, options.waterWalking = cache, speed, false
	local started = os.clock()
	local result = ns.Planner.Plan(options)
	return result, (os.clock() - started) * 1000
end
for _, case in ipairs({ { "Auberdine -> Gadgetzan", 26, 39 }, { "Auberdine -> Eastern Plaguelands", 26, 67 } }) do
	local cache = {}
	local from, to = ns.TaxiNodes[case[2]], ns.TaxiNodes[case[3]]
	plan(from, to, 7, cache)
	local _, changed = plan(from, to, 14, cache)
	local reused = 0
	for _ = 1, 5 do
		local _, ms = plan(from, to, 14, cache)
		reused = reused + ms
	end
	print(string.format("%s: speed-change plan %.3f ms, warm same-speed %.3f ms", case[1], changed, reused / 5))
end

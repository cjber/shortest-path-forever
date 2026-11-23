-- Compare exact outputs in one process. Pass an untouched source tree at the baseline revision:
-- luajit -joff tests/path_equivalence.lua /path/to/baseline
local baseline = assert(arg[1], "pass a baseline source tree")

local function equal(expected, actual, key)
	assert(type(expected) == type(actual), key .. ": different types")
	if type(expected) ~= "table" then
		assert(expected == actual, key .. ": " .. tostring(expected) .. " ~= " .. tostring(actual))
		return
	end
	for k, value in pairs(expected) do
		equal(value, actual[k], key .. "." .. tostring(k))
	end
	for k in pairs(actual) do
		assert(expected[k] ~= nil, key .. ": unexpected key " .. tostring(k))
	end
end

local function journeys(root)
	local routes = {}
	for _, mode in ipairs({ "default", "continent", "stormwind" }) do
		assert(loadfile("tests/journey_bench.lua"))(function(name, shown, followed)
			routes[name] = { shown = shown, followed = followed }
		end, root, mode)
	end
	return routes
end

local function queries(root)
	local driver = assert(loadfile("tests/journey_driver.lua"))(root)
	local ns = driver.ns
	for _, file in ipairs({
		"Data/RoadCells.lua",
		"Data/RoadEdges.lua",
		"Routing/PathGrid.lua",
		"Routing/Path.lua",
		"Routing/PathJobs.lua",
	}) do
		driver.load(file)
	end
	local nextFrame
	ns.Path.after = function(fn, delay)
		if not delay then
			nextFrame = fn
		end
	end
	local answers = {}
	local function capture(a, b)
		answers[#answers + 1] = { a, b }
	end
	local function drain()
		local frames = 0
		while nextFrame do
			frames = frames + 1
			assert(frames < 2000, "query did not settle")
			local fn = nextFrame
			nextFrame = nil
			fn()
		end
	end
	for _, map in ipairs({ 0, 1 }) do
		assert(loadfile("tools/load_nav.lua"))(map, nil, driver.env, true)
		local x, y, z = -8692, 694.1, 95
		if map == 1 then
			x, y, z = -4450, 1350, 0
		end
		local from = { map = map, x = x, y = y, z = z }
		local targets = {
			{ map = map, x = x + 16, y = y + 8 },
			{ map = map, x = x + 32, y = y - 8 },
			{ map = map, x = x + 48, y = y - 16 },
		}
		local weighted = {
			key = "equivalence",
			roads = true,
			roadFactor = 1.5,
			Point = function(_, px)
				return px > x + 32 and 1.2 or 1
			end,
			Charged = function()
				return true
			end,
			Near = function()
				return false
			end,
		}
		for _, waterWalking in ipairs({ false, true }) do
			local hazards = waterWalking and weighted or nil
			for _, reverse in ipairs({ false, true }) do
				ns.Path.FindMany(map, from, targets, capture, waterWalking, reverse, nil, hazards)
				drain()
				assert(type(answers[#answers][1][1]) == "number", "expected a reachable batch target")
			end
			for _, to in ipairs(targets) do
				ns.Path.Find(map, from, to, capture, waterWalking, hazards)
				drain()
				ns.Path.FindCost(map, from, to, capture, waterWalking, hazards)
				drain()
			end
		end
	end
	assert(#answers == 32, "expected every query to complete")
	return answers
end

equal(journeys(baseline), journeys("."), "journeys")
equal(queries(baseline), queries("."), "queries")
print("Identical final routes for 6 journeys and exact outputs for 32 walking queries")

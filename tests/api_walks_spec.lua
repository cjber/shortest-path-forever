-- #913: public walking costs for other addons, and the identity of the data they are measured against. The search is
-- the addon's own Path.FindMany, so the path queue's frame budget and its wait for combat apply unchanged.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = driver.ns, driver.env, 0
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/APIWalks.lua")
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
local API = env.ShortestPathForever.API
local path = driver.path
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected, label)
	checks = checks + 1
	assert(type(actual) == "number" and math.abs(actual - expected) < 1e-6, label)
end
local function why(expected, label, value, reason)
	equal(value, nil, label)
	equal(reason, expected, label .. " reason")
end
local FROM = { map = 1, x = 0.5, y = 0.5 }
local TARGET = { map = 1, x = 0.5014, y = 0.5 }
-- The driver's projection: uiMap fractions to world yards, on map 1.
local function world(x, y)
	return (0.5 - y) * 50000, (0.5 - x) * 50000
end

-- The walking data's identity: the build's own version, or the loaded maps for a checkout with no version token.
do
	equal(type(API.NavVersion()), "string", "NavVersion names the walking data")
	equal(API.NavVersion() ~= "", true, "with a name")
	equal(API.NavVersion(), API.NavVersion(), "and the same name twice")
	local bare = API.NavVersion()
	env.ShortestPathForeverPathData = {
		[0] = { format = 3, counts = { graph = 12 } },
		[1] = { format = 2, counts = { graph = 7 } },
	}
	equal(API.NavVersion():find("nav/", 1, true), 1, "an unpackaged checkout names its loaded maps")
	equal(API.NavVersion() ~= bare, true, "which is not the empty name")
	local maps = API.NavVersion()
	env.ShortestPathForeverPathData[1].counts.graph = 8
	equal(API.NavVersion() ~= maps, true, "a rebaked map changes the name")
	env.C_AddOns = {
		GetAddOnMetadata = function(_, field)
			return field == "Version" and "1.38.0" or nil
		end,
	}
	equal(API.NavVersion(), "1.38.0", "a release names its own build")
	env.C_AddOns.GetAddOnMetadata = function()
		return "@project-version@"
	end
	equal(API.NavVersion() ~= "1.38.0", true, "the packager's token is no version")
	env.C_AddOns = nil
	env.ShortestPathForeverPathData = nil
end

-- A batch asks the private searcher once, answers once with fresh costs, and can be cancelled twice.
do
	local batches, answers = #path.batches, {}
	local cancel = API.EstimateWalks("Twinmap", FROM, {
		{ map = 1, x = 0.5014, y = 0.5 },
		{ map = 1, x = 0.6, y = 0.5 },
	}, function(costs, reason)
		answers[#answers + 1] = { costs = costs, reason = reason }
	end)
	equal(type(cancel), "function", "a batch starts and returns its cancel")
	equal(#path.batches, batches + 1, "on one existing batch search")
	local batch = path.batches[batches + 1]
	equal(batch.map, 1, "on the from point's map")
	equal(#batch.targets, 2, "one target for each place")
	local x, y = world(FROM.x, FROM.y)
	near(batch.from.x, x, "the from point in world yards")
	near(batch.from.y, y, "and its other axis")
	equal(batch.water, false, "without water walking by default")
	equal(#answers, 0, "not answered inside the call")
	path.settle()
	equal(#answers, 1, "answered once")
	near(answers[1].costs[1], 70, "a target's walking yards")
	near(answers[1].costs[2], 5000, "and the far target's")
	equal(answers[1].costs[3], nil, "no cost beyond the targets")
	equal(answers[1].reason, nil, "a normal answer has no reason")
	cancel()
	cancel()
	equal(#answers, 1, "cancelling a finished search changes nothing")
end

-- Water walking follows opts, else the same setting and spell journeys use.
do
	ns.water = nil
	local batches = #path.batches
	local cancel = API.EstimateWalks("Water", FROM, { TARGET }, function() end, { waterWalking = true })
	equal(path.batches[batches + 1].water, true, "opts may allow water")
	cancel()
	batches = #path.batches
	ns.water = true
	cancel = API.EstimateWalks("Water", FROM, { TARGET }, function() end)
	equal(path.batches[batches + 1].water, true, "the player's own spell decides by default")
	cancel()
	batches = #path.batches
	cancel = API.EstimateWalks("Water", FROM, { TARGET }, function() end, { waterWalking = false })
	equal(path.batches[batches + 1].water, false, "and opts may refuse it")
	cancel()
	ns.water = nil
end

-- An unreachable target is false, and a batch that cannot answer says why with every cost false.
do
	local answers = {}
	path.auto = false
	local batches = #path.batches
	API.EstimateWalks("Marks", FROM, { TARGET, { map = 1, x = 0.6, y = 0.5 } }, function(costs, reason)
		answers[#answers + 1] = { costs = costs, reason = reason }
	end)
	path.finish(path.batches[batches + 1], { 42 })
	equal(answers[1].costs[1], 42, "a settled cost is kept")
	equal(answers[1].costs[2], false, "a target with no cost is false")
	equal(answers[1].reason, nil, "and that is no reason for the batch")
	batches = #path.batches
	API.EstimateWalks("Marks2", FROM, { TARGET }, function(costs, reason)
		answers[#answers + 1] = { costs = costs, reason = reason }
	end)
	path.finish(path.batches[batches + 1], nil, "outside")
	equal(answers[2].costs[1], false, "a whole batch that cannot answer is all false")
	equal(answers[2].reason, "outside", "with its reason")
	path.auto = true
	path.settle()
end

-- Refused arguments start no search. A point on another map is not a walking search on this one.
do
	local secret = driver.secret
	local batches = #path.batches
	local target = { map = 1, x = 0.51, y = 0.5 }
	for _, call in ipairs({
		function()
			return API.EstimateWalks(nil, FROM, { target }, function() end)
		end,
		function()
			return API.EstimateWalks("", FROM, { target }, function() end)
		end,
		function()
			return API.EstimateWalks(" ", FROM, { target }, function() end)
		end,
		function()
			return API.EstimateWalks(7, FROM, { target }, function() end)
		end,
		function()
			return API.EstimateWalks(secret, FROM, { target }, function() end)
		end,
		function()
			return API.EstimateWalks("A", nil, { target }, function() end)
		end,
		function()
			return API.EstimateWalks("A", {}, { target }, function() end)
		end,
		function()
			return API.EstimateWalks("A", { map = 0, x = 0.5, y = 0.5 }, { target }, function() end)
		end,
		function()
			return API.EstimateWalks("A", { map = 1, x = 2, y = 0.5 }, { target }, function() end)
		end,
		function()
			return API.EstimateWalks("A", { map = 1, x = secret, y = 0.5 }, { target }, function() end)
		end,
		function()
			return API.EstimateWalks("A", FROM, nil, function() end)
		end,
		function()
			return API.EstimateWalks("A", FROM, {}, function() end)
		end,
		function()
			return API.EstimateWalks("A", FROM, "one", function() end)
		end,
		function()
			return API.EstimateWalks("A", FROM, { target }, nil)
		end,
		function()
			return API.EstimateWalks("A", FROM, { target }, "callback")
		end,
		function()
			return API.EstimateWalks("A", FROM, { target }, function() end, 5)
		end,
		function()
			return API.EstimateWalks("A", FROM, { target }, function() end, { waterWalking = "yes" })
		end,
		function()
			return API.EstimateWalks("A", FROM, { target }, function() end, { waterWalking = secret })
		end,
		function()
			return API.EstimateWalks("A", FROM, { { map = 2, x = 0.5, y = 0.5 } }, function() end)
		end,
		function()
			return API.EstimateWalks("A", FROM, { { map = 1, x = 2, y = 0.5 } }, function() end)
		end,
		function()
			return API.EstimateWalks("A", FROM, { [2] = target }, function() end)
		end,
		function()
			return API.EstimateWalks("A", FROM, { target, map = 1 }, function() end)
		end,
		function()
			return API.EstimateWalks("A", FROM, { target, false }, function() end)
		end,
	}) do
		why("invalid", "a refused walk estimate", call())
	end
	equal(#path.batches, batches, "no refusal started a search")
	local many = {}
	for index = 1, 257 do
		many[index] = target
	end
	why("invalid", "more targets than one batch takes", API.EstimateWalks("A", FROM, many, function() end))
	local accepted = {}
	for index = 1, 256 do
		accepted[index] = target
	end
	local cancel = API.EstimateWalks("Many", FROM, accepted, function() end)
	equal(type(cancel), "function", "the bound itself is accepted")
	cancel()
end

-- Nothing to search yet or no walking map there: an answer that says when to ask again.
do
	local db = ns.db
	ns.db = nil
	why("loading", "before the saved variables load", API.EstimateWalks("A", FROM, { TARGET }, function() end))
	ns.db = db
	env.InCombatLockdown = function()
		return true
	end
	why("combat", "in combat", API.EstimateWalks("A", FROM, { TARGET }, function() end))
	env.InCombatLockdown = function()
		return false
	end
	path.data = false
	why("nodata", "with no walking map for the map", API.EstimateWalks("A", FROM, { TARGET }, function() end))
	path.data = true
end

-- Cancel stops a search in flight, and a cancelled batch never calls back. A new batch from the same owner replaces
-- the one still running, as a journey does.
do
	local answers = {}
	path.auto = false
	local batches = #path.batches
	local cancel = API.EstimateWalks("Cancel", FROM, { TARGET }, function()
		answers[#answers + 1] = "cancelled"
	end)
	local job = path.batches[batches + 1]
	cancel()
	equal(job.cancelled, true, "cancel stops the search")
	path.auto = true
	path.settle()
	equal(#answers, 0, "a cancelled search never calls back")

	batches = #path.batches
	local first = API.EstimateWalks("Owner", FROM, { TARGET }, function()
		answers[#answers + 1] = "first"
	end)
	local firstJob = path.batches[batches + 1]
	equal(type(first), "function", "a first batch")
	local second = API.EstimateWalks("Owner", FROM, { TARGET }, function()
		answers[#answers + 1] = "second"
	end)
	equal(firstJob.cancelled, true, "the same owner's new batch stops the old search")
	path.settle()
	equal(#answers, 1, "only the new batch answers")
	equal(answers[1], "second", "and it is the new one")
	second()
	second()
	equal(#answers, 1, "cancelling twice after the answer changes nothing")
end

-- An error in one caller's callback is caught for the report and leaves the search queue running.
do
	local caught = ns.core.CaughtErrors()
	local before = #caught
	API.EstimateWalks("Bad", FROM, { TARGET }, function()
		error("the caller broke")
	end)
	path.settle()
	local after = ns.core.CaughtErrors()
	equal(#after > before, true, "the callback's error is kept for the report")
	equal(after[#after].label, "API walk estimate", "under the walk estimate's label")
end

print("api_walks: ok, " .. checks .. " checks")

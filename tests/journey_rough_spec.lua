do
	local test = assert(loadfile("tests/journey_driver.lua"))()
	local journey, path = test.ns, test.path
	path.auto = false
	local stop = { map = 1, x = 100, y = 0, faction = "Alliance", name = "Middle" }
	journey.TaxiNodes = { stop }
	local plan = journey.Planner.Plan
	local forward
	journey.Planner.Plan = function(options, ...)
		if not options.feasibleOnly then
			for _, walk in ipairs(options.walks or {}) do
				if walk.estimated and walk.from.x == 0 and walk.to.x == stop.x then
					forward = walk
				end
			end
		end
		return plan(options, ...)
	end
	test.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 1000, y = 0 })
	for _, batch in ipairs(path.batches) do
		batch.valid, batch.snapped, batch.revision = true, true, 1
		batch.progress(batch.costs, nil, batch)
	end
	path.runAll()
	-- The first progress report can reuse the preview. The next revision replans from the snapped batches.
	forward = nil
	local start = path.batches[1]
	start.revision = start.revision + 1
	start.progress(start.costs, nil, start)
	path.runAll()
	assert(forward and forward.cost == 0 and forward.apart, "snapped forward zero estimate keeps apart in the planner")
end

do
	local test = assert(loadfile("tests/journey_driver.lua"))()
	local journey, path = test.ns, test.path
	path.auto = false
	test.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 1000, y = 0 })
	local rough = test.shown()
	assert(rough and rough.rough and not select(3, journey.JourneyInfo()), "a rough route is drawn, never followed")
	for _, leg in ipairs(rough.legs) do
		assert(leg.mode ~= "walk" or leg.measured or leg.walkPlaceholder, "its unmeasured walks are drawn as hints")
	end
	test.env.UnitOnTaxi = function()
		return true
	end
	for _, batch in ipairs(path.batches) do
		path.costs(batch, false)
	end
	for _, find in ipairs(path.waiting(path.finds)) do
		path.finish(find, { find.from, find.to }, 1000)
	end
	assert(not journey.JourneyStatus(), "taxi fixture finishes the proof")
	local followed = select(3, journey.JourneyInfo())
	assert(
		not (followed and followed.rough) and not (test.shown() and test.shown().rough),
		"boarding a taxi cannot settle on a rough route"
	)
end

do
	local test = assert(loadfile("tests/journey_driver.lua"))()
	local journey, path = test.ns, test.path
	path.auto = false
	journey.TaxiNodes = { { map = 1, x = 50, y = 0, faction = "Alliance", name = "Middle" } }
	path.bound = function(_, from, to)
		return math.abs(from.x - to.x) > 75 and 25 or 0
	end
	local arrived = false
	journey.JourneyChanged = function(_, reason)
		arrived = arrived or reason == "arrived"
	end
	test.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 100, y = 0 })
	assert(
		not arrived and journey.JourneyStatus(),
		"a rough route with no legs must wait for proof instead of arriving"
	)
	assert(not test.shown(), "an empty rough route is hidden")
	path.auto = true
	path.settle()
	assert(test.shown() and not journey.JourneyStatus(), "proof publishes the real walk")
end

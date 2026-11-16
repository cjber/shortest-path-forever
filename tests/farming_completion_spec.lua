-- Native lifecycle regression: real Journey, search, API hub and farming driver.
local function scenario(final)
	local d = assert(loadfile("tests/journey_driver.lua"))()
	local ns, queue = d.ns, {}
	d.env.C_Timer = {
		After = function(delay, fn)
			assert(delay == 0, "completion and settlement must not poll")
			queue[#queue + 1] = fn
		end,
	}
	local function flush()
		local work = queue
		queue = {}
		for _, fn in ipairs(work) do
			fn()
		end
	end
	d.load("UI/Looks.lua")
	d.load("Core/APIInput.lua")
	d.load("Core/API.lua")
	d.load("Journey/Itinerary.lua")
	d.load("Journey/FarmingCursor.lua")
	d.load("Journey/Farming.lua")
	local observe, callbacks = ns.ObserveFarmingJourney, {}
	ns.ObserveFarmingJourney = function(owner, callback)
		callbacks[#callbacks + 1] = callback
		return observe(owner, callback)
	end
	local c = ns.Farming.new()
	local function node(x)
		return { uiMapID = 1, x = 0.5, y = 0.5 - x / 50000, title = tostring(x) }
	end
	assert(c:Start({ node(1000), node(final) }))
	d.path.settle()
	flush()
	local oldOwner = ns.JourneyOwner()
	local oldGoal, oldPlan = ns.JourneyGoal(), ns.JourneyPlan()
	-- Every batch is validated before replacement, including a middle stop in a later batch.
	local large = {}
	for i = 1, 130 do
		large[i] = node(3000 + i)
	end
	large[80].title = false
	assert(not c:Start(large) and ns.JourneyOwner() == oldOwner)
	large[80].title = nil
	local project = ns.WorldPoint
	ns.WorldPoint = function(map, x, y)
		if y == large[80].y then
			return nil
		end
		return project(map, x, y)
	end
	assert(not c:Start(large) and ns.JourneyOwner() == oldOwner)
	ns.WorldPoint = project
	local corpse = false
	ns.Corpse = {
		Active = function()
			return corpse
		end,
	}
	corpse = true
	d.move({ map = 1, x = 1000, y = 0 })
	d.update(0.1)
	flush()
	assert(select(4, c:Status()) == 0 and ns.JourneyOwner() == oldOwner)
	corpse = false
	d.update(0.1)
	flush()
	if final > 1010 then
		assert(select(4, c:Status()) == 0, "distant final stop is not arrived")
		d.move({ map = 1, x = final, y = 0 })
		d.update(0.1)
		flush()
	end
	assert(c:Status() == "running" and select(4, c:Status()) == 1, "native close final stop completes")
	flush()
	local replacement = ns.JourneyOwner()
	ns.FarmingJourneyProof("arrived", oldGoal, oldPlan)
	callbacks[1]("arrived", 2, oldGoal, oldPlan)
	flush()
	assert(ns.JourneyOwner() == replacement and select(4, c:Status()) == 1, "late proof cannot complete replacement")
	c:Stop()
	flush()
	-- Native proximity arrival before a path measures cannot count as farming success.
	d.move({ map = 1, x = 0, y = 0 })
	d.path.auto = false
	assert(c:Start({ node(0), node(10) }))
	d.update(0.1)
	flush()
	assert(select(4, c:Status()) == 0)
	assert(c:Status() == "running", "unsettled zero-distance search cannot complete")
	c:Stop()
	d.path.auto = true
	d.move({ map = 1, x = 0, y = 0 })
	assert(c:Start({ node(1000), node(2000) }))
	d.path.settle()
	flush()
	d.move({ map = 1, x = 1000, y = 0 })
	d.update(0.1)
	flush()
	local plan = assert(ns.JourneyPlan())
	for _, leg in ipairs(plan.legs) do
		leg.measured = false
	end
	d.move({ map = 1, x = 2000, y = 0 })
	d.update(0.1)
	flush()
	local state, reason = c:Status()
	assert(state == "stopped" and reason == "unverified-arrival", tostring(state) .. ":" .. tostring(reason))
	c:Stop()
	flush()
	d.move({ map = 1, x = 0, y = 0 })
	d.path.auto = true
	local finish = d.path.finish
	d.path.finish = function(job, found, detail)
		if job.to and not job.costOnly then
			return finish(job, nil, "unreachable")
		end
		return finish(job, found, detail)
	end
	assert(c:Start({ node(3000), node(4000) }))
	d.path.settle()
	flush()
	assert(c:Status() == "stopped" and select(2, c:Status()) == "unreachable", "path failure notifies without polling")
	c:Stop()
	flush()
end
scenario(1010)
scenario(2000)
print(
	"PASS: native nearby/distant completion, atomic late-batch validation, corpse and stale proof, unmeasured proximity"
)

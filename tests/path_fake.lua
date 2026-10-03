-- The walking search as Journey and its search see it: every ns.Path call they make, answered when the spec says.
-- Like the real one it never calls back inside the call that asked. Until a spec turns `auto` off to answer for
-- itself, settle() answers every search with the straight-line cost and the straight line, or the points the
-- spec's `draw(from, to)` gives.
return function()
	local fake = { finds = {}, probes = {}, batches = {}, data = true, auto = true }
	local Path = {}
	fake.Path = Path

	local function distance(a, b)
		return a.map == b.map and math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
	end
	local function job(list, map, from, callback, water)
		local new = { map = map, from = from, callback = callback, water = water, cpu = 0 }
		list[#list + 1] = new
		return new
	end

	function Path.HasData()
		return fake.data
	end
	function Path.LowerBound(map, from, to)
		return fake.bound and fake.bound(map, from, to) or 0
	end
	function Path.Find(map, from, to, callback, water)
		local new = job(fake.finds, map, from, callback, water)
		new.to = to
		return new
	end
	function Path.FindCost(map, from, to, callback, water)
		local new = job(fake.probes, map, from, callback, water)
		new.to, new.costOnly = to, true
		return new
	end
	function Path.FindMany(map, from, targets, callback, water, reverse, progress)
		local new = job(fake.batches, map, from, callback, water)
		new.targets, new.reverse, new.progress = targets, reverse, progress
		new.costs, new.radius, new.revision = {}, 0, 0
		return new
	end
	function Path.Pause(paused)
		paused.paused = true
	end
	function Path.Resume(resumed)
		if not resumed.done and not resumed.cancelled then
			resumed.paused = false
		end
	end
	function Path.ReleaseMany(released)
		released.paused, released.callback, released.progress = true, nil, nil
	end
	function Path.ReuseMany()
		return false
	end
	function Path.Cancel(cancelled)
		cancelled.paused, cancelled.cancelled = true, true
	end
	function Path.ClearCaches() end
	function Path.Busy()
		return false
	end
	function Path.after() end

	-- Ends a search with what it found: Find's (points, cost) or (nil, reason), FindCost's (cost, reason), FindMany's
	-- (costs, reason). A spec may end a cancelled search to prove its late answer is ignored.
	function fake.finish(ended, found, detail)
		ended.done = true
		if ended.targets then
			ended.costs, ended.valid = found, detail == nil
		end
		if ended.callback then
			ended.callback(found, detail, ended)
		end
	end
	-- Ends an endpoint batch with one cost for every target.
	function fake.costs(batch, cost, reason)
		local costs = {}
		for i = 1, #batch.targets do
			costs[i] = cost
		end
		fake.finish(batch, costs, reason)
	end
	function fake.waiting(list)
		local waiting = {}
		for _, queued in ipairs(list) do
			if not queued.done and not queued.cancelled and not queued.paused then
				waiting[#waiting + 1] = queued
			end
		end
		return waiting
	end
	-- While auto, answers every search still waiting, and those their answers ask for.
	function fake.settle()
		for _ = 1, 100 do
			local ran = false
			for _, batch in ipairs(fake.auto and fake.waiting(fake.batches) or {}) do
				local costs = {}
				for i, target in ipairs(batch.targets) do
					costs[i] = distance(batch.from, target)
				end
				ran = true
				fake.finish(batch, costs)
			end
			for _, probe in ipairs(fake.auto and fake.waiting(fake.probes) or {}) do
				ran = true
				fake.finish(probe, distance(probe.from, probe.to))
			end
			for _, find in ipairs(fake.auto and fake.waiting(fake.finds) or {}) do
				ran = true
				local a, b = find.from, find.to
				local points = fake.draw and fake.draw(a, b) or { { map = a.map, x = a.x, y = a.y }, b }
				fake.finish(find, points, distance(a, b))
			end
			if not ran then
				return
			end
		end
		error("the walking search never settled")
	end
	return fake
end

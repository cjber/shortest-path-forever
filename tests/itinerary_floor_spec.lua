-- Later hops must not reuse a path to another floor at the same map coordinates.
local queued, plans = {}, 0
local stops = {
	{ map = 1, x = 10, y = 10, number = 1 },
	{ map = 1, x = 20, y = 20, number = 2 },
	{ map = 1, x = 30, y = 30, number = 3 },
}
local ns = {
	Path = {
		after = function(fn)
			queued[#queued + 1] = fn
		end,
		Busy = function() end,
		-- A path job runs on the next frame, as the pump's does.
		Run = function(fn, callback)
			local job = {}
			queued[#queued + 1] = function()
				if not job.cancelled then
					fn(job)
					job.done = true
					callback(nil, nil, job)
				end
			end
			return job
		end,
		Pause = function() end,
		Resume = function() end,
		Cancel = function(job)
			job.cancelled = true
		end,
		HasData = function()
			return false
		end,
	},
	JourneyStops = function()
		return stops, 1
	end,
	JourneyStatus = function() end,
	JourneyReplanning = function() end,
	RefreshJourneyPreview = function() end,
	EstimateLegs = function(from, to)
		plans = plans + 1
		return { { mode = "walk", from = from, to = to } }
	end,
	PlanContext = {
		LegPoints = function(leg)
			return { leg.from, leg.to }
		end,
	},
}
local env = setmetatable({
	GetTime = function()
		return 0
	end,
	InCombatLockdown = function()
		return false
	end,
}, { __index = _G })
setfenv(assert(loadfile("Journey/Itinerary.lua")), env)("ShortestPathForever", ns)
local function settle()
	ns.ItineraryChanged()
	local frames = 0
	while #queued > 0 do
		local due = queued
		queued = {}
		for _, fn in ipairs(due) do
			fn()
		end
		frames = frames + 1
		assert(frames < 20, "later hops settle")
	end
end
settle()
local first, second = unpack(ns.JourneyPreview())
assert(plans == 2, "both initial hops planned")
settle()
assert(plans == 2, "unchanged heights reuse both hops")

-- A guide learns the destination's height after initially submitting a heightless stop.
stops[3] = { map = 1, x = 30, y = 30, z = 0, number = 3 }
settle()
local paths = ns.JourneyPreview()
assert(plans == 3, "learning a destination floor replans its hop")
assert(paths[1] == first and paths[2] ~= second, "only the affected hop is replaced")
assert(paths[2].points[2].z == 0, "the new destination height reaches the planner")

-- A changed intermediate floor affects the hop arriving there and the one leaving it.
stops[2] = { map = 1, x = 20, y = 20, z = 15, number = 2 }
settle()
assert(plans == 5, "changing an intermediate floor replans both adjacent hops")
paths = ns.JourneyPreview()
assert(paths[1].points[2].z == 15 and paths[2].points[1].z == 15, "both hops use the corrected floor")
settle()
assert(plans == 5, "unchanged explicit heights retain cached hops")

stops[3] = { map = 1, x = 30, y = 30, number = 3 }
settle()
assert(plans == 6, "removing a destination height also invalidates its hop")
assert(ns.JourneyPreview()[2].points[2].z == nil, "a heightless destination does not retain an old floor")
print("itinerary_floor_spec: passed")

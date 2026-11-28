-- A looping route's later hops: all of them drawn, the next ones planned and walked first, the rest marked as far
-- or walked.
local queued, order = {}, {}
local stops, index, walked
local function Loop(count, first)
	stops = {}
	for number = 1, count do
		local place = (first or 1) + number - 2
		stops[number] = { map = 1, x = place % count * 10, y = 0, number = number }
	end
	index, walked = 1, 0
end

local function Job(run)
	local job = {}
	queued[#queued + 1] = function()
		if not job.cancelled then
			run(job)
		end
	end
	return job
end

local ns = {
	Path = {
		after = function(fn)
			queued[#queued + 1] = fn
		end,
		Busy = function() end,
		Run = function(fn, callback)
			return Job(function(job)
				fn(job)
				job.done = true
				callback(nil, nil, job)
			end)
		end,
		Find = function(_, from, to, callback)
			return Job(function(job)
				order[#order + 1] = "walk " .. from.x / 10
				job.done = true
				callback({ from, { x = (from.x + to.x) / 2, y = 1 }, to }, nil, job)
			end)
		end,
		Pause = function() end,
		Resume = function() end,
		Cancel = function(job)
			job.cancelled = true
		end,
		HasData = function()
			return true
		end,
		ClearCaches = function() end,
	},
	JourneyStops = function()
		return stops, index, walked
	end,
	JourneyStatus = function() end,
	JourneyReplanning = function() end,
	JourneyWaterWalking = function() end,
	RefreshJourneyPreview = function() end,
	EstimateLegs = function(from, to)
		order[#order + 1] = "plan " .. from.x / 10
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

local function Settle()
	local frames = 0
	while #queued > 0 do
		local due = queued
		queued = {}
		for _, fn in ipairs(due) do
			fn()
		end
		frames = frames + 1
		assert(frames < 1000, "later hops settle")
	end
end

-- How many drawn paths of each tier, in drawing order.
local function Tiers(paths)
	local runs = {}
	for _, path in ipairs(paths) do
		local tier = path.tier or "near"
		local run = runs[#runs]
		if run and run[1] == tier then
			run[2] = run[2] + 1
		else
			runs[#runs + 1] = { tier, 1 }
		end
	end
	local words = {}
	for number, run in ipairs(runs) do
		words[number] = run[1] .. " " .. run[2]
	end
	return table.concat(words, ", ")
end

local function Marked()
	return table.concat(ns.StopsToMark(), " ")
end

Loop(40)
ns.ItineraryChanged()
local waiting = ns.JourneyPreview(4)
assert(Tiers(waiting) == "near 1, far 1", "placeholders break where the tier changes: " .. Tiers(waiting))
assert(#waiting[1].points == 10 and #waiting[2].points == 32, "the placeholders go all the way round")
Settle()
assert(#order == 80, "every hop of the loop is planned and walked, the closing one too")
for step = 1, 9 do
	assert(order[step] == "plan " .. step - 1, "the near hops are planned first")
	assert(order[step + 9] == "walk " .. step - 1, "and walked before any further hop is planned")
end
assert(order[19] == "plan 9" and order[49] == "plan 39" and order[50] == "walk 9", "then the rest")
local drawn = ns.JourneyPreview(4)
assert(Tiers(drawn) == "near 9, far 31", "a hop limit does not cut a loop short: " .. Tiers(drawn))
assert(drawn[40].stop == 1, "the last hop leads back to the first stop")
assert(Marked() == "1 2 3 4 5 6 7 8 9 10", "only the near stops are marked: " .. Marked())

-- Five stops reached: four hops between them were walked, and the leg under way stands for the hop into this stop.
index, walked, order = 6, 5, {}
ns.ItineraryChanged()
Settle()
assert(#order == 0, "going round reuses every hop")
drawn = ns.JourneyPreview()
assert(Tiers(drawn) == "near 9, far 26, walked 4", Tiers(drawn))
assert(drawn[1].stop == 7 and drawn[39].stop == 5, "from the current stop round to the one before it")

-- Laps later only the last stops behind are dimmed.
index, walked = 38, 117
ns.ItineraryChanged()
assert(Tiers(ns.JourneyPreview()) == "near 9, far 5, walked 25", Tiers(ns.JourneyPreview()))
assert(Marked() == "38 39 40 1 2 3 4 5 6 7", "marks wrap round: " .. Marked())

-- The same loop sent again from another stop is joined there: its hops are kept, and nothing counts as walked.
Loop(40, 21)
ns.ItineraryChanged()
Settle()
assert(#order == 0, "a rotated loop plans nothing again")
drawn = ns.JourneyPreview()
assert(Tiers(drawn) == "near 9, far 31" and drawn[1].stop == 2, Tiers(drawn))

-- A short loop is bright all the way round.
Loop(8)
index, walked = 3, 10
ns.ItineraryChanged()
Settle()
assert(Tiers(ns.JourneyPreview()) == "near 7", Tiers(ns.JourneyPreview()))
assert(Marked() == "3 4 5 6 7 8 1 2", Marked())

-- A list stops at its end and at the hop limit.
Loop(8)
index, walked = 3, nil
ns.ItineraryChanged()
Settle()
assert(Tiers(ns.JourneyPreview()) == "near 5" and Tiers(ns.JourneyPreview(2)) == "near 2", "a list has no tiers")
assert(Marked() == "3 4 5 6 7 8", Marked())

print("itinerary_loop_spec: ok")

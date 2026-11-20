-- The planner on the real path job queue with its budget already spent, so every checkpoint pauses: a plan sliced
-- over frames answers as the whole plan does, and so do two plans queued on one topology cache and the next plan
-- after one cancelled part way.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
	"Transport/Model.lua",
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
	"Routing/Savings.lua",
	"Routing/Planner.lua",
	"Routing/LegPoints.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path, Planner = ns.Path, ns.Planner
local frames = {}
Path.after = function(fn)
	frames[#frames + 1] = fn
end
local now = 0
Path.clock = function()
	now = now + 1
	return now
end
Path.budget = -1
local function frame()
	local due = frames
	frames = {}
	for _, fn in ipairs(due) do
		fn()
	end
end
local function settle()
	local count = 0
	while #frames > 0 do
		count = count + 1
		assert(count < 100000, "the plans finish")
		frame()
	end
	return count
end

local known = {}
for id in pairs(ns.TaxiNodes) do
	known[id] = true
end
local function options(cache)
	return {
		from = ns.TaxiNodes[26],
		to = ns.TaxiNodes[67],
		now = 0,
		walkSpeed = 7,
		faction = "Alliance",
		docks = ns.Docks,
		routes = ns.Routes,
		taxiNodes = ns.TaxiNodes,
		taxiPaths = ns.TaxiPaths,
		taxiKnown = known,
		portals = ns.Portals,
		landmasses = ns.Landmasses,
		baked = ns.Walks,
		cache = cache,
	}
end
local whole = assert(Planner.Plan(options({})), "the whole plan answers")
local function sliced(cache)
	local answer = {}
	answer.job = Path.Run(function(job)
		return Planner.Plan(options(cache), job)
	end, function(plan)
		answer.plan = plan
	end)
	return answer
end
local function same(plan, label)
	assert(plan, label .. ": answered")
	assert(plan.arrive == whole.arrive and #plan.legs == #whole.legs, label .. ": the whole plan's answer")
end

local one = sliced({})
local count = settle()
same(one.plan, "sliced")
-- It checks in every 16 labels, so a cross-continent plan pauses many times; unsliced, it finishes in its first frame.
assert(count > 10, "a spent budget pauses the plan over frames")

local shared = {}
local a, b = sliced(shared), sliced(shared)
settle()
same(a.plan, "first of two interleaved on one cache")
same(b.plan, "second of two interleaved on one cache")

local cut = sliced(shared)
frame()
Path.Cancel(cut.job)
same(Planner.Plan(options(shared)), "the next plan after one cancelled part way")
assert(cut.plan == nil, "the cancelled plan never answers")

-- Weighing a baked walk for hazards can ask the client's map API once per sample, so a sliced plan reads the budget
-- before each walk it weighs, not only every 16 labels.
local checkpoint, reads, seen, weighed, unread = Path.Checkpoint, 0, -1, 0, 0
Path.Checkpoint = function()
	reads = reads + 1
	return checkpoint()
end
local weighing = options({})
weighing.hazards = {
	key = "spec",
	Segment = function()
		weighed = weighed + 1
		if reads == seen then
			unread = unread + 1
		end
		seen = reads
		return 1
	end,
}
local hazarded = {}
Path.Run(function(job)
	return Planner.Plan(weighing, job)
end, function(plan)
	hazarded.plan = plan
end)
settle()
Path.Checkpoint = checkpoint
same(hazarded.plan, "a sliced plan that weighs hazards")
assert(weighed > 0 and unread == 0, "the budget is read before every hazard weighing")
print(string.format("planner_slices_spec: a plan over %d frames answers as the whole plan", count))

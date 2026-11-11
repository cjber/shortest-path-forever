-- #717: a walking search's answer arrives in a path job's callback, and the journey search replans from the newly
-- settled costs there (JourneySearch.lua's consider). The client can call what a callback starts from C — a secure
-- hook (hooksecurefunc) is dispatched from C, and an estimate another addon asks for inside it runs there too — and
-- Lua 5.1 cannot yield across a C call: the reported job died with "attempt to yield across metamethod/C-call
-- boundary" and the journey got no route. A plan runs whole, in plain Lua frames; string.gsub's replacement is the C
-- call this harness can make across a yield.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
	"Routing/Planner.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path = ns.Path

-- The client's own scheduler and clock, replaced the way the specs replace them.
local frames = {}
Path.after = function(fn)
	frames[#frames + 1] = fn
end
local now = 0
Path.clock = function()
	now = now + 1
	return now
end
-- A budget already spent when each job resumes: every slice reaches its checkpoint.
Path.budget = -1
local reported
rawset(_G, "geterrorhandler", function()
	return function(message)
		reported = message
	end
end)

local function drain(limit)
	local count = 0
	while #frames > 0 do
		table.remove(frames, 1)()
		count = count + 1
		assert(count < limit, "the search did not settle")
	end
	return count
end

-- The C call the client makes in the middle of a callback: a yield inside it cannot cross.
local function UnderC(fn)
	("x"):gsub("x", function()
		fn()
		return "x"
	end)
end

local GOLDSHIRE = { x = -9459, y = 43 }
local STORMWIND_FM = { x = -8840.56, y = 489.7 }

-- The callback of a finished walk replans from where the walk landed, as JourneySearch does.
local replanned, answered = nil, false
local job
job = Path.Find(0, GOLDSHIRE, STORMWIND_FM, function(points, _, finished)
	if finished ~= job or not points then
		answered = true
		return
	end
	UnderC(function()
		replanned = ns.Planner.Plan({ from = points[#points], to = points[1], now = 0, walkSpeed = 7 })
	end)
	answered = true
end)
drain(20000)
assert(reported == nil, "a callback's replan must not yield across a C call: " .. tostring(reported))
assert(answered, "the callback received its walk")
assert(replanned and replanned.legs[1], "the replanned route landed")

-- The contract that keeps it so: a plan never slices. The checkpoint it used to reach is armed here; the planner must
-- finish without asking.
Path.Checkpoint = function()
	error("the planner yielded")
end
local plan =
	ns.Planner.Plan({ from = { map = 0, x = 0, y = 0 }, to = { map = 0, x = 70, y = 0 }, now = 0, walkSpeed = 7 })
assert(plan and plan.legs[1], "the plan landed in one frame")

print("path job callback: a replan never yields across the client's C calls: ok")

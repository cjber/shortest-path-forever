-- A paused walking search can be suspended inside a cluster decode, part way through reading a step. With no job
-- left in the queue, Grid.Idle evicts every cluster nothing pins (Floor.lua's Path.Pin runs it on every cluster you
-- cross), so the search resumes to find the cluster it was reading gone: PathGrid.lua's stepOpen indexed its moves
-- and raised "attempt to index field '?' (a nil value)", and the walk's journey replanned on the error. A reader keeps
-- a cluster's tables, never st's slots, across a call that can decode, and the answer is the one an undisturbed
-- search gives.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path, Grid = ns.Path, ns.PathGrid

local frames = {}
Path.after = function(fn)
	frames[#frames + 1] = fn
end
local now = 0
Path.clock = function()
	now = now + 1
	return now
end
-- A budget already spent when each job resumes: every slice reaches its checkpoint, decodes included.
Path.budget = -1
local reported
rawset(_G, "geterrorhandler", function()
	return function(message)
		reported = reported or message
	end
end)

-- Run job to its answer; with churn, pause it after every frame, idle the grid as an empty queue does, and resume.
local function run(job, churn)
	local count = 0
	while #frames > 0 do
		table.remove(frames, 1)()
		if churn and not job.done then
			Path.Pause(job)
			Grid.Idle()
			Path.Resume(job)
		end
		count = count + 1
		assert(count < 100000, "the search did not settle")
	end
end

local TRADE = { x = -8849, y = 647.9, z = 98 } -- Stormwind's Trade District
local DUNGAR = { x = -8832.8, y = 478.6 }
local GOLDSHIRE = { x = -9459, y = 43 }

for _, ends in ipairs({ { TRADE, DUNGAR }, { TRADE, GOLDSHIRE } }) do
	local answers = {}
	for _, churn in ipairs({ false, true }) do
		reported = nil
		local cost
		run(
			Path.Find(0, ends[1], ends[2], function(_, c)
				cost = c
			end),
			churn
		)
		assert(reported == nil, "a resumed search reads no evicted cluster: " .. tostring(reported))
		assert(type(cost) == "number", "the walk is found: " .. tostring(cost))
		answers[#answers + 1] = cost
	end
	assert(answers[1] == answers[2], ("the same walk either way: %s, %s"):format(answers[1], answers[2]))
end

-- A batch paused the same way keeps its frontier and settles the same costs.
do
	local targets = { DUNGAR, GOLDSHIRE }
	local answers = {}
	for _, churn in ipairs({ false, true }) do
		reported = nil
		local costs
		run(
			Path.FindMany(0, TRADE, targets, function(c)
				costs = c
			end),
			churn
		)
		assert(reported == nil, "a resumed batch reads no evicted cluster: " .. tostring(reported))
		answers[#answers + 1] = assert(costs)
	end
	for i = 1, #targets do
		assert(answers[1][i] == answers[2][i], "the same cost either way")
	end
end

print("path_pause_idle_spec: ok")

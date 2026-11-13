-- #803: a path job's answer arrives in its callback, which runs on a later frame and can ask this module questions
-- while the client is inside a C call. The journey's route setter is a hooksecurefunc trampoline (Transport/Taxi.lua),
-- and the world map it refreshes asks each stop for its ground; a batch's callback asks whether an endpoint can be
-- reused. Lua 5.1 in the client cannot yield across a C call (pcall included; LuaJIT only refuses string.gsub and
-- table.sort), so a question that decoded a cluster and sliced there killed the job with "attempt to yield across
-- metamethod/C-call boundary" (job.frames=1, expansions=0, as reported). A query decodes whole in the frame that asks,
-- so nothing it asks for pauses the work that asked.
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)

-- The client's Lua 5.1, modelled: a yield inside pcall or a C callback is the error the client raises, where LuaJIT
-- allows the pcall one. The path module takes coroutine.yield when it loads, so the guard goes in first.
local underC, crossed = false, false
local realYield = coroutine.yield
rawset(coroutine, "yield", function(...)
	if underC then
		crossed = true
		error("attempt to yield across metamethod/C-call boundary", 2)
	end
	return realYield(...)
end)
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Grid, Path = ns.PathGrid, ns.Path

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
end

-- The C call the client makes around work it did not start in plain Lua: a hook's trampoline, or a protected call.
local function UnderC(fn)
	underC = true
	local ok, err = pcall(fn)
	underC = false
	assert(ok, err)
end

local GOLDSHIRE, STORMWIND = { map = 0, x = -9459, y = 43 }, { map = 0, x = -8840.56, y = 489.7 }
local STORMWIND_GATE = { map = 0, x = -9010, y = 870 }

-- A stop's ground: the Ruins of Lordaeron's hall stands over the Undercity's city floor, in a cluster with floors whose
-- terrain exceptions no route has read (tests/stop_floor_spec.lua).
local CITY = { x = 1397.015, y = 131.343, z = -62 }
local st = Grid.State(0)
local city = Grid.locate(st, CITY.x, CITY.y)
Grid.Deadline(math.huge)
assert(Grid.grid(st, city), "the city cluster has walking data")
assert(st.terrain[city] == nil, "its terrain is undecoded")
local ground, decoded
Path.Find(0, STORMWIND_GATE, STORMWIND, function()
	UnderC(function()
		ground = Grid.ground(0, CITY.x, CITY.y, CITY.z)
		decoded = st.terrain[city] ~= nil
	end)
end)
drain(20000)
assert(not crossed, "a stop's ground was asked for under a C call")
assert(reported == nil, "a stop's ground must not yield across a C call: " .. tostring(reported))
assert(ground == "down", "the city floor below the ruins is down: " .. tostring(ground))
assert(decoded, "the answer decoded the cluster's terrain")

-- Reusing an endpoint: a released batch's source cluster has been let go, so asking whether a point is still its
-- start reads that cluster whole, in the frame that asks, and a search from elsewhere runs for the asking.
local batch
batch = Path.FindMany(0, GOLDSHIRE, { STORMWIND }, function(costs, reason, finished)
	assert(finished == batch and costs[1] and not reason, "the batch found its walk")
end)
drain(20000)
assert(batch.done and batch.costs[1], "the batch settled")
Path.ReleaseMany(batch)
Path.ClearCaches()
local state = Grid.State(0)
local source = Grid.locate(state, GOLDSHIRE.x, GOLDSHIRE.y)
assert(not Grid.Ready(state, source), "the released endpoint's cluster is cold")
local reused, decodedSource
Path.Find(0, STORMWIND_GATE, STORMWIND, function()
	UnderC(function()
		reused = Path.ReuseMany(batch, batch.from)
		decodedSource = Grid.Ready(state, source)
	end)
end)
drain(20000)
assert(not crossed, "a reuse was asked for under a C call")
assert(reported == nil, "a reuse must not yield across a C call: " .. tostring(reported))
assert(reused == true, "the released batch still recognises its endpoint")
assert(decodedSource, "the answer decoded the endpoint's cluster")
assert(
	Path.ReuseMany(batch, { map = 0, x = GOLDSHIRE.x + 30, y = GOLDSHIRE.y }) == false,
	"a point 30 yd away is not its start"
)

print("path job query: a stop's ground and a reuse answer without yielding across a C call: ok")

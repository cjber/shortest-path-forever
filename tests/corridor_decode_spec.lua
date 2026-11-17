-- #979: a long refined corridor must survive smoothing at the default decoded-grid ceiling.
local ns, frames = {}, {}
assert(loadfile("tools/load_nav.lua"))(0, nil, nil, true)
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path, Grid = ns.Path, ns.PathGrid
Path.after = function(fn)
	frames[#frames + 1] = fn
end
rawset(_G, "geterrorhandler", function()
	return error
end)
local st = Grid.State(0)
local decoded = {}
setmetatable(st.sizes, {
	__newindex = function(t, k, v)
		if v then
			decoded[k] = true
		end
		rawset(t, k, v)
	end,
})
local from = { x = -8832.77, y = 478.623, z = 109.616 }
local to = { x = -8227, y = -5783, z = 6 }
local result
Path.Find(0, from, to, function(points, cost)
	assert(points and cost > 0, tostring(cost))
	result = points
end)
local function drain()
	local n = 0
	while #frames > 0 do
		table.remove(frames, 1)()
		n = n + 1
		assert(n < 20000, "corridor search did not settle")
	end
end
drain()
assert(result and #result > 2, "the corridor produced drawing points")
local distinct = 0
for _ in pairs(decoded) do
	distinct = distinct + 1
end
print("corridor decodes: " .. Path.decodes .. ", distinct clusters: " .. distinct)
assert(Path.decodes == distinct, "the corridor decoded a cluster more than once")
assert(next(st.used) == nil, "completed job retained decoded grids")

-- Cancel a suspended search after it has acquired its endpoint hold. Another job keeps the cache active,
-- so Idle cannot hide a leaked hold. Reducing the count ceiling forces the released cluster out.
Path.budget = -1
local job = Path.Find(0, from, to, function()
	error("cancelled job notified")
end)
local source = Grid.locate(st, from.x, from.y)
while not st.val[source] do
	table.remove(frames, 1)()
end
local other = Path.Find(0, from, to, function()
	error("cancelled concurrent job notified")
end)
Grid.Hold(other, st, source)
Path.Cancel(job)
Grid.Deadline(math.huge)
Path.clusters = 4
local function pressure()
	for k in pairs(decoded) do
		if k ~= source then
			Grid.grid(st, k)
		end
	end
end
pressure()
assert(st.val[source], "cancellation released another job's hold")
Path.Cancel(other)
pressure()
assert(not st.val[source], "cancelled coroutine retained its corridor hold")
drain()
assert(next(st.used) == nil, "idle cancellation retained decoded grids")
-- An error after acquiring a hold must release it before reporting the failure.
Path.clusters, Path.budget = 64, -1
local reported
rawset(_G, "geterrorhandler", function()
	return function(message)
		reported = message
	end
end)
local bad = Path.Find(0, from, to, function(points, reason)
	assert(not points and reason == "error")
end)
local original = Grid.Hold
Grid.Hold = function(owner, state, k)
	original(owner, state, k)
	error("corridor failure")
end
table.remove(frames, 1)()
Grid.Hold = original
assert(bad.done and reported:find("corridor failure", 1, true), "job error was not reported")
Grid.Deadline(math.huge)
Grid.grid(st, source)
Path.clusters = 4
pressure()
assert(not st.val[source], "failed job retained its corridor hold")
drain()
print("corridor_decode_spec: one decode per cluster and cancellation release pass")

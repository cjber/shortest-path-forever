-- Decoded terrain outlives the search that decoded it: a journey searches its walks again every few seconds, and a
-- sweep the moment the queue drained made each of those searches decode the same clusters from nothing. The sweep
-- waits Path.linger seconds after the last search, then leaves only what the idle sweep always left.
local ns, frames, timers = {}, {}, {}
assert(loadfile("tools/load_nav.lua"))(0, nil, nil, true)
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path, Grid = ns.Path, ns.PathGrid
-- A delayed call is the sweep; everything else is the next frame.
Path.after = function(fn, seconds)
	if seconds then
		assert(seconds == Path.linger, "the sweep waits the linger")
		timers[#timers + 1] = fn
	else
		frames[#frames + 1] = fn
	end
end
rawset(_G, "geterrorhandler", function()
	return error
end)
local st = Grid.State(0)
local from = { x = -8832.77, y = 478.623, z = 109.616 }
local to = { x = -8227, y = -5783, z = 6 }

local function drain()
	local n = 0
	while #frames > 0 do
		table.remove(frames, 1)()
		n = n + 1
		assert(n < 20000, "the search did not settle")
	end
end
local function search()
	local cost
	Path.Find(0, from, to, function(points, yards)
		assert(points and yards > 0, tostring(yards))
		cost = yards
	end)
	drain()
	return assert(cost, "the search answered")
end
local function elapse()
	assert(#timers == 1, "one sweep is armed at a time, not one per drained queue")
	table.remove(timers, 1)()
end

local first = search()
local decodes = Path.decodes
assert(decodes > 0 and next(st.used) ~= nil, "the finished search kept its decoded grids")

-- The same walk again, as a journey's refresh asks it: answered from the grids already decoded.
assert(search() == first, "a kept grid changed the walking cost")
assert(Path.decodes == decodes, "the repeated search decoded " .. Path.decodes - decodes .. " clusters again")

-- Floor.lua pins and releases clusters as the player crosses them: a release within the linger leaves the rest.
local pinned = next(st.used)
Path.Pin(0, { [pinned] = true })
Path.Pin()
assert(st.val[pinned] and next(st.used) ~= nil, "a released pin swept the grids a journey is reusing")

-- The sweep armed by the first search comes due after the second: it waits once more rather than sweeping.
elapse()
assert(next(st.used) ~= nil, "the sweep ran less than the linger after the last search")
-- Nothing searched since: the grids go, as they did when the queue drained.
elapse()
assert(#timers == 0 and next(st.used) == nil, "the idle sweep retained decoded grids")

-- A search queued when the sweep comes due keeps its grids, and its own drain arms the next sweep.
search()
Path.budget = -1
Path.Find(0, from, to, function() end)
elapse()
assert(#timers == 0 and next(st.used) ~= nil, "the sweep ran under a queued search")
Path.budget = 2
drain()
elapse()
assert(#timers == 0 and next(st.used) == nil, "the sweep after a queued search retained decoded grids")
-- With no sweep due, a released pin goes at once, as before.
search()
elapse()
pinned = Grid.locate(st, from.x, from.y)
Grid.grid(st, pinned)
Path.Pin(0, { [pinned] = true })
assert(st.val[pinned], "a pinned cluster stays decoded")
Path.Pin()
assert(not st.val[pinned], "a released pin outlived an idle queue with no sweep due")
-- A search held by combat and then cancelled leaves an empty queue that no pump drains: the sweep still comes.
search()
rawset(_G, "InCombatLockdown", function()
	return true
end)
rawset(_G, "CreateFrame", function()
	local frame = {}
	function frame.SetScript() end
	function frame.RegisterEvent() end
	function frame.UnregisterEvent() end
	return frame
end)
local held = Path.Find(0, from, to, function() end)
drain()
elapse()
assert(#timers == 0 and next(st.used) ~= nil, "the sweep ran under a search waiting out combat")
Path.Cancel(held)
elapse()
assert(#timers == 0 and next(st.used) == nil, "a search cancelled in combat left its decoded grids for good")
rawset(_G, "InCombatLockdown", nil)
print("linger_spec: repeated searches reuse decoded terrain, and the idle sweep still clears it: ok")

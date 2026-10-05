local function runtime(failParts)
	_G.ShortestPathForeverPathData = nil
	local counts, frames, ns = {}, {}, {}
	_G.C_AddOns = {
		DoesAddOnExist = function(name)
			return name == "ShortestPathForever_Nav0"
		end,
		LoadAddOn = function(name)
			counts[name] = (counts[name] or 0) + 1
			if not failParts or name == "ShortestPathForever_Nav0" then
				assert(loadfile("tools/load_nav.lua"))(0, nil, nil, name)
			end
		end,
	}
	for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
		assert(loadfile(file))("ShortestPathForever", ns)
	end
	ns.Path.after = function(fn)
		frames[#frames + 1] = fn
	end
	local function drain()
		local n = 0
		while #frames > 0 do
			table.remove(frames, 1)()
			n = n + 1
			assert(n < 1000, "navigation loader did not settle")
		end
	end
	return ns.Path, counts, drain
end

local from, to = { x = -9459, y = 43 }, { x = -8840.56, y = 489.7 }
local Path, counts, drain = runtime(false)
local cancelled = Path.Find(0, from, to, function()
	error("cancelled search notified its owner")
end)
Path.Cancel(cancelled)
drain()
assert(next(counts) == nil, "cancelled search loaded navigation data")
local result, cost
Path.Find(0, from, to, function(points, yards)
	result, cost = points, yards
end)
drain()
assert(result and cost > 1000 and cost < 1300)
assert(counts.ShortestPathForever_Nav0 == 1)
local loaded = 0
for name, count in pairs(counts) do
	assert(count == 1, name .. " loaded repeatedly")
	if name ~= "ShortestPathForever_Nav0" then
		loaded = loaded + 1
	end
end
assert(loaded > 0 and loaded < 16, "short walk loaded the whole continent")
local sync, syncCost = Path.FindSync(0, from, to)
assert(sync and syncCost == cost, "sliced navigation changed the walking cost")

Path, counts, drain = runtime(true)
local failure
Path.Find(0, from, to, function(points, reason)
	assert(points == nil)
	failure = reason
end)
drain()
assert(failure == "offmesh", tostring(failure))
for name, count in pairs(counts) do
	assert(count == 1, name .. " retried indefinitely")
end
print("nav_loading_spec: cancellation, bounded loading, exact costs and missing parts pass")

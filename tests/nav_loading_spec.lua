local function runtime(corrupt)
	_G.ShortestPathForeverPathData = nil
	assert(loadfile("tools/load_nav.lua"))(0, nil, nil, true)
	local data, ns, frames, decodes = ShortestPathForeverPathData[0], {}, {}, 0
	local native = C_EncodingUtil.DecompressString
	_G.C_EncodingUtil = {
		DecodeBase64 = C_EncodingUtil.DecodeBase64,
		DecompressString = function(source, method)
			decodes = decodes + 1
			return not corrupt and native(source, method) or nil
		end,
	}
	_G.C_AddOns = {
		LoadAddOn = function()
			error("terrain must not load a helper addon")
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
	return ns.Path,
		data,
		drain,
		function()
			return decodes
		end,
		function()
			local fn = table.remove(frames, 1)
			if fn then
				fn()
			end
		end
end

local from, to = { x = -9459, y = 43 }, { x = -8840.56, y = 489.7 }
local Path, data, drain, count = runtime(false)
assert(Path.HasData(0) and not Path.IsLoaded(0))
local cancelled = Path.Find(0, from, to, function()
	error("cancelled search notified its owner")
end)
Path.Cancel(cancelled)
drain()
assert(count() == 0, "cancelled search decompressed terrain")
local result, cost
Path.Find(0, from, to, function(points, yards)
	result, cost = points, yards
end)
drain()
assert(result and cost > 1000 and cost < 1300)
assert(count() > 0 and count() < 100, "short walk decompressed the whole continent")
assert(
	next(data.grid) == nil and next(data.height) == nil and next(data.floor) == nil,
	"decoded grids retained raw strings"
)
local sync, syncCost = Path.FindSync(0, from, to)
assert(sync and syncCost == cost, "sliced navigation changed the walking cost")

local calls = 0
Path.Find(0, from, to, function(points, yards)
	assert(points and yards == cost)
	calls = calls + 1
end)
Path.Find(0, from, to, function(points, yards)
	assert(points and yards == cost)
	calls = calls + 1
end)
drain()
assert(calls == 2, "concurrent decodes changed a route or lost a callback")

local step
Path, data, drain, count, step = runtime(false)
local mid = Path.Find(0, from, to, function()
	error("mid-search cancellation notified its owner")
end)
step()
step()
local beforeCancel = count()
assert(beforeCancel > 0, "cancellation did not reach decoding")
Path.Cancel(mid)
drain()
assert(count() == beforeCancel, "cancelled job continued decoding")
assert(next(data.grid) == nil and next(data.height) == nil, "idle cancellation retained raw terrain")

Path, data, drain = runtime(true)
local failure
Path.Find(0, from, to, function(points, reason)
	assert(points == nil)
	failure = reason
end)
drain()
assert(failure == "offmesh", tostring(failure))
assert(next(data.grid) == nil, "failed decompression published terrain")
print("nav_loading_spec: bundled decoding, cancellation, exact costs and corrupt blocks pass")

local ns = {}
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local fixture = assert(loadfile("tests/nav_fixture.lua"))()
local map, cellSize = 44, 1600 / 3 / 67
fixture.install(
	map,
	fixture.format2({
		map = map,
		nx = 1,
		ny = 1,
		cell = {
			[5] = { [10] = { z = 20 }, [11] = { z = 20 }, [12] = { z = 20 } },
			[8] = { [10] = { z = 26 } },
			[9] = { [13] = { z = 26 } },
		},
		node = { { 5, 10, 1 } },
	})
)
local function point(x, y, z)
	return { x = (x + 0.5) * cellSize, y = (y + 0.5) * cellSize, z = z }
end

rawset(_G, "geterrorhandler", function()
	return error
end)

local path, frame = ns.Path
path.after = function(fn)
	frame = fn
end
local a, b, ground = point(8, 10, 26), point(9, 13, 26), point(5, 12, 20)
for _, reverse in ipairs({ false, true }) do
	local job, snapped, zeroAtSnap, finished
	-- The connector policy is queried after snapping and before the abstract graph search.
	local hazards = {
		key = "zero-entrance",
		Charged = function()
			return false
		end,
		ConnectorWalk = function()
			if not snapped then
				snapped, zeroAtSnap = job.snapped, job.costs[1]
			end
			return false
		end,
	}
	job = path.FindMany(map, reverse and b or a, { reverse and a or b, ground }, function(costs)
		finished = costs
	end, nil, reverse, nil, hazards)
	while frame do
		local run = frame
		frame = nil
		run()
	end
	assert(finished and finished[1] == 0, "both ledges are rescued to the shared entrance at zero cost")
	assert(snapped and zeroAtSnap == nil, "rescued ledges are resolved by the entrance search after snapping")
end

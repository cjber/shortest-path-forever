local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
local fixture = setfenv(assert(loadfile("tests/nav_fixture.lua")), env)()
local frame
local create = env.CreateFrame
env.CreateFrame = function(...)
	frame = create(...)
	return frame
end
local outdoors = true
env.IsOutdoors = function()
	return outdoors
end
ns.Floor = {
	Height = function()
		return 20
	end,
}
for _, file in ipairs({
	"Routing/PathGrid.lua",
	"UI/Art.lua",
	"UI/Mover.lua",
	"UI/TurnAround.lua",
	"UI/CastButton.lua",
	"UI/Arrow.lua",
	"Core/APIInput.lua",
	"Core/APIStops.lua",
	"Core/API.lua",
}) do
	driver.load(file)
end
ns.Path.Decode = function()
	error("the arrow requested a terrain decode")
end

local size = ns.PathGrid.TILE / 67
local map = 49000
local function install(wall, floor)
	map = map + 1
	local cells = {}
	for x = 8, 72 do
		cells[x] = {}
		for y = 8, 18 do
			cells[x][y] = { z = 20, flags = wall and y == 10 and x < 15 and 2 or 0 }
		end
	end
	fixture.install(map, fixture.format2({ nx = 2, ny = 1, cell = cells, floor = floor }))
	local state = ns.PathGrid.State(map)
	assert(ns.PathGrid.grid(state, 0))
	return state
end

local function point(x, y, z)
	return { map = map, x = (x + 0.5) * size, y = (y + 0.5) * size, z = z or 20 }
end

local function walk()
	return { point(10, 10), point(14, 10), point(15, 11), point(16, 12), point(17, 12) }
end

local function aimAt(start, points, expected, message)
	driver.move(start)
	if frame then
		frame.angle = nil
	end
	ns.PointGuideArrow(points)
	local bearing = math.atan2(expected.y - start.y, expected.x - start.x)
	assert(math.abs(frame.angle - bearing) < 1e-9, message)
end

install()
local points = walk()
aimAt(points[1], points, points[4], "the arrow aims past cell bends, stopping before the step end")
assert(ns.GuideTargets() == points[4], "the compass shares the arrow's visible aim")
local bend, source, index = ns.GuideState()
assert(bend == points[2] and source == points and index == 2, "the canonical path and index still name the next bend")
local guidance = env.ShortestPathForever.API.Guidance()
assert(
	guidance
		and guidance.index == 2
		and guidance.point.x == ns.APIInput.Place(points[2]).x
		and guidance.waypoints[4].x == ns.APIInput.Place(points[4]).x
		and #guidance.waypoints == #points,
	"public guidance still reports the original walk and next bend"
)

outdoors = false
aimAt(points[1], points, points[2], "indoors the arrow keeps each bend")
outdoors = true

install(true)
points = walk()
aimAt(points[1], points, points[2], "a wall blocks both later bends")

install(nil, { { 15, 12, 40, 1, 0 } })
points = walk()
aimAt(points[1], points, points[3], "an intervening stacked floor rules out the farther aim")
points[3].z = 22
aimAt(points[1], points, points[2], "a following height change stops the look-ahead")
points[3].z, points[3].map = 20, map + 1
aimAt(points[1], points, points[2], "the look-ahead cannot cross a map boundary")

local state = install()
points = { point(61, 10), point(65, 10), point(67, 11), point(68, 11) }
local decodes = ns.Path.decodes
aimAt(points[1], points, points[2], "an undecoded cluster leaves the arrow at the next bend")
frame:OnUpdate(0.1)
assert(ns.Path.decodes == decodes, "the arrow tick decoded no terrain")
assert(ns.PathGrid.grid(state, 1))
frame.angle = nil
frame:OnUpdate(0.1)
assert(ns.GuideTargets() == points[3] and frame.angle > 0, "the next tick can use the decoded cluster")
print("arrow_sight_spec: ok")

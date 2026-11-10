-- A stop against its cell's ground: PathGrid.ground says "up" when the surface its height snaps to is above the
-- cell's ground layer, "down" when it is below, and nil when it is the same node (or nothing is known). A cell with
-- no floors says nothing: it has one place to stand, and the route walks the player onto it. A cell with floors has
-- the ground layer the bake stored, or its base when the cell is left out, and a cell with floors over no terrain
-- says nothing either. Run from the repository root: luajit tests/stop_floor_spec.lua
local ns = {}
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Grid = ns.PathGrid

-- The Ruins of Lordaeron's hall stands over the Undercity's city floor. The hall's own cell is over an ADT hole, so
-- it has no terrain and says nothing; the hall floor's cell has the city floor as its base and the ruins as a floor.
local HALL = { x = 1588, y = 237, z = 60 }
local RUINS = { x = 1397.015, y = 131.343, z = 64 }
local CITY = { x = 1397.015, y = 131.343, z = -62 } -- the city floor under the ruins' own cell
local GOLDSHIRE = { x = -9459, y = 43, z = 58 }
-- Scout Riell stands at the top of Sentinel Hill's tower, above its ground.
local SCOUT = { x = -10504.8, y = 1033.25, z = 95.7958 }
local st = Grid.State(0)

local function cell(point)
	return Grid.locate(st, point.x, point.y)
end

local function decode(point)
	local k = cell(point)
	assert(Grid.grid(st, k), "a cluster with walking data")
end

-- Reading a cell never decodes it, and a hover must not force one.
assert(st.val[cell(HALL)] == nil, "the hall's cell is undecoded")
assert(Grid.ground(0, HALL.x, HALL.y, HALL.z) == nil, "an undecoded cell says nothing")
for _, point in ipairs({ HALL, RUINS, CITY, GOLDSHIRE, SCOUT }) do
	decode(point)
end

assert(Grid.ground(0, HALL.x, HALL.y, HALL.z) == nil, "the hall's ground has no terrain under it")
assert(Grid.ground(0, RUINS.x, RUINS.y, RUINS.z) == nil, "ruins ground on the terrain is not raised")
assert(Grid.ground(0, CITY.x, CITY.y, CITY.z) == "down", "the city floor below the ruins is down")
assert(Grid.ground(0, SCOUT.x, SCOUT.y, SCOUT.z) == "up", "the tower top above its ground is up")
assert(Grid.ground(0, GOLDSHIRE.x, GOLDSHIRE.y, GOLDSHIRE.z) == nil, "Goldshire's ground is the terrain")

-- Nothing to say: no height, no walking map, or no surface there.
assert(Grid.ground(0, CITY.x, CITY.y, nil) == nil, "no height says nothing")
assert(Grid.ground(1, 0, 0, 0) == nil, "a map with no walking data says nothing")
assert(Grid.ground(0, 0, 6000, 0) == nil, "a point off the walking map says nothing")

-- Synthetic clusters: one 2-yard cell each, base at 10 yards, one floor at 16 yards unless the cluster has none.
local FLOOR = "AABAAABBgQAAAAA"
local function synthetic(terrainText, floor, height)
	rawset(ShortestPathForeverPathData, 999, {
		cx0 = 0,
		cy0 = 0,
		nx = 1,
		ny = 1,
		cells = 1,
		swim = 3,
		zstep = 2,
		grid = { [1] = "Q" },
		height = { [1] = height or "c" },
		floor = { [1] = floor },
		terrain = { [1] = terrainText },
	})
end
local function ground(terrainText, floor, z, height)
	synthetic(terrainText, floor, height)
	Grid.Reset()
	local fake = Grid.State(999)
	assert(Grid.grid(fake, 0), "the synthetic cluster decodes")
	return Grid.ground(999, 100, 100, z)
end

-- A cell with no floor stores nothing: a base far above the terrain still says nothing.
assert(ground("", nil, 100, "vgy") == nil, "a floorless cell above the terrain says nothing")
assert(ground("", nil, 200, "vgy") == nil, "a floorless cell high above its base says nothing")
-- A cell left out of the exceptions has its base surface as the ground.
assert(ground("", FLOOR, 10) == nil, "a stop on the omitted cell's base is the ground")
assert(ground("", FLOOR, 16) == "up", "a floor above an omitted cell's base is up")
-- A stored ground layer: the floor is the ground, so its stop is neither up nor down.
assert(ground("AA", FLOOR, 16) == nil, "the stored ground floor is the ground")
assert(ground("AA", FLOOR, 10) == "down", "the base below the stored ground floor is down")
-- A cell with floors over no terrain stores the no-ground marker, so nothing is said.
assert(ground("A/", FLOOR, 10) == nil, "a floored cell with no ground says nothing")
assert(ground("A/", FLOOR, 16) == nil, "a floored cell with no ground says nothing above it")

print("stop_floor_spec: ground up, down, floorless, omitted base and no ground ok")

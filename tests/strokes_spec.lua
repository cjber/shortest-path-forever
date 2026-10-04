-- Route drawing as geometry (UI/Strokes.lua): paths and a view in, strokes out, with no frame or client in reach.
local checks = 0
local function check(value, label)
	checks = checks + 1
	assert(value, label)
end
local function close(a, b)
	return math.abs(a - b) < 1e-6
end

local ns = {}
for _, file in ipairs({ "UI/FlightLines.lua", "UI/Strokes.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Strokes = ns.Strokes
local DOT, RIM, GAP, SPACING, SMALL_DOT, SMALL_SPACING, LATER = 4, 1, 2, 9, 3, 7, 0.4
local CANVAS, MINIMAP = 1000, 140
-- Colours pass through untouched, so a name stands in for each.
local colors = {}
for _, mode in ipairs({ "walk", "flight", "boat", "zeppelin", "lift", "tram", "portal", "passage", "teleport" }) do
	colors[mode] = mode
end

-- Map fractions stand in for world yards: a point is on the map it names, at its own x and y.
local function mapView(fields)
	local view = {
		mapID = 0,
		position = function(point, mapID)
			if point.map == mapID then
				return point.x, point.y
			end
		end,
		width = CANVAS,
		height = CANVAS,
		scale = 1,
		zoom = 1,
		small = false,
		current = math.huge,
		colors = colors,
	}
	for key, value in pairs(fields or {}) do
		view[key] = value
	end
	return view
end
local function minimapView(player, fields)
	local view = {
		x = player.x,
		y = player.y,
		map = player.map,
		radius = 0.5,
		facing = 0,
		width = MINIMAP,
		height = MINIMAP,
		scale = 1,
		goalRadius = 8,
		colors = colors,
	}
	for key, value in pairs(fields or {}) do
		view[key] = value
	end
	return view
end
local function point(x, y, map)
	return { map = map or 0, x = x, y = y }
end
local function length(strokes, i)
	return math.sqrt((strokes.x2[i] - strokes.x1[i]) ^ 2 + (strokes.y2[i] - strokes.y1[i]) ^ 2)
end
-- Dot centres, in the view's units.
local function dots(strokes)
	local centres = {}
	for i = 1, strokes.n do
		if strokes.dot[i] then
			centres[#centres + 1] = { (strokes.x1[i] + strokes.x2[i]) / 2, (strokes.y1[i] + strokes.y2[i]) / 2 }
		end
	end
	return centres
end
-- Every dot's rim stays GAP clear of the mark, and the nearest dot is within one spacing of that.
local function clears(strokes, cx, cy, radius, scale, label)
	local reach, nearest = radius + (GAP + DOT / 2 + RIM) / scale, math.huge
	for _, dot in ipairs(dots(strokes)) do
		nearest = math.min(nearest, math.sqrt((dot[1] - cx) ^ 2 + (dot[2] - cy) ^ 2))
	end
	check(nearest >= reach, label .. ": a dot runs under the mark")
	check(nearest < reach + SPACING / scale, label .. ": the dots stop well short of the mark")
end

local strokes = Strokes.New()

-- A walk is round breadcrumbs: each a dot one diameter long with a rim all round, evenly spaced through a bend (#22,
-- #25). A dot on the joint belongs to the later segment, so none is lost or doubled there.
local bend = { mode = "walk", points = { point(0.1, 0.5), point(0.3, 0.5), point(0.3, 0.8) } }
Strokes.Map(strokes, { bend }, mapView())
check(strokes.n == 56, "one dot every " .. SPACING .. " along 500 units: " .. strokes.n)
for i = 1, strokes.n do
	local along = (i - 1) * SPACING
	local x, y = 100 + math.min(along, 200), -500 - math.max(along - 200, 0)
	local centre = dots(strokes)[i]
	check(close(centre[1], x) and close(centre[2], y), "dot " .. i .. " keeps its place along the walk")
	check(strokes.dot[i] and close(length(strokes, i), DOT), "a dot is one diameter long")
	check(strokes.width[i] == DOT and strokes.under[i] == DOT + RIM * 2, "a rim on every side")
	check(close(math.sqrt(strokes.ux[i] ^ 2 + strokes.uy[i] ^ 2), RIM), "the rim reaches past each end too")
	check(strokes.alpha[i] == 1 and strokes.color[i] == "walk" and strokes.route[i] == nil)
end
-- Sizes are screen pixels: twice the scale halves them in the view's units.
Strokes.Map(strokes, { bend }, mapView({ scale = 2 }))
check(strokes.n == 112 and strokes.width[1] == DOT / 2 and close(length(strokes, 1), DOT / 2), "pixels, not units")
-- Continent and world maps wear smaller dots, closer together (#26).
Strokes.Map(strokes, { bend }, mapView({ small = true }))
check(strokes.width[1] == SMALL_DOT and strokes.under[1] == SMALL_DOT + RIM * 2, "small maps, small dots")
check(close(dots(strokes)[2][1] - dots(strokes)[1][1], SMALL_SPACING), "and a smaller spacing")
-- A redraw overwrites the buffer: fewer strokes leave a smaller count, never stale ones.
Strokes.Map(strokes, { { mode = "walk", points = { point(0.1, 0.5), point(0.11, 0.5) } } }, mapView())
check(strokes.n == 2, "the buffer is reused")

-- Every other mode is a solid line in its colour, inside a darker outline two pixels wider.
Strokes.Map(strokes, { { mode = "lift", points = bend.points, route = 7 } }, mapView())
check(strokes.n == 2 and not strokes.dot[1] and strokes.color[1] == "lift", "one line per segment")
check(strokes.x1[1] == 100 and strokes.y1[1] == -500 and strokes.x2[1] == 300 and strokes.y2[2] == -800)
check(strokes.width[1] == 2 and strokes.under[1] == 4 and strokes.ux[1] == 0 and strokes.uy[1] == 0)
check(strokes.route[1] == 7 and strokes.route[2] == 7, "a stroke names its path's route")
local custom = {}
Strokes.Map(strokes, { { mode = "walk", color = custom, points = bend.points } }, mapView())
check(strokes.color[1] == custom, "a path's own colour wins")

-- Clip segments, not vertices: a line crossing the map with both ends outside it is still drawn, cut at the edges.
Strokes.Map(strokes, { { mode = "lift", points = { point(-0.5, 0.5), point(1.5, 0.5) } } }, mapView())
check(strokes.n == 1 and close(strokes.x1[1], 0) and close(strokes.x2[1], CANVAS), "clipped to the map")
Strokes.Map(strokes, { { mode = "lift", points = { point(-0.5, 0.5), point(-0.1, 0.9) } } }, mapView())
check(strokes.n == 0, "nothing off the map")
-- A walk is clipped a dot's reach inside, so every rim fits, and keeps its spacing from where it began.
Strokes.Map(strokes, { { mode = "walk", points = { point(-0.5, 0.5), point(1.5, 0.5) } } }, mapView())
local centres = dots(strokes)
check(#centres > 100, "the visible breadcrumbs")
for _, centre in ipairs(centres) do
	check(centre[1] >= DOT / 2 + RIM and centre[1] <= CANVAS - DOT / 2 - RIM, "every rim inside the map")
	check(
		close((centre[1] + 500) % SPACING, 0) or close((centre[1] + 500) % SPACING, SPACING),
		"spacing from the start"
	)
end
-- Client regions cannot be destroyed, so one drawing is bounded however far the map zooms.
Strokes.Map(strokes, { { mode = "walk", points = { point(0, 0.5), point(1, 0.5) } } }, mapView({ scale = 100 }))
check(strokes.n == 4096, "bounded strokes: " .. strokes.n)

-- The dots stop short of each stop's mark at any zoom (#51). Stop 3 goes back to stop 1's place: the route walks
-- there, on to stop 2, and back. Marks keep their size on screen, so their reach grows as the map zooms out.
local player, first, second = point(0.1, 0.5), point(0.3, 0.5), point(0.5, 0.5)
local journey = { { mode = "walk", points = { player, first } }, { mode = "walk", points = { first, second, first } } }
for _, zoom in ipairs({ 2, 0.5 }) do
	local marks = { { x = first.x, y = first.y, radius = 10 }, { x = second.x, y = second.y, radius = 10 } }
	Strokes.Map(strokes, journey, mapView({ scale = zoom, zoom = zoom, marks = marks, current = 1 }))
	for _, place in ipairs({ first, second }) do
		clears(strokes, place.x * CANVAS, -place.y * CANVAS, 10 / zoom, zoom, "world map at " .. zoom)
	end
	-- The leg being walked is at full strength; the later hops after it recede.
	local current, later = 0, 0
	for i = 1, strokes.n do
		check(strokes.alpha[i] == (strokes.x2[i] <= first.x * CANVAS and 1 or LATER), "current or later")
		current, later = current + (strokes.alpha[i] == 1 and 1 or 0), later + (strokes.alpha[i] == LATER and 1 or 0)
	end
	check(current > 0 and later > 0 and strokes.alpha[1] == 1, "the current leg is drawn first")
end

-- A portal or passage has no line: a small cross marks each end the map shows.
Strokes.Map(
	strokes,
	{ { mode = "portal", points = { point(0.2, 0.2), point(0.6, 0.6), point(0.5, 0.5, 9) } } },
	mapView()
)
check(strokes.n == 4, "two crosses, none for the end on another map")
check(close(strokes.x1[1], 196) and close(strokes.x2[1], 204) and strokes.y1[1] == -200 and strokes.y2[1] == -200)
check(strokes.x1[2] == 200 and close(strokes.y1[2], -196) and close(strokes.y2[2], -204), "four pixels each way")
-- A hop still planning dashes between places on one map and only marks a change of map: a straight line would
-- cross the sea (#26).
local hop = { mode = "walk", preview = true, points = { point(0.2, 0.2), point(0.4, 0.2), point(0.5, 0.5, 9) } }
Strokes.Map(strokes, { hop }, mapView())
local dashed, solid = 0, 0
for i = 1, strokes.n do
	dashed, solid = dashed + (strokes.dot[i] and 1 or 0), solid + (strokes.dot[i] and 0 or 1)
end
check(dashed == 23 and solid == 2, "dots to the last place on this map, then a cross: " .. dashed .. ", " .. solid)

-- Flights are drawn through FlightLines.lua's rounded corners, ends exact (#67).
local corner = { mode = "flight", points = { point(0.2, 0.2), point(0.6, 0.2), point(0.6, 0.6) } }
Strokes.Map(strokes, { corner }, mapView())
check(strokes.n > 2 and strokes.x1[1] == 200 and strokes.y1[1] == -200, "a rounded corner from the first point")
check(strokes.x2[strokes.n] == 600 and strokes.y2[strokes.n] == -600, "to the last")

-- A boat between maps is a curve, never a straight line across the sea. With both piers on the map it bridges them,
-- leaving along the way it was sailing.
local function ends(label, ax, ay, bx, by)
	check(close(strokes.x1[1], ax) and close(strokes.y1[1], ay), label .. ": leaves the first pier")
	check(close(strokes.x2[strokes.n], bx) and close(strokes.y2[strokes.n], by), label .. ": reaches the second")
end
local hopped = { point(0.1, 0.5), point(0.2, 0.5), point(0.6, 0.5), point(0.7, 0.5) }
hopped[2].jump = 1
Strokes.Map(strokes, { { mode = "boat", points = hopped } }, mapView())
check(strokes.n == 14, "a line in, a twelve-step bridge, a line out: " .. strokes.n)
check(close(strokes.x1[2], 200) and close(strokes.x2[13], 600), "pier to pier")
local bow = 0
for i = 2, 13 do
	check(strokes.alpha[i] == 1 and not strokes.dot[i])
	bow = math.max(bow, math.abs(strokes.y2[i] + 500))
end
check(bow > 10, "the bridge bows off the straight line")
-- With one pier off the map the curve runs out to the map's edge, fading as it goes.
local sailing = { point(0.5, 0.5), point(0.6, 0.5), point(0.3, 0.3, 9), point(0.4, 0.3, 9) }
Strokes.Map(strokes, { { mode = "boat", points = sailing } }, mapView())
check(strokes.n == 13, "a line to the pier and a twelve-step curve: " .. strokes.n)
check(close(strokes.x2[strokes.n], CANVAS) or close(strokes.y2[strokes.n], 0), "out to the edge")
for i = 3, 13 do
	check(strokes.alpha[i] < strokes.alpha[i - 1], "fading toward the edge")
end
check(close(strokes.alpha[2], 1 - 0.5 / 12) and close(strokes.alpha[13], 0.5 / 12))
-- An overview map placing both continents draws one arc, the same whichever way the boat sails.
local overview = mapView({
	position = function(spot)
		return spot.x, spot.y
	end,
})
local west, east = point(0.2, 0.6, 1), point(0.7, 0.5, 2)
Strokes.Map(
	strokes,
	{ { mode = "zeppelin", points = { west, point(0.25, 0.6, 1), point(0.65, 0.5, 2), east } } },
	overview
)
check(strokes.n == 12, "one arc for the whole crossing")
ends("overview", 200, -600, 700, -500)
local midX, midY = strokes.x2[6], strokes.y2[6]
Strokes.Map(
	strokes,
	{ { mode = "zeppelin", points = { east, point(0.65, 0.5, 2), point(0.25, 0.6, 1), west } } },
	overview
)
ends("overview back", 700, -500, 200, -600)
check(close(strokes.x2[6], midX) and close(strokes.y2[6], midY), "the same arc in either direction")
check(midY > -550, "arcing north, toward open sea")

-- The minimap: north up, the player at its centre, the view radius at its rim. A point north of the player sits
-- above the centre, and a turned minimap turns it.
local px, py = Strokes.Project(point(0.3, 0.5), 0.1, 0.5, 0.5, 1, 0)
check(close(px, 0) and close(py, 0.4), "north is up")
px, py = Strokes.Project(point(0.1, 0.3), 0.1, 0.5, 0.5, 1, 0)
check(close(px, 0.4) and close(py, 0), "world y runs west")
px, py = Strokes.Project(point(0.3, 0.5), 0.1, 0.5, 0.5, math.cos(math.pi / 2), math.sin(math.pi / 2))
check(close(px, 0.4) and close(py, 0), "a quarter turn puts north on the right")

-- On the minimap the dots stop short of the ring around the stop's own icon (#51). The stop is 0.2 north of the
-- player in a 0.5 view radius: 0.4 of the way from centre to rim.
local approach = { { mode = "walk", points = { player, first } } }
local gx, gy = Strokes.Minimap(strokes, approach, minimapView(player, { goal = first }))
check(gx == 0 and close(gy, 0.4), "where the stop's mark sits")
clears(strokes, MINIMAP / 2, -MINIMAP / 2 + 0.4 * MINIMAP / 2, 8, 1, "minimap")
for i = 1, strokes.n do
	check(strokes.alpha[i] == 1, "the minimap route stays at full strength")
end
-- A corpse wears the game's own tombstone: no mark, and the dots run right up to it.
local ghost = minimapView(player, { goal = { map = 0, x = first.x, y = first.y, corpse = true } })
check(Strokes.Minimap(strokes, approach, ghost) == nil, "no mark for a corpse")
local nearest = math.huge
for _, centre in ipairs(dots(strokes)) do
	nearest = math.min(nearest, math.abs(centre[2] - (-MINIMAP / 2 + 0.4 * MINIMAP / 2)))
end
check(nearest < SPACING, "dots up to the corpse")

-- Strokes are clipped to the minimap's face: a circle, or a square where another addon says so.
local through =
	{ { mode = "walk", points = { point(-2, 2.5), point(2, -1.5) } }, { mode = "portal", points = { player } } }
local function reach(square)
	local farthest, count = 0, 0
	Strokes.Minimap(strokes, through, minimapView(player, { square = square }))
	for _, centre in ipairs(dots(strokes)) do
		local x, y = centre[1] - MINIMAP / 2, centre[2] + MINIMAP / 2
		farthest, count =
			math.max(farthest, square and math.max(math.abs(x), math.abs(y)) or math.sqrt(x * x + y * y)), count + 1
	end
	return farthest, count
end
local rim, round = reach(false)
local side, boxed = reach(true)
check(round > 5 and rim <= MINIMAP / 2 - DOT / 2 - RIM, "every rim inside the round face")
check(boxed > round and side <= MINIMAP / 2 - DOT / 2 - RIM, "a square face shows its corners too")
-- Another continent's points, a jump and a portal draw nothing there.
local elsewhere = { point(0.1, 0.5), point(0.2, 0.5), point(0.3, 0.5), point(0.2, 0.5, 9) }
elsewhere[1].jump = 1
Strokes.Minimap(strokes, { { mode = "lift", points = elsewhere } }, minimapView(player))
check(strokes.n == 1 and close(strokes.y1[1], -MINIMAP / 2 + 0.2 * MINIMAP / 2), "only the segment on this map")
-- While the client withholds the view (no position, a secret radius or facing) nothing is drawn.
for _, missing in ipairs({ "x", "radius", "facing" }) do
	local view = minimapView(player, { goal = first })
	view[missing] = nil
	check(Strokes.Minimap(strokes, approach, view) == nil and strokes.n == 0, "nothing without " .. missing)
end
check(Strokes.Minimap(strokes, approach, minimapView(player, { goal = first, radius = 0 })) == nil and strokes.n == 0)

-- A ten-yard approach still draws visible dots outside the destination icon (#74).
local origin, nearGoal = point(0, 0), point(10, 0)
local near = { { mode = "walk", points = { origin, nearGoal } } }
Strokes.Minimap(strokes, near, minimapView(origin, { radius = 30, goal = nearGoal }))
check(strokes.n > 0, "near arrival keeps route strokes")
-- Held interaction stops must keep one marker even when the remaining span is shorter than the breadcrumb gap.
local held = { map = 0, x = 1, y = 0, hold = true }
near = { { mode = "walk", points = { origin, held } } }
Strokes.Minimap(strokes, near, minimapView(origin, { radius = 30, goal = held }))
check(strokes.n == 1 and not strokes.dot[1] and strokes.color[1] == "walk", "held near stop keeps a marker")
check(strokes.x1[1] == MINIMAP / 2 and strokes.y1[1] == -MINIMAP / 2, "from the player")
check(close(strokes.x2[1], MINIMAP / 2) and close(strokes.y2[1], -MINIMAP / 2 + MINIMAP / 2 / 30), "to the stop")
Strokes.Minimap(strokes, near, minimapView(origin, { radius = 30, goal = point(1, 0) }))
check(strokes.n == 0, "an ordinary near stop keeps the goal ring's breadcrumb gap")
local here = { map = 0, x = 0, y = 0, hold = true }
Strokes.Minimap(
	strokes,
	{ { mode = "walk", points = { origin, here } } },
	minimapView(origin, { radius = 30, goal = here })
)
check(strokes.n == 0, "an exact held destination has no zero-length stroke")

-- The objective area the player stands in is a ring in the guide's yellow, on the map and the minimap, in place of
-- the journey (Adventure Guide holds an objective stop inside its area). World x runs north and world y west, so a
-- circle's world radii give the map's two axes.
local swapped = mapView({
	area = { { map = 0, x = 0.5, y = 0.5, radius = 0.1 } },
	areaColor = "area",
	position = function(spot, mapID)
		if spot.map == mapID then
			return spot.y, spot.x
		end
	end,
})
Strokes.Map(strokes, {}, swapped)
check(strokes.n == 48, "a map ring is drawn as a closed circle: " .. strokes.n)
for i = 1, strokes.n do
	check(strokes.color[i] == "area" and not strokes.dot[i] and strokes.alpha[i] == 1, "a solid yellow ring")
	check(
		strokes.x1[i] >= 400 and strokes.x2[i] <= 600 and strokes.y1[i] >= -600 and strokes.y2[i] <= -400,
		"the ring stays on its shape"
	)
end
check(
	close(strokes.x1[1], 600) and close(strokes.y1[1], -500) and close(strokes.x2[strokes.n], 600),
	"from the first vertex round to the last"
)
-- Two overlapping circles draw one outline: the arcs inside the other circle are left out.
local pair = mapView({
	area = { { map = 0, x = 0.5, y = 0.5, radius = 0.1 }, { map = 0, x = 0.5, y = 0.6, radius = 0.1 } },
	areaColor = "area",
	position = swapped.position,
})
Strokes.Map(strokes, {}, pair)
check(strokes.n > 48 and strokes.n < 96, "overlapping circles share one outline: " .. strokes.n)
-- A shape the view cannot place draws nothing.
Strokes.Map(strokes, {}, mapView({ area = { { map = 9, x = 0.5, y = 0.5, radius = 0.1 } }, areaColor = "area" }))
check(strokes.n == 0, "no ring for a shape the view cannot place")

-- The minimap ring is the same circle around the player, its radius in the view's own units, clipped to the face.
local areaView = minimapView(player, {
	area = { { map = 0, x = 0.3, y = 0.5, radius = 0.05 } },
	areaColor = "area",
})
check(Strokes.Minimap(strokes, {}, areaView) == nil, "no goal mark while inside the area")
check(strokes.n > 0, "the area's ring is drawn: " .. strokes.n)
for i = 1, strokes.n do
	check(strokes.color[i] == "area" and not strokes.dot[i], "a solid yellow ring on the minimap")
end
local inside = true
for i = 1, strokes.n do
	local x, y = strokes.x1[i] - MINIMAP / 2, strokes.y1[i] + MINIMAP / 2
	inside = inside and math.sqrt(x * x + y * y) <= MINIMAP / 2 + 1e-6
end
check(inside, "the ring is clipped to the round face")
-- A shape on another continent is not drawn on this one.
Strokes.Minimap(
	strokes,
	{},
	minimapView(player, { area = { { map = 9, x = 0.3, y = 0.5, radius = 0.05 } }, areaColor = "area" })
)
check(strokes.n == 0, "only the player's own map's areas draw")

-- The minimap redraws ten times a second, so a redraw into a grown buffer allocates nothing. Measured in the
-- interpreter, as in the game: JIT traces allocate on their own schedule.
local walk = { mode = "walk", points = {} }
for i = 0, 60 do
	walk.points[i + 1] = point(0.1 + i * 0.01, 0.5 + (i % 2) * 0.01)
end
local flight = { mode = "flight", points = { point(0, 0.4), point(0.3, 0.4), point(0.3, 0.9) } }
local view = minimapView(player, { goal = point(0.4, 0.5) })
if jit then
	jit.off()
	jit.flush()
end
local paths = { walk, flight }
local function measured(draw)
	draw()
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	draw()
	local allocated = collectgarbage("count") - before
	collectgarbage("restart")
	return allocated
end
check(measured(function()
	for i = 1, 600 do
		view.x, view.facing = 0.1 + i * 0.0005, i * 0.01
		Strokes.Minimap(strokes, paths, view)
	end
end) == 0, "a minimap redraw allocates nothing")
check(strokes.n > 10, "while drawing the route: " .. strokes.n)
local world = mapView({ marks = { { x = 0.4, y = 0.5, radius = 10 } }, current = 1 })
check(measured(function()
	for i = 1, 100 do
		world.zoom = 1 + i / 100
		Strokes.Map(strokes, paths, world)
	end
end) == 0, "nor does a world map redraw")

print(string.format("strokes_spec: %d checks ok", checks))

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
-- The minimap's own player arrow is 16 units across (Strokes.lua PLAYER_ARROW is its radius).
local ARROW = 8
-- StopPin.lua fades a later stop by the same amount, read from here (UI/Strokes.lua).
check(ns.LaterAlpha == LATER, "one later alpha for stops and strokes")
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

-- A dot's centre begins outside the mark's own radius, with the nearest within one spacing of it.
local function beginsOutside(strokes, cx, cy, radius, scale, label)
	local nearest = math.huge
	for _, dot in ipairs(dots(strokes)) do
		nearest = math.min(nearest, math.sqrt((dot[1] - cx) ^ 2 + (dot[2] - cy) ^ 2))
	end
	check(nearest >= radius, label .. ": a dot runs under the mark")
	check(nearest < radius + SPACING / scale, label .. ": the dots stop well short of the mark")
end

-- Dense flight smoothing must not become subpixel native lines at default map zoom.
do
	local source = {}
	for index = 0, 150 do
		source[#source + 1] = { map = 0, x = 0.1 + index * 0.005, y = 0.4 + math.sin(index / 15) * 0.02 }
	end
	local path = { mode = "flight", points = source }
	local low, high = Strokes.New(), Strokes.New()
	Strokes.Map(low, { path }, mapView({ scale = 0.3 }))
	Strokes.Map(high, { path }, mapView({ scale = 4 }))
	for index = 1, low.n - 1 do
		check(length(low, index) * 0.3 >= 3 - 1e-6, "flight segments remain drawable at low zoom")
		check(
			close(low.x2[index], low.x1[index + 1]) and close(low.y2[index], low.y1[index + 1]),
			"flight segments remain connected"
		)
	end
	check(
		close(low.x1[1], source[1].x * CANVAS) and close(low.y1[1], -source[1].y * CANVAS),
		"low zoom keeps departure exact"
	)
	check(
		close(low.x2[low.n], source[#source].x * CANVAS) and close(low.y2[low.n], -source[#source].y * CANVAS),
		"low zoom keeps arrival exact"
	)
	check(low.n < high.n, "flight detail adapts to screen scale")
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

-- The saved style changes the walking producer for both surfaces, while the default above remains dotted.
ns.db = { routeStyle = "solid" }
Strokes.Map(strokes, { bend }, mapView())
check(strokes.n == 2 and not strokes.dot[1] and not strokes.dot[2], "solid world-map walking lines are continuous")
Strokes.Minimap(strokes, { bend }, minimapView(point(0.2, 0.5)))
check(strokes.n == 2 and not strokes.dot[1] and not strokes.dot[2], "solid minimap walking lines are continuous")
ns.db = nil

-- A tour's walk is solid whatever the player's style, its bends cut back a few screen pixels and bridged by a curve;
-- the ends stay exact and later legs recede less.
do
	local ends = bend.points
	Strokes.Map(
		strokes,
		{ { mode = "walk", points = ends }, { mode = "walk", points = ends } },
		mapView({ tour = true, current = 1 })
	)
	local each = strokes.n / 2
	check(each == 6, "two sides and four steps round the bend: " .. each)
	for i = 1, each do
		check(not strokes.dot[i] and strokes.alpha[i] == 1 and strokes.alpha[i + each] == 0.6)
		check(
			i == 1 or close(strokes.x1[i], strokes.x2[i - 1]) and close(strokes.y1[i], strokes.y2[i - 1]),
			"connected"
		)
	end
	check(close(strokes.x1[1], 100) and close(strokes.y1[1], -500), "the start stays exact")
	check(close(strokes.x2[each], 300) and close(strokes.y2[each], -800), "the end stays exact")
	check(close(strokes.x2[1], 300 - 3.5) and close(strokes.y2[1], -500), "the bend is cut back")
	check(close(strokes.x1[each], 300) and close(strokes.y1[each], -503.5))
	Strokes.Map(strokes, { { mode = "walk", points = ends } }, mapView({ tour = true, scale = 2 }))
	check(close(strokes.x2[1], 300 - 1.75), "the cut is screen pixels")
	local short = { point(0.1, 0.5), point(0.106, 0.5), point(0.106, 0.7) }
	Strokes.Map(strokes, { { mode = "walk", points = short } }, mapView({ tour = true }))
	check(close(strokes.x2[1], 103.6), "never more than two fifths of a side")
	local straight = { point(0.1, 0.5), point(0.2, 0.5), point(0.3, 0.5) }
	Strokes.Map(strokes, { { mode = "walk", points = straight } }, mapView({ tour = true }))
	check(strokes.n == 2, "a straight run gains no strokes")
	-- Two walked segments either side of a jump: no curve joins them, and the jump keeps its two end marks.
	local apart = { point(0.1, 0.5), point(0.2, 0.5), point(0.2, 0.6), point(0.3, 0.6) }
	apart[2].jump = true
	Strokes.Map(strokes, { { mode = "walk", points = apart } }, mapView({ tour = true }))
	check(strokes.n == 6, "a break in the walk is not rounded across: " .. strokes.n)
	-- A fall straight down lands on the map point it left from.
	local fall = { point(0.1, 0.5), point(0.2, 0.5), point(0.2, 0.5), point(0.2, 0.6) }
	fall[2].jump = true
	Strokes.Map(strokes, { { mode = "walk", points = fall } }, mapView({ tour = true }))
	check(strokes.n == 6, "nor across a fall in place: " .. strokes.n)
	Strokes.Minimap(strokes, { bend }, minimapView(point(0.2, 0.7), { tour = true }))
	check(strokes.n == 2 and not strokes.dot[1], "a tour's minimap walk is solid")
	-- It stops short of the player's arrow and of the next stop's ring, so both show.
	local player = point(0.1, 0.5)
	local goal = point(0.1 + 0.25, 0.5)
	local past = { mode = "walk", points = { player, point(0.1 + 0.4, 0.5) } }
	local view = minimapView(player, { tour = true, goal = goal })
	local gx, gy = Strokes.Minimap(strokes, { past }, view)
	local cx, cy = (gx + 1) * MINIMAP / 2, (gy - 1) * MINIMAP / 2
	check(strokes.n == 2, "the line breaks round the ring: " .. strokes.n)
	-- The line runs straight up from the player, so each end's distance to a mark on it is enough.
	for i = 1, strokes.n do
		for _, y in ipairs({ strokes.y1[i], strokes.y2[i] }) do
			check(math.abs(y + MINIMAP / 2) >= ARROW - 1e-9, "the tour line under the arrow")
			check(math.abs(y - cy) >= view.goalRadius, "the tour line under the ring")
		end
		check((strokes.y1[i] - cy) * (strokes.y2[i] - cy) > 0, "the tour line across the ring")
		check(close(strokes.x1[i], cx), "straight up")
	end
	-- Beside a held stop, a tour's ring is the mark: no line is drawn back through it.
	local beside = point(0.1 + 0.05, 0.5)
	beside.hold = true
	local approach = { mode = "walk", points = { player, beside } }
	Strokes.Minimap(strokes, { approach }, minimapView(player, { tour = true, goal = beside }))
	check(strokes.n == 0, "nothing runs through a held stop's ring: " .. strokes.n)
end

-- Terrain walks step about a pixel at a time on a zone map, and the client draws nothing for a sliver of one: a
-- solid walk, a tour's or the player's own style, is one unbroken line with no stroke under a pixel short of its end.
do
	local stairs = { point(0.1, 0.5) }
	for i = 1, 120 do
		local last, along, aside = stairs[i], 0.0011, i % 6 == 0 and 0.0011 or 0
		-- A shallow run, then a steep one that turns at every step.
		if i > 60 then
			along, aside = i % 2 == 0 and 0.0011 or 0, i % 2 == 1 and 0.0011 or 0
		end
		stairs[i + 1] = point(last.x + along, last.y + aside)
	end
	local finish = stairs[#stairs]
	for _, tour in ipairs({ true, false }) do
		ns.db = { routeStyle = "solid" }
		Strokes.Map(strokes, { { mode = "walk", points = stairs } }, mapView({ tour = tour }))
		ns.db = nil
		for i = 1, strokes.n do
			local left = math.sqrt((strokes.x2[i] - finish.x * CANVAS) ^ 2 + (strokes.y2[i] + finish.y * CANVAS) ^ 2)
			check(left < 8 or length(strokes, i) >= 1, "a sliver the client drops: " .. i .. " " .. length(strokes, i))
			check(
				i == 1 or close(strokes.x1[i], strokes.x2[i - 1]) and close(strokes.y1[i], strokes.y2[i - 1]),
				"unbroken"
			)
		end
		check(close(strokes.x1[1], 100) and close(strokes.y1[1], -500), "from the first point")
		check(close(strokes.x2[strokes.n], finish.x * CANVAS), "to the last")
		check(close(strokes.y2[strokes.n], -finish.y * CANVAS), "to the last, down")
	end
end

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

-- A walk whose spaced breadcrumbs all fall in the gaps at its ends gets one between them (#1418).
do
	local radius = 10
	local function between(apart, points)
		local a, b = point(0.3, 0.5), point(0.3 + apart / CANVAS, 0.5)
		local marks = { { x = a.x, y = a.y, radius = radius }, { x = b.x, y = b.y, radius = radius } }
		local walk = points and points(a, b) or { a, b }
		Strokes.Map(strokes, { { mode = "walk", points = walk } }, mapView({ marks = marks }))
		return dots(strokes), a, b
	end
	local drawn, a, b = between(32)
	check(#drawn == 1 and close(drawn[1][1], (a.x + b.x) / 2 * CANVAS), "one dot, midway")
	check(close(drawn[1][2], -a.y * CANVAS), "on the walk")
	check(drawn[1][1] - a.x * CANVAS >= radius + 2 + DOT / 2 + RIM, "the usual gap")
	-- Measured along the walk, whatever its segments.
	drawn, a, b = between(32, function(from, to)
		return { from, point(from.x + 0.004, from.y), point(from.x + 0.02, from.y), to }
	end)
	check(#drawn == 1 and close(drawn[1][1], (a.x + b.x) / 2 * CANVAS), "midway over several segments")
	check(#between(28) == 0, "no room between the gaps")
	check(#between(80) > 1, "an open walk keeps its spacing")
end

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

-- A stop under the pointer shows its own leg at full strength, and only its own: stop 2's leg is lit while stop 3's
-- stays faded (UI/Route.lua's ns.HoverStop).
local legged = {
	{ mode = "walk", points = { player, first }, stop = 1 },
	{ mode = "walk", points = { first, second }, stop = 2 },
	{ mode = "walk", points = { second, point(0.7, 0.5) }, stop = 3 },
}
Strokes.Map(strokes, legged, mapView({ current = 1, highlight = { [2] = true } }))
local lit, faded = 0, 0
for i = 1, strokes.n do
	local middle = (strokes.x1[i] + strokes.x2[i]) / 2
	if middle > first.x * CANVAS then
		check(strokes.alpha[i] == (middle < second.x * CANVAS and 1 or LATER), "the hovered stop's own leg")
		lit, faded = lit + (middle < second.x * CANVAS and 1 or 0), faded + (middle >= second.x * CANVAS and 1 or 0)
	end
end
check(lit > 0 and faded > 0, "one leg lights while the rest of the way ahead recedes")

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
-- A tour draws the same hop as a solid line.
Strokes.Map(strokes, { hop }, mapView({ tour = true }))
check(strokes.n == 3 and #dots(strokes) == 0, "a tour's hop still planning is solid: " .. strokes.n)

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
local width, under, defaultCount = strokes.width[1], strokes.under[1], strokes.n
Strokes.Minimap(strokes, approach, minimapView(player, { goal = first, walkSize = 100 }))
check(
	strokes.n == defaultCount and strokes.width[1] == width and strokes.under[1] == under,
	"100% matches the old size"
)
local sx, sy = Strokes.Minimap(strokes, approach, minimapView(player, { goal = first, walkSize = 50 }))
check(sx == gx and sy == gy, "smaller breadcrumbs leave the goal in the same place")
check(strokes.width[1] == width / 2 and strokes.under[1] == under / 2, "the whole breadcrumb shrinks")
check(close(length(strokes, 1), width / 2), "breadcrumbs shrink along the path as well as across it")
-- A goal off the minimap: its mark waits on the rim in its direction, its ring inside the face.
local far = point(1.4, 0.5)
local ex, ey, edge =
	Strokes.Minimap(strokes, { { mode = "walk", points = { player, far } } }, minimapView(player, { goal = far }))
local ringRim = 1 - minimapView(player).goalRadius / (MINIMAP / 2)
check(edge and close(ex, 0) and close(ey, ringRim), "due north, on the rim")
clears(strokes, MINIMAP / 2, -MINIMAP / 2 + ringRim * MINIMAP / 2, 8, 1, "the rim mark")
-- The player's own arrow sits at the centre: its breadcrumbs begin outside the arrow's radius, so it still shows the
-- facing (#583).
beginsOutside(strokes, MINIMAP / 2, -MINIMAP / 2, ARROW, 1, "the player arrow")
-- Still on the face but too near its rim for the whole ring: pulled in onto the rim at full strength, not an edge.
local close_rim = point(0.1 + 0.5 * 0.95, 0.5)
ex, ey, edge = Strokes.Minimap(strokes, {}, minimapView(player, { goal = close_rim }))
check(not edge and close(ex, 0) and close(ey, ringRim), "near the rim: on it, not an edge")
local eastward = point(0.1, -0.5)
ex, ey, edge = Strokes.Minimap(strokes, {}, minimapView(player, { goal = eastward, square = true }))
check(edge and close(ex, ringRim) and close(ey, 0), "on a square face's side")
check(
	select(3, Strokes.Minimap(strokes, approach, minimapView(player, { goal = first }))) == nil,
	"on the face: no edge"
)
check(Strokes.Minimap(strokes, {}, minimapView(player, { goal = point(1.4, 0.5, 9) })) == nil, "another map: no mark")
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
-- The first dot's centre is just inside the smaller clip boundary but outside the default one.
local nearRim = {
	{ mode = "walk", points = { point(player.x + 66 / MINIMAP, player.y), point(player.x + 0.5, player.y) } },
}
Strokes.Minimap(strokes, nearRim, minimapView(player))
check(strokes.n == 0, "a default breadcrumb starts too close to the rim")
Strokes.Minimap(strokes, nearRim, minimapView(player, { walkSize = 50 }))
check(strokes.n == 1, "the smaller breadcrumb fits inside the rim")
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

-- Clipped to the view: a long walk's far end is drawn at a zoom where the whole walk would run past LIMIT, its dots in
-- the places the whole walk has them, so a drag does not make them crawl.
do
	local long = { mode = "walk", points = { point(0.1, 0.5), point(6, 0.5) } }
	local clipped = Strokes.New()
	Strokes.Map(
		clipped,
		{ long },
		mapView({ stitched = true, scale = 16, clipLeft = 5.5, clipRight = 5.6, clipTop = 0, clipBottom = 1 })
	)
	local kept = dots(clipped)
	check(#kept > 0 and #kept < 200, "only what is near the view is drawn: " .. #kept)
	for _, dot in ipairs(kept) do
		check(dot[1] >= 5.5 * CANVAS and dot[1] <= 5.6 * CANVAS, "inside the clip")
		local along = (dot[1] - 0.1 * CANVAS) % (SPACING / 16)
		check(along < 1e-6 or SPACING / 16 - along < 1e-6, "where the whole walk has a dot")
	end
end

-- Under terrain, the same scheduled dots get depth color and one larger dot at the baked mouth.
do
	local makeColor = _G.CreateColor
	_G.CreateColor = function(r, g, b)
		return { r = r, g = g, b = b }
	end
	local route = {
		mode = "walk",
		points = {
			{ map = 0, x = 0.1, y = 0.55, depthCut = 0.75 },
			{ map = 0, x = 0.4, y = 0.55, depth = 5 },
			{ map = 0, x = 0.6, y = 0.55, depth = 90, depthCut = 0.25 },
			{ map = 0, x = 0.9, y = 0.55 },
		},
	}
	local caveStrokes = Strokes.New()
	local function Inspect(size, alpha)
		local larger, surface, shallow, deep = 0, 0
		for i = 1, caveStrokes.n do
			if caveStrokes.color[i] == colors.walk then
				surface = surface + 1
				check(caveStrokes.width[i] == size, "surface dots keep their size")
			else
				shallow = shallow or caveStrokes.color[i].r
				deep = caveStrokes.color[i].r
				check(caveStrokes.alpha[i] == alpha, "cave color uses the normal route opacity")
				if caveStrokes.width[i] > size then
					larger = larger + 1
				end
			end
		end
		check(larger == 1 and surface > 0 and deep < shallow, "one mouth dot and stronger blue at depth")
	end
	Strokes.Map(caveStrokes, { route }, mapView({ current = 0 }))
	Inspect(DOT, LATER)
	local n = caveStrokes.n
	local a, b = route.points[2], route.points[3]
	local aDepth, bDepth = a.depth, b.depth
	a.depth, b.depth = nil, nil
	Strokes.Map(caveStrokes, { route }, mapView({ current = 0 }))
	check(caveStrokes.n == n, "the entrance enlarges a scheduled dot without adding another")
	a.depth, b.depth = aDepth, bDepth
	Strokes.Minimap(caveStrokes, { route }, minimapView(point(0.5, 0.4), { walkSize = 50 }))
	Inspect(DOT / 2, 1)
	_G.CreateColor = makeColor
end

print(string.format("strokes_spec: %d checks ok", checks))

---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Route drawing as geometry: paths and a view in, strokes out. Nothing here touches a frame or the client, so the
-- painters (Route.lua's map pin and minimap frame, RouteTransports.lua's pin) only copy strokes onto pooled lines.
--
-- A stroke is a solid colour line with a slim dark border, so it reads on parchment and minimap alike; the taxi line
-- atlas is mostly transparent and turned into a thin core inside a heavy border. Walks are round breadcrumbs, each
-- a dot-textured line one diameter long over a slightly larger dark dot, spaced evenly across the walk's bends.
local THICKNESS, DOT, RIM, SPACING = 2, 4, 1, 9
-- Continent and world maps show a whole journey at a fraction of a zone's scale, so their dots are smaller.
local SMALL_DOT, SMALL_SPACING = 3, 7
local UNDER_THICKNESS = THICKNESS + 2
-- Everything past the stop being guided to recedes, so the way ahead reads first. Later lines keep their colour
-- but drop well back against parchment; StopPin.lua fades its later stops by this same amount.
local LATER_ALPHA = 0.4
ns.LaterAlpha = LATER_ALPHA
-- A tour's later legs are solid and only a few, so they stay readable while receding less. Its bends are cut back this
-- many screen pixels, never past this share of either side, and bridged by this many segments: enough to soften a
-- corner without moving the line off the walk.
local TOUR_LATER_ALPHA, TOUR_CUT, TOUR_CUT_SHARE, TOUR_STEPS = 0.6, 3.5, 0.4, 4
-- Screen pixels. The client draws nothing for a sliver of a line, so a flight or a solid walk passes over points
-- closer than these (five leaves a pixel of a walk's segment cut at both ends), and a bend's curve takes no more
-- steps than its cut has room for at TOUR_STEP each.
local FLIGHT_APART, WALK_APART, TOUR_STEP = 3, 5, 0.75
-- Breadcrumbs stop short of each stop's mark, so the way runs up to a stop rather than under it: a dot is left out when
-- its rim would come within STOP_GAP of the mark, on screen, at either end of a leg.
local STOP_GAP = 2
local ENTRANCE_SCALE, DEPTH_SHADES = 1.35, 16
local depthColors = {}
-- The minimap's player arrow is the game's own 16-unit arrow, centred on the player: the route begins outside its
-- radius, so the arrow still shows which way the player faces (#583).
local PLAYER_ARROW = 8
-- Client regions cannot be destroyed. Bound each painter's pool even after extreme map zooms.
local LIMIT = 4096
-- OpenMap's stitched map, for the drawing: the view runs past the host map, so nothing is clipped to its rectangle.
local wide = false
-- What a line is clipped to, in map fractions: the map (nothing over the stitched map), and the view's margin if known.
local minX, maxX, minY, maxY = 0, 1, 0, 1

-- Strokes in drawing order, as parallel arrays 1..n, in the view's own units with x right and y up from its top left.
-- A redraw overwrites the arrays in place: the minimap redraws ten times a second and must not allocate.
---@class SPFStrokes
---@field n number
---@field x1 number[]
---@field y1 number[]
---@field x2 number[]
---@field y2 number[]
---@field ux number[] -- the outline reaches this far past each end
---@field uy number[]
---@field width number[]
---@field under number[] -- the outline's thickness
---@field alpha number[]
---@field color colorRGBA[]
---@field dot boolean[] -- a breadcrumb, drawn with the dot texture
---@field route number[] -- the path's route, where it has one

-- The world map at one zoom. Positions are map fractions; sizes are the painter's, so strokes anchor to it directly.
---@class SPFMapView
---@field mapID number
---@field position fun(point: SPFPoint, mapID: number): number?, number? -- nil where the map cannot place the point
---@field width number
---@field height number
---@field scale number -- screen pixels per unit
---@field zoom number -- the canvas scale stop marks are held against
---@field small boolean -- continent and world maps
---@field stitched? boolean -- OpenMap's stitched map: the view runs past the host map, so lines are not clipped to it
---@field clipLeft? number -- the view and a margin, in map fractions: nothing past it is worth drawing
---@field clipRight? number
---@field clipTop? number
---@field clipBottom? number
---@field marks? {x: number, y: number, radius: number}[] -- stop marks the dots leave a gap around
---@field current number -- paths after this many belong to later hops
---@field tour? boolean -- a tour of many close stops: solid walks with soft corners, later legs receding less
---@field highlight? table<number, boolean> -- stops whose leg is shown at full strength while the pointer is on them
---@field colors table<SPFMode, colorRGBA>

-- The minimap around the player. radius and facing are nil while the client withholds them.
---@class SPFMinimapView
---@field x number?
---@field y number?
---@field map number?
---@field radius number?
---@field facing number?
---@field width number
---@field height number
---@field scale number
---@field square boolean?
---@field walkSize number? breadcrumb size as a percent
---@field goal SPFPoint?
---@field goalRadius number -- the goal mark's radius on the minimap
---@field tour? boolean -- a tour of many close stops: its walks are solid
---@field colors table<SPFMode, colorRGBA>

---@class SPFStrokeGeometry
local Strokes = {}
ns.Strokes = Strokes

-- One drawing at a time: the buffer being filled and the pen's state.
---@type SPFStrokes
local out
---@type number, number, number, number, number, number, number
local scale, width, height, dot, dotRim, spacing, walked
-- Where along the walk the first dot sits.
local phase = 0
-- Whether a dotted segment of the current path lies in the view.
local inView
---@type number, number, number?
local fade, later, route
-- Walk distance of the cave mouth, until its first regular breadcrumb has been considered.
local entranceDistance
-- Stop marks as x, y and reach, flat; near holds those the segment in hand passes.
---@type number[], number, number[]
local circles, circleCount, near = {}, 0, {}
-- Whether solid lines stop short of the marks too, as a tour's do on the minimap.
local gapped = false

-- Walking geometry defaults to breadcrumbs. Solid mode, the player's choice or a tour's, keeps the same route, but
-- emits continuous segments for both the world map and the minimap.
---@param tour boolean?
local function WalkingRouteDotted(tour)
	return not (tour or ns.db and ns.db.routeStyle == "solid")
end

---@return SPFStrokes
function Strokes.New()
	return {
		n = 0,
		x1 = {},
		y1 = {},
		x2 = {},
		y2 = {},
		ux = {},
		uy = {},
		width = {},
		under = {},
		alpha = {},
		color = {},
		dot = {},
		route = {},
	}
end

---@param buffer SPFStrokes
---@param viewScale number
---@param small boolean?
---@param stitched boolean? OpenMap's stitched map: nothing is clipped to the host map's rectangle
local function Begin(buffer, viewScale, small, stitched)
	out, scale = buffer, viewScale
	out.n = 0
	wide = stitched == true
	minX, maxX = wide and -math.huge or 0, wide and math.huge or 1
	minY, maxY = minX, maxX
	dot, dotRim, spacing = small and SMALL_DOT or DOT, RIM, small and SMALL_SPACING or SPACING
	walked, fade, later, route, circleCount, gapped = 0, 1, 1, nil, 0, false
end

local function Stroke(x1, y1, x2, y2, color, isDot, dotSize)
	local n = out.n
	if n >= LIMIT then
		return
	end
	n = n + 1
	out.n = n
	-- A dot's rim reaches RIM past it on every side, so its underline is longer as well as thicker.
	local ux, uy = 0, 0
	if isDot then
		local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		ux, uy = (x2 - x1) / length * dotRim / scale, (y2 - y1) / length * dotRim / scale
	end
	out.x1[n], out.y1[n], out.x2[n], out.y2[n], out.ux[n], out.uy[n] = x1, y1, x2, y2, ux, uy
	out.width[n] = (isDot and (dotSize or dot) or THICKNESS) / scale
	out.under[n] = (isDot and (dotSize or dot) + dotRim * 2 or UNDER_THICKNESS) / scale
	out.alpha[n], out.color[n], out.dot[n], out.route[n] = fade * later, color, isDot or false, route
end

-- Clip segments, not vertices: a line can cross a zone with both endpoints outside it.
local function ClipAxis(start, delta, low, high, minimum, maximum)
	if delta == 0 then
		if start < minimum or start > maximum then
			return nil
		end
	else
		local a, b = (minimum - start) / delta, (maximum - start) / delta
		low, high = math.max(low, math.min(a, b)), math.min(high, math.max(a, b))
	end
	if low < high then
		return low, high
	end
end

-- The stop marks this segment passes near, copied from circles into near; returns the length copied.
local function Near(x1, y1, x2, y2)
	local count = 0
	local dx, dy = x2 - x1, y2 - y1
	local lengthSquared = dx * dx + dy * dy
	for i = 1, circleCount, 3 do
		local cx, cy, reach = circles[i], circles[i + 1], circles[i + 2]
		local t = math.max(0, math.min(1, ((cx - x1) * dx + (cy - y1) * dy) / lengthSquared))
		local ex, ey = x1 + t * dx - cx, y1 + t * dy - cy
		if ex * ex + ey * ey < reach * reach then
			near[count + 1], near[count + 2], near[count + 3] = cx, cy, reach
			count = count + 3
		end
	end
	return count
end

local function Clear(count, x, y)
	for i = 1, count, 3 do
		local dx, dy = x - near[i], y - near[i + 1]
		if dx * dx + dy * dy < near[i + 2] * near[i + 2] then
			return false
		end
	end
	return true
end

-- A mark the dots avoid: their centres stay outside its reach, in the view's own units.
local function Avoid(x, y, reach)
	circles[circleCount + 1], circles[circleCount + 2], circles[circleCount + 3] = x, y, reach
	circleCount = circleCount + 3
end

-- A stop mark the dots leave a gap around: its radius plus what leaves STOP_GAP on screen past a dot's rim.
local function EntranceClear(x, y, extra)
	for i = 1, circleCount, 3 do
		local dx, dy = x - circles[i], y - circles[i + 1]
		if dx * dx + dy * dy < (circles[i + 2] + extra) ^ 2 then
			return false
		end
	end
	return true
end

local function Circle(x, y, radius)
	Avoid(x, y, radius + (STOP_GAP + dot / 2 + dotRim) / scale)
end

-- A solid stretch, from low to high of a segment, left open inside the avoided marks from the one at `mark` on.
local function Open(x1, y1, dx, dy, low, high, color, mark)
	if low >= high then
		return
	end
	if mark > circleCount then
		Stroke(x1 + low * dx, y1 + low * dy, x1 + high * dx, y1 + high * dy, color)
		return
	end
	local fx, fy, reach = x1 - circles[mark], y1 - circles[mark + 1], circles[mark + 2]
	local a, b = dx * dx + dy * dy, fx * dx + fy * dy
	local discriminant = b * b - a * (fx * fx + fy * fy - reach * reach)
	if discriminant <= 0 then
		return Open(x1, y1, dx, dy, low, high, color, mark + 3)
	end
	local root = math.sqrt(discriminant)
	Open(x1, y1, dx, dy, low, math.min(high, (-b - root) / a), color, mark + 3)
	Open(x1, y1, dx, dy, math.max(low, (-b + root) / a), high, color, mark + 3)
end

-- Clip before subdividing: even continent-sized walks need only the visible breadcrumbs. Dots sit at every SPACING
-- along the whole walk, walked carrying the distance across segment joins so bends never bunch them.
local function Segment(x1, y1, x2, y2, low, high, color, dashed, a, b, entranceLow, entranceHigh)
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy) * scale
	if length == 0 then
		return
	end
	if not dashed then
		walked, entranceDistance = 0, nil
		if low then
			Open(x1, y1, dx, dy, low, high, color, gapped and 1 or circleCount + 1)
		end
		return
	end
	local start = walked
	walked = start + length
	local aDepth, bDepth, cut = a and a.depth, b and b.depth, a and a.depthCut or 0.5
	if not aDepth then
		entranceDistance = bDepth and (start + length * cut) or nil
	end
	if not low then
		return
	end
	inView = true
	-- The caller clipped a walk a dot's reach inside its frame, so every rim fits and joints need no trim, which
	-- would drop the dots at each bend. A dot on a joint belongs to the later segment: both ends share a tolerance,
	-- so rounding in the running total cannot push it out of both.
	local half = dot / 2 / length
	local first = math.ceil((start + low * length - 0.001 - phase) / spacing) * spacing + phase - start
	local count = Near(x1, y1, x2, y2)
	for distance = first, high * length - 0.001, spacing do
		local t = distance / length
		if count == 0 or Clear(count, x1 + t * dx, y1 + t * dy) then
			local depth = aDepth
			if aDepth and bDepth then
				depth = aDepth + t * (bDepth - aDepth)
			elseif t >= cut then
				depth = bDepth
			end
			local ink = color
			if depth then
				-- Quantize only the color. The surface data decides which dots are underground.
				local shade = math.floor(depth / (depth + 20) * DEPTH_SHADES)
				if not depthColors[shade] then
					local strength = shade / DEPTH_SHADES
					depthColors[shade] = CreateColor(0.62 - 0.38 * strength, 0.86 - 0.24 * strength, 1)
				end
				ink = depthColors[shade]
			end
			local size, radius = dot, half
			if depth and entranceDistance and start + distance >= entranceDistance then
				local extra = dot * (ENTRANCE_SCALE - 1) / 2 / scale
				if
					start + distance < entranceDistance + spacing
					and entranceLow
					and t >= entranceLow
					and t <= entranceHigh
					and EntranceClear(x1 + t * dx, y1 + t * dy, extra)
				then
					size, radius = dot * ENTRANCE_SCALE, half * ENTRANCE_SCALE
				end
				entranceDistance = nil
			end
			Stroke(
				x1 + (t - radius) * dx,
				y1 + (t - radius) * dy,
				x1 + (t + radius) * dx,
				y1 + (t + radius) * dy,
				ink,
				true,
				size
			)
		end
	end
end

-- A line between two map fractions, clipped to the map and the view. Over OpenMap's stitched map the view runs past
-- the host map into its neighbours, so the map does not clip there.
local function Line(x1, y1, x2, y2, color, dashed, a, b)
	local reach = dot / 2 + dotRim
	local mx = dashed and reach / scale / width or 0
	local my = dashed and reach / scale / height or 0
	---@type number?, number?
	local low, high = ClipAxis(x1, x2 - x1, 0, 1, minX + mx, maxX - mx)
	if low then
		low, high = ClipAxis(y1, y2 - y1, low, high, minY + my, maxY - my)
	end
	local entranceLow, entranceHigh
	if dashed and b and ((b.depth and not a.depth) or (a.depth and entranceDistance)) then
		local extra = (dot * ENTRANCE_SCALE / 2 + dotRim) / scale
		entranceLow, entranceHigh = ClipAxis(x1, x2 - x1, 0, 1, minX + extra / width, maxX - extra / width)
		if entranceLow then
			entranceLow, entranceHigh =
				ClipAxis(y1, y2 - y1, entranceLow, entranceHigh, minY + extra / height, maxY - extra / height)
		end
	end
	Segment(
		x1 * width,
		-y1 * height,
		x2 * width,
		-y2 * height,
		low,
		high,
		color,
		dashed,
		a,
		b,
		entranceLow,
		entranceHigh
	)
end

-- A short walk between stops can have every spaced breadcrumb fall inside the gaps at its ends although there is room
-- between them. It is dotted again with the one dot at its middle.
---@param view SPFMapView
local function MiddleDot(view, path, points, color)
	local usual = spacing
	spacing, phase, walked, entranceDistance = walked, walked / 2, 0, nil
	local previous, px, py
	for index = 1, #points do
		local point = points[index]
		local x, y = view.position(point, view.mapID)
		if px and x then
			Line(px, py, x, y, color, true, not path.preview and previous or nil, not path.preview and point or nil)
		end
		previous, px, py = point, x, y
	end
	spacing, phase = usual, 0
end

-- The segment of a tour's walk still waiting to learn whether it ends in a bend: its ends, as map fractions, and its
-- length before any cut, in the view's units.
local held, hx1, hy1, hx2, hy2, hlength = false, 0, 0, 0, 0, 0

local function Flush(color)
	if held then
		held = false
		Line(hx1, hy1, hx2, hy2, color)
	end
end

-- A tour's walk, one segment at a time: where the next one carries on from the held one, both are cut back from the
-- bend and joined by a curve around it. Ends and breaks in the walk stay exact.
local function Soft(x1, y1, x2, y2, color)
	local length = math.sqrt(((x2 - x1) * width) ^ 2 + ((y2 - y1) * height) ^ 2)
	if length == 0 then
		return
	end
	local startX, startY = x1, y1
	if held and hx2 == x1 and hy2 == y1 then
		-- A straight run needs no curve, and no extra strokes.
		local cross = (x1 - hx1) * (y2 - y1) - (y1 - hy1) * (x2 - x1)
		if math.abs(cross) * width * height > 0.01 * hlength * length then
			local cut = math.min(TOUR_CUT / scale, TOUR_CUT_SHARE * hlength, TOUR_CUT_SHARE * length)
			local ax, ay = x1 + (hx1 - x1) * cut / hlength, y1 + (hy1 - y1) * cut / hlength
			startX, startY = x1 + (x2 - x1) * cut / length, y1 + (y2 - y1) * cut / length
			held = false
			Line(hx1, hy1, ax, ay, color)
			local px, py = ax, ay
			local steps = math.max(1, math.min(TOUR_STEPS, math.floor(cut * scale / TOUR_STEP)))
			for step = 1, steps do
				local t = step / steps
				local x = (1 - t) ^ 2 * ax + 2 * (1 - t) * t * x1 + t ^ 2 * startX
				local y = (1 - t) ^ 2 * ay + 2 * (1 - t) * t * y1 + t ^ 2 * startY
				Line(px, py, x, y, color)
				px, py = x, y
			end
		end
	end
	Flush(color)
	held, hx1, hy1, hx2, hy2, hlength = true, startX, startY, x2, y2, length
end

-- A small cross where a hop with no line of its own (a portal, a preview across the sea) leaves or lands.
local function Mark(x, y, color)
	if x and (wide or (x >= 0 and x <= 1 and y >= 0 and y <= 1)) then
		local size = 4 / scale
		local dx, dy = size / width, size / height
		Line(x - dx, y, x + dx, y, color)
		Line(x, y - dy, x, y + dy, color)
	end
end

-- Smooth loading-screen bridges. The control follows the last sampled direction of travel.
local function Curve(ax, ay, bx, by, cx, cy, color, fading)
	local px, py = ax, ay
	for step = 1, 12 do
		local t = step / 12
		local x = (1 - t) ^ 2 * ax + 2 * (1 - t) * t * cx + t ^ 2 * bx
		local y = (1 - t) ^ 2 * ay + 2 * (1 - t) * t * cy + t ^ 2 * by
		fade = fading and (1 - (step - 0.5) / 12) or 1
		Line(px, py, x, y, color)
		px, py = x, y
	end
	fade = 1
end

local function CrossingCurve(ax, ay, bx, by, color, px, py)
	local dx, dy = bx - ax, by - ay
	local cx, cy = (ax + bx) / 2 - dy * 0.25, (ay + by) / 2 + dx * 0.25
	if px then
		local tx, ty = ax - px, ay - py
		local length = math.sqrt(tx * tx + ty * ty)
		if length > 0 then
			local reach = math.sqrt(dx * dx + dy * dy) * 0.6 / length
			cx, cy = ax + tx * reach, ay + ty * reach
		end
	else
		-- Overview crossings arc toward open sea to the north, identically in either travel direction.
		local side = dx < 0 and -1 or 1
		cx, cy = (ax + bx) / 2 + dy * side * 0.6, (ay + by) / 2 - dx * side * 0.6
	end
	if math.abs((cx - ax) * dy - (cy - ay) * dx) < (dx * dx + dy * dy) * 0.1 then
		cx, cy = (ax + bx) / 2 - dy * 0.25, (ay + by) / 2 + dx * 0.25
	end
	Curve(ax, ay, bx, by, cx, cy, color)
end

local function EdgeCurve(x, y, nx, ny, color)
	if not nx then
		return
	end
	local dx, dy = x - nx, y - ny
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 0.000001 then
		return
	end
	dx, dy = dx / length, dy / length
	-- Bend gently out to sea while retaining the sampled tangent at the loading point.
	local ex, ey = dx - dy * 0.3, dy + dx * 0.3
	local distance = math.huge
	if ex ~= 0 then
		distance = math.min(distance, ((ex > 0 and 1 or 0) - x) / ex)
	end
	if ey ~= 0 then
		distance = math.min(distance, ((ey > 0 and 1 or 0) - y) / ey)
	end
	if distance > 0 and distance < math.huge then
		local cx, cy = x + dx * distance * 0.55, y + dy * distance * 0.55
		Curve(x, y, x + ex * distance, y + ey * distance, cx, cy, color, true)
	end
end

---@param view SPFMapView
local function Bridge(view, points, index, ax, ay, bx, by, color)
	local before, after = points[index - 2] or points[#points - 1], points[index + 1] or points[2]
	local px, py, nx, ny
	if before and before.map == points[index - 1].map then
		px, py = view.position(before, view.mapID)
	end
	if after and after.map == points[index].map then
		nx, ny = view.position(after, view.mapID)
	end
	if ax and bx then
		CrossingCurve(ax, ay, bx, by, color, px, py)
	elseif ax then
		EdgeCurve(ax, ay, px, py, color)
	elseif bx then
		EdgeCurve(bx, by, nx, ny, color)
	end
end

---@param view SPFMapView
local function OverviewCrossing(view, path, color)
	if path.mode ~= "boat" and path.mode ~= "zeppelin" then
		return false
	end
	local first, last = path.points[1], path.points[#path.points]
	if not first or first.map == last.map then
		return false
	end
	local ax, ay = view.position(first, view.mapID)
	local bx, by = view.position(last, view.mapID)
	if ax and bx then
		CrossingCurve(ax, ay, bx, by, color)
		return true
	end
	return false
end

-- The paths as the world map shows them at this view: lines clipped to the map and the view, walks as breadcrumbs with
-- a gap at each stop mark, sea crossings as curves and hops with no line of their own as marks.
---@param buffer SPFStrokes
---@param paths SPFDrawPath[]
---@param view SPFMapView
function Strokes.Map(buffer, paths, view)
	Begin(buffer, view.scale, view.small, view.stitched)
	width, height = view.width, view.height
	if view.clipLeft then
		minX, maxX = math.max(minX, view.clipLeft), math.min(maxX, view.clipRight)
		minY, maxY = math.max(minY, view.clipTop), math.min(maxY, view.clipBottom)
	end
	-- The journey's stop pins keep their size on screen while the canvas zooms under them (MapCanvasPinMixin's
	-- ApplyCurrentScale sets 1 / canvas scale), so their reach in canvas units grows as the map zooms out.
	if view.marks then
		for _, mark in ipairs(view.marks) do
			Circle(mark.x * width, -mark.y * height, mark.radius / view.zoom)
		end
	end
	local mapID, position = view.mapID, view.position
	for pathIndex, path in ipairs(paths) do
		local color = path.color or view.colors[path.mode]
		route = path.route
		fade = path.placeholder and 0.45 or 1
		later = pathIndex > view.current and (view.tour and TOUR_LATER_ALPHA or LATER_ALPHA) or 1
		-- A stop under the pointer shows its own leg at full strength, so the faded way ahead answers the cursor.
		if view.highlight and path.stop and view.highlight[path.stop] then
			later = 1
		end
		walked, entranceDistance = 0, nil
		local previous, px, py
		local points = ns.FlightLinePoints(path)
		local crossing = OverviewCrossing(view, path, color)
		local apart = path.mode == "flight" and not path.preview and FLIGHT_APART
			or path.mode == "walk" and not WalkingRouteDotted(view.tour) and WALK_APART
		local drawn, broken = out.n, false
		inView = false
		for index = 1, crossing and 0 or #points do
			local point = points[index]
			local x, y = position(point, mapID)
			local after = points[index + 1]
			-- Smoothed flight points and terrain walk steps can be about a pixel apart or less on the world map.
			-- Keep longer connected strokes, retaining endpoints and loading boundaries.
			local short = apart
				and after
				and previous
				and not previous.jump
				and not point.jump
				and previous.map == point.map
				and after.map == point.map
				and px
				and py
				and x
				and y
				and ((x - px) * width) ^ 2 + ((y - py) * height) ^ 2 < (apart / scale) ^ 2
			if not short then
				if path.mode == "portal" or path.mode == "passage" then
					Mark(x, y, color)
				elseif previous then
					broken = broken
						or not (px and x and previous.map == point.map and (path.preview or not previous.jump))
					if path.preview then
						-- A hop still planning has no geometry to draw; a straight line would cross the sea.
						if previous.map ~= point.map then
							Flush(color)
							Mark(px, py, color)
							Mark(x, y, color)
						elseif px and x then
							if view.tour then
								Soft(px, py, x, y, color)
							else
								Line(px, py, x, y, color, true)
							end
						end
					elseif previous.jump or previous.map ~= point.map then
						Flush(color)
						entranceDistance = nil
						if path.mode == "boat" or path.mode == "zeppelin" then
							Bridge(view, path.points, index, px, py, x, y, color)
						else
							Mark(px, py, color)
							Mark(x, y, color)
						end
					elseif px and x then
						if view.tour and path.mode == "walk" then
							Soft(px, py, x, y, color)
						else
							Line(px, py, x, y, color, path.mode == "walk" and WalkingRouteDotted(), previous, point)
						end
					else
						entranceDistance = nil
					end
				end
				previous, px, py = point, x, y
			end
		end
		Flush(color)
		if path.mode == "walk" and inView and not broken and out.n == drawn then
			MiddleDot(view, path, points, color)
		end
	end
end

local function ClipMinimap(x, y, dx, dy, inset, square)
	if square then
		local low, high = ClipAxis(x, dx, 0, 1, -inset, inset)
		if low then
			return ClipAxis(y, dy, low, high, -inset, inset)
		end
		return nil
	end
	local a, b, c = dx * dx + dy * dy, x * dx + y * dy, x * x + y * y - inset * inset
	local discriminant = b * b - a * c
	if a == 0 or discriminant <= 0 then
		return nil
	end
	local root = math.sqrt(discriminant)
	local low, high = math.max(0, (-b - root) / a), math.min(1, (-b + root) / a)
	if low < high then
		return low, high
	end
end

-- A world point on a minimap centred on x, y and turned by the facing whose cosine and sine these are: -1 to 1
-- across its face, x right and y up. The minimap's transport pins share it.
---@param point SPFPoint
---@return number, number
function Strokes.Project(point, x, y, radius, cosine, sine)
	-- UnitPosition's X is north, Y is west; minimap X is right, Y is up.
	local east, north = y - point.y, point.x - x
	return (east * cosine + north * sine) / radius, (north * cosine - east * sine) / radius
end
local Project = Strokes.Project

-- The paths on the player's own map as the minimap shows them, clipped to its face. Returns where the goal's mark
-- sits, as Project gives it: on the face (the dots leave a gap around it), or on the rim towards a goal off it.
---@param buffer SPFStrokes
---@param paths SPFDrawPath[]
---@param view SPFMinimapView
---@return number? x, number? y, boolean? edge the goal is off the minimap and its mark waits on the rim
function Strokes.Minimap(buffer, paths, view)
	Begin(buffer, view.scale)
	local walkSize = view.walkSize
	if type(walkSize) == "number" and walkSize == walkSize then
		local walkScale = math.max(25, math.min(100, walkSize)) / 100
		dot, dotRim = dot * walkScale, dotRim * walkScale
	end
	local x, y, map, radius, facing = view.x, view.y, view.map, view.radius, view.facing
	local square, goal = view.square, view.goal
	width, height = view.width, view.height
	local border = UNDER_THICKNESS / scale
	if not (x and facing and radius and radius > 0 and width > border and height > border) then
		return nil
	end
	local cosine, sine = math.cos(facing), math.sin(facing)
	gapped = view.tour == true
	-- The player's arrow sits at the centre of the minimap: no breadcrumb is centred under it, so the route never
	-- hides which way the player faces. Only the arrow's own radius, not a stop's full gap, so a ten-yard approach
	-- still has room for dots (#74).
	Avoid(width / 2, -height / 2, PLAYER_ARROW)
	local markX, markY, edge
	if goal and goal.map == map and not goal.corpse then
		local gx, gy = Project(goal, x, y, radius, cosine, sine)
		-- The mark's whole ring stays inside the face: nearer the rim than that, it waits on the rim in the goal's
		-- direction, and past the rim (off the minimap) it says so with `edge`. The dots leave a gap around it
		-- wherever it sits.
		local rim = 1 - view.goalRadius / (math.min(width, height) / 2)
		local reach = square and math.max(math.abs(gx), math.abs(gy)) or math.sqrt(gx * gx + gy * gy)
		if rim > 0 then
			local pull = reach > rim and rim / reach or 1
			markX, markY, edge = gx * pull, gy * pull, reach > 1 or nil
			Circle((markX + 1) * width / 2, (markY - 1) * height / 2, view.goalRadius)
		end
	end
	local shortestSide = math.min(width, height)
	local inset = 1 - border / shortestSide
	local dotted = WalkingRouteDotted(view.tour)
	local walkInset = dotted and inset - (dot + dotRim * 2) / scale / shortestSide or inset
	for _, path in ipairs(paths) do
		walked, entranceDistance = 0, nil
		fade = path.placeholder and 0.45 or 1
		if path.mode ~= "portal" and path.mode ~= "passage" then
			local points = ns.FlightLinePoints(path)
			local color = path.color or view.colors[path.mode]
			local walk = path.mode == "walk"
			for index = 2, #points do
				local a, b = points[index - 1], points[index]
				if a.map == map and b.map == map and not a.jump then
					local ax, ay = Project(a, x, y, radius, cosine, sine)
					local bx, by = Project(b, x, y, radius, cosine, sine)
					local within = dotted and walk and walkInset or inset
					local low, high = ClipMinimap(ax, ay, bx - ax, by - ay, within, square)
					local entranceLow, entranceHigh
					if dotted and walk and ((b.depth and not a.depth) or (a.depth and entranceDistance)) then
						local extra = dot * (ENTRANCE_SCALE - 1) / scale / shortestSide
						entranceLow, entranceHigh = ClipMinimap(ax, ay, bx - ax, by - ay, within - extra, square)
					end
					Segment(
						(ax + 1) * width / 2,
						(ay - 1) * height / 2,
						(bx + 1) * width / 2,
						(by - 1) * height / 2,
						low,
						high,
						color,
						walk and dotted,
						a,
						b,
						entranceLow,
						entranceHigh
					)
				else
					entranceDistance = nil
				end
			end
		end
	end
	-- Keep the final few yards visible when the goal ring covers every breadcrumb.
	if goal and goal.hold and not gapped and goal.map == map and out.n == 0 then
		local gx, gy = Project(goal, x, y, radius, cosine, sine)
		local distance = gx * gx + gy * gy
		if distance > 0 and distance < 0.25 then
			Stroke(width / 2, -height / 2, (gx + 1) * width / 2, (gy - 1) * height / 2, view.colors.walk)
		end
	end
	return markX, markY, edge
end

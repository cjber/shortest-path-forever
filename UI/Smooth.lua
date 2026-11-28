---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- A tour's walks as one flowing line: each walk keeps only the bends that matter, and a curve runs through what is
-- left, walk after walk. Geometry only, in the view's own units; Strokes.lua draws it.
--
-- Screen pixels: a walk drops a bend within TOLERANCE of the line past it; points closer than APART are one, as the
-- client draws nothing for a sliver of a line; walks ending within JOIN of each other are one line; and the curve is
-- drawn in chords about STEP long.
local TOLERANCE, APART, JOIN, STEP = 6, 2.5, 12, 4

-- A segment's look, handed back with each of its chords.
---@class SPFSmoothStyle
---@field rank number lower ranks are drawn first, beneath

---@class SPFSmooth
local Smooth = {}
ns.Smooth = Smooth

-- The line's control points in order. style[i] and depth[i] are those of the segment ending at point i, which a point
-- starting a new line has none of; ending[i] marks the last point of a walk.
---@type number[], number[], (SPFSmoothStyle|false)[], (number|false)[], boolean[]
local xs, ys, styles, depths, ending = {}, {}, {}, {}, {}
local count, scale = 0, 1
-- Simplify's scratch: the points it keeps, and the spans still to look at.
---@type boolean[], number[]
local keep, spans = {}, {}

---@param viewScale number screen pixels per unit
function Smooth.Begin(viewScale)
	count, scale = 0, viewScale
end

-- Ramer, Douglas and Peucker: keep[i] is set for the points the line needs to stay within the tolerance of them all.
local function Simplify(x, y, last, tolerance)
	for i = 1, last do
		keep[i] = i == 1 or i == last
	end
	spans[1], spans[2] = 1, last
	local top = 2
	while top > 0 do
		local a, b = spans[top - 1], spans[top]
		top = top - 2
		local dx, dy = x[b] - x[a], y[b] - y[a]
		local squared = dx * dx + dy * dy
		local worst, at = tolerance * tolerance, nil
		for i = a + 1, b - 1 do
			local t = squared > 0 and math.max(0, math.min(1, ((x[i] - x[a]) * dx + (y[i] - y[a]) * dy) / squared)) or 0
			local ex, ey = x[a] + t * dx - x[i], y[a] + t * dy - y[i]
			if ex * ex + ey * ey > worst then
				worst, at = ex * ex + ey * ey, i
			end
		end
		if at then
			keep[at] = true
			spans[top + 1], spans[top + 2], spans[top + 3], spans[top + 4] = a, at, at, b
			top = top + 4
		end
	end
end

local function Add(x, y, style, depth, first, last)
	local far = math.huge
	if count > 0 then
		far = math.sqrt((x - xs[count]) ^ 2 + (y - ys[count]) ^ 2) * scale
	end
	if far < APART then
		-- A walk's own end stands in for a nearby bend, so lines meet where the walks do.
		if last and not ending[count] then
			xs[count], ys[count], ending[count] = x, y, true
		end
		return
	end
	count = count + 1
	local starts = first and far > JOIN
	xs[count], ys[count], ending[count] = x, y, last
	styles[count], depths[count] = not starts and style, not starts and depth or false
end

-- One walk, or one stretch of it under or out of cover: its points in order. `exact` keeps every point, as for a
-- straight placeholder through the stops themselves.
---@param x number[]
---@param y number[]
---@param depth (number|false)[]
---@param points number
---@param style SPFSmoothStyle
---@param exact boolean?
function Smooth.Walk(x, y, depth, points, style, exact)
	if points < 2 then
		return
	end
	if not exact then
		Simplify(x, y, points, TOLERANCE / scale)
		-- Where the walk goes under cover or comes out stays, with the point before it.
		for i = 2, points do
			if (depth[i] ~= false) ~= (depth[i - 1] ~= false) then
				keep[i], keep[i - 1] = true, true
			end
		end
	end
	local previous = depth[1]
	for i = 1, points do
		if exact or keep[i] then
			local under = depth[i] and previous and (depth[i] + previous) / 2
			Add(x[i], y[i], style, under or false, i == 1, i == points)
			previous = depth[i]
		end
	end
end

-- The next walk does not carry on from the last, however near it starts.
function Smooth.Break()
	if count > 0 then
		count = count + 1
		xs[count], ys[count], styles[count], depths[count], ending[count] = math.huge, math.huge, false, false, true
	end
end

local function Knot(ax, ay, bx, by)
	-- Centripetal: the square root of the distance, never nothing, so a line's doubled end point divides safely.
	return math.max((bx - ax) ^ 2 + (by - ay) ^ 2, 1e-8) ^ 0.25
end

local function Mix(a, b, from, to, at)
	return (a * (to - at) + b * (at - from)) / (to - from)
end

-- The chords of the segment ending at point i, along the centripetal Catmull-Rom curve through its neighbours.
local function Curve(i, emit)
	local x1, y1, x2, y2 = xs[i - 1], ys[i - 1], xs[i], ys[i]
	local x0, y0, x3, y3 = x1, y1, x2, y2
	if styles[i - 1] then
		x0, y0 = xs[i - 2], ys[i - 2]
	end
	if i < count and styles[i + 1] then
		x3, y3 = xs[i + 1], ys[i + 1]
	end
	local style, depth = styles[i], depths[i]
	local t1 = Knot(x0, y0, x1, y1)
	local t2 = t1 + Knot(x1, y1, x2, y2)
	local t3 = t2 + Knot(x2, y2, x3, y3)
	local steps = math.max(1, math.ceil(math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) * scale / STEP))
	local px, py = x1, y1
	for step = 1, steps do
		local x, y = x2, y2
		if step < steps then
			local t = t1 + (t2 - t1) * step / steps
			local ax, bx, cx = Mix(x0, x1, 0, t1, t), Mix(x1, x2, t1, t2, t), Mix(x2, x3, t2, t3, t)
			local ay, by, cy = Mix(y0, y1, 0, t1, t), Mix(y1, y2, t1, t2, t), Mix(y2, y3, t2, t3, t)
			x = Mix(Mix(ax, bx, 0, t2, t), Mix(bx, cx, t1, t3, t), t1, t2, t)
			y = Mix(Mix(ay, by, 0, t2, t), Mix(by, cy, t1, t3, t), t1, t2, t)
		end
		-- The curve's speed varies along it; a stretch of under a pixel is drawn with the next.
		if step == steps or ((x - px) ^ 2 + (y - py) ^ 2) * scale * scale >= 1 then
			emit(px, py, x, y, style, depth)
			px, py = x, y
		end
	end
end

-- Every chord of the segments of one rank, in the line's order. Segments wholly outside the box are passed over.
---@param rank number
---@param left number
---@param right number
---@param bottom number
---@param top number
---@param emit fun(x1: number, y1: number, x2: number, y2: number, style: SPFSmoothStyle, depth: number|false)
function Smooth.Draw(rank, left, right, bottom, top, emit)
	for i = 2, count do
		local style = styles[i]
		if style and style.rank == rank then
			local x1, y1, x2, y2 = xs[i - 1], ys[i - 1], xs[i], ys[i]
			-- The curve strays less than its chord's length from its ends.
			local reach = math.abs(x2 - x1) + math.abs(y2 - y1)
			if
				math.max(x1, x2) + reach >= left
				and math.min(x1, x2) - reach <= right
				and math.max(y1, y2) + reach >= bottom
				and math.min(y1, y2) - reach <= top
			then
				Curve(i, emit)
			end
		end
	end
end

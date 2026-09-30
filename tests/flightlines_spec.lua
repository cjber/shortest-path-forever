local ns = {}
assert(loadfile("UI/FlightLines.lua"))("ShortestPathForever", ns)
local a, b, c = { map = 0, x = 0, y = 0 }, { map = 0, x = 1, y = 0 }, { map = 0, x = 1, y = 1 }
local path = { mode = "flight", points = { a, b, c } }
local points = ns.FlightLinePoints(path)
assert(points[1] == a and points[#points] == c, "flight endpoints stay exact")
assert(#points > #path.points and ns.FlightLinePoints(path) == points, "curves are cached for redraws")
local biggest = 0
for i, p in ipairs(points) do
	assert(p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1, "no overshoot")
	local prev, nextPoint = points[i - 1], points[i + 1]
	if prev and nextPoint then
		local ax, ay, bx, by = p.x - prev.x, p.y - prev.y, nextPoint.x - p.x, nextPoint.y - p.y
		local length = math.sqrt((ax * ax + ay * ay) * (bx * bx + by * by))
		if length > 0 then
			biggest = math.max(biggest, math.acos(math.min(1, (ax * bx + ay * by) / length)))
		end
	end
end
assert(biggest < math.pi / 8, "a ninety-degree corner is smoothed into gentle turns")
assert(path.points[2] == b and b.x == 1 and b.y == 0, "source navigation geometry is untouched")
for _, mode in ipairs({ "walk", "boat", "portal" }) do
	local other = { mode = mode, points = path.points }
	assert(ns.FlightLinePoints(other) == other.points, "only flights are smoothed")
end
local preview = { mode = "flight", points = path.points, preview = true }
assert(ns.FlightLinePoints(preview) == preview.points, "unknown preview geometry is unchanged")
local jump = { map = 0, x = 1, y = 0, jump = 1 }
local foreign = { map = 1, x = 9, y = 9 }
local split = ns.FlightLinePoints({ mode = "flight", points = { a, jump, c, foreign } })
assert(#split == 4 and split[2] == jump and split[3] == c, "never round through a jump or map boundary")
for _, source in ipairs({ {}, { a }, { a, a }, { a, b } }) do
	local result = ns.FlightLinePoints({ mode = "flight", points = source })
	assert(#result == #source, "short and duplicate paths are safe")
end
print("flightlines_spec: ok")

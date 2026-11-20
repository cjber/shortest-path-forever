---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- A plan's legs as world points to draw and follow, kept apart from the search that chooses them.
local Model = ns.Model
---@class SPFPlanner
local Planner = ns.Planner

-- Preview geometry while a walking leg is still pending.
---@param from SPFPoint
---@param to SPFPoint
---@return SPFWalkPoints
function Planner.WalkPoints(from, to)
	return { { map = from.map, x = from.x, y = from.y }, { map = to.map, x = to.x, y = to.y } }
end

-- Whether a walk's searched cost (a reason or nil when it has no route) contradicts the leg's planned yards. An
-- estimated leg holds a lower bound, which a longer or unreachable walk refutes without contradicting: a search that
-- outlasts the grace period shows such a candidate, and only its proof decides.
---@param leg SPFLeg
---@param cost number|string?
---@return boolean
function Planner.WalkContradicts(leg, cost)
	local tolerance = math.max(1, leg.yards * 0.1)
	if type(cost) ~= "number" then
		return not leg.estimated
	elseif leg.estimated then
		return cost < leg.yards - tolerance
	end
	return math.abs(cost - leg.yards) > tolerance
end

-- World points in travel order; jump marks a teleport to the next point. Keep this free of map APIs.
---@param leg SPFLeg
---@param routes table<number, SPFRoute>
---@return SPFWalkPoints
function Planner.LegPoints(leg, routes)
	if leg.mode == "walk" then
		return leg.walkPoints or Planner.WalkPoints(leg.from, leg.to)
	end
	local points = { { map = leg.from.map, x = leg.from.x, y = leg.from.y } }
	if leg.mode == "flight" then
		for _, hop in ipairs(leg.hops or {}) do
			for i = 1, #hop.points, 3 do
				points[#points + 1] = { map = hop.points[i], x = hop.points[i + 1], y = hop.points[i + 2] }
			end
		end
	elseif leg.mode == "teleport" then
		-- Nothing to draw between the ends: a jump, marked at both.
		points[1].jump = 1
	elseif leg.route then
		local route = routes[leg.route]
		local boarding, alighting = leg.boarding, leg.alighting
		if route and route.frames and leg.aboard and alighting then
			-- Only the remaining geometry, including any continent jump ahead of the player.
			local remaining = leg.arrive - leg.depart
			local ordered = {}
			for index, frame in ipairs(route.frames) do
				local untilDock = (alighting.arrive - frame[1]) % route.period
				if untilDock > 0 and untilDock < remaining then
					ordered[#ordered + 1] = { frame = frame, remaining = untilDock, index = index }
				end
			end
			table.sort(ordered, function(a, b)
				return a.remaining > b.remaining or (a.remaining == b.remaining and a.index < b.index)
			end)
			for _, entry in ipairs(ordered) do
				local frame = entry.frame
				points[#points + 1] = { map = frame[3], x = frame[4], y = frame[5], jump = frame[6] }
			end
		elseif route and route.frames and boarding and alighting then
			local duration = Model.RideTime(route, boarding, alighting)
			for index, frame in ipairs(route.frames) do
				if frame[2] % route.period == boarding.depart % route.period then
					points[1].jump = frame[6]
					for offset = 1, #route.frames - 1 do
						local nextFrame = route.frames[(index + offset - 1) % #route.frames + 1]
						local elapsed = (nextFrame[1] - boarding.depart) % route.period
						if elapsed >= duration then
							break
						end
						points[#points + 1] = {
							map = nextFrame[3],
							x = nextFrame[4],
							y = nextFrame[5],
							jump = nextFrame[6],
						}
					end
					break
				end
			end
		end
	end
	-- Portal endpoints are drawn as separate marks.
	points[#points + 1] = { map = leg.to.map, x = leg.to.x, y = leg.to.y }
	return points
end

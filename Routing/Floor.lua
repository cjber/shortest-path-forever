---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- The player's floor. The client gives no player height (UnitPosition's is a placeholder 0), so a search from where
-- you stand starts from every surface near you and keeps the cheapest: under the Ruins of Lordaeron that is the
-- ruins, and on the Undercity's rings a walkway above you. Floor follows the surfaces you can be on as you move
-- instead: a surface stays a candidate while the walking map has a way from it to each new cell you reach, and a cell
-- with one surface settles it. Once the candidates are one floor, Height gives its height and the search starts on it
-- (Path.lua's snap takes the surface nearest a height). Until then, and wherever it cannot tell, searches start as
-- before.
-- Reading a cell never decodes: the clusters around you are decoded by a job under the walking search's frame budget
-- (Path.Decode) and kept while you are followed (Path.Pin).
---@class SPFFloor
local Floor = {}
ns.Floor = Floor

local Path, Grid = ns.Path, ns.PathGrid
local floor, max, min, abs, huge = math.floor, math.max, math.min, math.abs, math.huge

local SAME = 3 -- surfaces this close in height (yd) are one floor: the baker keeps floors at least this far apart
local NEAR = 8 -- yd from the last sample within which Height still answers: a second's run, about one cell
local JUMP = 30 -- yd since the last sample: a hearth, teleport, landing or loading screen; the floor is unknown again
local REACH = 6 -- cells between samples beyond which the step is a jump too
local RISE = 4 -- a fall lands on the highest surface at most this many yards above the floor it left
local LIFT = 10 -- yd from a lift's landing: a lift changes floor without moving, so the floor is unknown there
local FIRST_LIFT = 1001 -- Data/Transports.lua numbers lift and tram landings from here

---@class SPFFloorSurface
---@field k number cluster
---@field node number node in the cluster
---@field z number height

---@class SPFFloorState
---@field map number
---@field gx number global cell
---@field gy number
---@field x number last sample
---@field y number
---@field nodes SPFFloorSurface[] the surfaces you may be on

---@type SPFFloorState?
local here
local decoding -- the queued Path.Decode job, one at a time

-- Cluster and local cell of global cell (gx, gy).
local function Cell(st, gx, gy)
	local C = st.C
	return floor(gx / C) * st.ny + floor(gy / C), (gx % C) * C + gy % C
end

-- Every surface of a decoded cell: the base surface, then its floors.
local function Surfaces(st, gx, gy)
	local k, lc = Cell(st, gx, gy)
	local val, z, at = st.val[k], st.z[k], st.at[k]
	local out = {}
	if not val then
		return out
	end
	if val[lc + 1] ~= 0 then
		out[1] = { k = k, node = lc, z = z[lc + 1] }
	end
	local node = at[-(lc + 1)]
	while node and at[node + 1] == lc do
		out[#out + 1] = { k = k, node = node, z = z[node + 1] }
		node = node + 1
	end
	return out
end

-- The surfaces of cell (gx, gy) the walking map reaches within reach steps from nodes at cell (ox, oy), staying in
-- the box around both cells. Water steps count: you may have swum.
local function Step(st, nodes, ox, oy, gx, gy, reach)
	local x0, x1, y0, y1 = min(ox, gx) - 1, max(ox, gx) + 1, min(oy, gy) - 1, max(oy, gy) + 1
	local seen, queue, found = {}, {}, {}
	for _, s in ipairs(nodes) do
		local id = s.k * 1048576 + s.node
		if not seen[id] then
			seen[id] = true
			queue[#queue + 1] = { s.k, s.node, ox, oy, 0 }
		end
	end
	local head = 1
	while queue[head] do
		local q = queue[head]
		local k, node, x, y, depth = q[1], q[2], q[3], q[4], q[5]
		head = head + 1
		if x == gx and y == gy then
			found[#found + 1] = { k = k, node = node, z = st.z[k][node + 1] }
		end
		if depth < reach then
			for dx = -1, 1 do
				for dy = -1, 1 do
					local nx, ny = x + dx, y + dy
					if (dx ~= 0 or dy ~= 0) and nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1 then
						local tk, tn = Grid.neighbour(st, k, node, x, y, dx, dy, true)
						local id = tk and tk * 1048576 + tn
						if id and not seen[id] then
							seen[id] = true
							queue[#queue + 1] = { tk, tn, nx, ny, depth + 1 }
						end
					end
				end
			end
		end
	end
	return found
end

-- The walking map has no way down a ledge, so a step it does not allow is a fall (or a knockback): the highest
-- surface of the new cell not far above the floor you left. None: the floor is unknown.
local function Fall(st, nodes, gx, gy)
	local top = -huge
	for _, s in ipairs(nodes) do
		top = max(top, s.z)
	end
	local best
	for _, s in ipairs(Surfaces(st, gx, gy)) do
		if s.z <= top + RISE and (not best or s.z > best.z) then
			best = s
		end
	end
	return best and { best } or {}
end

-- A lift changes floor without moving you on the map.
local function NearLift()
	if not ns.NearestDock then
		return false
	end
	local dock, yards = ns.NearestDock()
	return dock ~= nil and dock >= FIRST_LIFT and yards ~= nil and yards <= LIFT
end

---Stop following: the floor is unknown and the clusters kept for it can go.
function Floor.Forget()
	here = nil
	if Path and Path.Pin then
		Path.Pin()
	end
end

---Follow the player to (x, y) on map. Cheap: only cells already decoded are read; missing clusters are queued for
---decoding and the step waits for them.
---@param map number
---@param x number
---@param y number
function Floor.Sample(map, x, y)
	if not (Grid and Path and Path.HasData(map)) or UnitOnTaxi("player") or NearLift() then
		return Floor.Forget()
	end
	if InCombatLockdown() then
		return
	end
	local st = Grid.State(map)
	if not st then
		return Floor.Forget()
	end
	local gx, gy = floor((x - st.x0) / st.cs), floor((y - st.y0) / st.cs)
	if gx < 0 or gy < 0 or gx >= st.GX or gy >= st.GY then
		return Floor.Forget()
	end
	local last = here
	if last and last.map == map and last.gx == gx and last.gy == gy then
		last.x, last.y = x, y
		return
	end
	local steps = last and last.map == map and max(abs(gx - last.gx), abs(gy - last.gy))
	if not (last and steps) or steps > REACH or (x - last.x) ^ 2 + (y - last.y) ^ 2 > JUMP ^ 2 then
		last = nil
	end
	-- Every cluster the step reads: neighbour looks one cell past the box Step walks.
	local ox, oy = last and last.gx or gx, last and last.gy or gy
	local keep, missing = {}, {}
	for cx = min(ox, gx) - 2, max(ox, gx) + 2 do
		for cy = min(oy, gy) - 2, max(oy, gy) + 2 do
			if cx >= 0 and cy >= 0 and cx < st.GX and cy < st.GY then
				local k = Cell(st, cx, cy)
				if not keep[k] then
					keep[k] = true
					if not Grid.Ready(st, k) then
						missing[#missing + 1] = k
					end
				end
			end
		end
	end
	Path.Pin(map, keep)
	if #missing > 0 then
		if not decoding then
			decoding = Path.Decode(map, missing, function()
				decoding = nil
			end)
		end
		-- The step waits for its clusters; a fresh start is unknown meanwhile.
		if not last then
			here = nil
		end
		return
	end
	local nodes
	if last then
		nodes = Step(st, last.nodes, ox, oy, gx, gy, steps + 1)
		if #nodes == 0 then
			nodes = Fall(st, last.nodes, gx, gy)
		end
	end
	if not nodes or #nodes == 0 then
		nodes = Surfaces(st, gx, gy)
	end
	-- Swimming, you are on a water surface.
	if #nodes > 1 and IsSwimming and IsSwimming() then
		local wet = {}
		for _, s in ipairs(nodes) do
			if st.val[s.k][s.node + 1] == 2 then
				wet[#wet + 1] = s
			end
		end
		if #wet > 0 then
			nodes = wet
		end
	end
	here = { map = map, gx = gx, gy = gy, x = x, y = y, nodes = nodes }
end

---The height of the floor you are on at (x, y) on map, when it is known: nil while the surfaces you may be on lie on
---more than one floor, away from the last sample, or not followed.
---@param map number
---@param x number
---@param y number
---@return number?
function Floor.Height(map, x, y)
	local h = here
	if not h or h.map ~= map or #h.nodes == 0 or (h.x - x) ^ 2 + (h.y - y) ^ 2 > NEAR ^ 2 then
		return nil
	end
	local low, high = huge, -huge
	for _, s in ipairs(h.nodes) do
		low, high = min(low, s.z), max(high, s.z)
	end
	return high - low <= SAME and high or nil
end

-- Indoors, where floors stack, the floor is followed whenever you move, so a journey planned there starts on it. A
-- journey's own frame follows it everywhere else (Journey.lua); outdoors with none, nothing is kept.
if ns.OnTravelTick then
	ns.OnTravelTick(function()
		if ns.HasJourney and ns.HasJourney() then
			return
		end
		local x, y, _, map = ns.JourneyPosition()
		if x and y and map and IsIndoors and IsIndoors() then
			Floor.Sample(map, x, y)
		else
			Floor.Forget()
		end
	end)
end

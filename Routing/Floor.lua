---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- The player's floor. The client gives no player height (UnitPosition's is a placeholder 0), so a search from where
-- you stand starts from every surface near you and keeps the cheapest: under the Ruins of Lordaeron that is the
-- ruins, and on the Undercity's rings a walkway above you. Floor follows the surfaces you can be on as you move
-- instead: a surface stays a candidate while the walking map has a way from it to each new cell you reach, or is held
-- where it was last seen while the map has a hole at its height, and a cell with one surface settles it. Once the
-- candidates are one floor, Height gives its height and the search starts on it (Path.lua's snap takes the surface
-- nearest a height). Until then, and wherever it cannot tell, searches start as before.
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
local LIFT = 10 -- yd from a lift's landing: a lift changes floor without moving, so the floor is unknown there
local FIRST_LIFT = 1001 -- Data/Transports.lua numbers lift and tram landings from here

---@class SPFFloorSurface
---@field k number cluster
---@field node number node in the cluster
---@field z number height
---@field gx number global cell the surface was last seen on
---@field gy number
---@field held true? held where it was last seen, or a fresh start's neighbour: no way from it to you yet
---@field root number? the surface this one stepped on from, as k * 1048576 + node, once it has stepped

---@class SPFFloorState
---@field map number
---@field gx number global cell
---@field gy number
---@field x number last sample
---@field y number
---@field nodes SPFFloorSurface[] the surfaces you may be on
---@field gapX number? the cell a held floor last failed to reach
---@field gapY number?
---@field swam boolean whether you were swimming when the surfaces were weighed
---@field fell true? whether you were seen falling since

---@type SPFFloorState?
local here
-- The lift landing you stand at, where the floor is not followed, and the height of the floor you walked onto it on:
-- a lift's landings share a spot on the map, one above the other, so that height names the landing (Core.lua's
-- NearestDock). A ride takes you to another landing without moving you on the map, so a ride seen there
-- (Transport/Observer.lua) drops the height.
---@type { map: number, z: number? }?
local landing
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
		out[1] = { k = k, node = lc, z = z[lc + 1], gx = gx, gy = gy }
	end
	local node = at[-(lc + 1)]
	while node and at[node + 1] == lc do
		out[#out + 1] = { k = k, node = node, z = z[node + 1], gx = gx, gy = gy }
		node = node + 1
	end
	return out
end

-- The surfaces of cell (gx, gy) the walking map reaches within reach steps from nodes at cell (ox, oy), staying in
-- the box around both cells. Water steps count: you may have swum. Every surface a step walks onto is followed, as
-- search() expands them (a ramp's link climbs beside a base step on the floor below); a drop off a ledge counts only
-- once you fell: walking, the client shows no fall, and a drop beside every walkway would hold the floor below it too.
local function Step(st, nodes, ox, oy, gx, gy, reach, fell)
	local landK, landN, landC = {}, {}, {}
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
					-- A ledge and its landing can quantize to the same cell on different floors.
					if nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1 then
						for i = 1, Grid.neighbours(st, k, node, x, y, dx, dy, true, landK, landN, landC) do
							local tk, tn = landK[i], landN[i]
							local id = tk * 1048576 + tn
							if (fell or landC[i] == 0) and not seen[id] then
								seen[id] = true
								queue[#queue + 1] = { tk, tn, nx, ny, depth + 1 }
							end
						end
					end
				end
			end
		end
	end
	return found
end

-- A lift changes floor without moving you on the map.
local function NearLift()
	if not ns.NearestDockSpot then
		return false
	end
	local dock, yards = ns.NearestDockSpot()
	return dock ~= nil and dock >= FIRST_LIFT and yards ~= nil and yards <= LIFT
end

---Stop following: the floor is unknown and the clusters kept for it can go.
function Floor.Forget()
	here, landing = nil, nil
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
	if not (Grid and Path and Path.HasData(map)) or UnitOnTaxi("player") then
		return Floor.Forget()
	end
	if NearLift() then
		-- Arriving, the floor you walked in on names the landing; standing there it is kept, until a ride.
		if not (landing and landing.map == map) then
			landing = { map = map, z = Floor.Height(map, x, y) }
		end
		if ns.IsObservingRide and ns.IsObservingRide() then
			landing.z = nil
		end
		here = nil
		Path.Pin()
		return
	end
	landing = nil
	if InCombatLockdown() then
		-- Held, not followed; a knockback seen here still counts once combat ends.
		if here and IsFalling and IsFalling() then
			here.fell = true
		end
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
	-- Falling or swimming is the client's evidence of a floor change the walking map cannot show. A fall is kept until
	-- the next cell is weighed, so one seen in the air still counts at the landing, a sample or a decode later.
	local falling = IsFalling and IsFalling() and true or false
	local swimming = IsSwimming and IsSwimming() and true or false
	if last and falling then
		last.fell = true
	end
	-- The same cell, or the gap cell a held floor already failed to reach: nothing new, unless you fell there or
	-- started or stopped swimming.
	if
		last
		and last.map == map
		and swimming == last.swam
		and ((last.gx == gx and last.gy == gy) or (last.gapX == gx and last.gapY == gy and not last.fell))
	then
		last.x, last.y = x, y
		return
	end
	local steps = last and last.map == map and max(abs(gx - last.gx), abs(gy - last.gy))
	if not (last and steps) or steps > REACH or (x - last.x) ^ 2 + (y - last.y) ^ 2 > JUMP ^ 2 then
		last = nil
	end
	-- Every cluster the step reads: neighbour looks one cell past the box Step walks, from each surface's own cell.
	-- A fresh start also weighs the cells around you (below).
	local x0, x1, y0, y1 = gx - 1, gx + 1, gy - 1, gy + 1
	for _, s in ipairs(last and last.nodes or {}) do
		x0, x1, y0, y1 = min(x0, s.gx), max(x1, s.gx), min(y0, s.gy), max(y1, s.gy)
	end
	local keep, missing = {}, {}
	for cx = x0 - 2, x1 + 2 do
		for cy = y0 - 2, y1 + 2 do
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
				-- Standing still, the travel clock may have stopped meanwhile: wake it to weigh the step now.
				if ns.WakeTravel then
					ns.WakeTravel()
				end
			end)
		end
		-- The step waits for its clusters; a fresh start is unknown meanwhile.
		if not last then
			here = nil
		end
		return
	end
	-- Swimming, you are on a water surface: a fall into water, a swim under a pier.
	local nodes
	if last and #last.nodes > 0 and not swimming then
		-- Each surface steps on its own, from the cell it was last seen on. One with no way on the walking map to this
		-- cell is a building or a street's edge the map has no surface for at that height, unless you fell: it is held
		-- where it was seen rather than ruled out, since beside Stormwind's streets the only surface such a cell holds is
		-- the ground under the city (#1046). Ruling the street out there would settle a fresh start on the ground under
		-- it. A held surface steps again from its own cell, so it settles on the way out; past REACH cells from that
		-- cell, or a JUMP between samples, it is gone. A jump in such a cell reads as a fall.
		-- After a fall only a surface you could have been on counts as a jump: a held one is a guess.
		local seen, held, moved = {}, {}, {}
		nodes = {}
		for _, s in ipairs(last.nodes) do
			local reach = max(abs(gx - s.gx), abs(gy - s.gy))
			if reach <= REACH and not (last.fell and s.held) then
				local found = Step(st, { s }, s.gx, s.gy, gx, gy, reach + 1, last.fell)
				local root = s.root or s.k * 1048576 + s.node
				if #found == 0 then
					s.held, s.root = true, root
					held[#held + 1] = s
				else
					moved[root] = true
				end
				for _, f in ipairs(found) do
					local id = f.k * 1048576 + f.node
					if not seen[id] then
						seen[id] = true
						f.gx, f.gy, f.root = gx, gy, root
						nodes[#nodes + 1] = f
					end
				end
			end
		end
		if #nodes == 0 then
			if not last.fell and #held > 0 then
				last.nodes, last.x, last.y, last.gapX, last.gapY = held, x, y, gx, gy
				return
			end
			nodes = Surfaces(st, gx, gy)
		elseif not last.fell then
			-- A held surface is a floor the map may lack. One that branched off a floor which stepped on, stairs beside a
			-- street, is not: the map shows that floor's way here. One on a floor of its own, the street over the ground
			-- under the city, stays held.
			for _, s in ipairs(held) do
				if not moved[s.root] then
					nodes[#nodes + 1] = s
				end
			end
		end
	else
		-- A fresh start holds every surface of the cells around you with no way into yours, as a step would: a cell
		-- beside a street can hold only the ground under it, and standing there you are as likely on the street.
		nodes = Surfaces(st, gx, gy)
		if not swimming then
			for cx = gx - 1, gx + 1 do
				for cy = gy - 1, gy + 1 do
					if (cx ~= gx or cy ~= gy) and cx >= 0 and cy >= 0 and cx < st.GX and cy < st.GY then
						for _, s in ipairs(Surfaces(st, cx, cy)) do
							if #Step(st, { s }, cx, cy, gx, gy, 2) == 0 then
								s.held = true
								nodes[#nodes + 1] = s
							end
						end
					end
				end
			end
		end
	end
	if swimming then
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
	-- Still in the air, the fall is weighed again where you land; landed on a floor the map reaches, it was a jump.
	here = { map = map, gx = gx, gy = gy, x = x, y = y, nodes = nodes, swam = swimming, fell = falling or nil }
end

---Whether you stand at a lift's landing on map, and the height of the floor you walked onto it on: nil when it was
---not known (Floor.Height's rule) or a ride has moved you since.
---@param map number
---@return boolean atLanding, number? z
function Floor.Landing(map)
	if landing and landing.map == map then
		return true, landing.z
	end
	return false, nil
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

-- The floor is followed whenever you move, indoors or out, so a journey planned where floors stack starts on yours:
-- Stormwind's streets over the open ground beneath the city, a pier over the water (#737). Outdoors floors stack on
-- nearly every walking-map tile, so there is no cheaper test than following. It keeps the one to four tiles around
-- you decoded, about 3 MB each in a city, as a journey's own frame (Journey.lua) does.
if ns.OnTravelTick then
	ns.OnTravelTick(function()
		if ns.HasJourney and ns.HasJourney() then
			return
		end
		local x, y, _, map = ns.JourneyPosition()
		if x and y and map then
			Floor.Sample(map, x, y)
		else
			Floor.Forget()
		end
	end)
end

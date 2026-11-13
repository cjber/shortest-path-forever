---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Journey searches only the way to the current stop. Each later hop between stops is planned here with the
-- estimate's planner (no endpoint searches, about 2 ms cold), then its walking legs are searched on the walking
-- maps like the current leg's. One piece of work runs at a time, and only on frames the journey's own searches
-- leave free: a walking search in flight is paused while the journey settles. Until a hop is ready, its stops are
-- joined by a straight dotted placeholder, and a walking leg keeps its straight line until its search lands.

---@class SPFHop
---@field from SPFPoint
---@field to SPFPoint
---@field paths? SPFDrawPath[]|false false when the planner found no way
---@field walks {path: SPFDrawPath, leg: SPFLeg}[] walking legs still to search, nearest first

-- Hops are keyed by both stops' coordinates, so an unchanged hop survives a replan of the current leg and a caller
-- sending the same stops again. Only the current route's hops are kept, at most one per stop (64).
---@type table<string, SPFHop>
local hops = {}
local scheduled, wait, dirty
-- Redrawing the map's route line redraws every hop, so ready hops are drawn together at most once a second, in a
-- frame of their own, and once more when nothing is left to do.
local DRAW_EVERY, drawnAt = 1, -math.huge
---@type SPFPathJob?, SPFHop?
local job, searching
local Step

local function Key(from, to)
	return string.format("%d:%.17g:%.17g:%d:%.17g:%.17g", from.map, from.x, from.y, to.map, to.x, to.y)
end

local function Schedule()
	if not scheduled then
		scheduled = true
		ns.Path.after(Step)
	end
end

local function DrawDue()
	return dirty and GetTime() - drawnAt >= DRAW_EVERY
end

-- The journey's own searches (the current leg) always come first.
local function Settling()
	return ns.JourneyStatus() == true
end

---@param hop SPFHop
local function PlanHop(hop)
	local legs = ns.EstimateLegs(hop.from, hop.to)
	hop.paths = legs and {} or false
	for index, leg in ipairs(legs or {}) do
		local walk = leg.mode == "walk"
		local path = { mode = leg.mode, points = ns.PlanContext.LegPoints(leg), preview = walk or nil }
		hop.paths[index] = path
		if walk and leg.from.map == leg.to.map and ns.Path.HasData(leg.from.map) then
			hop.walks[#hop.walks + 1] = { path = path, leg = leg }
		end
	end
end

-- The next piece of work, and whether it is a plan. Every hop is planned before any walk is searched, so the walks
-- run back to back, and one hop's last walk and the next hop's first, which meet at a stop, share decoded grids.
---@return SPFHop?, boolean?
local function Next()
	local points, index = ns.JourneyStops()
	if not (points and index) then
		return nil
	end
	local walk
	for stop = index, #points - 1 do
		local hop = hops[Key(points[stop], points[stop + 1])]
		if hop and hop.paths == nil then
			return hop, true
		end
		walk = walk or hop and hop.walks[1] and hop
	end
	return walk, false
end

local SearchWalk

-- The search loads the continent's walking map on demand, like the current leg's.
---@param hop SPFHop
SearchWalk = function(hop)
	local walk = hop.walks[1]
	searching = hop
	job = ns.Path.Find(walk.leg.from.map, walk.leg.from, walk.leg.to, function(points, _, finished)
		if job ~= finished then
			return
		end
		job, searching = nil, nil
		table.remove(hop.walks, 1)
		-- An unreachable walk keeps its straight placeholder rather than vanishing.
		if points and #points > 1 then
			walk.path.points, walk.path.preview = points, nil
			dirty = true
		end
		-- Queued from this callback, the next walk keeps the search queue from draining, which frees the grids. A
		-- due redraw waits for a free frame instead, so it never adds to a search slice.
		local following, plan = Next()
		if following and not plan and not Settling() and not DrawDue() then
			SearchWalk(following)
		end
		Schedule()
	end, (ns.JourneyWaterWalking()))
end

Step = function()
	scheduled = false
	local points, index = ns.JourneyStops()
	if not (points and index) then
		return
	end
	if InCombatLockdown() then
		if not wait then
			wait = CreateFrame("Frame")
			wait:SetScript("OnEvent", function(self)
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				Schedule()
			end)
		end
		wait:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if job then
		-- A finished job's callback is already queued; pausing it then would drop the callback.
		if not job.done then
			if Settling() then
				ns.Path.Pause(job)
			else
				ns.Path.Resume(job)
			end
		end
		Schedule()
		return
	end
	-- The journey's timed replan also comes first: it plans in the frame like a hop does.
	if ns.Path.Busy() or Settling() or ns.JourneyReplanning() then
		Schedule()
		return
	end
	local hop, plan = Next()
	if dirty and (DrawDue() or not hop) then
		dirty, drawnAt = false, GetTime()
		ns.RefreshJourneyPreview()
		Schedule()
	elseif plan then
		---@cast hop -?
		PlanHop(hop)
		dirty = true
		Schedule()
	elseif hop then
		SearchWalk(hop)
		Schedule()
	end
end

-- The route was replaced, advanced or cancelled: keep only the hops still ahead, dropping a search for any other.
---@param invalidate? boolean
function ns.ItineraryChanged(invalidate)
	local points, index = ns.JourneyStops()
	local kept = {}
	if points and index then
		for stop = index, #points - 1 do
			local key = Key(points[stop], points[stop + 1])
			kept[key] = not invalidate and hops[key] or { from = points[stop], to = points[stop + 1], walks = {} }
		end
	end
	local owner = searching
	if job and not (owner and kept[Key(owner.from, owner.to)] == owner) then
		ns.Path.Cancel(job)
		job, searching = nil, nil
		-- A cleared journey skipped this while the walk was queued; release its decoded grids now.
		if not points then
			ns.Path.ClearCaches()
		end
	end
	hops = kept
	if points then
		Schedule()
	end
end

-- The drawn itinerary after the current stop. A planned hop draws its legs; consecutive unplanned hops are one
-- straight placeholder, which the map shows as end marks where it changes continent.
---@return SPFDrawPath[]
function ns.JourneyPreview()
	local drawn = {}
	local points, index = ns.JourneyStops()
	if not (points and index) then
		return drawn
	end
	local chain = { points[index] }
	for stop = index, #points - 1 do
		local hop, to = hops[Key(points[stop], points[stop + 1])], points[stop + 1]
		if hop and hop.paths then
			if #chain > 1 then
				-- The placeholder leads to the last stop it reaches (UI/Route.lua highlights a stop's own leg).
				drawn[#drawn + 1] = { mode = "walk", points = chain, preview = true, stop = points[stop].number }
			end
			for _, path in ipairs(hop.paths) do
				path.stop = to.number
				drawn[#drawn + 1] = path
			end
			chain = { to }
		else
			chain[#chain + 1] = to
		end
	end
	if #chain > 1 then
		drawn[#drawn + 1] = { mode = "walk", points = chain, preview = true, stop = points[#points].number }
	end
	return drawn
end

-- Two stops at the same place, height included: the same destination, not a new journey.
---@param a SPFPoint?
---@param b SPFPoint?
---@return boolean
local function SameStop(a, b)
	return a ~= nil and b ~= nil and a.map == b.map and a.x == b.x and a.y == b.y and a.z == b.z
end

-- One entry of a list a stop keeps: a quest ID, a detail line, or an area as its place and radius.
---@param a any
---@param b any
---@return boolean
local function SameEntry(a, b)
	if type(a) == "table" and type(b) == "table" then
		return a.map == b.map and a.x == b.x and a.y == b.y and a.radius == b.radius
	end
	return a == b
end

-- Whether two lists a stop keeps hold the same entries; a resubmitted stop builds new tables for them every time.
---@param a any
---@param b any
---@return boolean
local function SameList(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
		return false
	end
	for index = 1, #a do
		if not SameEntry(a[index], b[index]) then
			return false
		end
	end
	return true
end

-- The words a stop shows, which an owner may change without moving the player: its title, its quests, the actions it
-- names and the area it holds, as API.NavigateRoute builds them. The stop object itself stays, because the journey
-- follows that object.
---@param into SPFPoint
---@param from SPFPoint
---@return boolean changed nothing the player can read moved
local function CopyWords(into, from)
	local changed = into.label ~= from.label
		or into.questID ~= from.questID
		or into.radius ~= from.radius
		or into.hold ~= from.hold
		or into.npc ~= from.npc
		or into.look ~= from.look
		or into.stopLabel ~= from.stopLabel
		or into.routeTitleFormat ~= from.routeTitleFormat
		or into.routeCount ~= from.routeCount
		or into.routeTitle ~= from.routeTitle
		or into.number ~= from.number
		or not SameList(into.details, from.details)
		or not SameList(into.questIDs, from.questIDs)
		or not SameList(into.handins, from.handins)
		or not SameList(into.shapes, from.shapes)
	into.label = from.label
	into.details = from.details
	into.questID = from.questID
	into.questIDs = from.questIDs
	into.handins = from.handins
	into.shapes = from.shapes
	into.radius = from.radius
	into.hold = from.hold
	into.npc = from.npc
	into.look = from.look
	into.stopLabel = from.stopLabel
	into.routeTitleFormat = from.routeTitleFormat
	into.routeCount = from.routeCount
	into.routeTitle = from.routeTitle
	into.number = from.number
	return changed
end

-- An owner sending its route again: a guide re-points at the stop it already had, or moves it to the next objective
-- of the step it is on. Answering a re-point with a whole new journey tears down the tracker, the drawn line and the
-- native waypoint, and the writes that go with them make the guide re-point again: the flicker #693 is about. The
-- owner, the stop and the progress stay; only the place may move.
---@param route {owner: string, points: SPFPoint[], index: integer} the route the owner already holds
---@param points SPFPoint[] the route as it was just submitted
---@return boolean? handled nil when this is a new route after all
function ns.ResubmitRoute(route, points)
	if not ns.RetargetJourney then
		return nil
	end
	local previous = route.points
	if #points ~= #previous then
		return nil
	end
	local moved, movedCount = nil, 0
	for index, point in ipairs(points) do
		if not SameStop(previous[index], point) then
			moved, movedCount = index, movedCount + 1
		end
	end
	if movedCount == 0 then
		-- The same places: a relabel, and its quests and area as the guide has them now.
		local changed = false
		for index, point in ipairs(points) do
			changed = CopyWords(previous[index], point) or changed
		end
		-- Nothing the player can read moved: the owner repeated itself, and the journey is left exactly as it was.
		if changed then
			ns.JourneyRelabeled()
			if ns.RefreshRouteLines then
				ns.RefreshRouteLines()
			end
			if ns.RefreshArrowLines then
				ns.RefreshArrowLines()
			end
		end
		if ns.RefreshJourneySearch then
			ns.RefreshJourneySearch()
		end
		return true
	end
	if movedCount > 1 or not moved then
		return nil
	end
	local old = previous[moved]
	-- Another map is a different journey: the route drawn for the old one says nothing about the new.
	if not old or old.map ~= points[moved].map then
		return nil
	end
	previous[moved] = points[moved]
	if moved == route.index then
		return ns.RetargetJourney(points[moved]) == true
	end
	-- A stop still ahead moved: the hops after the current stop are planned again, and the journey under way is not.
	ns.ItineraryChanged()
	if ns.RefreshRouteLines then
		ns.RefreshRouteLines()
	end
	return true
end

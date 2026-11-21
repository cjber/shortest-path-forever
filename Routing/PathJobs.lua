---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Coroutine-sliced walking searches: Path.lua's searches share one frame budget. Cancelled and released jobs give up
-- their scratch; a paused job keeps it.
---@class SPFPath
local Path = ns.Path
local Grid, Search = ns.PathGrid, ns.PathSearch
local clock, Deadline, Expansions = Grid.clock, Grid.Deadline, Grid.Expansions
local start, scratch, Spare = Search.start, Search.scratch, Search.Spare

-- Round-robin slices share one frame budget, including callbacks that replan from newly settled costs.
local queue = {}
local scheduled, pumped = false, false
local pump, combatWait

-- A journey searches its walks again every few seconds as the player moves, over the terrain the last search
-- decoded. Dropping the grids the moment the queue drained made each of those searches decode its clusters from
-- nothing, so the sweep waits until no search has run for this long. The grid and graph ceilings still bound what
-- is kept meanwhile.
Path.linger = 30 -- seconds
-- drains counts the times the queue emptied; waiting is the count the pending sweep was armed at.
local drains, waiting = 0, nil

local function sweep()
	local armed = waiting
	waiting = nil
	if #queue > 0 or scheduled then
		return -- work is queued or a pump is due: the drain after it arms the next sweep
	end
	if drains ~= armed then
		-- Searched since this sweep was armed: wait once more, so the grids outlive the last search by the linger.
		waiting = drains
		Path.after(sweep, Path.linger)
		return
	end
	-- Exact endpoint costs survive; decoded grids and local trees are only useful during active work.
	Grid.Idle()
	Spare(nil)
end

-- The queue emptied: arm the sweep. A pump a callback scheduled is still due: it finds the queue empty and arms the
-- sweep itself.
local function drained()
	drains = drains + 1
	if not waiting and not scheduled then
		waiting = drains
		Path.after(sweep, Path.linger)
	end
end

-- A callback runs as a job of its own at the head of the queue, under the budget left in the frame. It is meant to
-- record the answer and schedule what follows (Path.Run), never to plan or decode itself.
local function notify(job, callback, points, cost)
	if callback then
		table.insert(queue, 1, {
			co = coroutine.create(start),
			notify = callback,
			front = true,
			plain = true,
			owner = job,
			points = points,
			cost = cost,
			frames = 0,
			cpu = 0,
		})
	end
end

local function schedule()
	if not scheduled and #queue > 0 then
		scheduled = true
		Path.after(pump)
	end
end

-- Path work so far, for the report's journey timings: frames that ran a slice, and their milliseconds.
Path.work = { frames = 0, cpu = 0 }

pump = function()
	scheduled, pumped = false, true
	if InCombatLockdown and InCombatLockdown() then
		if not combatWait then
			combatWait = CreateFrame("Frame")
			combatWait:SetScript("OnEvent", function(self)
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				schedule()
			end)
		end
		combatWait:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local began = clock()
	local finish = began + Path.budget
	repeat
		local job = table.remove(queue, 1)
		if not job then
			break
		end
		local t0 = clock()
		Deadline(math.min(finish, t0 + (not job.front and #queue > 0 and Path.budget / 2 or Path.budget)))
		Expansions(job.expansions or 0)
		-- Plain jobs (callbacks, plans) have no walking search, so no search scratch to swap in.
		local saved = not job.plain and scratch(job.scratch)
		local co = job.co
		Grid.Running(job)
		local ok, points, cost = coroutine.resume(co, job)
		Grid.Running(nil)
		if saved then
			job.scratch = scratch(saved)
		end
		job.expansions = Expansions()
		job.frames = job.frames + 1
		job.cpu = job.cpu + clock() - t0
		Deadline(math.huge)
		if job.cancelled then
			-- Cancelled from inside its own resume (a plan's answer that replaced its journey): nothing more runs.
			Grid.Release(job)
			job.scratch, job.co = nil, nil
			if not ok then
				geterrorhandler()(points)
			end
		elseif not ok or coroutine.status(co) == "dead" then
			Grid.Release(job)
			if not job.targets and not job.plain then
				Spare(job.scratch)
			end
			job.done, job.scratch, job.co = true, nil, nil
			if not ok then
				geterrorhandler()(points)
				points, cost = nil, "error"
			end
			-- A pause drops the queued answer; a batch's costs are already on the job, and this keeps why.
			job.reason = type(cost) == "string" and cost or nil
			if not job.cancelled then
				notify(job, job.callback, points, cost)
			end
		else
			if points == "load" then
				finish = 0
			end
			if job.front then
				table.insert(queue, 1, job)
			else
				queue[#queue + 1] = job
			end
			if job.progress then
				notify(job, job.progress, job.costs)
			end
		end
	until clock() >= finish
	Path.work.frames, Path.work.cpu = Path.work.frames + 1, Path.work.cpu + clock() - began
	if #queue == 0 then
		drained()
	end
	schedule()
end

-- Idle work skips frames a queued search holds or one since the last call spent, so they never share a budget.
function Path.Busy()
	local busy = pumped or #queue > 0
	pumped = false
	return busy
end

-- Next-frame scheduling, or after `seconds`; tests replace it.
---@param fn fun()
---@param seconds? number
function Path.after(fn, seconds)
	C_Timer.After(seconds or 0, fn)
end

local function enqueue(job)
	job.co, job.frames, job.cpu = coroutine.create(start), 0, 0
	queue[#queue + 1] = job
	schedule()
	return job
end

-- Search coroutine-sliced over frames between two { x, y, z } points (z optional: it picks the floor to start or end
-- on). callback(points, cost, job) or callback(nil, reason, job): points are { map, x, y, z } from the start to the
-- goal, with points.wet the drawn yards over water. Cost is the abstract route's real running yards, not the
-- smoothed polyline length; a swum grid yard counts as the data's swim (so routes keep out of water) unless
-- waterWalking, when water is ground. Hazards (Journey/Hazards.lua) affect which route is selected, not this cost.
-- reason is "nodata", "outside", "offmesh", "unreachable" or "error". Returns a Cancel handle.
---@param map number
---@param from SPFPoint
---@param to SPFPoint
---@param callback fun(points: SPFWalkPoints?, cost: number|string, job: SPFPathJob)
---@param waterWalking? boolean
---@param hazards? SPFHazards
---@return SPFPathJob
function Path.Find(map, from, to, callback, waterWalking, hazards)
	return enqueue({
		map = map,
		from = from,
		to = to,
		waterWalking = waterWalking,
		hazards = hazards,
		callback = callback,
	})
end

-- A candidate can be ruled in or out without refining all its intermediate clusters into drawing points.
-- callback(cost, reason, job) uses the same exact graph cost as Find and FindMany.
---@param map number
---@param from SPFPoint
---@param to SPFPoint
---@param callback fun(cost: number?, reason: string?, job: SPFPathJob)
---@param waterWalking? boolean
---@param hazards? SPFHazards
---@return SPFPathJob
function Path.FindCost(map, from, to, callback, waterWalking, hazards)
	local job = Path.Find(map, from, to, callback, waterWalking, hazards)
	job.costOnly = true
	return job
end

-- A Path.Decode job: its clusters, decoded under the frame budget like a search's.
local function decode(job)
	local st = Grid.State(job.map)
	for _, k in ipairs(st and job.decode or {}) do
		Grid.grid(st, k)
	end
end

-- Decode clusters under the shared frame budget, then callback(nil, nil, job). Floor.lua reads only decoded
-- clusters, so following the player's floor never decodes in a frame of its own.
---@param map number
---@param clusters number[]
---@param callback fun(points: nil, reason: string?, job: SPFPathJob)
---@return SPFPathJob
function Path.Decode(map, clusters, callback)
	local job = enqueue({ map = map, decode = clusters, callback = callback })
	job.co = coroutine.create(decode)
	return job
end

-- Keep these clusters of map decoded while no search runs, or none (no arguments).
---@param map number?
---@param clusters table<number, true>?
function Path.Pin(map, clusters)
	-- A released cluster goes now when no job runs and no sweep is due: otherwise it stays decoded until the next
	-- job drains the queue. Within the linger the pending sweep takes it, with the grids a journey is still reusing.
	if Grid.Pin(map, clusters) and #queue == 0 and not waiting then
		Grid.Idle()
	end
end

-- callback(costs, reason, job) completes once; optional progress(costs, nil, job) runs after each slice.
-- costs[i] is nil until settled, the real running-yard cost on the hazard-selected route afterwards, or false when
-- unreachable. job.radius
-- bounds every unsettled target, including a popped entrance whose expansion has not finished. Pause/Resume
-- retain the frontier. Missing data or an invalid source completes with all false plus a reason.
---@param map number
---@param from SPFPoint
---@param targets SPFPoint[]
---@param callback fun(costs: (number|false)[], reason: string?, job: SPFPathJob)
---@param waterWalking? boolean
---@param reverse? boolean
---@param progress? fun(costs: (number|false)[], reason: nil, job: SPFPathJob)
---@param hazards? SPFHazards
---@return SPFPathJob
function Path.FindMany(map, from, targets, callback, waterWalking, reverse, progress, hazards)
	return enqueue({
		map = map,
		from = from,
		targets = targets,
		waterWalking = waterWalking,
		hazards = hazards,
		reverse = reverse,
		progress = progress,
		costs = {},
		radius = 0,
		revision = 0,
		callback = callback,
	})
end

-- Paused batches retain their settled costs and frontier for later replans, without consuming frames. A callback
-- still queued for the job is dropped for good.
---@param job SPFPathJob
function Path.Pause(job)
	job.paused = true
	local removed = false
	for i = #queue, 1, -1 do
		local queued = queue[i]
		if queued == job or queued.owner == job then
			table.remove(queue, i)
			removed = true
			if queued ~= job then
				queued.cancelled = true
			end
		end
	end
	-- No pump may come to drain it (one waiting out combat schedules nothing for an empty queue), so arm the sweep.
	if removed and #queue == 0 then
		drained()
	end
end

-- Plain Lua work under the same frame budget: a plan, an ordering, a callback's follow-up. fn runs in the job's own
-- coroutine, so Path.Checkpoint inside it yields at the deadline and the work goes on next frame; callback(a, b, job)
-- receives fn's first two results. Nothing between fn and a checkpoint may be a C call (pcall, a hook, a sort's
-- comparator): Lua 5.1 cannot yield across one (#717). It runs ahead of walking searches, as a callback does.
---@param fn fun(job: SPFPathJob): any, any
---@param callback? fun(a: any, b: any, job: SPFPathJob)
---@return SPFPathJob
function Path.Run(fn, callback)
	local job = { callback = callback, front = true, plain = true, frames = 0, cpu = 0 }
	job.co = coroutine.create(fn)
	table.insert(queue, 1, job)
	schedule()
	return job
end

---@param job SPFPathJob
function Path.Resume(job)
	if job.paused and not job.done and not job.cancelled then
		job.paused = false
		job.co = job.co or coroutine.create(start)
		queue[#queue + 1] = job
		schedule()
	end
end

-- A proved journey needs the exact costs and validity/bounds, not a suspended Dijkstra stack.
-- If a later timetable exposes another alternative, Resume rebuilds only the missing frontier.
---@param job SPFPathJob
function Path.ReleaseMany(job)
	Path.Pause(job)
	Grid.Release(job)
	job.co, job.scratch, job.callback, job.progress = nil, nil, nil, nil
end

function Path.ClearCaches()
	-- Cancellation removes a journey's jobs first; never invalidate another active search's grids.
	if #queue > 0 then
		return
	end
	Grid.Reset()
	Spare(nil)
end

---@param job SPFPathJob
function Path.Cancel(job)
	Path.Pause(job)
	Grid.Release(job)
	job.cancelled, job.scratch, job.co = true, nil, nil
end

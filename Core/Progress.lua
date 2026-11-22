---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- Per-character travel journal. Distance is an estimate from same-map position samples while walking; map changes,
-- secret positions, taxi flights, recognized rides and implausible jumps reset the baseline.
local DISTANCE_MILESTONES, COUNT_MILESTONES = { 1000, 10000, 100000 }, { 1, 10, 50 }
local MILESTONES = {
	walkedYards = {
		key = "distance",
		message = L["You've walked %s yards."],
	},
	routesCompleted = {
		key = "routes",
		message = L["You've completed %s journeys."],
		first = L["You've completed your first journey."],
	},
	transportsUsed = {
		key = "transports",
		message = L["You've taken %s transport rides."],
		first = L["You've taken your first transport ride."],
	},
	flightsTaken = {
		key = "flights",
		message = L["You've taken %s flights."],
		first = L["You've taken your first flight."],
	},
	portalsUsed = {
		key = "portals",
		message = L["You've used %s portals or passages."],
		first = L["You've used your first portal or passage."],
	},
}
local MAX_SAMPLE_GAP, MAX_SPEED = 2.5, 60
local lastPosition, lastSample, lastRide, wasFlying, lastPortalLeg

local function Ensure()
	if not ns.charDB then
		return nil
	end
	local stats = ns.charDB.progress
	if type(stats) ~= "table" then
		stats = {
			walkedYards = 0,
			routesCompleted = 0,
			transportsUsed = 0,
			flightsTaken = 0,
			portalsUsed = 0,
			milestones = {},
		}
		ns.charDB.progress = stats
	end
	for _, key in ipairs({ "walkedYards", "routesCompleted", "transportsUsed", "flightsTaken", "portalsUsed" }) do
		if type(stats[key]) ~= "number" or stats[key] < 0 or stats[key] ~= stats[key] then
			stats[key] = 0
		end
	end
	if type(stats.milestones) ~= "table" then
		stats.milestones = {}
	end
	-- Peer snapshots belonged to the retired Forever Leaderboards feature. Clear them once on load.
	rawset(stats, "peers", nil)
	return stats
end

local function Milestone(stats, value, thresholds, milestone)
	for _, threshold in ipairs(thresholds) do
		local marker = milestone.key .. ":" .. threshold
		if value >= threshold and not stats.milestones[marker] then
			stats.milestones[marker] = GetServerTime()
			ns.Notice(threshold == 1 and milestone.first or milestone.message:format(BreakUpLargeNumbers(threshold)))
		end
	end
end

---@return SPFProgressData?
local function Snapshot()
	local stats = Ensure()
	if not stats then
		return nil
	end
	return {
		walkedYards = math.floor(stats.walkedYards),
		routesCompleted = math.floor(stats.routesCompleted),
		transportsUsed = math.floor(stats.transportsUsed),
		flightsTaken = math.floor(stats.flightsTaken),
		portalsUsed = math.floor(stats.portalsUsed),
		milestones = stats.milestones,
	}
end

ns.TravelStats = function()
	local snapshot = Snapshot()
	return snapshot
end

local function Record(key, amount)
	if not ns.db.stats then
		return
	end
	local stats = Ensure()
	if not stats then
		return
	end
	stats[key] = stats[key] + amount
	Milestone(stats, stats[key], key == "walkedYards" and DISTANCE_MILESTONES or COUNT_MILESTONES, MILESTONES[key])
end

local function Position()
	local x, y, _, map = ns.JourneyPosition()
	if not x then
		return nil
	end
	return x, y, map
end

local function Sample()
	if not ns.db.stats then
		lastPosition, lastSample = nil, nil
		return
	end
	local now, x, y, map = GetTime(), Position()
	local flying, ride = UnitOnTaxi("player"), ns.CurrentRide and ns.CurrentRide()
	if flying and not wasFlying then
		Record("flightsTaken", 1)
	elseif ride and ride ~= lastRide then
		Record("transportsUsed", 1)
	end
	wasFlying, lastRide = flying, ride
	if not x or not IsPlayerMoving() or flying or ride then
		lastPosition, lastSample = nil, nil
		return
	end
	if lastPosition and lastSample then
		local elapsed = now - lastSample
		local dx, dy = x - lastPosition.x, y - lastPosition.y
		local distance = math.sqrt(dx * dx + dy * dy)
		if
			map == lastPosition.map
			and elapsed > 0
			and elapsed <= MAX_SAMPLE_GAP
			and distance <= MAX_SPEED * elapsed
		then
			Record("walkedYards", distance)
		end
	end
	lastPosition, lastSample = { x = x, y = y, map = map }, now
end

local function OnJourneyChanged(point, reason)
	if not point and reason == "arrived" then
		Record("routesCompleted", 1)
	end
end
ns.ProgressJourneyChanged = OnJourneyChanged

ns.Init(function()
	Ensure()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(_, event)
		if event == "ZONE_CHANGED_NEW_AREA" then
			local plan, index
			if ns.JourneyPlan then
				plan, index = ns.JourneyPlan()
			end
			local leg = plan and plan.legs[index]
			if leg and (leg.mode == "portal" or leg.mode == "passage") and leg ~= lastPortalLeg then
				Record("portalsUsed", 1)
				lastPortalLeg = leg
			elseif not leg or (leg.mode ~= "portal" and leg.mode ~= "passage") then
				lastPortalLeg = nil
			end
			lastPosition, lastSample = nil, nil
		else
			lastPosition, lastSample = nil, nil
		end
	end)
	ns.OnTravelTick(Sample)
end)

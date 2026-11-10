---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- Per-character travel journal. Distance is an estimate from same-map position samples while walking; map changes,
-- secret positions, taxi flights, recognized rides and implausible jumps reset the baseline.
local DISTANCE_MILESTONES, COUNT_MILESTONES = { 1000, 10000, 100000 }, { 1, 10, 50 }
local MAX_SAMPLE_GAP, MAX_SPEED = 2.5, 60
local METRICS = {
	{ id = "distance_yards", field = "walkedYards" },
	{ id = "routes_completed", field = "routesCompleted" },
	{ id = "transports_used", field = "transportsUsed" },
	{ id = "flights_taken", field = "flightsTaken" },
	{ id = "portals_used", field = "portalsUsed" },
}
local localStats, lastPosition, lastSample, lastRide, wasFlying, lastPortalLeg
local nextSend, pendingSend = 0, false
local peer

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
			peers = {},
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
	if type(stats.peers) ~= "table" then
		stats.peers = {}
	end
	for addon in pairs(stats.peers) do
		if addon ~= "spf" or type(stats.peers[addon]) ~= "table" then
			stats.peers[addon] = nil
		end
	end
	localStats = stats
	return stats
end

local function Milestone(key, value, thresholds)
	for _, threshold in ipairs(thresholds) do
		local marker = key .. ":" .. threshold
		if value >= threshold and not localStats.milestones[marker] then
			localStats.milestones[marker] = GetServerTime()
			ns.Print(string.format(L["Travel milestone reached: %s"], marker))
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
		peers = {},
	}
end
local TAB_ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local BOARD_METRIC = "routes_completed"

-- Sharing is opt-out: only an explicit off stays off, so a missing saved setting reads as on.
local function Sharing()
	return ns.db ~= nil and ns.db.statsShare ~= false
end

-- Recording has its own switch, and an explicit off there keeps the journal local even while sharing is on.
local function Enabled()
	return Sharing() and ns.db.stats ~= false
end

ns.TravelStats = function()
	local snapshot = Snapshot()
	if snapshot and Enabled() then
		snapshot.peers.spf = peer:Shared()
	end
	return snapshot
end

-- One row per ranked player, in the shape the shared window draws. The all-time board keeps the completed journeys
-- total in the value column; the weekly board draws the progress since the reset there and the total in grey. The
-- shared window fills each row's class from the client's own knowledge, so these rows leave it nil.
---@param scope ForeverLeaderboardsScope
---@return ForeverLeaderboardsRow[]
local function Board(scope)
	local stats = Ensure()
	local value = stats and stats.routesCompleted or 0
	local weekly = scope == "week"
	local ranked
	local totals
	if weekly then
		ranked = peer:WeekBoard(BOARD_METRIC, "all", value)
		totals = {}
		for _, row in ipairs(peer:Board(BOARD_METRIC, "all", value)) do
			totals[row.identity] = row.value
			totals[row.name:lower()] = row.value
		end
	else
		ranked = peer:Board(BOARD_METRIC, "all", value)
	end
	local rows = {}
	for _, row in ipairs(ranked) do
		local total = totals and (totals[row.identity] or totals[row.name:lower()])
		rows[#rows + 1] = {
			name = row.name,
			value = row.value,
			extra = total and (total .. " " .. L["total"]) or nil,
			you = row.self == true,
		}
	end
	return rows
end
ns.TravelBoard = Board

--- Open the shared Forever Leaderboards window on this addon's tab.
function ns.OpenTravelLeaderboard()
	ForeverCore.Leaderboards:Open("spf")
end

ForeverCore.Leaderboards:Register("spf", {
	title = L["Shortest Path Forever"],
	icon = TAB_ICON,
	metric = L["Completed journeys"],
	board = Board,
	revision = function()
		return peer:Revision()
	end,
	sharing = Sharing,
	setSharing = function(shared)
		ns.db.statsShare = shared == true
		ns.TravelSharingChanged()
		if ns.SetOption then
			pcall(ns.SetOption, "statsShare", shared == true)
		end
	end,
	safeCall = ns.core.SafeCall,
})

local function Record(key, amount)
	if not ns.db.stats then
		return
	end
	local stats = Ensure()
	if not stats then
		return
	end
	stats[key] = stats[key] + amount
	if key == "walkedYards" then
		Milestone("distance", stats[key], DISTANCE_MILESTONES)
	else
		local label = ({
			routesCompleted = "routes",
			transportsUsed = "transports",
			flightsTaken = "flights",
			portalsUsed = "portals",
		})[key]
		if label then
			Milestone(label, stats[key], COUNT_MILESTONES)
		end
	end
	if ns.db.statsShare ~= false and not pendingSend then
		pendingSend = true
		C_Timer.After(math.max(5, nextSend - GetTime()), function()
			pendingSend = false
			nextSend = GetTime() + 30
			ns.SendTravelStats()
		end)
	end
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

-- Core owns validation, identity normalization, bounded persistence and the shared send queue.
local metricConfig = {}
for _, metric in ipairs(METRICS) do
	metricConfig[metric.id] = { subject = "all" }
end
peer = ForeverCore.PeerStats.New({
	safeCall = ns.core.SafeCall,
	addon = "spf",
	enabled = Enabled,
	db = function()
		local stats = Ensure()
		if not stats then
			return nil
		end
		stats.peers.spf = stats.peers.spf or {}
		return stats.peers.spf
	end,
	metrics = metricConfig,
	snapshot = function()
		local stats, rows = Snapshot(), {}
		if stats then
			for _, metric in ipairs(METRICS) do
				rows[#rows + 1] = { metric = metric.id, subject = "all", value = stats[metric.field] }
			end
		end
		return rows
	end,
})

function ns.SendTravelStats()
	return peer:Sync()
end

function ns.TravelSharingChanged()
	peer:SetEnabled(Enabled())
	lastPosition, lastSample = nil, nil
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
	C_Timer.After(15, function()
		if ns.db.statsShare ~= false then
			nextSend = GetTime() + 30
			ns.SendTravelStats()
		end
	end)
end)

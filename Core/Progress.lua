---@class SPFNamespace
local ns = select(2, ...)

-- Per-character travel journal. Distance is an estimate from same-map position samples while walking; map changes,
-- secret positions, taxi flights, recognized rides and implausible jumps reset the baseline.
local DISTANCE_MILESTONES, COUNT_MILESTONES = { 1000, 10000, 100000 }, { 1, 10, 50 }
local MAX_SAMPLE_GAP, MAX_SPEED, PREFIX = 2.5, 60, "WFAStats"
local ACCEPTED = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
local METRICS = {
	{ id = "distance_yards", field = "walkedYards" },
	{ id = "routes_completed", field = "routesCompleted" },
	{ id = "transports_used", field = "transportsUsed" },
	{ id = "flights_taken", field = "flightsTaken" },
	{ id = "portals_used", field = "portalsUsed" },
}
local METRICS_BY_ADDON = {
	spf = {
		distance_yards = true,
		routes_completed = true,
		transports_used = true,
		flights_taken = true,
		portals_used = true,
	},
	fieldguide = {
		creature_kills = true,
		rare_kills = true,
		shiny_finds = true,
		first_sighting = true,
		first_kill = true,
		first_rare = true,
		first_shiny = true,
		boss_sightings = true,
		boss_kills = true,
		boss_first_sighting = true,
		boss_first_kill = true,
	},
	agf = { quest_turn_ins = true, quest_turn_in = true },
	legacy = { flight_path_known = true },
	skillup = { recipes_observed_learned = true },
}
local MAX_PEERS, MAX_ROWS_PER_PEER = 100, 128
local localStats, lastPosition, lastSample, lastRide, wasFlying, lastPortalLeg
local nextSend = 0
local queue, sending = {}, false

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
		if not METRICS_BY_ADDON[addon] or type(stats.peers[addon]) ~= "table" then
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
			ns.Print(string.format("Travel milestone reached: %s", marker))
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
		peers = stats.peers,
	}
end
ns.TravelStats = Snapshot

---@param metric? string
---@return SPFProgressRank[]
function ns.TravelLeaderboard(metric)
	metric = metric or "routesCompleted"
	local allowed = {
		walkedYards = true,
		routesCompleted = true,
		transportsUsed = true,
		flightsTaken = true,
		portalsUsed = true,
	}
	if not allowed[metric] then
		metric = "routesCompleted"
	end
	local stats = Ensure()
	if not stats then
		return {}
	end
	local metricIDs = {
		walkedYards = "distance_yards",
		routesCompleted = "routes_completed",
		transportsUsed = "transports_used",
		flightsTaken = "flights_taken",
		portalsUsed = "portals_used",
	}
	local metricID = metricIDs[metric]
	local ranks = { { name = "You (local)", localRecord = true, value = stats[metric] } }
	for name, peer in pairs(stats.peers.spf or {}) do
		local record = peer[metricID] and peer[metricID].all
		if record then
			ranks[#ranks + 1] = { name = name .. " (reported)", localRecord = false, value = record.value }
		end
	end
	table.sort(ranks, function(a, b)
		if a.value == b.value then
			return a.name < b.name
		end
		return a.value > b.value
	end)
	return ranks
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
	if ns.db.statsShare then
		C_Timer.After(5, function()
			if GetTime() >= nextSend then
				nextSend = GetTime() + 30
				ns.SendTravelStats()
			end
		end)
	end
end

local function Position()
	local x, y, _, map = UnitPosition("player")
	if not (canaccessvalue(x) and canaccessvalue(y) and canaccessvalue(map)) then
		return nil
	end
	if type(x) ~= "number" or type(y) ~= "number" or type(map) ~= "number" then
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

local function Distributions()
	local channels = {}
	if IsInGuild() then
		channels[#channels + 1] = "GUILD"
	end
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		channels[#channels + 1] = "INSTANCE_CHAT"
	elseif IsInRaid() then
		channels[#channels + 1] = "RAID"
	elseif IsInGroup() then
		channels[#channels + 1] = "PARTY"
	end
	return channels
end

local function Pump()
	if sending or #queue == 0 then
		return
	end
	sending = true
	local function Flush()
		if not ns.db.statsShare then
			queue, sending = {}, false
			return
		end
		local item = table.remove(queue, 1)
		if not item then
			sending = false
			return
		end
		local result = C_ChatInfo.SendAddonMessage(PREFIX, item.message, item.channel)
		local throttle = Enum.SendAddonMessageResult.AddonMessageThrottle
		if throttle and result == throttle then
			table.insert(queue, 1, item)
			C_Timer.After(2, Flush)
		else
			C_Timer.After(1.5, Flush)
		end
	end
	Flush()
end

function ns.SendTravelStats()
	if not (ns.db.stats and ns.db.statsShare) then
		return
	end
	local stats = Snapshot()
	if not stats then
		return
	end
	for _, channel in ipairs(Distributions()) do
		for _, metric in ipairs(METRICS) do
			queue[#queue + 1] = {
				channel = channel,
				message = string.format(
					"1|spf|%s|all|%d|%d",
					metric.id,
					math.floor(stats[metric.field]),
					GetServerTime()
				),
			}
		end
	end
	Pump()
end

local function OnMessage(prefix, message, channel, sender)
	if prefix ~= PREFIX or not ns.db.statsShare or not ACCEPTED[channel] or not sender or #message > 80 then
		return
	end
	local version, addon, metric, subject, value, eventUnix =
		message:match("^(%d)|([a-z0-9_]+)|([a-z0-9_]+)|([a-z0-9_]+)|(%d+)|(%d+)$")
	if
		version ~= "1"
		or not (METRICS_BY_ADDON[addon] and METRICS_BY_ADDON[addon][metric])
		or not subject
		or #subject > 32
		or not subject:match("^[a-z0-9_%-]+$")
	then
		return
	end
	value, eventUnix = tonumber(value), tonumber(eventUnix)
	if not value or not eventUnix or value > 1000000000 or eventUnix > GetServerTime() + 300 then
		return
	end
	local stats = Ensure()
	if not stats or Ambiguate(sender, "none") == UnitName("player") or #sender > 64 then
		return
	end
	local peers, knownSenders, rowsForSender = stats.peers, {}, 0
	for _, addonPeers in pairs(peers) do
		if type(addonPeers) == "table" then
			for peerName, peerRows in pairs(addonPeers) do
				knownSenders[peerName] = true
				if peerName == sender and type(peerRows) == "table" then
					for _, subjects in pairs(peerRows) do
						if type(subjects) == "table" then
							for _ in pairs(subjects) do
								rowsForSender = rowsForSender + 1
							end
						end
					end
				end
			end
		end
	end
	local addonPeers = peers[addon]
	if type(addonPeers) ~= "table" then
		addonPeers = {}
	end
	local oldPeer = addonPeers[sender]
	local oldSubject = type(oldPeer) == "table" and type(oldPeer[metric]) == "table" and oldPeer[metric][subject]
	local peerCount = 0
	for _ in pairs(knownSenders) do
		peerCount = peerCount + 1
	end
	if
		(not knownSenders[sender] and peerCount >= MAX_PEERS) or (not oldSubject and rowsForSender >= MAX_ROWS_PER_PEER)
	then
		return
	end
	stats.peers[addon] = addonPeers
	local peer = type(oldPeer) == "table" and oldPeer or {}
	stats.peers[addon][sender] = peer
	peer[metric] = type(peer[metric]) == "table" and peer[metric] or {}
	local old = peer[metric][subject]
	if
		not old
		or (metric:match("^first_") and eventUnix < old.eventUnix)
		or (not metric:match("^first_") and value > old.value)
	then
		peer[metric][subject] = { value = value, eventUnix = eventUnix }
	end
end

local function OnJourneyChanged(point, reason)
	if not point and reason == "arrived" then
		Record("routesCompleted", 1)
	end
end
ns.ProgressJourneyChanged = OnJourneyChanged

ns.Init(function()
	Ensure()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("CHAT_MSG_ADDON")
	frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "CHAT_MSG_ADDON" then
			OnMessage(...)
		elseif event == "ZONE_CHANGED_NEW_AREA" then
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
		if ns.db.statsShare then
			nextSend = GetTime() + 30
			ns.SendTravelStats()
		end
	end)
end)

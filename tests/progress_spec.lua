local ns
ns = {
	db = { stats = true, statsShare = false },
	charDB = {},
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	OnTravelTick = function(fn)
		ns.tick = fn
	end,
	JourneyChanged = function() end,
	JourneyPlan = function()
		return ns.plan, 1
	end,
	Print = function() end,
}
local now, x, y, map, moving, taxi = 0, 0, 0, 1, true, false
local frame
ns.JourneyPosition = function()
	return x, y, nil, map
end
local env = setmetatable({
	GetTime = function()
		return now
	end,
	GetServerTime = function()
		return math.floor(now)
	end,
	UnitPosition = function()
		return x, y, 0, map
	end,
	canaccessvalue = function()
		return true
	end,
	IsPlayerMoving = function()
		return moving
	end,
	UnitOnTaxi = function()
		return taxi
	end,
	IsInGuild = function()
		return false
	end,
	IsInGroup = function()
		return false
	end,
	IsInRaid = function()
		return false
	end,
	LE_PARTY_CATEGORY_INSTANCE = 1,
	UnitName = function()
		return "Player"
	end,
	Ambiguate = function(name)
		return name
	end,
	C_ChatInfo = {
		RegisterAddonMessagePrefix = function()
			return true
		end,
		SendAddonMessage = function()
			return 0
		end,
	},
	C_Timer = {
		After = function() end,
	},
	Enum = {
		SendAddonMessageResult = { InvalidPrefix = 1, InvalidChatType = 2 },
	},
	CreateFrame = function()
		frame = {}
		frame.RegisterEvent = function() end
		frame.SetScript = function(_, _, callback)
			frame.onEvent = callback
		end
		return frame
	end,
}, { __index = _G })
ns.Init = function(callback)
	callback()
end
setfenv(assert(loadfile("Core/Progress.lua")), env)("ShortestPathForever", ns)

ns.tick()
now, x = 1, 7
ns.tick()
assert(ns.TravelStats().walkedYards == 7, "plausible movement on the same map counts toward estimated distance")
now, x = 2, 1000
ns.tick()
assert(ns.TravelStats().walkedYards == 7, "a position jump is discarded")
now, x, map = 3, 1007, 2
ns.tick()
assert(ns.TravelStats().walkedYards == 7, "a map transition resets the distance baseline")

taxi, now = true, 4
ns.tick()
taxi, now = false, 5
ns.tick()
assert(ns.TravelStats().flightsTaken == 1, "a taxi start is recorded once")

ns.ProgressJourneyChanged(nil, "arrived")
assert(ns.TravelStats().routesCompleted == 1, "only a completed journey increments the route count")
ns.ProgressJourneyChanged(nil, "cleared")
assert(ns.TravelStats().routesCompleted == 1, "clearing a journey is not completion")

ns.plan = { legs = { { mode = "portal" } } }
frame.onEvent(frame, "ZONE_CHANGED_NEW_AREA")
assert(ns.TravelStats().portalsUsed == 1, "portal use is inferred only for an active portal or passage leg")
frame.onEvent(frame, "ZONE_CHANGED_NEW_AREA")
assert(ns.TravelStats().portalsUsed == 1, "duplicate zone events for one leg count once")

ns.db.statsShare = true
frame.onEvent(frame, "CHAT_MSG_ADDON", "WFAStats", "1|spf|routes_completed|all|10|100", "GUILD", "Peer-Realm")
frame.onEvent(frame, "CHAT_MSG_ADDON", "WFAStats", "1|fieldguide|creature_kills|12345|6|200", "GUILD", "Guide-Realm")
frame.onEvent(frame, "CHAT_MSG_ADDON", "WFAStats", "1|fieldguide|first_sighting|12345|1|200", "GUILD", "Guide-Realm")
frame.onEvent(frame, "CHAT_MSG_ADDON", "WFAStats", "1|fieldguide|first_sighting|12345|1|150", "GUILD", "Guide-Realm")
frame.onEvent(frame, "CHAT_MSG_ADDON", "WFAStats", "1|fieldguide|not_allowed|12345|1|100", "GUILD", "Guide-Realm")
local ranks = ns.TravelLeaderboard("routesCompleted")
assert(
	ranks[1].name == "Peer-Realm (reported)" and ranks[1].value == 10,
	"peer snapshots are ranked as reported claims"
)
assert(
	ns.charDB.progress.peers.fieldguide["Guide-Realm"].creature_kills["12345"].value == 6,
	"suite records retain addon and subject"
)
assert(
	ns.charDB.progress.peers.fieldguide["Guide-Realm"].first_sighting["12345"].eventUnix == 150,
	"firsts merge to earliest event"
)
assert(
	not ns.charDB.progress.peers.fieldguide["Guide-Realm"].not_allowed,
	"unknown addon-specific metrics are rejected"
)
for id = 1, 126 do
	frame.onEvent(
		frame,
		"CHAT_MSG_ADDON",
		"WFAStats",
		"1|fieldguide|creature_kills|" .. id .. "|1|200",
		"GUILD",
		"Guide-Realm"
	)
end
frame.onEvent(frame, "CHAT_MSG_ADDON", "WFAStats", "1|fieldguide|creature_kills|999999|1|200", "GUILD", "Guide-Realm")
assert(#(function()
	local subjects = {}
	for subject in pairs(ns.charDB.progress.peers.fieldguide["Guide-Realm"].creature_kills) do
		subjects[#subjects + 1] = subject
	end
	return subjects
end)() == 127, "per-peer row cap rejects additional metric/subject records")
for index = 1, 98 do
	frame.onEvent(frame, "CHAT_MSG_ADDON", "WFAStats", "1|spf|routes_completed|all|1|200", "GUILD", "Peer-" .. index)
end
frame.onEvent(frame, "CHAT_MSG_ADDON", "WFAStats", "1|spf|routes_completed|all|1|200", "GUILD", "Peer-overflow")
assert(not ns.charDB.progress.peers.spf["Peer-overflow"], "global peer cap rejects new senders")
ns.db.statsShare = false
frame.onEvent(frame, "CHAT_MSG_ADDON", "WFAStats", "1|spf|routes_completed|all|99|100", "GUILD", "Peer-Realm")
assert(
	ns.charDB.progress.peers.spf["Peer-Realm"].routes_completed.all.value == 10,
	"sharing opt out stops receiving snapshots"
)

ns.db.stats = false
moving, now, x = true, 6, 1014
ns.tick()
assert(ns.TravelStats().walkedYards == 7, "turning off local collection stops updates")

-- A fresh install: the saved variables hold no `stats` key, so the shipped default (off) applies. Nothing is
-- recorded, no position is sampled and no snapshot is sent until the player turns the journal on (#269).
local sent = 0
env.C_ChatInfo.SendAddonMessage = function()
	sent = sent + 1
	return 0
end
ns.db = {}
ns.charDB.progress = nil
ns.SendTravelStats()
assert(sent == 0, "a fresh install sends no snapshot")
moving, now, x = true, 7, 1014
ns.tick()
now, x = 8, 1021
ns.tick()
assert(ns.TravelStats().walkedYards == 0, "a fresh install records no distance")
taxi, now = true, 9
ns.tick()
taxi, now = false, 10
ns.tick()
assert(ns.TravelStats().flightsTaken == 0, "and no flights")
ns.ProgressJourneyChanged(nil, "arrived")
assert(ns.TravelStats().routesCompleted == 0, "and no completed journeys")
assert(sent == 0, "and still nothing sent")
-- A character who already had the journal on keeps it: the default only fills a key that was absent.
ns.db.stats = true
now, x = 11, 1021
ns.tick()
now, x = 12, 1028
ns.tick()
assert(ns.TravelStats().walkedYards == 7, "turning the journal on starts recording again")

print("progress_spec: local stats, conservative movement, milestones, sharing opt out, defaults and leaderboard ok")

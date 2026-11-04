local harness = dofile("tests/progress_harness.lua")

local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end

local off = harness({ stats = true, statsShare = false })
off.ns.ProgressJourneyChanged(nil, "arrived")
off:Fire("PLAYER_ENTERING_WORLD")
off:Fire("GROUP_ROSTER_UPDATE")
for _ = 1, 20 do
	off:Tick()
end
check(#off.sent == 0, "saved opt-out sends nothing on progress or membership events")
check(off.ns.TravelStats().routesCompleted == 1, "opt-out still records personal progress")

local migrated = harness(nil, {
	routesCompleted = 11,
	peers = {
		fieldguide = { Unused = {} },
		spf = {
			["Amy-Test Realm"] = { routes_completed = { all = { value = 7, eventUnix = 900 } } },
			amy = { routes_completed = { all = { value = 12, eventUnix = 950 } } },
			["Tester-TestRealm"] = { routes_completed = { all = { value = 999, eventUnix = 950 } } },
			Bad = { routes_completed = { all = { value = "bad", eventUnix = 950 } } },
		},
	},
})
local migratedBoard = migrated.ns.TravelLeaderboard("routesCompleted")
check(
	#migratedBoard == 2 and migratedBoard[1].value == 12,
	"migration merges realm spellings and rejects own or malformed rows"
)
check(migrated.ns.charDB.progress.peers.fieldguide == nil, "migration drops unused foreign caches")
check(migrated.ns.TravelStats().routesCompleted == 11, "migration preserves personal progress")

local h = harness()
for _ = 1, 100 do
	h.ns.ProgressJourneyChanged(nil, "arrived")
end
check(#h.timers <= 2, "many progress events schedule only one progress sync plus login")
h:Tick(5)
h.group = false
h:Fire("GROUP_ROSTER_UPDATE")
for _ = 1, 20 do
	h:Tick()
end
local guild, group = 0, 0
for _, row in ipairs(h.sent) do
	check(
		row.prefix == "WFAStats" and row.payload:match("^1|spf|[%w_]+|all|%d+|%d+$"),
		"only local aggregate rows are sent"
	)
	if row.channel == "GUILD" then
		guild = guild + 1
	else
		group = group + 1
	end
end
check(guild == 5 and group == 0, "leaving the group does not strand queued guild rows")
local before = #h.sent
h.ns.SendTravelStats()
for _ = 1, 5 do
	h:Tick()
end
check(#h.sent == before, "unchanged snapshots are not sent again")

h:Fire("CHAT_MSG_ADDON", "WFAStats", "1|spf|routes_completed|all|200|1000", "GUILD", "Amy-TestRealm")
h:Fire("CHAT_MSG_ADDON", "WFAStats", "1|spf|routes_completed|all|200|1000", "GUILD", "Zed-TestRealm")
local board = h.ns.TravelLeaderboard("routesCompleted")
check(board[1].name == "Amy (reported)" and board[2].name == "Zed (reported)", "ties use canonical names")
h.ns.ProgressJourneyChanged(nil, "arrived")
h.ns.SendTravelStats()
h.ns.db.statsShare = false
h.ns.TravelSharingChanged()
before = #h.sent
for _ = 1, 40 do
	h:Tick()
end
check(#h.sent == before, "opt-out cancels queued and scheduled sends")
check(#h.ns.TravelLeaderboard("routesCompleted") == 1, "opt-out retains only the personal row")
check(next(h.ns.TravelStats().peers) == nil, "public stats hide cached peers during opt-out")
h:Fire("CHAT_MSG_ADDON", "WFAStats", "1|spf|routes_completed|all|999|1000", "GUILD", "Amy-TestRealm")
h.ns.db.statsShare = true
h.ns.TravelSharingChanged()
check(
	h.ns.TravelLeaderboard("routesCompleted")[1].value == 200,
	"opt-out ignored incoming reports and re-enable retains cache"
)
for _ = 1, 10 do
	h:Tick()
end
check(#h.sent > before, "re-enable resends personal rows")

local cached = h.ns.charDB.progress
local reload = harness({ stats = false, statsShare = true }, cached)
reload:Fire("PLAYER_ENTERING_WORLD")
reload.ns.ProgressJourneyChanged(nil, "arrived")
for _ = 1, 20 do
	reload:Tick()
end
check(
	#reload.sent == 0 and reload.ns.TravelStats().routesCompleted == 101,
	"recording opt-out survives reload without sends or updates"
)
check(#reload.ns.TravelLeaderboard("routesCompleted") == 1, "recording opt-out hides peers too")
reload.ns.db.stats = true
reload.ns.TravelSharingChanged()
check(#reload.ns.TravelLeaderboard("routesCompleted") == 3, "reload preserves peer history")
for id = 1, 7 do
	reload:Fire(
		"CHAT_MSG_ADDON",
		"WFAStats",
		"1|spf|routes_completed|all|300|1000",
		"GUILD",
		"Example" .. id .. "-Other"
	)
end
reload.ns.PrintTravelLeaderboard("routesCompleted")
check(
	#reload.printed == 8 and reload.printed[8]:find("You (local)", 1, true),
	"printed top five also includes the player's lower rank"
)
local actualStore = {}
local source = h.ns.PeerStats.New({
	addon = "agf",
	enabled = function()
		return true
	end,
	db = function()
		return actualStore
	end,
	metrics = { quest_turn_ins = { subject = "all" } },
	snapshot = function()
		return { { metric = "quest_turn_ins", subject = "all", value = 9 } }
	end,
})
check(source:Sync() == 1, "another addon's source sender stays independent")
h:Fire("CHAT_MSG_ADDON", "WFAStats", "1|agf|quest_turn_ins|all|19|1000", "GUILD", "Alice-Other")
check(actualStore["Alice-Other"].quest_turn_ins.all.value == 19, "the source receives its own metric")
check(h.ns.TravelStats().peers.agf == nil, "SPF does not copy unrelated addon records")
print(("progress transport: %d checks passed"):format(checks))

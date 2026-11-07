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
local migratedBoard = migrated.ns.TravelBoard("all")
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
local board = h.ns.TravelBoard("all")
check(board[1].name == "Amy" and board[2].name == "Zed", "ties use canonical names")
h.ns.ProgressJourneyChanged(nil, "arrived")
h.ns.SendTravelStats()
h.ns.db.statsShare = false
h.ns.TravelSharingChanged()
before = #h.sent
for _ = 1, 40 do
	h:Tick()
end
check(#h.sent == before, "opt-out cancels queued and scheduled sends")
check(#h.ns.TravelBoard("all") == 1, "opt-out retains only the personal row")
check(next(h.ns.TravelStats().peers) == nil, "public stats hide cached peers during opt-out")
h:Fire("CHAT_MSG_ADDON", "WFAStats", "1|spf|routes_completed|all|999|1000", "GUILD", "Amy-TestRealm")
h.ns.db.statsShare = true
h.ns.TravelSharingChanged()
check(h.ns.TravelBoard("all")[1].value == 200, "opt-out ignored incoming reports and re-enable retains cache")
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
check(#reload.ns.TravelBoard("all") == 1, "recording opt-out hides peers too")
reload.ns.db.stats = true
reload.ns.TravelSharingChanged()
check(#reload.ns.TravelBoard("all") == 3, "reload preserves peer history")
for id = 1, 7 do
	reload:Fire(
		"CHAT_MSG_ADDON",
		"WFAStats",
		"1|spf|routes_completed|all|300|1000",
		"GUILD",
		"Example" .. id .. "-Other"
	)
end
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

--[[ Forever Leaderboards: the addon's own board and command ]]
local opened, spec
local boards = {
	Register = function(_, key, registered)
		registered.key = key
		spec = registered
	end,
	Open = function(_, key)
		opened = key
	end,
}
local shared = harness(nil, nil, boards)
check(spec and spec.key == "spf", "the addon registers its board with the shared window")
check(spec.title == "Shortest Path Forever", "the tab carries the addon's title")
check(spec.icon == "Interface\\Icons\\INV_Misc_Spyglass_03", "the tab carries the game's spyglass icon")
check(spec.metric == "Completed journeys", "the board names its metric")
check(type(spec.revision) == "function", "the board has a revision callback")
check(spec.sharing(), "sharing is on by default")
shared.ns.ProgressJourneyChanged(nil, "arrived")
shared:Fire("CHAT_MSG_ADDON", "WFAStats", "1|spf|routes_completed|all|9|1000", "GUILD", "Amy-TestRealm")
local sharedRows = spec.board("all")
check(sharedRows[1].name == "Amy" and sharedRows[1].value == 9, "the all-time board ranks peers")
check(sharedRows[1].class == nil, "a peer's class stays unknown")
check(
	sharedRows[2].you == true and sharedRows[2].class == nil,
	"the player's own row is marked, its class left to the shared window"
)
shared:Fire("CHAT_MSG_ADDON", "WFAStats", "1|spf|routes_completed|all|14|1100", "GUILD", "Amy-TestRealm")
local weekRows = spec.board("week")
check(
	weekRows[1].name == "Amy" and weekRows[1].value == 5 and weekRows[1].extra == "14 total",
	"the weekly board shows progress since the reset and the cumulative total"
)
spec.setSharing(false)
check(not spec.sharing() and #spec.board("all") == 1, "the window's sharing switch hides peers at once")
spec.setSharing(true)
check(spec.sharing(), "turning the switch back on restores sharing")
shared.ns.OpenTravelLeaderboard()
check(opened == "spf", "the leaderboard command opens this addon's tab")
print(("progress transport: %d checks passed"):format(checks))

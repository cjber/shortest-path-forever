-- Run from the repository root: luajit tests/timetable_spec.lua
-- The live timetable through its own interface, against a clock the spec moves: the saved sightings, what leaves a
-- dock and in what order, lanes merged per destination, freshness, the faction filter and the status wording.
local clock = { time = 0, server = 1790000000 }
local faction = "Alliance"

-- Core.lua for the real Init, clock and faction filter; then the timetable, started as at login.
local function login(saved)
	local frames = {}
	local env = setmetatable({
		ShortestPathForeverDB = saved,
		GetRealmName = function()
			return "Test"
		end,
		GetServerTime = function()
			return clock.server
		end,
		GetTime = function()
			return clock.time
		end,
		UnitFactionGroup = function()
			return faction
		end,
		geterrorhandler = function()
			return error
		end,
		CreateFrame = function()
			local frame = { RegisterEvent = function() end, RegisterUnitEvent = function() end }
			frame.UnregisterEvent = frame.RegisterEvent
			function frame:SetScript(name, fn)
				self[name] = fn
			end
			frames[#frames + 1] = frame
			return frame
		end,
	}, { __index = _G })
	local ns = {
		Docks = { { name = "One" }, { name = "Two" }, { name = "Three" }, { name = "Four" }, { name = "Five" } },
		Routes = {
			-- Two boats sharing the lane from One to Two.
			[10] = {
				kind = "boat",
				period = 100000,
				stops = { { dock = 1, arrive = 0, depart = 20000 }, { dock = 2, arrive = 50000, depart = 70000 } },
			},
			[11] = {
				kind = "boat",
				period = 100000,
				stops = { { dock = 1, arrive = 30000, depart = 40000 }, { dock = 2, arrive = 80000, depart = 90000 } },
			},
			[12] = {
				kind = "zeppelin",
				faction = "Horde",
				period = 90000,
				stops = {
					{ dock = 1, arrive = 0, depart = 10000 },
					{ dock = 3, arrive = 30000, depart = 40000 },
					{ dock = 2, arrive = 60000, depart = 70000 },
				},
			},
			[13] = {
				kind = "tram",
				period = 60000,
				stops = { { dock = 4, arrive = 0, depart = 10000 }, { dock = 5, arrive = 30000, depart = 40000 } },
			},
		},
	}
	for _, file in ipairs({ "Locales/enUS.lua", "Transport/Model.lua", "Core/Core.lua", "Transport/Timetable.lua" }) do
		setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
	end
	frames[1]:OnEvent("ADDON_LOADED", "ShortestPathForever")
	return ns, ns.Timetable
end
local function advance(seconds)
	clock.time, clock.server = clock.time + seconds, clock.server + seconds
end
local function equal(actual, expected, label)
	assert(actual == expected, ("%s: %s, expected %s"):format(label, tostring(actual), tostring(expected)))
end
local function routes(departures)
	local ids = {}
	for index, departure in ipairs(departures) do
		ids[index] = departure.route
	end
	return table.concat(ids, " ")
end

-- The saved file: a fresh install gains this realm's table; a stale sighting is dropped at login, nothing else moves.
local MAX_AGE = 6 * 3600
equal(next(login(nil).db.anchors.Test), nil, "a new install starts with no sightings")
local saved = {
	anchors = {
		Test = {
			[10] = { epoch = 5, seen = clock.server - MAX_AGE - 1, source = "you" },
			[11] = { epoch = 7, seen = clock.server - MAX_AGE, source = "player" },
		},
		Other = { [10] = { epoch = 9, seen = 1 } },
	},
}
local held = saved.anchors.Test[11]
local ns, Timetable = login(saved)
assert(ns.db == saved and saved.anchors.Test[10] == nil, "a sighting too stale to count down from is dropped")
assert(saved.anchors.Test[11] == held and saved.anchors.Other[10].epoch == 9, "fresh and other-realm sightings stay")
assert(Timetable.Anchor(11) == held and Timetable.Anchors()[11] == held and Timetable.Anchor(10) == nil)
advance(1)
assert(Timetable.Anchor(11) == nil and next(Timetable.Anchors()) == nil, "a sighting ages out while you play")
assert(saved.anchors.Test[11] == held, "and is only dropped from the file at the next login")

-- Untimed: every shown route in route order, with no times.
ns, Timetable = login({})
saved = ns.db
local changes = 0
Timetable.OnChange(function()
	changes = changes + 1
end)
equal(Timetable.Version(), 0, "version")
local departures = Timetable.Departures(1)
equal(routes(departures), "10 11", "untimed order, the other faction's zeppelin hidden")
assert(not departures[1].known and departures[1].kind == "boat" and departures[1].departIn == nil)
equal(table.concat(departures[1].to, " "), "2", "where it calls after this dock")
equal(Timetable.Status(departures[1]), "no sighting yet", "untimed status")
equal(Timetable.Destination(departures[1]), "Two", "destination")
equal(#Timetable.ByDestination(1), 1, "one line per destination")
equal(Timetable.ByDestination(1)[1].thenIn, nil, "nothing to follow an untimed boat")
equal(#Timetable.Departures(99), 0, "a dock no route calls at")
assert(Timetable.NextStop(10) == nil and Timetable.Visit(10, ns.Routes[10].stops[1], ns.NowMs()) == nil, "untimed")

-- One boat timed, docked at One with 15 s left.
local function sight(routeID, phase, source)
	return Timetable.Sighted(routeID, { epoch = ns.NowMs() - phase, seen = clock.server, source = source })
end
assert(sight(10, 5000, "you"), "a first sighting is kept")
assert(changes == 1 and Timetable.Version() == 1, "a kept sighting tells the listeners once")
local stored = saved.anchors.Test[10]
assert(stored.epoch == ns.NowMs() - 5000 and stored.seen == clock.server and stored.source == "you", "saved shape")
for key in pairs(stored) do
	assert(key == "epoch" or key == "seen" or key == "source", "saved shape gained " .. key)
end
departures = Timetable.Departures(1)
equal(routes(departures), "10 11", "timed boats come before untimed ones")
local first = departures[1]
assert(first.known and first.docked and first.arriveIn == nil and first.departIn == 15000, "docked now")
assert(first.seen == 0 and first.source == "you", "when and by whom it was timed")
equal(Timetable.Status(first), "docked · leaves 0:15", "docked status")
equal(Timetable.ByDestination(1)[1].thenIn, nil, "the lane's other boat is untimed")
local docked, arriveIn, departIn = Timetable.Visit(10, ns.Routes[10].stops[2], ns.NowMs())
assert(docked == false and arriveIn == 45000 and departIn == 65000, "its other stop, now")
docked, arriveIn, departIn = Timetable.Visit(10, ns.Routes[10].stops[2], ns.NowMs() + 50000)
assert(docked == true and arriveIn == nil and departIn == 15000, "and as of a later time")
local nextDock, nextIn = Timetable.NextStop(10)
assert(nextDock == 2 and nextIn == 45000, "the docked stop is not the next one")

-- The lane's second boat, timed by someone else: arrives in 10 s, leaves in 20 s.
assert(sight(11, 20000, "player"))
departures = Timetable.Departures(1)
equal(routes(departures), "10 11", "soonest to leave first")
equal(Timetable.Status(departures[2]), "arrives 0:10 · leaves 0:20", "arriving status")
local lines = Timetable.ByDestination(1)
assert(#lines == 1 and lines[1].route == 10 and lines[1].thenIn == 20000, "a shared lane reads as one line")
equal(Timetable.Status(lines[1]), "docked · leaves 0:15, then 0:20", "merged status")
equal(routes(Timetable.Departures(2)), "10 11", "the far dock, by its own departures")

-- 16 s on, the first boat has sailed and the second is in.
advance(16)
departures = Timetable.Departures(1)
equal(routes(departures), "11 10", "order follows the clock")
assert(
	departures[1].docked
		and departures[1].departIn == 4000
		and departures[1].seen == 16
		and departures[1].source == "player"
)
assert(not departures[2].docked and departures[2].arriveIn == 79000 and departures[2].departIn == 99000)
lines = Timetable.ByDestination(1)
assert(lines[1].route == 11 and lines[1].thenIn == 99000, "the line leads with whichever leaves next")
nextDock, nextIn = Timetable.NextStop(10)
assert(nextDock == 2 and nextIn == 29000, "under way to Two")

-- Which sighting stands.
local version = Timetable.Version()
assert(not Timetable.Sighted(10, { epoch = 1, seen = clock.server - 20, source = "you" }), "an older sighting")
assert(not Timetable.Sighted(10, { epoch = 1, seen = clock.server, source = "player" }), "your own recent ride stands")
assert(Timetable.Version() == version and changes == 2, "a rejected sighting changes nothing")
assert(saved.anchors.Test[10] == stored, "nor the saved file")
assert(Timetable.Sighted(11, { epoch = stored.epoch, seen = clock.server, source = "player" }), "a newer sighting")
assert(Timetable.Version() == version + 1 and changes == 3)
equal(Timetable.Departures(1)[1].departIn, 19000, "the newer sighting is the one counted down from")

-- The faction filter: the other side's zeppelin only when asked for, with every call it makes.
saved.otherFaction = true
departures = Timetable.Departures(1)
equal(routes(departures), "11 10 12", "opted in")
equal(Timetable.Destination(departures[3]), "Three, then Two", "a route with two calls onward")
equal(#Timetable.ByDestination(1), 2, "a different destination is its own line")
saved.otherFaction = false
faction = "Horde"
equal(routes(Timetable.Departures(1)), "11 10 12", "your own faction's route needs no opt-in")
faction = "Alliance"
equal(#Timetable.Visits(1), 3, "visits list every route, shown or not")

-- Each kind's word for being here.
assert(sight(13, 2000, "you"))
equal(Timetable.Status(Timetable.Departures(4)[1]), "boarding · leaves 0:08", "tram status")
departures = Timetable.Departures(5)
equal(Timetable.Status(departures[1]), "arrives 0:28 · leaves 0:38", "the far station")
ns.Routes[13].kind = "lift"
equal(Timetable.Status(Timetable.Departures(4)[1]), "here · leaves 0:08", "lift status")

-- Freshness: six hours after its sighting a route is untimed again.
advance(MAX_AGE - 16)
assert(Timetable.Anchor(10) and Timetable.Departures(1)[2].known, "still fresh at exactly six hours")
advance(1)
assert(Timetable.Anchor(10) == nil and Timetable.Anchors()[10] == nil and Timetable.Anchors()[11], "aged out")
departures = Timetable.Departures(1)
assert(routes(departures) == "11 10" and not departures[2].known, "the fresher boat still counts down")
assert(Timetable.NextStop(10) == nil and Timetable.Visit(10, ns.Routes[10].stops[1], ns.NowMs()) == nil)
print("timetable_spec: ok")

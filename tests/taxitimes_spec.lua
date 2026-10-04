-- Run from the repository root: luajit tests/taxitimes_spec.lua
-- The learned flight times through their own interface: the saved file pruned to the shipped paths and a sane
-- range, a shared opening matched to the path actually flown, each hop timed and saved, and the remaining time of
-- a leg read from where the player is on its drawn path.
local ns
ns = {
	db = {
		taxiTimes = {
			["1:2"] = 40,
			["9:9"] = 12,
			["1:3"] = 99999,
			["2:1"] = "nope",
		},
	},
	TaxiNodes = {
		[1] = { map = 1, x = 0, y = 0, name = "A" },
		[2] = { map = 1, x = 1000, y = 0, name = "B" },
		[3] = { map = 1, x = 2000, y = 0, name = "C" },
	},
	Init = function(fn)
		ns.start = fn
	end,
}
ns.TaxiPaths = {
	{ from = 1, to = 2, seconds = 30, points = { 1, 0, 0, 1, 500, 0, 1, 1000, 0 } },
	-- Shares the first stretch from A, then turns away, so the flown path is not clear at take-off.
	{ from = 1, to = 3, seconds = 60, points = { 1, 0, 0, 1, 400, 300, 1, 1000, 600, 1, 2000, 0 } },
	{ from = 2, to = 3, seconds = 30, points = { 1, 1000, 0, 1, 1500, 0, 1, 2000, 0 } },
}
local now, onTaxi, map, x, y = 0, false, 1, 0, 0
local tick
ns.OnTravelTick = function(fn)
	tick = fn
end
local env = setmetatable({
	GetTime = function()
		return now
	end,
	UnitPosition = function()
		return x, y, 0, map
	end,
	UnitOnTaxi = function()
		return onTaxi
	end,
	geterrorhandler = function()
		return error
	end,
}, { __index = _G })
local function load(file)
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end
local function equal(actual, expected, label)
	assert(actual == expected, ("%s: %s, expected %s"):format(label, tostring(actual), tostring(expected)))
end
local function near(actual, expected, label)
	assert(
		actual and math.abs(actual - expected) < 0.001,
		("%s: %s, expected %s"):format(label, tostring(actual), expected)
	)
end

load("Locales/enUS.lua")
load("Transport/TaxiTimes.lua")
ns.start()
ns.FormatCountdown = function(ms)
	return tostring(math.floor(ms))
end
load("Journey/JourneySteps.lua")
local TaxiTimes = ns.TaxiTimes

-- The file at login: a reading for a path the data still has stays, everything else goes.
equal(ns.db.taxiTimes["1:2"], 40, "a measured path in the shipped data stays")
assert(ns.db.taxiTimes["9:9"] == nil, "a path the data no longer has is dropped")
assert(ns.db.taxiTimes["1:3"] == nil, "an implausible reading is dropped")
assert(ns.db.taxiTimes["2:1"] == nil, "a non-number is dropped")

local first = TaxiTimes.Snapshot()
assert(TaxiTimes.Snapshot() == first, "the snapshot is reused until a ride adds one")
equal(first["1:2"], 40, "the snapshot carries the saved reading")
equal(TaxiTimes.Seconds(1, 2), 40, "measured seconds by directed path")
assert(TaxiTimes.Seconds(2, 1) == nil, "an unmeasured path has no time")

local function step(at, px, py)
	now, x, y = at, px, py
	tick()
end

-- A ride from A to B with a second path sharing the opening.
onTaxi = true
step(0, 0, 0)
assert(not TaxiTimes.CurrentPath(), "a shared opening does not commit a hop")
step(3, 300, 0)
assert(TaxiTimes.CurrentPath() == ns.TaxiPaths[1], "the flown path is committed once the match is clear")

local leg = { mode = "flight", hops = { ns.TaxiPaths[1] }, depart = 0, arrive = 30000 }
step(6, 600, 0)
near(TaxiTimes.Remaining(leg), 12000, "remaining follows progress on the drawn path")
equal(ns.LegTime(leg), "12000", "the flight step shows the observed remaining time")
local other = { mode = "flight", hops = { ns.TaxiPaths[2] }, depart = 0, arrive = 60000 }
assert(TaxiTimes.Remaining(other) == nil, "another flight leg is not the one being flown")

step(9, 1000, 0)
equal(ns.db.taxiTimes["1:2"], 9, "the landed hop's own seconds are saved")
assert(TaxiTimes.CurrentPath() == nil, "the hop ended at its flight point")
step(12, 1500, 0)
assert(TaxiTimes.CurrentPath() == ns.TaxiPaths[3], "the connecting hop begins where the last one landed")
step(15, 2000, 0)
equal(ns.db.taxiTimes["2:3"], 6, "the connecting hop is timed too")
onTaxi = false
step(18, 2000, 0)
assert(TaxiTimes.CurrentPath() == nil, "landing clears the ride")

local second = TaxiTimes.Snapshot()
assert(second ~= first, "a new measurement is a fresh snapshot")
equal(second["1:2"], 9, "the fresh snapshot carries the measured time")
assert(TaxiTimes.Remaining(leg) == nil, "no remaining time once landed")

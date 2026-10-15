-- Keeping the player's own journey across a reload or relog (Journey/Resume.lua).
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
local timers = {}
env.C_Timer = {
	After = function(delay, fn)
		timers[#timers + 1] = { delay = delay, fn = fn }
	end,
}
env.hooksecurefunc = function(target, key, hook)
	local original = target[key]
	target[key] = function(...)
		original(...)
		hook(...)
	end
end
local combat = false
env.InCombatLockdown = function()
	return combat
end
-- The waits longer than a frame: Resume's own.
local function waits()
	local count = 0
	for _, timer in ipairs(timers) do
		if timer.delay > 0 then
			count = count + 1
		end
	end
	return count
end
local function runTimers()
	local due = timers
	timers = {}
	for _, timer in ipairs(due) do
		timer.fn()
	end
end
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API
-- A fresh copy of the module, as after a /reload: its first loading screen is the reload's.
local function reload()
	driver.load("Journey/Resume.lua")
end
reload()
driver.fire("PLAYER_ENTERING_WORLD")
runTimers()
ns.serverTime = 1000

-- Off by default: nothing is kept.
ns.db.resumeJourney = false
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 2000, y = 0 })
assert(ns.HasJourney() and ns.charDB.journey == nil, "the setting off keeps nothing")
ns.ClearJourney()

-- On: the player's own journey is kept with its goal and when it was planned.
ns.db.resumeJourney = true
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 2000, y = 0 })
local kept = ns.charDB.journey
local function near(a, b)
	return math.abs(a - b) < 1e-6
end
assert(kept and kept.map == 1 and near(kept.x, 2000) and near(kept.y, 0) and kept.at == 1000, "the goal is kept")
ns.ClearJourney()
assert(ns.charDB.journey == nil, "an ended journey is forgotten")

-- A journey another addon owns is theirs to start again.
assert(API.Navigate("AGF", 1, 0.6, 0.5, "Quest giver"))
assert(ns.charDB.journey == nil, "an owned journey is not kept")
ns.ClearJourney()
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 2000, y = 0 })
assert(ns.charDB.journey)
assert(API.Navigate("AGF", 1, 0.6, 0.5, "Quest giver"))
assert(ns.charDB.journey == nil, "replaced by an owned journey: forgotten")
ns.ClearJourney()

-- A /reload: the kept journey starts again a moment after the loading screen, as it was.
local function keep(fields)
	ns.charDB.journey = fields
end
keep({ map = 1, x = 2000, y = 0, label = "Goldshire", at = 1000 })
ns.serverTime = 1000 + 60
reload()
driver.fire("PLAYER_ENTERING_WORLD")
assert(waits() == 1, "after the owners have had a moment")
assert(not ns.HasJourney(), "not straight away")
runTimers()
assert(ns.HasJourney(), "the journey starts again")
assert(ns.JourneyInfo() == "Journey to Goldshire", "with its name")
local again = ns.charDB.journey
assert(again and near(again.x, 2000) and again.at == 1060, "and is kept again as a new journey")
driver.fire("PLAYER_ENTERING_WORLD")
assert(waits() == 0, "a later loading screen is not a reload")
ns.ClearJourney()

-- Too old, turned off, Journeys off, or another journey first: forgotten, never started.
local function resumes(setup)
	keep({ map = 1, x = 2000, y = 0, at = ns.serverTime })
	setup()
	reload()
	driver.fire("PLAYER_ENTERING_WORLD")
	runTimers()
	local started = ns.HasJourney()
	ns.ClearJourney()
	ns.db.resumeJourney, ns.db.journey = true, true
	return started
end
assert(not resumes(function()
	ns.serverTime = ns.serverTime + 31 * 60
end), "half an hour old is too old")
assert(
	resumes(function()
		ns.charDB.journey.at = ns.serverTime - 29 * 60
	end),
	"a relog within half an hour"
)
assert(not resumes(function()
	ns.db.resumeJourney = false
end), "the setting off")
assert(not resumes(function()
	ns.db.journey = false
end), "Journeys off")
assert(not resumes(function()
	ns.charDB.journey.x = "far"
end), "a damaged entry")
do
	keep({ map = 1, x = 2000, y = 0, label = "Kept", at = ns.serverTime })
	reload()
	driver.fire("PLAYER_ENTERING_WORLD")
	ns.StartJourney({ map = 1, x = 500, y = 0, label = "Elsewhere" })
	runTimers()
	assert(ns.JourneyInfo() == "Journey to Elsewhere", "a journey you started meanwhile runs on")
	assert(ns.charDB.journey and ns.charDB.journey.label == "Elsewhere", "and stays the one kept")
	ns.ClearJourney()
end
do
	keep({ map = 1, x = 2000, y = 0, label = "Kept", at = ns.serverTime })
	reload()
	driver.fire("PLAYER_ENTERING_WORLD")
	assert(API.Navigate("AGF", 1, 0.6, 0.5, "Guide step"))
	runTimers()
	assert(ns.JourneyInfo() == "Journey to Guide step", "an owner that started first wins")
	assert(ns.charDB.journey == nil, "and the kept journey is forgotten")
	ns.ClearJourney()
end

-- In combat it waits for combat to end.
keep({ map = 1, x = 2000, y = 0, at = ns.serverTime })
reload()
driver.fire("PLAYER_ENTERING_WORLD")
combat = true
runTimers()
assert(not ns.HasJourney() and ns.charDB.journey, "kept through the fight")
combat = false
driver.fire("PLAYER_REGEN_ENABLED")
assert(ns.HasJourney(), "and started once it ends")
ns.ClearJourney()
driver.fire("PLAYER_REGEN_ENABLED")
assert(not ns.HasJourney(), "only once")

print("resume_spec: ok")

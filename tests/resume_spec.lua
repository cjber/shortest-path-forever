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
driver.load("Core/APIInput.lua")
driver.load("Core/APIStops.lua")
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

-- The player's own journey is kept with its goal and when it was planned.
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 2000, y = 0 })
local kept = ns.charDB.journey
local function near(a, b)
	return math.abs(a - b) < 1e-6
end
assert(kept and kept.map == 1 and near(kept.x, 2000) and near(kept.y, 0), "the goal is kept")
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
keep({ map = 1, x = 2000, y = 0, label = "Goldshire" })
ns.serverTime = 1000 + 60
reload()
driver.fire("PLAYER_ENTERING_WORLD")
assert(waits() == 1, "after the owners have had a moment")
assert(not ns.HasJourney(), "not straight away")
runTimers()
assert(ns.HasJourney(), "the journey starts again")
assert(ns.JourneyInfo() == "Journey to Goldshire", "with its name")
local again = ns.charDB.journey
assert(again and near(again.x, 2000), "and is kept again as a new journey")
driver.fire("PLAYER_ENTERING_WORLD")
assert(waits() == 0, "a later loading screen is not a reload")
ns.ClearJourney()

-- Too old, turned off, Journeys off, or another journey first: forgotten, never started.
local function resumes(setup)
	keep({ map = 1, x = 2000, y = 0 })
	setup()
	reload()
	driver.fire("PLAYER_ENTERING_WORLD")
	runTimers()
	local started = ns.HasJourney()
	ns.ClearJourney()
	ns.db.journey = true
	return started
end
assert(
	resumes(function()
		ns.serverTime = ns.serverTime + 3 * 24 * 60 * 60
	end),
	"a journey days old still starts again"
)
assert(not resumes(function()
	ns.db.journey = false
end), "Journeys off")
assert(not resumes(function()
	ns.charDB.journey.x = "far"
end), "a damaged entry")
do
	keep({ map = 1, x = 2000, y = 0, label = "Kept" })
	reload()
	driver.fire("PLAYER_ENTERING_WORLD")
	ns.StartJourney({ map = 1, x = 500, y = 0, label = "Elsewhere" })
	runTimers()
	assert(ns.JourneyInfo() == "Journey to Elsewhere", "a journey you started meanwhile runs on")
	assert(ns.charDB.journey and ns.charDB.journey.label == "Elsewhere", "and stays the one kept")
	ns.ClearJourney()
end
do
	keep({ map = 1, x = 2000, y = 0, label = "Kept" })
	reload()
	driver.fire("PLAYER_ENTERING_WORLD")
	assert(API.Navigate("AGF", 1, 0.6, 0.5, "Guide step"))
	runTimers()
	assert(ns.JourneyInfo() == "Journey to Guide step", "an owner that started first wins")
	assert(ns.charDB.journey == nil, "and the kept journey is forgotten")
	ns.ClearJourney()
end

-- Nearby services' journeys go through the API under this addon's own name: they are the player's.
assert(API.Navigate("Shortest Path Forever", 1, 0.6, 0.5, "Innkeeper", "innkeeper"))
assert(ns.charDB.journey and ns.charDB.journey.label == "Innkeeper", "a Nearby journey is kept")
ns.ClearJourney()

-- A kept stop's hand-in quests travel with it, so the game's own pins stay hidden after a reload too.
assert(API.NavigateRoute("Shortest Path Forever", {
	{ map = 1, x = 0.6, y = 0.5, label = "Hand-in", handins = { 21, 22 } },
}))
local keptHandins = ns.charDB.journey and ns.charDB.journey.handins
assert(keptHandins and keptHandins[1] == 21 and keptHandins[2] == 22, "a kept stop's hand-ins are kept")
ns.serverTime = ns.serverTime + 10
reload()
driver.fire("PLAYER_ENTERING_WORLD")
runTimers()
assert(ns.HasJourney() and ns.JourneyGoal().handins[1] == 21, "the hand-ins are resumed with the journey")
ns.ClearJourney()
-- A damaged hand-in list is dropped, not resumed.
keep({ map = 1, x = 2000, y = 0, handins = { 21, "22" } })
reload()
driver.fire("PLAYER_ENTERING_WORLD")
runTimers()
assert(ns.HasJourney() and ns.JourneyGoal().handins == nil, "a damaged hand-in list is dropped")
ns.ClearJourney()

-- A long journey survives its reload however long ago it was planned.
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 2000, y = 0 })
ns.serverTime = ns.serverTime + 45 * 60
local saved = ns.charDB.journey
ns.ClearJourney()
ns.charDB.journey = saved
ns.serverTime = ns.serverTime + 10
reload()
driver.fire("PLAYER_ENTERING_WORLD")
runTimers()
assert(ns.HasJourney(), "a journey planned 45 minutes ago starts again after its reload")
ns.ClearJourney()

-- A journey started and ended while the owners have their moment: the kept one is not brought back.
keep({ map = 1, x = 2000, y = 0 })
reload()
driver.fire("PLAYER_ENTERING_WORLD")
ns.StartJourney({ map = 1, x = 500, y = 0, label = "Brief" })
ns.ClearJourney()
runTimers()
assert(not ns.HasJourney(), "the player moved on from the kept journey")

-- Infinite coordinates from a damaged file are refused.
assert(not resumes(function()
	ns.charDB.journey.x = math.huge
end), "an infinite coordinate")

-- In combat it waits for combat to end.
keep({ map = 1, x = 2000, y = 0 })
reload()
driver.fire("PLAYER_ENTERING_WORLD")
combat = true
runTimers()
assert(not ns.HasJourney() and ns.charDB.journey, "kept through the fight")
combat = false
driver.fire("PLAYER_REGEN_ENABLED")
assert(ns.HasJourney(), "and started once it ends")
ns.ClearJourney()
-- Combat ending before the owners' moment is over still waits for it.
keep({ map = 1, x = 2000, y = 0 })
reload()
driver.fire("PLAYER_ENTERING_WORLD")
driver.fire("PLAYER_REGEN_ENABLED")
assert(not ns.HasJourney(), "not before the owners have had their moment")
runTimers()
assert(ns.HasJourney(), "then it starts")
ns.ClearJourney()
driver.fire("PLAYER_REGEN_ENABLED")
assert(not ns.HasJourney(), "only once")

print("resume_spec: ok")

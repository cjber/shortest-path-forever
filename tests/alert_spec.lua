-- The arrival sound (UI/Alert.lua, #155): the map's ping once when a journey reaches its last stop, only with
-- "Play a sound on arrival" on; never on a clear, a replacement or a guide's next stop.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
local played = {}
local warnings, flashes, ticks = {}, 0, {}
env.RaidWarningUtil = {
	AddMessage = function(text)
		warnings[#warnings + 1] = text
	end,
}
env.ChatTypeInfo = { RAID_WARNING = {} }
env.FlashClientIcon = function()
	flashes = flashes + 1
end
ns.OnTravelTick = function(fn)
	ticks[#ticks + 1] = fn
end
env.PlaySoundFile = function(file, channel)
	played[#played + 1] = { file = file, channel = channel }
end
env.hooksecurefunc = function(target, key, hook)
	local original = target[key]
	target[key] = function(...)
		original(...)
		hook(...)
	end
end
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
driver.load("UI/Alert.lua")
local API = env.ShortestPathForever.API

-- Off by default: arriving is silent.
ns.db.arrivalSound = false
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 100, y = 0 })
driver.move({ map = 1, x = 100, y = 0 })
driver.update(0.1)
assert(not ns.HasJourney() and #played == 0, "off: arrived in silence")

-- On: the ping, on the Master channel, when the journey reaches its goal.
ns.db.arrivalSound = true
driver.begin({ map = 1, x = 100, y = 0 }, { map = 1, x = 300, y = 0 })
ns.ClearJourney()
assert(#played == 0, "clearing a journey is no arrival")
driver.begin({ map = 1, x = 100, y = 0 }, { map = 1, x = 300, y = 0 })
driver.begin({ map = 1, x = 100, y = 0 }, { map = 1, x = 500, y = 0 })
assert(#played == 0, "replacing a journey is no arrival")
driver.move({ map = 1, x = 500, y = 0 })
driver.update(0.1)
assert(#played == 1 and played[1].file == 567416 and played[1].channel == "Master", "the map's ping on arrival")

-- A guide's route, or a guide's TomTom waypoint: quiet, at every stop and at the last; the guide has its own cues.
driver.move({ map = 1, x = 0, y = 0 })
assert(API.NavigateRoute("AGF", { { map = 1, x = 0.502, y = 0.5 }, { map = 1, x = 0.504, y = 0.5 } }))
driver.update(0.1)
driver.move({ map = 1, x = 0, y = -100 })
driver.update(0.1)
assert(API.CurrentStop("AGF") == 2 and #played == 1, "a guide's next stop is quiet")
driver.move({ map = 1, x = 0, y = -200 })
driver.update(0.1)
assert(API.CurrentStop("AGF") == nil and not ns.HasJourney() and #played == 1, "and so is its last")
assert(API.Navigate("TomTom", 1, 0.506, 0.5))
driver.update(0.1)
driver.move({ map = 1, x = 0, y = -300 })
driver.update(0.1)
assert(not ns.HasJourney() and #played == 1, "a guide's waypoint is quiet")

-- Nearby services' journeys are the player's own: they ping, and a second arrival straight after pings again.
assert(API.Navigate("Shortest Path Forever", 1, 0.508, 0.5, "Innkeeper", "innkeeper"))
driver.update(0.1)
driver.move({ map = 1, x = 0, y = -400 })
driver.update(0.1)
assert(not ns.HasJourney() and #played == 2, "a Nearby journey pings")
driver.begin({ map = 1, x = 0, y = -400 }, { map = 1, x = 0, y = -460 })
driver.move({ map = 1, x = 0, y = -460 })
driver.update(0.1)
assert(not ns.HasJourney() and #played == 3, "every arrival of your own pings")

-- An unknown flight master gets one plan warning, then one more on approach, through the same raid-warning banner
-- and taskbar flash as the timed transport alerts. No sound is guessed for a flight master.
local unknown = { mode = "walk", to = { id = 9001, map = 1, x = 1000, y = 0, undiscovered = true } }
local plan = { legs = { unknown } }
local current = 1
ns.JourneyPlan = function()
	return plan, current
end
local position = { x = 0, y = 0, map = 1 }
ns.JourneyPosition = function()
	return position.x, position.y, position.map
end
ns.LegLabel = function()
	return "Test flight master"
end
ns.db.alerts, ns.db.flightPathReminder, ns.db.alertSound = true, true, true
for _, tick in ipairs(ticks) do
	tick()
end
assert(#warnings == 1 and warnings[1]:find("Step 1", 1, true), "unknown master warns when the plan lands")
for _, tick in ipairs(ticks) do
	tick()
end
assert(#warnings == 1, "plan warning is deduped across tracker ticks")
position.x = 900
for _, tick in ipairs(ticks) do
	tick()
end
assert(#warnings == 2 and warnings[2]:find("near", 1, true), "unknown current master warns on approach")
assert(flashes == 2 and #played == 3, "both warnings flash, with no invented flight-master sound")

-- A known master stays quiet; an unknown master in a later step gets a plan warning but no approach warning.
warnings = {}
plan.legs = { { mode = "walk", to = { id = 9002, map = 1, x = 90, y = 0 } } }
for _, tick in ipairs(ticks) do
	tick()
end
assert(#warnings == 0, "known master is quiet")
plan.legs = {
	{ mode = "walk", to = { id = 9003, map = 1, x = 1000, y = 0 } },
	{ mode = "walk", to = { id = 9004, map = 1, x = 100, y = 0, undiscovered = true } },
}
for _, tick in ipairs(ticks) do
	tick()
end
assert(#warnings == 1 and warnings[1]:find("Step 2", 1, true), "later unknown master is named by its step")

ns.db.flightPathReminder = false
plan.legs = { { mode = "walk", to = { id = 9005, map = 1, x = 100, y = 0, undiscovered = true } } }
for _, tick in ipairs(ticks) do
	tick()
end
assert(#warnings == 1, "the reminder option turns off banners")

print("alert_spec: ok")

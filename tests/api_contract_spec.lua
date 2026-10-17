-- The meanings other addons build on, pinned so they cannot drift without this spec failing. Polestar's hand-off
-- (its docs/ARCHITECTURE.md, "Hand-off to Shortest Path Forever") reads every one of them: it sends its target as one
-- stop through NavigateRoute, steps aside while Active() says a journey not its own guides, guides a stop itself when
-- CurrentStop names it but Active() is false, stops resending once Ended() names a reason, and listens on Subscribe.
-- docs/api.md is the contract; tests/api_spec.lua tests each call in depth.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = driver.ns, driver.env, 0
driver.load("Core/SafeCall.lua")
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API
local OWNER = "Polestar"

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local timers = {}
env.C_Timer = {
	After = function(_, fn)
		timers[#timers + 1] = fn
	end,
}
local combat = false
env.InCombatLockdown = function()
	return combat
end
-- The next frame: Subscribe's callbacks run.
local function frame()
	local due = timers
	timers = {}
	for _, fn in ipairs(due) do
		fn()
	end
end
local heard = {}
local function last()
	return heard[#heard] or {}
end

-- What is there to call: version 1, minor 1 or more, and every function the hand-off checks before calling it.
equal(API.version, 1, "version stays 1")
equal(type(API.minor) == "number" and API.minor >= 1, true, "minor 1 or more")
for _, name in ipairs({ "NavigateRoute", "Navigate", "Cancel", "CurrentStop", "Active", "Ended", "Subscribe" }) do
	equal(type(API[name]), "function", name)
end
local unsubscribe = API.Subscribe(function(changes)
	heard[#heard + 1] = changes
end)
equal(type(unsubscribe), "function", "Subscribe returns its unsubscribe")

-- Before anything: no stop, no end, nothing guiding, and Cancel has nothing to clear.
equal(API.CurrentStop(OWNER), nil, "no stop before the first journey")
equal(API.Ended(OWNER), nil, "no end before the first journey")
equal(API.Active(), false, "nothing guides")
equal(API.Cancel(OWNER), false, "Cancel clears nothing")

-- One stop with a title and a kind: taken, current, guiding, and news of it on the next frame.
local stop = { map = 1, x = 0.502, y = 0.5, title = "Goldshire", kind = "innkeeper" }
equal(API.NavigateRoute(OWNER, { stop }), true, "NavigateRoute takes one stop")
driver.path.settle()
equal(API.CurrentStop(OWNER), 1, "CurrentStop is 1 on the only stop")
equal(API.Active(), true, "Active while it guides")
equal(API.Ended(OWNER), nil, "Ended is nil while it runs")
equal(#heard, 0, "Subscribe's news waits for the next frame")
frame()
equal(#heard, 1, "one call for the burst")
equal(last().started and last().stop and last().active, true, "started, stop and active")

-- The same stop sent again is no change: the journey keeps running and nobody is told.
equal(API.NavigateRoute(OWNER, { stop }), true, "the same stop again")
frame()
equal(#heard, 1, "no news for the same destination")
equal(API.CurrentStop(OWNER), 1, "and the stop stays current")

-- Refused: a stop it cannot place, in combat, or with Journeys off. Each returns false and leaves the journey running.
equal(API.NavigateRoute(OWNER, { { map = 1, x = 2, y = 0.5 } }), false, "a point off the map is refused")
equal(API.NavigateRoute(OWNER, { { map = 0, x = 0.5, y = 0.5 } }), false, "a map the client does not know is refused")
combat = true
equal(API.NavigateRoute(OWNER, { { map = 1, x = 0.6, y = 0.5 } }), false, "refused in combat")
combat = false
ns.db.journey = false
equal(API.NavigateRoute(OWNER, { { map = 1, x = 0.6, y = 0.5 } }), false, "refused with Journeys off")
ns.db.journey = true
equal(API.CurrentStop(OWNER), 1, "a refusal leaves the journey as it was")
equal(API.Navigate(OWNER, 1, 0.502, 0.5, "Goldshire", "innkeeper"), true, "Navigate is the one-stop form")
equal(API.CurrentStop(OWNER), 1, "of the same stop")

-- Arriving at the last stop ends the journey: "arrived", no stop, nothing guiding.
driver.move({ map = 1, x = 0, y = -100 })
driver.update(0.1)
equal(API.Ended(OWNER), "arrived", "Ended says arrived")
equal(API.CurrentStop(OWNER), nil, "no stop after arriving")
equal(API.Active(), false, "nothing guides after arriving")
frame()
equal(last().ended, true, "Subscribe says it ended")
driver.move({ map = 1, x = 0, y = 0 })

-- A held objective area, with its radius, circles and quests, never arrives: standing in it keeps the stop.
local held = {
	map = 1,
	x = 0.502,
	y = 0.5,
	title = "Defias camp",
	kind = "objective",
	hold = true,
	radius = 40,
	shapes = { { map = 1, x = 0.502, y = 0.5, radius = 40 } },
	questID = 12,
	questIDs = { 12, 13 },
}
equal(API.NavigateRoute(OWNER, { held }), true, "a held stop is taken")
equal(API.Ended(OWNER), nil, "a new journey forgets the last end")
driver.move({ map = 1, x = 0, y = -100 })
driver.update(0.1)
driver.update(0.1)
equal(API.CurrentStop(OWNER), 1, "a held stop does not arrive")
equal(API.Ended(OWNER), nil, "and does not end")

-- Another addon's journey, or the player's, replaces it: "replaced", no stop of its own, and another journey guides.
-- Cancel then clears nothing, so it never ends a journey that is not its own.
equal(API.Navigate("OtherAddon", 1, 0.6, 0.5, "Elsewhere"), true, "another addon's journey")
driver.path.settle()
equal(API.Ended(OWNER), "replaced", "Ended says replaced")
equal(API.CurrentStop(OWNER), nil, "no stop of its own")
equal(API.Active(), true, "Active: a journey not its own guides")
equal(API.Cancel(OWNER), false, "Cancel leaves the other journey alone")
equal(API.CurrentStop("OtherAddon"), 1, "which runs on")
frame()
equal(last().changed, true, "Subscribe says the journey changed")
API.Cancel("OtherAddon")

-- The player clearing it: "cleared".
API.Navigate(OWNER, 1, 0.6, 0.5, "Elsewhere")
driver.path.settle()
ns.ClearJourney()
equal(API.Ended(OWNER), "cleared", "Ended says cleared")
equal(API.Active(), false, "nothing guides after clearing")

-- Its own Cancel: true, "cancelled".
API.Navigate(OWNER, 1, 0.6, 0.5, "Elsewhere")
driver.path.settle()
equal(API.Cancel(OWNER), true, "Cancel clears its own journey")
equal(API.Ended(OWNER), "cancelled", "Ended says cancelled")
equal(API.CurrentStop(OWNER), nil, "no stop after Cancel")

-- No way there: the stop is taken and stays current, but nothing guides, so the caller can guide it itself.
equal(API.NavigateRoute(OWNER, { { map = 2, x = 0.5, y = 0.5, title = "Across the sea" } }), true, "a stop with no way")
driver.path.settle()
equal(API.CurrentStop(OWNER), 1, "the stop with no way stays current")
equal(API.Active(), false, "and Active is false")
API.Cancel(OWNER)

-- Unsubscribing ends the news, and is safe twice.
frame()
local count = #heard
unsubscribe()
unsubscribe()
API.Navigate(OWNER, 1, 0.6, 0.5)
frame()
equal(#heard, count, "no news after unsubscribing")

print("api_contract: ok, " .. checks .. " checks")

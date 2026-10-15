-- The goal pin's line on the other faction's transport (Journey/FactionHint.lua, #162): time only, only with
-- "Other Faction's Routes" off, only for two minutes or more over the plan being followed.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
driver.load("Journey/FactionHint.lua")
ns.Routes =
	{ [1] = { faction = "Horde", stops = {} }, [2] = { faction = "Alliance", stops = {} }, [3] = { stops = {} } }
ns.IsObservingRide, ns.JourneyWithoutHearth = function() end, ns.JourneyWithoutHearth or function() end
-- The plan with the other faction's routes allowed, as the spec sets it; the journey plans as usual.
local other, calls = nil, {}
local plan = ns.Planner.Plan
ns.Planner.Plan = function(options)
	if options.otherFaction == true then
		calls[#calls + 1] = { cache = options.cache, withoutHearth = options.withoutHearth }
		return other
	end
	return plan(options)
end
-- The comparison's own clock, so no journey frame runs between checks.
local clock = 0
ns.NowMs = function()
	return clock
end
local function Other(arrive, route)
	return { arrive = arrive, legs = { { mode = route and "boat" or "walk", route = route } } }
end

assert(ns.OtherFactionHint() == nil, "no journey, no line")
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 2000, y = 0 })
local _, _, own = ns.JourneyInfo()
local arrive = own.arrive
other = Other(arrive - 240000, 1)
assert(ns.OtherFactionHint() == "Through Horde transport: about 4 min faster", "four minutes through Horde transport")
assert(#calls == 1, "one plan: the journey's own is the other side")
assert(ns.OtherFactionHint() and #calls == 1, "the comparison stands a while")

-- Under two minutes is no line: the comparison can be out by about that much.
clock = clock + 31000
other = Other(arrive - 119000, 1)
assert(ns.OtherFactionHint() == nil, "119 seconds is not worth a line")
clock = clock + 31000
other = Other(arrive - 120000, 1)
assert(ns.OtherFactionHint() == "Through Horde transport: about 2 min faster", "two minutes is")

-- Faster without any of the other faction's transport (a neutral boat, or the player's own) is no line either.
clock = clock + 31000
other = Other(arrive - 600000, 3)
assert(ns.OtherFactionHint() == nil, "a neutral route is not the other faction's")
clock = clock + 31000
other = Other(arrive - 600000, 2)
assert(ns.OtherFactionHint() == nil, "the player's own faction's route")

-- Moving on compares again before the half minute is up.
clock = clock + 31000
other = Other(arrive - 300000, 1)
assert(ns.OtherFactionHint() == "Through Horde transport: about 5 min faster")
other = Other(arrive, 1)
driver.move({ map = 1, x = 0, y = 100 })
assert(ns.OtherFactionHint() == nil, "a new place is compared again")
driver.move({ map = 1, x = 0, y = 0 })

-- On a ride, a flight or a corpse run, in combat or with the setting on: no line, and no planning.
other = Other(arrive - 300000, 1)
clock = clock + 31000
calls = {}
local function quiet(label)
	assert(ns.OtherFactionHint() == nil and #calls == 0, label)
end
ns.CurrentRide = function()
	return 1
end
quiet("aboard a boat")
ns.CurrentRide = function() end
env.UnitOnTaxi = function()
	return true
end
quiet("on a flight")
env.UnitOnTaxi = function() end
ns.Corpse = {
	Info = function()
		return "Corpse run", {}, {}, 1
	end,
}
quiet("during a corpse run")
ns.Corpse = nil
env.InCombatLockdown = function()
	return true
end
quiet("in combat")
env.InCombatLockdown = function() end
ns.db.otherFaction = true
quiet("the setting on")
ns.db.otherFaction = false
local faction = env.UnitFactionGroup
env.UnitFactionGroup = function() end
assert(ns.OtherFactionHint() == nil, "no faction yet (loading)")
env.UnitFactionGroup = faction
clock = clock + 31000
assert(ns.OtherFactionHint() == "Through Horde transport: about 5 min faster", "and back")
assert(calls[#calls].withoutHearth == ns.JourneyWithoutHearth(), "a refused Hearthstone stays refused")

-- No way for the journey: the line says there is one through the other faction's transport.
ns.ClearJourney()
driver.path.auto = false
driver.click({ map = 2, x = 500, y = 0 })
driver.path.auto = true
driver.update(0.1)
local _, _, none, _, loading = ns.JourneyInfo()
assert(none == nil and not loading, "the journey found no way")
clock = clock + 31000
assert(ns.OtherFactionHint() == "Through Horde transport, there is a way", "a way only through it")
other = nil
clock = clock + 31000
assert(ns.OtherFactionHint() == nil, "no way either way")

print("faction_hint_spec: ok")

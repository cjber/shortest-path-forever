-- The goal pin's line on the other faction's transport (Journey/FactionHint.lua, #162): time only, only with
-- "Other Faction's Routes" off, only for two minutes or more.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
driver.load("Journey/FactionHint.lua")
ns.Routes = { [1] = { faction = "Horde" }, [2] = { faction = "Alliance" }, [3] = {} }
-- The two plans as the spec sets them: the journey's own policy, and with the other faction's routes allowed.
local plans, calls = {}, {}
local plan = ns.Planner.Plan
ns.Planner.Plan = function(options)
	calls[#calls + 1] = { otherFaction = options.otherFaction, cache = options.cache }
	if options.cache and options.from and options.otherFaction ~= nil and options.to == ns.JourneyGoal() then
		return plans[options.otherFaction]
	end
	return plan(options)
end
-- The comparison's own clock, so no journey frame runs between checks.
local clock = 0
ns.NowMs = function()
	return clock
end
local function Plan(arrive, route)
	return { arrive = arrive, legs = { { mode = route and "boat" or "walk", route = route } } }
end

assert(ns.OtherFactionHint() == nil, "no journey, no line")
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 2000, y = 0 })
calls = {}
plans[false], plans[true] = Plan(600000), Plan(360000, 1)
assert(ns.OtherFactionHint() == "Through Horde transport: about 4 min faster", "four minutes through Horde transport")
assert(#calls == 2 and calls[1].otherFaction == false and calls[2].otherFaction == true, "both policies planned")
assert(calls[1].cache ~= calls[2].cache, "each with its own topology")
assert(ns.OtherFactionHint() and #calls == 2, "the comparison stands a while")

-- Under two minutes is no line: the comparison can be out by about that much.
clock = clock + 31000
plans[true] = Plan(600000 - 119000, 1)
assert(ns.OtherFactionHint() == nil, "119 seconds is not worth a line")
clock = clock + 31000
plans[true] = Plan(600000 - 120000, 1)
assert(ns.OtherFactionHint() == "Through Horde transport: about 2 min faster", "two minutes is")

-- Faster without any of the other faction's transport (a neutral boat, or the player's own) is no line either.
clock = clock + 31000
plans[true] = Plan(100000, 3)
assert(ns.OtherFactionHint() == nil, "a neutral route is not the other faction's")
clock = clock + 31000
plans[true] = Plan(100000, 2)
assert(ns.OtherFactionHint() == nil, "the player's own faction's route")

-- No way at all without it: the line says there is one, and nothing about safety.
clock = clock + 31000
plans[false], plans[true] = nil, Plan(100000, 1)
assert(ns.OtherFactionHint() == "Through Horde transport, there is a way", "a way only through it")
clock = clock + 31000
plans[true] = nil
assert(ns.OtherFactionHint() == nil, "no way either way")

-- Moving on, or a new goal, compares again before the half minute is up.
plans[false], plans[true] = Plan(600000), Plan(300000, 1)
clock = clock + 31000
assert(ns.OtherFactionHint() == "Through Horde transport: about 5 min faster")
plans[true] = Plan(600000, 1)
driver.move({ map = 1, x = 0, y = 100 })
assert(ns.OtherFactionHint() == nil, "a new place is compared again")

-- The setting on (those routes already planned with) or combat: no line, and no planning.
plans[true] = Plan(300000, 1)
clock = clock + 31000
ns.db.otherFaction = true
calls = {}
assert(ns.OtherFactionHint() == nil and #calls == 0, "the setting on")
ns.db.otherFaction = false
env.InCombatLockdown = function()
	return true
end
assert(ns.OtherFactionHint() == nil and #calls == 0, "in combat")
env.InCombatLockdown = function() end

print("faction_hint_spec: ok")

-- Exercise the shared capability producer through the real journey modules.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
local aura, known, queries = false, true, 0
env.C_UnitAuras.GetPlayerAuraBySpellID = function()
	queries = queries + 1
	return aura or nil
end
env.C_SpellBook.IsSpellKnown = function()
	queries = queries + 1
	return known
end
env.C_Spell = {
	GetSpellName = function()
		return "Water Walking"
	end,
}
local wetLeg = { mode = "walk", wet = 1000, to = { map = 1, x = 700, y = 0, name = "Goal" } }
assert(ns.JourneyWaterWalking(), "unset preference preserves known water-walking spells")
assert(ns.StepText(wetLeg):find("cast Water Walking", 1, true), "enabled known spell has a cast hint")
ns.db.useWaterWalking = false
queries = 0
assert(ns.JourneyWaterWalking() == false, "disabled preference ignores a known water-walking spell")
assert(queries == 0, "disabled preference does not query auras or spells")
assert(not ns.StepText(wetLeg):find("cast Water Walking", 1, true), "disabled preference has no cast hint")
aura = true
assert(ns.JourneyWaterWalking() == false, "disabled preference also ignores an active aura")
ns.db.useWaterWalking = true
local water, spell = ns.JourneyWaterWalking()
assert(water and not spell, "enabled active aura needs no cast")
aura = false
assert(select(2, ns.JourneyWaterWalking()), "enabled known spell is offered")
known = false
assert(ns.JourneyWaterWalking() == false, "enabled preference cannot invent a capability")
known = true
local from, goal = { map = 1, x = 0, y = 0 }, wetLeg.to
driver.begin(from, goal)
assert(driver.path.finds[#driver.path.finds].water, "enabled journey searches with water walking")
local before = #driver.path.finds
ns.db.useWaterWalking = false
local invalidated, woke = false, false
ns.ItineraryChanged = function(changed)
	invalidated = changed
end
ns.WakeTravel = function()
	woke = true
end
ns.TravelPolicyChanged()
assert(invalidated and woke, "toggle invalidates the itinerary and wakes travel")
driver.update(5.1)
assert(#driver.path.finds > before, "toggle replans an active journey")
assert(not driver.path.finds[#driver.path.finds].water, "replan uses ordinary swim costs")
-- Estimates obtain the same policy at the planner boundary and invalidate their cached answer.
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/API.lua")
local plan, modes = ns.Planner.Plan, {}
ns.Planner.Plan = function(options)
	modes[#modes + 1] = options.waterWalking
	return plan(options)
end
local API = env.ShortestPathForever.API
assert(API.Estimate(1, 0.5, 0.5, 1, 0.5014, 0.5))
assert(modes[#modes] == false, "estimator uses ordinary swimming when disabled")
local calls = #modes
ns.db.useWaterWalking = true
assert(API.Estimate(1, 0.5, 0.5, 1, 0.5014, 0.5))
assert(#modes > calls and modes[#modes] == true, "toggle invalidates the estimate cache and enables water walking")
print("water walking policy: ok")

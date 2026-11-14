-- Regression for incremental StopOrder context invalidation at the real teleport producer seam.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
for _, file in ipairs({ "UI/Looks.lua", "Core/API.lua", "Journey/StopOrder.lua" }) do
	driver.load(file)
end

local stocked = true
local cooldown = { startTime = 0, duration = 0 }
ns.charDB = {}
ns.db.teleports = true
ns.Teleports = {
	{ spell = 3561, cast = 10000, to = { map = 1, x = 0, y = 4990 }, reagents = { [17031] = 1 } },
}
env.GetBindLocation = function()
	return "Inn"
end
env.C_Item = {
	GetItemCount = function()
		return stocked and 1 or 0
	end,
}
env.C_SpellBook.IsSpellKnown = function()
	return true
end
env.C_Spell = {
	GetSpellCooldown = function()
		return cooldown
	end,
	GetSpellInfo = function()
		return { castTime = 10000 }
	end,
}
local init = ns.Init
ns.Init = function() end
driver.load("Transport/Teleports.lua")
ns.Init = init

local stops = {
	{ map = 1, x = 0.4, y = 0.5, title = "Far teleport" },
	{ map = 1, x = 0.49, y = 0.5, title = "Near walk" },
}
local origin = { map = 1, x = 0.5, y = 0.5 }
local function step(job)
	job:Step()
	return job.status
end

local unchanged = ns.StopOrder.Begin(stops, origin)
assert(step(unchanged) == "working")
local stable = ns.EstimateContextRevision()
assert(step(unchanged) == "working" or unchanged.status == "ready")
assert(ns.EstimateContextRevision() == stable, "cooldown timestamp drift must not churn revision")

local removed = ns.StopOrder.Begin(stops, origin)
assert(step(removed) == "working")
local before = ns.EstimateContextRevision()
stocked = false
assert(step(removed) == "invalid" and removed.reason == "context-changed", "reagent loss invalidates partial order")
assert(ns.EstimateContextRevision() > before, "reagent loss advances context revision")

stocked = true
local restored = ns.StopOrder.Begin(stops, origin)
assert(step(restored) == "working")
for _ = 1, 8 do
	if step(restored) ~= "working" then
		break
	end
end
assert(
	restored.status == "ready" and restored.points[1].title == "Far teleport",
	"reagent regain restores teleport ordering"
)

-- A cooldown reset changes the stable producer state even while the slot remains present.
env.ShortestPathForever.API.Estimate(1, 0.5, 0.5, 1, 0.49, 0.5)
local firstRevision = ns.EstimateContextRevision()
cooldown = { startTime = env.GetTime() + 30, duration = 30 }
env.ShortestPathForever.API.Estimate(1, 0.5, 0.5, 1, 0.49, 0.5)
local resetRevision = ns.EstimateContextRevision()
assert(resetRevision > firstRevision, "cooldown start invalidates the estimate context")
cooldown = { startTime = env.GetTime() + 60, duration = 30 }
env.ShortestPathForever.API.Estimate(1, 0.5, 0.5, 1, 0.49, 0.5)
local resetAgain = ns.EstimateContextRevision()
assert(resetAgain > resetRevision, "cooldown reset invalidates with stable membership")
cooldown = { startTime = env.GetTime() + 1, duration = 30 }
env.ShortestPathForever.API.Estimate(1, 0.5, 0.5, 1, 0.49, 0.5)
local activeRevision = ns.EstimateContextRevision()
driver.update(31)
env.ShortestPathForever.API.Estimate(1, 0.5, 0.5, 1, 0.49, 0.5)
assert(ns.EstimateContextRevision() > activeRevision, "cooldown expiry changes readiness without membership change")
print("teleport_readiness_revision_spec: passed")

local ns, speed, moving = {}, 7, 0
local secret = setmetatable({}, {
	__lt = function()
		error("secret speed compared")
	end,
})
local env = setmetatable({
	GetUnitSpeed = function()
		return moving, speed
	end,
	canaccessvalue = function(value)
		return value ~= secret
	end,
}, { __index = _G })
setfenv(assert(loadfile("Core/Speed.lua")), env)("ShortestPathForever", ns)
assert(ns.RunSpeed() == 7)
speed = 14
assert(ns.RunSpeed() == 14, "standing still preserves mounted run speed")
speed, moving = 3.5, 3.5
assert(ns.RunSpeed() == 3.5, "slows below base speed are respected")
speed, moving = secret, secret
assert(ns.RunSpeed() == 3.5, "secret values preserve the last readable run speed")
for _, invalid in ipairs({ 0, -1, math.huge, 0 / 0, "14", false }) do
	speed = invalid
	assert(ns.RunSpeed() == 3.5, "invalid readings preserve the last readable speed")
end
speed = 7
assert(ns.RunSpeed() == 7, "dismounting or a slow expiring restores base speed")
print("speed: stationary, mounted, slowed, secret and invalid readings passed")

local driver = assert(loadfile("tests/journey_driver.lua"))()
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
local fixture, API = driver.ns, driver.env.ShortestPathForever.API
local function estimate(expected)
	local seconds = API.Estimate(1, 0.5, 0.5, 1, 0.5014, 0.5)
	assert(math.abs(seconds - expected) < 1e-6, "ETA and estimate cache follow readable run speed")
end
estimate(10)
fixture.speed = 14
estimate(5)
fixture.speed = 3.5
estimate(20)
fixture.speed = driver.secret
estimate(20)
fixture.speed = 7
local plan, plannedSpeed = fixture.Planner.Plan, nil
fixture.Planner.Plan = function(options)
	plannedSpeed = options.walkSpeed
	return plan(options)
end
driver.begin({ map = 1, x = 0, y = 0, z = 0 }, { map = 1, x = 700, y = 0 })
assert(plannedSpeed == 7)
fixture.speed = 14
driver.update(0.1)
assert(plannedSpeed == 14, "mounting replans the active route before the five-second timer")
fixture.speed = 3.5
driver.update(0.1)
assert(plannedSpeed == 3.5, "slows replan the active route immediately")
fixture.speed = driver.secret
driver.update(0.1)
assert(plannedSpeed == 3.5, "secret combat speed retains the usable route speed")
fixture.speed = 7
driver.update(0.1)
assert(plannedSpeed == 7, "dismounting or expiring slow replans the active route")
print("speed: cached estimates and active journey replanning passed")

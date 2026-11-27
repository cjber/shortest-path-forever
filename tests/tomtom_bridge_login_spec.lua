local Boot = assert(loadfile("tests/tomtom_arrow_driver.lua"))()
local failures = 0

local function check(name, run)
	local ok, message = pcall(run)
	if ok then
		print("ok - " .. name)
	else
		failures = failures + 1
		print("FAIL - " .. name .. ": " .. message)
	end
end

local function visible(c)
	assert(c.tomtom.Arrow() and c.tomtom.Arrow() == c.bridge.Waypoint(), "TomTom must select the bridge's waypoint")
	assert(not c.crazy.hidden and c.crazy.alpha > 0, "TomTom's arrow must be visible")
	assert(not c.bridge.paused, "the bridge must stay unpaused")
	assert(c.env.RXPG_ARROW.alpha == 0 and not c.env.RXPG_ARROW.hidden, "the bridge owns RestedXP's native arrow")
	-- With Follow TomTom's arrow on, the journey may follow the bridge's waypoint instead of the guide's own element.
	local owner = c.ns.JourneyOwner()
	assert(owner == "RestedXP" or (owner == "TomTom" and c.ns.db.tomtomFollow), "the journey must be the guide's step")
end

local function publishStep(c)
	local rxp = c.env.RXP
	local element = { zone = 1, x = 60, y = 50, title = "RXP Step 1", arrow = true, step = { active = true } }
	rxp.arrowFrame.element, rxp.activeWaypoints = element, { element }
	rxp.UpdateGotoSteps()
	rxp.DrawArrow()
end

for _, follow in ipairs({ false, true }) do
	local suffix = follow and " with tomtomFollow on" or " with tomtomFollow off"
	local function boot(restored, extra)
		local opts = extra or {}
		opts.tomtomArrow, opts.tomtomFollow, opts.restedXPBridge, opts.deferLogin = true, follow, true, true
		local c = Boot(opts, restored)
		c.ns.db.guideStops = true
		return c
	end

	check("bridge selects after Shortest Path's login callbacks" .. suffix, function()
		local c = boot(false)
		c.driver.path.draw = function(from, to)
			return { from, { map = from.map, x = 800, y = -900 }, to }
		end
		c.login()
		c.world()
		c.runTimers()
		publishStep(c)
		c.driver.update(0)
		c.runTimers()
		visible(c)
	end)

	check("TomTom reloads a saved foreign target before the bridge ticks" .. suffix, function()
		local c = boot(true, {
			savedWaypoints = { { 1, 0.7, 0.5, title = "Saved", crazy = true } },
		})
		c.login()
		local saved = c.tomtom.Arrow()
		assert(saved and saved.title == "Saved", "reload selects the persisted crazy waypoint")
		c.world()
		c.runTimers()
		c.driver.update(0)
		assert(
			c.bridge.paused and c.tomtom.Arrow() == saved,
			"the bridge deliberately yields to the saved foreign point"
		)
		c.env.RXPTOMTOM_SetCurrentWaypoint()
		c.driver.update(0)
		visible(c)
	end)
end

check("Follow TomTom's arrow still routes to the bridge's step with both guide settings off", function()
	local c = Boot({ tomtomFollow = true, restedXPBridge = true, deferLogin = true }, false)
	c.ns.db.restedxp = false
	c.login()
	c.world()
	c.runTimers()
	publishStep(c)
	c.driver.update(0)
	c.runTimers()
	assert(c.API.CurrentStop("TomTom") == 1, "the journey must follow TomTom's arrow")
	assert(not c.bridge.paused and c.tomtom.Arrow() == c.bridge.Waypoint(), "the bridge keeps TomTom's arrow")
	assert(c.crazy.alpha == 0, "without Use TomTom's arrow, Shortest Path's arrow replaces TomTom's")
end)

check("turning the direction arrow off also hides the bridge's arrow", function()
	local c = Boot({ tomtomArrow = true, tomtomFollow = true, restedXPBridge = true, deferLogin = true }, false)
	c.ns.db.restedxp, c.ns.db.arrow = false, false
	c.login()
	c.world()
	c.runTimers()
	publishStep(c)
	c.driver.update(0)
	c.runTimers()
	assert(c.API.CurrentStop("TomTom") == 1, "the journey must follow TomTom's arrow")
	assert(c.crazy.alpha == 0, "no direction arrow shows")
end)

check("Follow TomTom's arrow still points TomTom's arrow along the route to a manual waypoint", function()
	local c = Boot({ tomtomArrow = true, tomtomFollow = true, restedXPBridge = true, deferLogin = true }, false)
	c.ns.db.restedxp = false
	c.login()
	c.world()
	c.runTimers()
	local manual = c.tomtom:Way(1, 10, 20, "Manual waypoint")
	c.driver.path.settle()
	c.driver.update(0)
	c.runTimers()
	assert(c.API.CurrentStop("TomTom") == 1, "the journey must follow the manual waypoint")
	assert(c.ns.TomTomArrowActive() and c.tomtom.Arrow() == manual, "Shortest Path drives TomTom's arrow")

	c.tomtom:RemoveWaypoint(manual)
	publishStep(c)
	c.driver.update(2)
	c.runTimers()
	c.driver.path.settle()
	c.driver.update(1)
	c.runTimers()
	visible(c)
end)

assert(failures == 0, failures .. " TomTom bridge login scenarios failed")
print("tomtom RestedXP bridge login: ok")

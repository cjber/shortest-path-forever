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
	assert(c.API.CurrentStop("RestedXP") == 1, "RestedXP must own the Shortest Path journey")
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

	check("RestedXP native pin before its first route" .. suffix, function()
		local c = boot(false)
		local map, rxp = c.env.C_Map, c.env.RXP
		c.login()
		c.world()
		-- An .ingamewaypoint element can write a native pin before the arrow element is ready.
		local pin = { zone = 1, zx = 0.7, zy = 0.5 }
		rxp.RXPFrame.activeSteps[1] = { elements = { pin } }
		map.SetUserWaypoint(c.env.UiMapPoint.CreateFromCoordinates(pin.zone, pin.zx, pin.zy))
		c.env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		pin.waypointSet = true
		local position = map.GetUserWaypointPositionForMap(pin.zone)
		pin.zx, pin.zy = position.x, position.y
		c.driver.update(0)
		c.runTimers()
		publishStep(c)
		c.driver.update(0)
		c.runTimers()
		visible(c)

		map.SetUserWaypoint(c.env.UiMapPoint.CreateFromCoordinates(1, 0.8, 0.5))
		c.driver.update(0)
		assert(c.ns.HasJourney() and not c.ns.JourneyOwner(), "a different pin still starts a player journey")
	end)

	check("saved player journey and an early RestedXP step" .. suffix, function()
		local c = boot(true, { keptJourney = { map = 1, x = 0, y = -8000, label = "Player destination" } })
		c.login()
		c.world()
		c.runTimers()
		c.driver.update(2)
		c.runTimers()
		visible(c)
		assert(c.ns.charDB.journey == nil, "the saved player journey was dropped")
	end)

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
			savedWaypoints = {
				{ 1, 0.7, 0.5, title = "Saved", crazy = true },
				{ 1, 0.75, 0.5, title = "Unselected", crazy = false },
			},
		})
		local beforeLogin = c.tomtom:AddWaypoint(1, 0.8, 0.5, { persistent = false, crazy = false })
		local removed
		c.tomtom.RegisterCallback({}, "WaypointRemoved", function(_, uid)
			removed = uid
		end)
		c.login()
		assert(removed == beforeLogin and not c.tomtom:IsValidWaypoint(beforeLogin), "reload drops ephemeral waypoints")
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
end)

assert(failures == 0, failures .. " TomTom bridge login scenarios failed")
print("tomtom RestedXP bridge login: ok")

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

-- Every route bends, so Shortest Path always has a bearing an arrow could draw.
local function bend(c)
	c.driver.path.draw = function(from, to)
		return { from, { map = from.map, x = 800, y = -900 }, to }
	end
end

-- The harness records a frame's Show and Hide in its hidden field.
local function ourArrowShown(c)
	local frame = c.arrowFrame()
	return frame ~= nil and frame.hidden == false
end

local function settle(c)
	c.driver.update(0)
	c.runTimers()
	c.driver.path.settle()
	c.driver.update(1)
	c.runTimers()
end

local function visible(c)
	assert(c.tomtom.Arrow() and c.tomtom.Arrow() == c.bridge.Waypoint(), "TomTom must select the bridge's waypoint")
	assert(not c.crazy.hidden and c.crazy.alpha > 0, "TomTom's arrow must be visible")
	assert(not c.bridge.paused, "the bridge must stay unpaused")
	assert(c.env.RXPG_ARROW.alpha == 0 and not c.env.RXPG_ARROW.hidden, "the bridge owns RestedXP's native arrow")
	-- RestedXP's journey keeps our arrow down by default; one that follows TomTom's arrow shows the route beside it.
	assert(ourArrowShown(c) == c.ns.db.tomtomFollow, "our arrow must show the route only while following TomTom's")
	assert(c.env.C_Map.GetUserWaypoint() ~= nil, "the game's marker must show the route")
	-- With Follow TomTom's arrow on, the journey may follow the bridge's waypoint instead of the guide's own element.
	local owner = c.ns.JourneyOwner()
	assert(owner == "RestedXP" or (owner == "TomTom" and c.ns.db.tomtomFollow), "the journey must be the guide's step")
end

local function publishStep(c, x)
	local rxp = c.env.RXP
	local element = { zone = 1, x = x or 60, y = 50, title = "RXP Step 1", arrow = true, step = { active = true } }
	element.tag, element.questId = "accept", 22
	rxp.arrowFrame.element, rxp.activeWaypoints = element, { element }
	rxp.UpdateGotoSteps()
	rxp.DrawArrow()
end

-- The guide's own stop: it stays on arrival and carries the step's quest, whoever follows it.
local function held(c, owner, when)
	local goal = c.ns.JourneyGoal()
	local who = tostring(c.ns.JourneyOwner())
	assert(goal and c.API.CurrentStop(owner) == 1, when .. ": " .. owner .. " must own the step, not " .. who)
	assert(goal.hold == true, when .. ": the step must be held")
	assert(goal.questIDs and goal.questIDs[1] == 22, when .. ": the step must keep its quest")
end

local function setFollow(c, on)
	c.ns.db.tomtomFollow = on
	c.ns.RefreshTomTomFollow(true)
	settle(c)
end

-- The journey goes to the place the guide's element names now, wherever the bridge's waypoint was left.
local function atElement(c, when)
	local at, element = c.ns.JourneyGoal().submitted, c.env.RXP.arrowFrame.element
	assert(at.x == element.x / 100 and at.y == element.y / 100, when .. ": the stop must be the guide's own")
end

local function arrive(c)
	local goal = c.ns.JourneyGoal()
	c.driver.move({ map = goal.map, x = goal.x, y = goal.y })
	for _ = 1, 5 do
		settle(c)
	end
	assert(c.ns.HasJourney(), "reaching the step must not end it")
	c.driver.move({ map = 1, x = 0, y = 0 })
	settle(c)
end

-- A logged-in client following the guide, in or out of combat as the spec says.
local function guided(follow)
	local c = Boot({ tomtomArrow = true, tomtomFollow = follow, restedXPBridge = true, deferLogin = true }, false)
	c.ns.db.guideStops = true
	bend(c)
	c.login()
	c.world()
	c.runTimers()
	c.env.InCombatLockdown = function()
		return c.combat == true
	end
	return c
end

-- The client may deliver the end of combat to the TomTom follower or to RestedXP's integration first.
local function endCombat(c, guideFirst)
	c.combat = false
	if guideFirst then
		c.env.RXP.UpdateMap()
	end
	c.driver.fire("PLAYER_REGEN_ENABLED")
	settle(c)
end

for _, follow in ipairs({ false, true }) do
	local suffix = follow and " with tomtomFollow on" or " with tomtomFollow off"
	local function boot(restored, extra)
		local opts = extra or {}
		opts.tomtomArrow, opts.tomtomFollow, opts.restedXPBridge, opts.deferLogin = true, follow, true, true
		local c = Boot(opts, restored)
		c.ns.db.guideStops = true
		bend(c)
		return c
	end

	check("bridge selects after Shortest Path's login callbacks" .. suffix, function()
		local c = boot(false)
		c.login()
		c.world()
		c.runTimers()
		publishStep(c)
		settle(c)
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
		settle(c)
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
	bend(c)
	c.login()
	c.world()
	c.runTimers()
	local manual = c.tomtom:Way(1, 10, 20, "Manual waypoint")
	c.driver.path.settle()
	c.driver.update(0)
	c.runTimers()
	assert(c.API.CurrentStop("TomTom") == 1, "the journey must follow the manual waypoint")
	assert(c.ns.TomTomArrowActive() and c.tomtom.Arrow() ~= manual, "Shortest Path points TomTom's arrow at the bend")

	c.tomtom:RemoveWaypoint(manual)
	publishStep(c)
	c.driver.update(2)
	c.runTimers()
	c.driver.path.settle()
	c.driver.update(1)
	c.runTimers()
	visible(c)
end)

check("turning Follow TomTom's arrow on, off and on again keeps the guide's stop", function()
	local c = guided(false)
	publishStep(c)
	settle(c)
	held(c, "RestedXP", "before")
	setFollow(c, true)
	held(c, "TomTom", "on")
	visible(c)
	arrive(c)
	setFollow(c, false)
	held(c, "RestedXP", "off")
	visible(c)
	arrive(c)
	setFollow(c, true)
	held(c, "TomTom", "on again")
	visible(c)
end)

check("a step the bridge sets before the world is up keeps the guide's stop", function()
	local c = Boot({ tomtomArrow = true, tomtomFollow = true, restedXPBridge = true, deferLogin = true }, false)
	bend(c)
	c.login()
	publishStep(c)
	c.world()
	c.runTimers()
	settle(c)
	held(c, "TomTom", "login")
end)

check("turning Follow on takes the guide's stop where TomTom's waypoint lags behind", function()
	local c = guided(false)
	publishStep(c)
	settle(c)
	c.env.RXP.arrowFrame.element.x = 80
	c.env.RXP.UpdateMap()
	setFollow(c, true)
	held(c, "TomTom", "moved on")
	atElement(c, "moved on")
end)

check("a stale bridge waypoint selected again follows the guide's stop, as does its replacement", function()
	local c = guided(true)
	publishStep(c)
	settle(c)
	local stale = c.bridge.Waypoint()
	c.env.RXP.arrowFrame.element.x = 80
	c.env.RXP.UpdateMap()
	c.env.RXPTOMTOM_SetCurrentWaypoint()
	settle(c)
	assert(c.bridge.Waypoint() == stale, "the bridge still holds its old waypoint")
	held(c, "TomTom", "stale")
	atElement(c, "stale")
	publishStep(c, 70)
	settle(c)
	assert(c.bridge.Waypoint() ~= stale, "the bridge replaced its waypoint")
	held(c, "TomTom", "next tick")
	atElement(c, "next tick")
	visible(c)
	arrive(c)
end)

check("a step renamed while TomTom holds it takes the new name and quest in place", function()
	local c = guided(true)
	publishStep(c)
	settle(c)
	held(c, "TomTom", "followed")
	local goal, element = c.ns.JourneyGoal(), c.env.RXP.arrowFrame.element
	element.title, element.questId, element.tag = "Turn it in", 33, "turnin"
	c.env.RXP.UpdateMap()
	settle(c)
	assert(c.ns.JourneyOwner() == "TomTom" and c.ns.JourneyGoal() == goal, "the stop must not be planned again")
	assert(goal.label == "Turn it in", "the stop must take the new name, not " .. tostring(goal.label))
	assert(goal.questIDs[1] == 33 and #goal.questIDs == 1, "the stop must take the new quest")
	assert(goal.hold == true, "the stop stays the guide's")
end)

check("a guide step's new name leaves the player's own journey alone", function()
	local c = guided(true)
	publishStep(c)
	settle(c)
	assert(c.ns.JourneyToMapPoint(1, 0.1, 0.2, "Mine"))
	c.env.RXP.arrowFrame.element.title = "Renamed"
	c.env.RXP.UpdateMap()
	settle(c)
	assert(c.ns.JourneyOwner() == nil and c.ns.JourneyGoal().label == "Mine", "the player's journey is kept")
end)

check("turning Follow on leaves the player's own journey to the step's place", function()
	local c = guided(false)
	publishStep(c)
	settle(c)
	c.ns.PlayerClear()
	assert(c.ns.JourneyToMapPoint(1, 0.6, 0.5, "Mine"))
	setFollow(c, true)
	assert(c.ns.JourneyOwner() == nil and c.ns.JourneyGoal().label == "Mine", "the player's journey is kept")
end)

check("a route the player cleared stays cleared when Follow is turned off", function()
	local c = guided(true)
	publishStep(c)
	settle(c)
	held(c, "TomTom", "followed")
	c.ns.PlayerClear()
	setFollow(c, false)
	c.env.RXP.UpdateMap()
	settle(c)
	assert(not c.ns.HasJourney(), "the guide must not restart a cleared route")
	setFollow(c, true)
	held(c, "TomTom", "on after the clear")
	arrive(c)
end)

check("turning Follow off leaves a destination the player picked", function()
	local c = guided(true)
	publishStep(c)
	settle(c)
	assert(c.ns.JourneyToMapPoint(1, 0.1, 0.2, "Mine"))
	setFollow(c, false)
	assert(c.ns.JourneyOwner() == nil and c.ns.JourneyGoal().label == "Mine", "the player's journey is kept")
end)

for _, guideFirst in ipairs({ false, true }) do
	local order = guideFirst and ", the guide planning first" or ", TomTom's follower first"

	for _, previous in ipairs({ false, true }) do
		local which = previous and "the next step" or "a first step"
		check(which .. " that arrives in combat is the guide's stop after it" .. order, function()
			local c = guided(true)
			if previous then
				publishStep(c, 40)
				settle(c)
			end
			c.combat = true
			publishStep(c)
			settle(c)
			assert(not c.ns.HasJourney(), "nothing is planned in combat")
			endCombat(c, guideFirst)
			held(c, "TomTom", "after combat")
			visible(c)
			arrive(c)
			assert(c.ns.ResumeRestedXP(), "Resume guide has a step")
			held(c, "RestedXP", "Resume guide")
			setFollow(c, false)
			held(c, "RestedXP", "off")
			setFollow(c, true)
			held(c, "TomTom", "on")
			visible(c)
			setFollow(c, false)
			held(c, "RestedXP", "off after the fight")
			arrive(c)
		end)
	end

	check("a step that moves a little during combat is the guide's stop after it" .. order, function()
		local c = guided(true)
		c.combat = true
		publishStep(c)
		settle(c)
		-- Too small a move for the guide to name a new target, and the bridge keeps the waypoint it set.
		c.env.RXP.arrowFrame.element.x = 60.02
		endCombat(c, guideFirst)
		held(c, "TomTom", "after combat")
		atElement(c, "after combat")
		visible(c)
		arrive(c)
	end)

	check("a step that arrives in combat with Follow off is the guide's" .. order, function()
		local c = guided(false)
		c.combat = true
		publishStep(c)
		settle(c)
		endCombat(c, guideFirst)
		held(c, "RestedXP", "after combat")
		visible(c)
		arrive(c)
	end)

	for _, before in ipairs({ false, true }) do
		local which = before and "a step planned before the fight" or "a step that arrived in the fight"
		check("Follow turned on in combat takes over " .. which .. order, function()
			local c = guided(false)
			c.combat = not before
			publishStep(c)
			settle(c)
			c.combat = true
			setFollow(c, true)
			endCombat(c, guideFirst)
			held(c, "TomTom", "after combat")
			visible(c)
			arrive(c)
		end)
	end

	check("a destination picked after a step arrives in combat is kept" .. order, function()
		local c = guided(true)
		c.combat = true
		publishStep(c)
		settle(c)
		assert(c.ns.PickInCombat({ map = 1, x = 0.1, y = 0.2, title = "Picked" }))
		endCombat(c, guideFirst)
		assert(c.ns.JourneyGoal().label == "Picked", "the player's later pick must win")
	end)

	for _, case in ipairs({
		{ name = "with the guide setting off", off = true },
		{ name = "while the guide has no active step" },
	}) do
		check("a bridge waypoint set in combat is followed " .. case.name .. order, function()
			local c = guided(true)
			c.ns.db.restedxp = not case.off
			c.combat = true
			publishStep(c)
			c.env.RXP.arrowFrame.element.step.active = case.off == true
			settle(c)
			endCombat(c, guideFirst)
			assert(c.API.CurrentStop("TomTom") == 1, "the journey must follow TomTom's arrow")
			assert(c.ns.JourneyGoal().hold == false, "there is no guide stop to keep")
		end)
	end

	for _, path in ipairs({ "live", "after combat" }) do
		check("a bridge step leaves Adventure Guide's journey alone " .. path .. order, function()
			local c = guided(true)
			c.env.AdventureGuideForever = {
				API = {
					RestedXPIntegrated = function()
						return true
					end,
				},
			}
			assert(c.API.NavigateRoute("AdventureGuideForever", { { map = 1, x = 0.6, y = 0.4, title = "Guide" } }))
			c.combat = path == "after combat"
			publishStep(c)
			settle(c)
			if c.combat then
				endCombat(c, guideFirst)
			end
			assert(c.ns.JourneyOwner() == "AdventureGuideForever", tostring(c.ns.JourneyOwner()))
			assert(c.ns.JourneyGoal().label == "Guide", tostring(c.ns.JourneyGoal().label))
		end)
	end
end

assert(failures == 0, failures .. " TomTom bridge login scenarios failed")
print("tomtom RestedXP bridge login: ok")

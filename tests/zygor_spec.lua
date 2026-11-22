local FakeTomTom = assert(loadfile("tests/tomtom_fake.lua"))()

local function Boot(tomtom)
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local ns, env = driver.ns, driver.env
	driver.load("UI/Looks.lua")
	driver.load("Core/APIInput.lua")
	driver.load("Core/APIStops.lua")
	driver.load("Core/API.lua")
	driver.load("Journey/Itinerary.lua")
	local API = env.ShortestPathForever.API
	local client = { ns = ns, env = env, API = API, calls = {}, combat = false, secret = driver.secret }
	local savedTimers, frames = {}, {}
	env.C_Timer = {
		After = function(_, fn)
			savedTimers[#savedTimers + 1] = fn
		end,
	}
	local create = env.CreateFrame
	env.CreateFrame = function(...)
		local frame = create(...)
		local events = {}
		function frame.RegisterEvent(_, event)
			events[event] = true
		end
		function frame.UnregisterEvent(_, event)
			events[event] = nil
		end
		frames[frame] = events
		return frame
	end
	env.InCombatLockdown = function()
		return client.combat
	end
	env.hooksecurefunc = function(target, name, hook)
		local original = target[name]
		target[name] = function(...)
			local result = original(...)
			hook(...)
			return result
		end
	end
	env.C_AddOns = {
		DoesAddOnExist = function(name)
			return name == "TomTom" and tomtom ~= nil
		end,
		IsAddOnLoaded = function(name)
			return name == "TomTom" and tomtom ~= nil
		end,
	}
	local navigate = API.NavigateRoute
	function API.NavigateRoute(owner, stops)
		client.calls[#client.calls + 1] = owner
		return navigate(owner, stops)
	end

	local pointer = { ArrowFrame = {} }
	function pointer:ShowArrow(waypoint)
		if waypoint then
			self.ArrowFrame.waypoint = waypoint
		else
			self:HideArrow()
		end
	end
	function pointer.HideArrow() end
	local zgv = { Pointer = pointer }
	function zgv:SetCurrentStep(step)
		self.CurrentStep = step
	end
	client.zgv, client.pointer = zgv, pointer
	env.ZGV, env.TomTom = zgv, tomtom
	ns.db.zygor, ns.db.tomtom, ns.db.tomtomFollow = false, true, tomtom ~= nil
	driver.load("Core/Zygor.lua")
	driver.load("Core/TomTom.lua")

	function client.fire(event, ...)
		for frame, events in pairs(frames) do
			if events[event] then
				frame:OnEvent(event, ...)
			end
		end
	end
	function client.frame()
		local due = savedTimers
		savedTimers = {}
		for _, fn in ipairs(due) do
			fn()
		end
		driver.path.settle()
	end
	function client.enable()
		ns.db.zygor = true
		if ns.RefreshZygor then
			ns.RefreshZygor()
		end
		client.frame()
	end
	client.fire("PLAYER_ENTERING_WORLD")
	client.frame()
	return client
end

do
	local c = Boot()
	local waypoint = { m = 1, x = 0.6, y = 0.5, title = "Goldshire" }
	c.pointer:ShowArrow(waypoint)
	c.frame()
	assert(not c.ns.HasJourney(), "Zygor is idle before the setting is turned on")
	c.enable()
	assert(c.API.CurrentStop("Zygor") == 1, "enabling Zygor follows its current pointer without TomTom")
	assert(c.ns.JourneyInfo() == "Journey to Goldshire", "the journey uses Zygor's waypoint title")
	assert(c.ns.JourneyGoal().submitted.x == 0.6, "the journey uses normalized pointer coordinates")
	assert(c.ns.JourneyGoal().hold, "Zygor decides when the step advances")

	waypoint.x, waypoint.title = 0.7, "Eastvale"
	c.pointer:ShowArrow(waypoint)
	c.pointer:ShowArrow(waypoint)
	c.frame()
	assert(#c.calls == 2, "recycled waypoints replan once when their point changes")
	assert(c.ns.JourneyGoal().submitted.x == 0.7, "the route moves to the changed waypoint")

	waypoint.GetArrowTitle = function()
		return "Turn in the quest"
	end
	c.zgv:SetCurrentStep({ goals = { { questid = 100 } } })
	c.frame()
	assert(#c.calls == 2, "changes at the same point keep its route")
	assert(c.ns.JourneyInfo() == "Journey to Turn in the quest", "step changes refresh the arrow's title")
	assert(c.ns.JourneyGoal().questIDs[1] == 100, "step changes refresh the stop's quests")

	c.combat = true
	c.pointer:ShowArrow({ m = 1, x = 0.8, y = 0.5, title = "After combat" })
	c.frame()
	assert(#c.calls == 2, "combat defers the new route")
	c.combat = false
	c.fire("PLAYER_REGEN_ENABLED")
	c.frame()
	assert(#c.calls == 3 and c.API.CurrentStop("Zygor") == 1, "the latest waypoint is followed after combat")
	c.pointer:HideArrow()
	c.frame()
	assert(not c.ns.HasJourney(), "hiding the arrow drops its route even when the frame retains the waypoint")
end

-- Another route replaces Zygor's while its arrow stays put; Zygor's step comes back once that route ends.
do
	local c = Boot()
	c.pointer:ShowArrow({ m = 1, x = 0.6, y = 0.5, title = "Goldshire" })
	c.enable()
	assert(c.API.NavigateRoute("Other", { { map = 1, x = 0.3, y = 0.5, title = "Elsewhere" } }), "another route starts")
	c.frame()
	assert(c.API.CurrentStop("Other") == 1 and not c.API.CurrentStop("Zygor"), "the other route replaces Zygor's")
	c.API.Cancel("Other")
	c.frame()
	assert(c.API.CurrentStop("Zygor") == 1, "Zygor's unchanged step resumes when the other route ends")
end

do
	local c = Boot()
	c.pointer.ArrowFrame = "unexpected"
	c.enable()
	assert(not c.ns.HasJourney(), "an unexpected pointer shape starts nothing")
	c.pointer.ArrowFrame = {}
	for _, x in ipairs({ "0.6", 60, 0 / 0, c.secret }) do
		c.pointer:ShowArrow({ m = 1, x = x, y = 0.5 })
		c.frame()
		assert(#c.calls == 0, "an invalid coordinate never reaches the journey API")
	end
end

-- A TomTom waypoint already accepted from Zygor wins the same point, whether the shim or TomTom follows it.
for _, installed in ipairs({ false, true }) do
	local c = Boot(installed and FakeTomTom.New() or nil)
	local waypointer = {}
	c.zgv.WaypointFunctions = { tomtom = waypointer }
	c.zgv.ConnectedWaypointer = waypointer
	c.zgv.CurrentStep = { goals = { { questid = 100 } } }
	local point = { m = 1, x = 0.65, y = 0.5, title = "One guide point" }
	c.pointer:ShowArrow(point)
	c.env.TomTom:AddWaypoint(point.m, point.x, point.y, { title = point.title })
	c.enable()
	assert(#c.calls == 1 and c.API.CurrentStop("TomTom") == 1, "a forwarded Zygor point plans once")
	assert(c.ns.JourneyGoal().questIDs[1] == 100, "TomTom keeps Zygor's step quests")
end

-- A bridge can publish after the direct route has started, and tag its waypoint with Zygor's name.
for _, installed in ipairs({ false, true }) do
	local c = Boot(installed and FakeTomTom.New() or nil)
	local point = { m = 1, x = 0.65, y = 0.5, title = "Direct guide point" }
	c.pointer:ShowArrow(point)
	c.enable()
	local uid = c.env.TomTom:AddWaypoint(point.m, point.x, point.y, { title = point.title, from = "Zygor" })
	c.frame()
	assert(type(uid) == "table", "the bridge gets a TomTom waypoint it can remove")
	assert(#c.calls == 1 and c.API.CurrentStop("Zygor") == 1, "a late mirror of the same point keeps one route")
	c.env.TomTom:RemoveWaypoint(uid)
	assert(c.API.CurrentStop("Zygor") == 1, "removing the mirror leaves the pointer's route alone")
end

print("zygor: ok")

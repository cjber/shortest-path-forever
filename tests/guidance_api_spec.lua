-- The public guidance read: the next point the arrow leads to, every bend of the active leg as fresh
-- uiMapID/0-1 copies, and a Subscribe notice when that point moves on within the leg. The state must stay
-- current with the arrow turned off and without a renderer or an extra poll.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = driver.ns, driver.env, 0
local create = env.CreateFrame
env.CreateFrame = function(...)
	local frame = create(...)
	frame.GetEffectiveScale = function(self)
		return self.scale or 1
	end
	frame.SetScale = function(self, scale)
		self.scale = scale
	end
	frame.SetPoint = function(self, ...)
		self.point = { ... }
	end
	frame.GetCenter = function(self)
		return self.centerX, self.centerY
	end
	frame.SetShown = function(self, shown)
		if shown then
			self:Show()
		else
			self:Hide()
		end
	end
	return frame
end
driver.load("UI/Art.lua")
driver.load("UI/Mover.lua")
driver.load("UI/TurnAround.lua")
driver.load("UI/Arrow.lua")
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected, label)
	checks = checks + 1
	assert(type(actual) == "number" and math.abs(actual - expected) < 1e-6, label)
end
local function why(expected, label, value, reason)
	equal(value, nil, label)
	equal(reason, expected, label .. " reason")
end
local function settle(limit)
	for _ = 1, limit or 100 do
		driver.update(0.1)
		if API.Guidance() then
			return
		end
	end
end

-- World (x, y) on the driver's map 1 is uiMap fraction (0.5 - y / 50000, 0.5 - x / 50000).
local function uiX(_, worldY)
	return 0.5 - worldY / 50000
end
local function uiY(worldX)
	return 0.5 - worldX / 50000
end
local function draw(a, b)
	return {
		{ map = a.map, x = a.x, y = a.y },
		{ map = a.map, x = a.x + 40, y = a.y },
		{ map = a.map, x = a.x + 80, y = a.y },
		{ map = b.map, x = b.x, y = b.y },
	}
end
local route = { { map = 1, x = 0.5, y = 0.48, title = "Goal" } }

-- No journey is not an error: the read says why there is nothing to point at.
why("none", "no journey", API.Guidance())

-- A walk with three bends: the next point is the first bend, and every bend of the leg is copied out.
driver.path.draw = draw
driver.move({ map = 1, x = 0, y = 0, z = 0 })
equal(API.NavigateRoute("AGF", route), true, "a route starts")
-- The first plan is still being searched: there is no arrow point yet, and the read says why while it works.
why("loading", "the first plan still searching", API.Guidance())
settle()
local guidance = API.Guidance()
assert(guidance, "guidance answers while the arrow leads")
equal(guidance.owner, "AGF", "the journey's owner")
equal(guidance.leg, 1, "the leg under way")
equal(#guidance.waypoints, 4, "every bend of the active leg")
equal(guidance.index, 2, "the bend under way")
near(guidance.point.x, uiX(40, 0), "the next point's uiMap x")
near(guidance.point.y, uiY(40, 0), "the next point's uiMap y")
near(guidance.waypoints[1].x, uiX(0, 0), "the first waypoint's uiMap x")
near(guidance.waypoints[4].y, uiY(1000, 0), "the last waypoint's uiMap y")

-- Every table is a copy: changing one reaches neither the producer nor the next read.
guidance.owner, guidance.point.x, guidance.waypoints[2].x = "Other", 9, 9
guidance.waypoints[5] = { map = 1, x = 9, y = 9 }
local again = API.Guidance()
assert(again and again ~= guidance, "a fresh snapshot each call")
equal(again.owner, "AGF", "the owner is copied")
equal(#again.waypoints, 4, "the waypoint list is copied")
near(again.point.x, uiX(40, 0), "the point is copied")
near(again.waypoints[2].x, uiX(40, 0), "each waypoint is copied")
assert(again.point ~= guidance.point and again.waypoints ~= guidance.waypoints, "no table is shared")
assert(again.waypoints[2] ~= guidance.waypoints[2], "no waypoint table is shared")

-- A bend passed within the leg changes the point and tells subscribers, once.
local timers, heard = {}, {}
local clearedGuidance
env.C_Timer = {
	After = function(_, fn)
		timers[#timers + 1] = fn
	end,
}
local function frameEnd()
	local due = timers
	timers = {}
	for _, fn in ipairs(due) do
		fn()
	end
end
local unsubscribe = API.Subscribe(function(changes)
	heard[#heard + 1] = changes
	if changes.guidance then
		local reading, reason = API.Guidance()
		if reading then
			assert(reading.waypoints[reading.index], "a subscriber reads the new point from its callback")
		else
			assert(
				reason == "paused" or reason == "none" or reason == "cast" or reason == "unavailable",
				"a guidance change without a point says why"
			)
			if reason == "none" then
				clearedGuidance = true
			end
		end
	end
end)
driver.move({ map = 1, x = 40, y = 0, z = 0 })
driver.update(0.1)
equal(#timers, 1, "one burst for the bend")
frameEnd()
assert(heard[1] and heard[1].guidance == true, "the bend under way is a guidance change")
equal(heard[1].leg, nil, "a bend inside the leg is not a journey leg change")
equal(API.Guidance().index, 3, "the read agrees with the notice")

-- With the arrow turned off, the same producer still advances: no renderer dependency and no new poll.
API.Cancel("AGF")
frameEnd()
ns.db.arrow = false
driver.move({ map = 1, x = 0, y = 0, z = 0 })
equal(API.NavigateRoute("AGF", route), true, "a route starts with the arrow off")
settle()
equal(API.Guidance().index, 2, "the first bend with the arrow off")
driver.move({ map = 1, x = 40, y = 0, z = 0 })
driver.update(0.1)
equal(API.Guidance().index, 3, "a bend passes with the arrow off")
ns.db.arrow = true

-- Pausing guidance leaves no stale point; the goal and owner wait behind the reason.
equal(API.Pause("AGF"), true, "pause")
why("paused", "paused journey", API.Guidance())
equal(API.Resume("AGF"), true, "resume")
assert(API.Guidance(), "the point returns with guidance")

-- A teleport is cast where you stand: no walking point, and the read says so.
local prompt = ns.PointCastPrompt
ns.PointCastPrompt = function() end
ns.JourneyGuide.Cast({ teleport = { spell = 1 } })
why("cast", "cast leg", API.Guidance())
ns.JourneyGuide.Retarget()
ns.PointCastPrompt = prompt
driver.update(0.1)
assert(API.Guidance(), "guidance returns after the cast")

-- guideStops only collapses what the arrow draws. The API keeps the canonical source walk and names the target
-- inside it, and the switch is a guidance change.
driver.move({ map = 1, x = 0, y = 0, z = 0 })
driver.update(0.1)
frameEnd()
local before = #heard
ns.db.guideStops = true
ns.RefreshGuideStops()
frameEnd()
local collapsed = API.Guidance()
equal(#collapsed.waypoints, 4, "the full source walk survives guideStops")
equal(collapsed.index, 4, "the target is the source walk's endpoint")
near(collapsed.point.x, uiX(1000, 0), "the endpoint is the next point")
assert(#heard > before and heard[#heard].guidance, "the guideStops switch is a guidance change")
ns.db.guideStops = false
ns.RefreshGuideStops()
frameEnd()
equal(API.Guidance().index, 2, "back to the nearest bend")

-- A measured walk replacing a provisional one changes the source and says so.
local measured = { { map = 1, x = 0, y = 0 }, { map = 1, x = 1000, y = 0 } }
frameEnd()
before = #heard
ns.PointGuideArrow(measured, nil, { map = 1, x = 1000, y = 0 }, { map = 1, x = 1000, y = 0 })
frameEnd()
local fresh = API.Guidance()
equal(#fresh.waypoints, 2, "the measured source replaces the provisional walk")
assert(#heard > before and heard[#heard].guidance, "a changed source is a guidance change")

-- A point this client cannot place is not silently dropped: the read answers nil, "unavailable".
local project = env.C_Map.GetMapPosFromWorldPos
env.C_Map.GetMapPosFromWorldPos = function(map, point)
	if point.x == 1000 then
		return nil
	end
	return project(map, point)
end
why("unavailable", "unprojectable waypoint", API.Guidance())
env.C_Map.GetMapPosFromWorldPos = project
assert(API.Guidance(), "and answers again once it can place every point")

-- Combat does not hide the point, and its existing 0.1 s tick advances it without a guidance poll.
local lockdown = env.InCombatLockdown
env.InCombatLockdown = function()
	return true
end
ns.db.arrow = false
driver.move({ map = 1, x = 0, y = 0, z = 0 })
ns.PointGuideArrow(draw({ map = 1, x = 0, y = 0 }, { map = 1, x = 1000, y = 0 }))
frameEnd()
local combatHeard = #heard
driver.move({ map = 1, x = 40, y = 0, z = 0 })
driver.update(0.1)
frameEnd()
assert(#heard > combatHeard and heard[#heard].guidance, "combat arrow-off progress notifies without a read")
local inCombat = API.Guidance()
assert(inCombat and inCombat.owner == "AGF", "guidance answers in combat")
ns.db.arrow = true
env.InCombatLockdown = lockdown

-- A first plan still being searched is "loading", never the arrow's leftover state from the journey before it.
equal(API.Cancel("AGF"), true, "the measured walk's journey clears")
frameEnd()
driver.move({ map = 1, x = 0, y = 0, z = 0 })
equal(API.NavigateRoute("AGF", route), true, "a fresh route starts")
why("loading", "first plan still searching", API.Guidance())
settle()
assert(API.Guidance(), "and answers when the first plan lands")

-- The journey being replaced changes the owner the read reports.
frameEnd()
equal(API.NavigateRoute("OtherAddon", { { map = 1, x = 0.5, y = 0.47, title = "Elsewhere" } }), true, "replacement")
settle()
local replaced = API.Guidance()
assert(replaced and replaced.owner == "OtherAddon", "the new owner")
frameEnd()
local beforeClear = #heard
clearedGuidance = false
API.Cancel("OtherAddon")
frameEnd()
assert(#heard > beforeClear and heard[#heard].guidance, "cleared guidance is a guidance change")
assert(clearedGuidance, "a guidance subscriber sees the cleared guide, not a stale point")
why("none", "cancelled route", API.Guidance())

-- Stable ownership: the player's own journey has no owner.
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 1000, y = 0 })
settle()
local own = API.Guidance()
assert(own and own.owner == nil, "the player's own journey has no owner")
ns.ClearJourney()
frameEnd()
why("none", "cleared own journey", API.Guidance())

-- A corpse run is the player's own guidance, and its existing tick advances the bend with the arrow off.
local ghost, corpseAt = false, nil
env.CreateColor = function(r, g, b)
	return { r = r, g = g, b = b }
end
env.UnitIsGhost = function()
	return ghost
end
env.C_DeathInfo = {
	GetCorpseMapPosition = function(uiMap)
		return corpseAt and corpseAt[1] == uiMap and env.CreateVector2D(corpseAt[2], corpseAt[3]) or nil
	end,
}
driver.load("Journey/Corpse.lua")
ns.db.corpse = true
ns.db.arrow = false
ghost = true
corpseAt = { 1, 0.5, 0.5 - 1000 / 50000 }
driver.move({ map = 1, x = 0, y = 0, z = 0 })
ns.RefreshCorpseRun()
driver.update(0.6)
local corpseGuide = API.Guidance()
assert(corpseGuide and corpseGuide.owner == nil and corpseGuide.leg == 1, "a corpse run is the player's own guidance")
assert(#corpseGuide.waypoints >= 2, "the corpse walk's source")
ns.db.journey = false
local corpseWhileOff = API.Guidance()
assert(corpseWhileOff and corpseWhileOff.owner == nil, "a corpse run guides with Journeys switched off")
ns.db.journey = true
frameEnd()
local beforeCorpse = #heard
driver.move({ map = 1, x = 40, y = 0, z = 0 })
driver.update(0.6)
frameEnd()
assert(#heard > beforeCorpse and heard[#heard].guidance, "the corpse tick advances guidance with the arrow off")
ghost = false
ns.RefreshCorpseRun()
ns.db.arrow = true
frameEnd()

-- Journeys switched off is its own reason, before "none".
ns.db.journey = false
why("disabled", "journeys switched off", API.Guidance())
ns.db.journey = true

-- Loading wins over whatever the arrow still holds from a previous plan.
local db = ns.db
ns.db = nil
why("loading", "saved variables loading", API.Guidance())
ns.db = db
assert(API.Guidance() == nil, "no journey after loading")

unsubscribe()
frameEnd()
equal(#timers, 0, "no subscribers left: nothing scheduled")
print(("guidance_api_spec: ok (%d checks)"):format(checks))

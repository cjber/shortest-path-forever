-- Polestar has a TomTom stand-in, a /way and a "Follow TomTom's arrow" of its own, and can hand its target to
-- Shortest Path as a journey. With both addons loaded, in either order, Shortest Path's stand-in, /way and Follow
-- TomTom's arrow are never blocked by Polestar's, and no waypoint is planned twice.
local Fake = assert(loadfile("tests/tomtom_fake.lua"))()
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Polestar as its docs/ARCHITECTURE.md describes it ("Nav API" and "Hand-off to Shortest Path Forever"), cut down to
-- what meets TomTom, /way and Shortest Path's API. Its stand-in is Polestar.Nav.tomtomShim, put in the global at login
-- while no addon holds it and TomTom is not enabled. /way is claimed at login while no SLASH_ global spells it. With
-- TomTom installed and nav.followTomTom on, its hook on TomTom's SetCrazyArrow points its arrow at the waypoint, and
-- with nav.spfHandoff on that target goes to Shortest Path as one stop owned by "Polestar". It never follows the copy
-- of its own target it puts in TomTom (from = "Polestar").
---@param c table the client Boot builds
---@param settings table<string, any>
local function Polestar(c, settings)
	local env, polestar = c.env, { planned = {}, settings = settings }
	local standIn = { waypoints = {} }
	-- Polestar plans each in its own travel planner, recorded here.
	local function Target(map, x, y, title)
		polestar.planned[#polestar.planned + 1] = { map, x, y, title = title }
		if settings["nav.spfHandoff"] then
			c.API.NavigateRoute("Polestar", { { map = map, x = x, y = y, title = title } })
		end
	end
	function standIn.AddWaypoint(_, map, x, y, opts)
		Target(map, x, y, opts and opts.title)
		return { map, x, y, title = opts and opts.title }
	end
	function standIn.SetCrazyArrow(_, uid)
		Target(uid[1], uid[2], uid[3], uid.title)
	end
	function standIn.RemoveWaypoint()
		return false
	end
	standIn.ClearWaypoint = standIn.RemoveWaypoint
	polestar.standIn = standIn
	env.Polestar = {
		Nav = { tomtomShim = standIn },
		Get = function(path)
			return settings[path]
		end,
	}
	function polestar.login()
		if settings["nav.answerTomTom"] and env.TomTom == nil and not c.tomtomInstalled then
			env.TomTom = standIn
		end
		if not settings["nav.answerTomTom"] or c.tomtomInstalled then
			return
		end
		for key, value in pairs(env) do
			if
				type(key) == "string"
				and key:find("^SLASH_")
				and type(value) == "string"
				and value:lower() == "/way"
			then
				return
			end
		end
		env.SLASH_POLESTARWAY1 = "/way"
		env.SlashCmdList.POLESTARWAY = function(line)
			polestar.way = line
		end
	end
	function polestar.tomtomLoaded()
		local tomtom = env.TomTom
		if settings["nav.followTomTom"] and tomtom ~= standIn then
			env.hooksecurefunc(tomtom, "SetCrazyArrow", function(_, uid)
				if uid.from ~= "Polestar" then
					Target(uid[1], uid[2], uid[3], uid.title)
				end
			end)
		end
	end
	return polestar
end

-- A fresh client. Polestar loads first, as the AddOns folder orders it, unless `spfFirst`. TomTom, when installed,
-- loads after both.
---@param o {spfFirst?: boolean, tomtom?: boolean, standIn?: boolean, follow?: boolean, polestar: table<string, any>}
local function Boot(o)
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local ns, env = driver.ns, driver.env
	-- One global table, as in the client: the slash commands each addon looks for are in it.
	env._G = env
	env.SlashCmdList = {}
	driver.load("UI/Looks.lua")
	driver.load("Core/API.lua")
	driver.load("Journey/Itinerary.lua")
	local c = { driver = driver, ns = ns, env = env, API = env.ShortestPathForever.API, timers = {} }
	c.tomtomInstalled = o.tomtom == true
	env.C_AddOns = {
		DoesAddOnExist = function(name)
			return name == "TomTom" and c.tomtomInstalled
		end,
		IsAddOnLoaded = function(name)
			return name == "TomTom" and c.tomtom ~= nil
		end,
		GetAddOnEnableState = function(name)
			return name == "TomTom" and c.tomtomInstalled and 2 or 0
		end,
	}
	env.UnitName = function()
		return "Tester"
	end
	-- The real hooksecurefunc runs the hook after the function it hooks, with the same arguments.
	env.hooksecurefunc = function(target, key, hook)
		local original = target[key]
		target[key] = function(...)
			original(...)
			hook(...)
		end
	end
	env.C_Timer = {
		After = function(_, fn)
			c.timers[#c.timers + 1] = fn
		end,
	}
	env.InCombatLockdown = function()
		return false
	end
	ns.db.tomtom, ns.db.tomtomFollow = o.standIn ~= false, o.follow == true
	-- PLAYER_LOGIN reaches each addon's frame in the order the frames registered for it, that is load order.
	local logins = {}
	if not o.spfFirst then
		c.polestar = Polestar(c, o.polestar)
		logins[#logins + 1] = c.polestar.login
	end
	local created = {}
	local baseFrame = env.CreateFrame
	env.CreateFrame = function(...)
		local frame = baseFrame(...)
		created[#created + 1] = frame
		return frame
	end
	driver.load("Core/TomTom.lua")
	local watcher = created[#created]
	driver.load("Core/Way.lua")
	local login = created[#created]
	logins[#logins + 1] = function()
		login:OnEvent("PLAYER_LOGIN")
	end
	if o.spfFirst then
		c.polestar = Polestar(c, o.polestar)
		logins[#logins + 1] = c.polestar.login
	end
	-- TomTom's files load, taking /way and the global, then its ADDON_LOADED reaches each addon.
	if c.tomtomInstalled then
		c.tomtom = Fake.New()
		env.TomTom = c.tomtom
		env.SLASH_TOMTOM_WAY1 = "/way"
		watcher:OnEvent("ADDON_LOADED", "TomTom")
		c.polestar.tomtomLoaded()
	end
	for _, fn in ipairs(logins) do
		fn()
	end
	if c.tomtom then
		c.tomtom:Enable()
	end
	watcher:OnEvent("PLAYER_ENTERING_WORLD")
	local due = c.timers
	c.timers = {}
	for _, fn in ipairs(due) do
		fn()
	end
	return c
end

local EVERYTHING = { ["nav.answerTomTom"] = true, ["nav.followTomTom"] = true, ["nav.spfHandoff"] = true }

-- Both stand-ins and both /way commands on, in either load order: Shortest Path holds the global and /way from its own
-- load, Polestar finds both taken at login and stays out, and a guide's waypoint is one journey.
for _, spfFirst in ipairs({ false, true }) do
	local order = spfFirst and "Shortest Path first" or "Polestar first"
	local c = Boot({ spfFirst = spfFirst, polestar = EVERYTHING })
	local env = c.env
	equal(type(env.TomTom), "table", order .. ": a TomTom global")
	equal(env.TomTom ~= c.polestar.standIn, true, order .. ": the global is Shortest Path's stand-in")
	equal(env.SLASH_SHORTESTPATHFOREVERWAY1, "/way", order .. ": /way is Shortest Path's")
	equal(env.SLASH_POLESTARWAY1, nil, order .. ": Polestar leaves /way alone")
	local uid = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "Questie" })
	c.driver.path.settle()
	equal(type(uid), "table", order .. ": the guide's waypoint is set")
	equal(c.API.CurrentStop("TomTom"), 1, order .. ": as one Shortest Path journey")
	equal(#c.polestar.planned, 0, order .. ": which Polestar does not plan as well")
	env.SlashCmdList.SHORTESTPATHFOREVERWAY("#1 30 40 Goldshire")
	c.driver.path.settle()
	equal(c.ns.JourneyInfo(), "Journey to Goldshire", order .. ": /way plans the journey")
	equal(c.polestar.way, nil, order .. ": and Polestar's /way never sees it")
end

-- With Shortest Path's stand-in off at login, Polestar's takes the global. It is not TomTom: Follow TomTom's arrow
-- never hooks it, turning Shortest Path's stand-in on takes the global over, and turning it off gives it back while
-- Polestar still answers waypoints.
do
	local c = Boot({ standIn = false, follow = true, polestar = { ["nav.answerTomTom"] = true } })
	local env, standIn = c.env, c.polestar.standIn
	equal(env.TomTom, standIn, "Polestar's stand-in takes a free global at login")
	equal(env.SLASH_SHORTESTPATHFOREVERWAY1, "/way", "Shortest Path's /way is claimed even so")
	c.ns.RefreshTomTomFollow()
	env.TomTom:SetCrazyArrow({ 1, 0.6, 0.5, title = "Polestar's" })
	c.driver.path.settle()
	equal(c.API.CurrentStop("TomTom"), nil, "Follow TomTom's arrow does not follow Polestar's stand-in")
	equal(#c.polestar.planned, 1, "the waypoint stays Polestar's alone")
	c.ns.db.tomtom = true
	c.ns.RefreshTomTom()
	equal(env.TomTom ~= standIn and type(env.TomTom), "table", "Shortest Path's stand-in is not blocked by Polestar's")
	env.TomTom:AddWaypoint(1, 0.6, 0.55, { title = "Guide" })
	c.driver.path.settle()
	equal(c.API.CurrentStop("TomTom"), 1, "a guide's waypoint is then Shortest Path's journey")
	equal(#c.polestar.planned, 1, "and not Polestar's")
	c.ns.db.tomtom = false
	c.ns.RefreshTomTom()
	equal(env.TomTom, standIn, "standing down gives Polestar's stand-in back")
	equal(c.ns.HasJourney(), false, "and clears the journey it started")
	-- Not while Polestar hands its target to Shortest Path, when it keeps its stand-in out of the global itself.
	c.ns.db.tomtom = true
	c.ns.RefreshTomTom()
	env.Polestar.Nav.HandedOff = function()
		return true
	end
	c.ns.db.tomtom = false
	c.ns.RefreshTomTom()
	equal(env.TomTom, nil, "not while Polestar hands off to Shortest Path")
	env.Polestar.Nav.HandedOff = nil
	-- Nor once it stopped answering waypoints.
	env.TomTom = standIn
	c.ns.db.tomtom = true
	c.ns.RefreshTomTom()
	c.polestar.settings["nav.answerTomTom"] = false
	c.ns.db.tomtom = false
	c.ns.RefreshTomTom()
	equal(env.TomTom, nil, "nor once Polestar stopped answering waypoints")
end

-- TomTom installed, with Follow TomTom's arrow on in both. Polestar handing its target to Shortest Path already makes
-- the waypoint a journey here, so Shortest Path does not follow it as well; with Polestar guiding itself, Shortest
-- Path follows, and Polestar steps aside while that journey runs.
do
	local c = Boot({ tomtom = true, follow = true, polestar = EVERYTHING })
	equal(c.env.TomTom, c.tomtom, "TomTom keeps its global")
	equal(c.env.SLASH_SHORTESTPATHFOREVERWAY1, nil, "and its /way")
	equal(c.env.SLASH_POLESTARWAY1, nil, "from Polestar too")
	c.tomtom:Way(1, 60, 50, "Goldshire")
	c.driver.path.settle()
	equal(#c.polestar.planned, 1, "Polestar follows TomTom's arrow")
	equal(c.API.CurrentStop("Polestar"), 1, "and hands the waypoint to Shortest Path")
	equal(c.API.Ended("TomTom"), nil, "which never planned it as its own first")
	equal(c.ns.JourneyInfo(), "Journey to Goldshire", "one journey, to the waypoint")
	c.polestar.settings["nav.spfHandoff"] = false
	c.ns.ClearJourney()
	c.tomtom:Way(1, 62, 50, "Inn")
	c.driver.path.settle()
	equal(c.API.CurrentStop("TomTom"), 1, "with Polestar guiding itself, Shortest Path follows the arrow")
	equal(c.API.CurrentStop("Polestar"), nil, "and Polestar sent nothing")
	-- Guiding by itself, Polestar copies its own target into TomTom, from "Polestar". That is Polestar's to guide.
	c.ns.ClearJourney()
	c.tomtom:AddWaypoint(1, 0.63, 0.5, { title = "Polestar's target", from = "Polestar" })
	c.driver.path.settle()
	equal(c.tomtom.Arrow().title, "Polestar's target", "TomTom's arrow takes Polestar's copy")
	equal(c.ns.HasJourney(), false, "which Shortest Path does not follow")
end

-- TomTom enabled but not yet loaded when Shortest Path loads: /way is left for it from the start.
do
	local c = Boot({ tomtom = true, spfFirst = true, polestar = {} })
	equal(c.env.SLASH_SHORTESTPATHFOREVERWAY1, nil, "TomTom loading later keeps /way")
	equal(c.env.SlashCmdList.SHORTESTPATHFOREVERWAY, nil, "with no handler of Shortest Path's")
end

print("polestar_compat: ok, " .. checks .. " checks")

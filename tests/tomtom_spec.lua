-- The TomTom shim answers a third-party guide's waypoint with a Shortest Path journey, but only while TomTom is
-- absent and the setting is on, and never leaves a waypoint behind a journey that ended.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = driver.ns, driver.env, 0
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- The client has both; the harness supplies them before the shim asks.
local installed, disabled, loaded = false, false, false
env.C_AddOns = {
	DoesAddOnExist = function()
		return installed or disabled
	end,
	IsAddOnLoaded = function()
		return loaded
	end,
	-- The client keys a character by GUID; a name is ignored and reads 2 for every addon.
	GetAddOnEnableState = function(_, character)
		assert(character == "Player-1-TESTER", "enabled for this character, by GUID")
		return installed and 2 or 0
	end,
}
env.UnitName = function()
	return "Tester"
end
env.UnitGUID = function()
	return "Player-1-TESTER"
end
-- The real hooksecurefunc runs the hook after the function it hooks.
env.hooksecurefunc = function(target, key, hook)
	local original = target[key]
	target[key] = function(...)
		original(...)
		hook(...)
	end
end
ns.db.tomtom = true
-- The follow watcher's PLAYER_ENTERING_WORLD waits a frame; nothing here runs it.
env.C_Timer = {
	After = function() end,
}
local combat = false
env.InCombatLockdown = function()
	return combat
end

-- The shim's ADDON_LOADED watcher, to hand it TomTom loading later.
local created = {}
local baseFrame = env.CreateFrame
env.CreateFrame = function(...)
	local frame = baseFrame(...)
	created[#created + 1] = frame
	return frame
end
driver.load("Core/TomTom.lua")
local watcher = created[#created]

equal(type(env.TomTom), "table", "the shim is defined while TomTom is absent")
equal(type(env.TomTom.AddWaypoint), "function", "AddWaypoint is present")
equal(type(env.TomTom.AddZWaypoint), "function", "AddZWaypoint is present")
equal(type(env.TomTom.AddMFWaypoint), "function", "AddMFWaypoint is present")
equal(type(env.TomTom.RemoveWaypoint), "function", "RemoveWaypoint is present")
equal(type(env.TomTom.waypoints), "table", "waypoints is present")

-- A Questie ctrl-click names the map first, with normalized coordinates and its own options.
local uid = env.TomTom:AddWaypoint(1, 0.6, 0.5, {
	title = "Questie",
	from = "Questie",
	crazy = true,
	persistent = false,
})
driver.path.settle()
equal(type(uid), "table", "AddWaypoint returns the waypoint")
equal(uid[1], 1, "waypoint map")
equal(uid[2], 0.6, "waypoint x")
equal(uid[3], 0.5, "waypoint y")
equal(uid.title, "Questie", "the caller's title is kept")
equal(uid.from, "Questie", "the caller's name is kept")
equal(uid.crazy, true, "extra options are copied")
equal(uid.persistent, false, "false options are copied")
equal(API.CurrentStop("TomTom"), 1, "the waypoint starts a journey")
equal(ns.HasJourney(), true, "the journey is active")
equal(ns.JourneyInfo(), "Journey to Questie", "the title leads the journey")
equal(env.TomTom.waypoints[1][next(env.TomTom.waypoints[1])], uid, "the waypoint is recorded on its map")

-- A second waypoint replaces the journey rather than queueing behind the first.
local second = env.TomTom:AddWaypoint(1, 0.7, 0.5, { title = "Zygor" })
driver.path.settle()
equal(API.CurrentStop("TomTom"), 1, "a replaced waypoint keeps one journey")
local maps, keys = 0, 0
for _ in pairs(env.TomTom.waypoints) do
	maps = maps + 1
end
for _ in pairs(env.TomTom.waypoints[1]) do
	keys = keys + 1
end
equal(maps, 1, "only the current map carries waypoints")
equal(keys, 1, "only the newest waypoint is kept")
equal(env.TomTom.waypoints[1][next(env.TomTom.waypoints[1])], second, "the newest waypoint is the recorded one")
equal(ns.JourneyInfo(), "Journey to Zygor", "the newest title leads the journey")

-- A guide removes the waypoint it set, and nothing else.
equal(env.TomTom:RemoveWaypoint(second), true, "removing the current waypoint")
equal(API.CurrentStop("TomTom"), nil, "the journey is cleared")
equal(ns.HasJourney(), false, "no journey runs")
equal(next(env.TomTom.waypoints), nil, "the waypoints table is emptied")
equal(env.TomTom:RemoveWaypoint(second), false, "removing twice does nothing")
local live = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "Questie" })
driver.path.settle()
equal(env.TomTom:RemoveWaypoint({ 1, 0.6, 0.5, title = "Something else" }), false, "a foreign waypoint is refused")
equal(API.CurrentStop("TomTom"), 1, "a foreign waypoint leaves the journey running")
env.TomTom:RemoveWaypoint(live)

-- The rest of TomTom's waypoint calls that guides make, for the shim's one waypoint.
for _, name in ipairs({
	"IsValidWaypoint",
	"WaypointExists",
	"ClearWaypoint",
	"ClearAllWaypoints",
	"GetClosestWaypoint",
	"SetClosestWaypoint",
	"SetCrazyArrow",
	"GetDistanceToWaypoint",
	"AddWaypointToCurrentZone",
}) do
	equal(type(env.TomTom[name]), "function", name .. " is present")
end
local set = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "RestedXP" })
driver.path.settle()
equal(env.TomTom:IsValidWaypoint(set), true, "the shim's waypoint is valid")
equal(env.TomTom:IsValidWaypoint({ 1, 0.6, 0.5, title = "Other" }), false, "another is not")
equal(env.TomTom:IsValidWaypoint("uid"), false, "nor is a non-table")
equal(env.TomTom:WaypointExists(1, 0.6, 0.5, "RestedXP"), true, "the waypoint exists")
equal(env.TomTom:WaypointExists(1, 0.6, 0.5, "Other"), false, "under its own title only")
equal(env.TomTom:WaypointExists(1, 60 / 100 + 1e-12, 0.5, "RestedXP"), true, "the same point worked out another way")
equal(env.TomTom:WaypointExists(1, driver.secret, 0.5, "RestedXP"), false, "a secret point is never compared")
driver.move({ map = 1, x = 0, y = 0 })
equal(env.TomTom:GetClosestWaypoint(), set, "the closest is the only one")
equal(env.TomTom:SetClosestWaypoint(), set, "and setting it changes nothing")
driver.move({ map = 0, x = 0, y = 0 })
equal(env.TomTom:GetClosestWaypoint(), nil, "none on another continent")
equal(env.TomTom:GetDistanceToWaypoint(set), nil, "and no distance to it")
equal(API.CurrentStop("TomTom"), 1, "the journey runs on")
driver.move({ map = 1, x = 0, y = 0 })
local yards = env.TomTom:GetDistanceToWaypoint(set)
equal(type(yards) == "number" and math.abs(yards - 5000) < 1e-6, true, "its yards from you")
equal(env.TomTom:GetDistanceToWaypoint({ 1, 0.6, 0.5 }), nil, "no distance to another")
env.TomTom:SetCrazyArrow(set, 15, "RestedXP")
equal(env.TomTom:IsValidWaypoint(set), true, "pointing at the current one keeps it")
local held = { 1, 0.7, 0.5, title = "Next step", from = "Guide" }
env.TomTom:SetCrazyArrow(held, 15, "Step 3: Next step")
driver.path.settle()
equal(ns.JourneyInfo(), "Journey to Next step", "pointing at another starts its journey, under its own title")
equal(env.TomTom:IsValidWaypoint(held), true, "and the table the guide holds is the one set")
equal(env.TomTom:GetClosestWaypoint().from, "Guide", "with its own fields")
equal(env.TomTom:ClearWaypoint(set), false, "clearing a replaced waypoint does nothing")
env.TomTom:ClearAllWaypoints()
equal(ns.HasJourney(), false, "clearing all ends the journey")
local bestMap = env.C_Map.GetBestMapForUnit
env.C_Map.GetBestMapForUnit = function()
	return 1
end
local here = env.TomTom:AddWaypointToCurrentZone(60, 50, "Here")
driver.path.settle()
equal(type(here) == "table" and here[1] == 1 and here[2] == 0.6, true, "a waypoint on the map you are on")
equal(env.TomTom:ClearWaypoint(here), true, "cleared like a removal")
equal(env.TomTom:AddWaypointToCurrentZone("60", 50), nil, "bad coordinates are refused")
env.C_Map.GetBestMapForUnit = bestMap

-- Every argument is checked like the public API's own.
for _, bad in ipairs({ { 0, 0.5, 0.5 }, { 1, 2, 0.5 }, { 1, 0.5, -0.1 }, { 1, 0.5, "0.5" }, { 1, 0 / 0, 0.5 } }) do
	equal(env.TomTom:AddWaypoint(bad[1], bad[2], bad[3], {}), nil, "a bad point is refused")
end
equal(env.TomTom:AddWaypoint(1, 0.5, 0.5, "opts"), nil, "opts must be a table")
equal(env.TomTom:AddWaypoint(1, 0.5, 0.5, { from = 7 }), nil, "from must be a string")
equal(env.TomTom:AddWaypoint(1, 0.5, 0.5, { title = 7 }), nil, "title must be a string")
equal(ns.HasJourney(), false, "bad input starts nothing")

-- The old continent and zone form, on a 0-100 scale.
local zone = env.TomTom:AddZWaypoint(10, 1, 50, 50, "Step", false, true, true, nil, true, true)
driver.path.settle()
equal(type(zone), "table", "AddZWaypoint accepts the zone as a uiMapID")
equal(zone[1], 1, "the zone names the map")
equal(zone[2], 0.5, "coordinates are scaled to 0-1")
equal(zone.title, "Step", "the description is the title")
equal(zone.minimap, true, "flags are copied")
env.TomTom:RemoveWaypoint(zone)
local mapInfo = env.C_Map.GetMapInfo
env.C_Map.GetMapInfo = function(id)
	if id >= 998 then
		return nil
	end
	return mapInfo(id)
end
local fallback = env.TomTom:AddZWaypoint(1, 999, 50, 50, "From the continent")
driver.path.settle()
equal(type(fallback), "table", "the continent is used when the zone is not a map")
equal(fallback[1], 1, "the continent names the map")
env.TomTom:RemoveWaypoint(fallback)
equal(env.TomTom:AddZWaypoint(998, 999, 50, 50, "Nowhere"), nil, "no map means no journey")
env.C_Map.GetMapInfo = mapInfo
local flags = env.TomTom:AddZWaypoint(1, 1, 50, 50, "Flags", false, false, false, false, false, false)
driver.path.settle()
equal(type(flags), "table", "false callbacks and flags are accepted")
env.TomTom:RemoveWaypoint(flags)

-- The map and floor form the newer TomTom also carries.
local mf = env.TomTom:AddMFWaypoint(1, 0, 0.6, 0.5, { title = "Floor" })
driver.path.settle()
equal(type(mf), "table", "AddMFWaypoint starts a journey")
equal(mf.title, "Floor", "AddMFWaypoint keeps the title")
for _, opts in ipairs({ true, false, 5, "options" }) do
	equal(env.TomTom:AddMFWaypoint(1, 0, 0.5, 0.5, opts), nil, "non-table floor waypoint options are refused")
end
equal(env.TomTom:IsValidWaypoint(mf), true, "refused options preserve the existing waypoint")
equal(API.CurrentStop("TomTom"), 1, "refused options preserve the existing journey")
env.TomTom:RemoveWaypoint(mf)
equal(env.TomTom:AddMFWaypoint(1, "0", 0.5, 0.5, {}), nil, "the floor must be a number")

-- A journey the shim did not cancel still leaves no waypoint behind.
local ending = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "Arrive" })
driver.path.settle()
equal(type(ending), "table", "a journey to arrive at")
ns.ClearJourney()
equal(next(env.TomTom.waypoints), nil, "a cleared journey leaves no waypoint")
equal(API.CurrentStop("TomTom"), nil, "the journey is gone")

-- The setting and an installed TomTom both take the global away.
local off = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "Off" })
driver.path.settle()
equal(type(off), "table", "a journey the setting will clear")
ns.db.tomtom = false
ns.RefreshTomTom()
equal(env.TomTom, nil, "the setting removes the global")
equal(ns.HasJourney(), false, "and clears the journey it started")
ns.db.tomtom = true
ns.RefreshTomTom()
equal(type(env.TomTom.AddWaypoint), "function", "the setting brings the global back")
installed = true
ns.RefreshTomTom()
equal(env.TomTom, nil, "an installed TomTom keeps its own global")
installed = false
ns.RefreshTomTom()
equal(type(env.TomTom.AddWaypoint), "function", "with TomTom absent the shim returns")
-- TomTom switched off in the AddOns list never loads, so the shim answers in its place.
disabled = true
ns.RefreshTomTom()
equal(type(env.TomTom.AddWaypoint), "function", "a disabled TomTom leaves the shim in place")
loaded = true
ns.RefreshTomTom()
equal(env.TomTom, nil, "a loaded TomTom keeps its own global")
disabled, loaded = false, false
ns.RefreshTomTom()
-- A client with no answer for the enable state errs towards TomTom, as before the state was read.
local enableState = env.C_AddOns.GetAddOnEnableState
env.C_AddOns.GetAddOnEnableState = function() end
disabled = true
ns.RefreshTomTom()
equal(env.TomTom, nil, "no enable state reads as an enabled TomTom")
env.C_AddOns.GetAddOnEnableState = enableState
disabled = false
ns.RefreshTomTom()
equal(type(env.TomTom.AddWaypoint), "function", "the shim returns once TomTom is gone")

-- Zygor's guide state is read only through the fields its own tables name. Questie and the shim are already here;
-- Zygor's TomTom waypointer is what a guide with no bridge used to leave titled alone.
driver.load("Core/Zygor.lua")
env.C_QuestLog = {
	GetTitleForQuestID = function(questID)
		if questID == 100 then
			return "The Escape"
		elseif questID == 101 then
			return "The Letter"
		end
	end,
}

-- Questie names the quest inside the tracker call that sets the waypoint: the shim reads it there, never from the
-- title, and the stop carries it into the journey.
local questieTitle = "Turn in 'The Escape'"
local trackerUtils = {
	SetQuestTomTomTarget = function()
		env.TomTom:AddWaypoint(1, 0.55, 0.45, { title = questieTitle, from = "Questie" })
		return true
	end,
}
env.Questie = {}
env.QuestieLoader = {
	ImportModule = function(_, name)
		return name == "TrackerUtils" and trackerUtils or nil
	end,
}
watcher:OnEvent("ADDON_LOADED", "Questie")
trackerUtils.SetQuestTomTomTarget(4242)
driver.path.settle()
equal(ns.JourneyGoal().questID, 4242, "Questie's quest reaches the stop it sets")
equal(ns.JourneyInfo(), "Journey to " .. questieTitle, "the waypoint keeps the guide's own title")
env.TomTom:AddWaypoint(1, 0.4, 0.4, { title = "All The Things", questID = 1234 })
driver.path.settle()
equal(ns.JourneyGoal().questID, 1234, "a caller's own questID is used")
env.TomTom:AddWaypoint(1, 0.3, 0.3, { title = "Plain", questID = "7" })
driver.path.settle()
equal(ns.JourneyGoal().questID, nil, "a questID that is not a quest id is left alone")

-- Zygor: the current step's goals name its quests, and a turn-in or pick-up step says so.
local zgv = {
	WaypointFunctions = { tomtom = {} },
	CurrentStep = {
		goals = {
			{ action = "turnin", questid = 100 },
			{ action = "accept", questid = 101 },
		},
	},
}
zgv.ConnectedWaypointer = zgv.WaypointFunctions.tomtom
env.ZGV = zgv
local zygor = env.TomTom:AddZWaypoint(10, 1, 60, 50, "Turn in 'The Escape'", false, true, true, nil, true, true)
driver.path.settle()
equal(type(zygor), "table", "Zygor's waypoint starts a journey")
equal(table.concat(ns.JourneyGoal().questIDs, ","), "100,101", "the step's goals name its quests")
equal(ns.JourneyGoal().details[1], "The Escape (turn in)", "a turn-in goal says what to do")
equal(ns.JourneyGoal().details[2], "The Letter (pick up)", "and a pick-up goal its own action")

-- A shape this build does not have leaves the guide's title alone rather than inventing a quest.
zgv.CurrentStep = { goals = "not a table" }
env.TomTom:AddWaypoint(1, 0.2, 0.2, { title = "Title only" })
driver.path.settle()
equal(ns.JourneyGoal().questIDs, nil, "a step of another shape names no quests")
equal(ns.JourneyGoal().details, nil, "and no action")
env.ZGV = nil

-- TomTom loading later replaces the global; the shim stands down and clears what it started.
local late = env.TomTom:AddWaypoint(1, 0.6, 0.5, { title = "Late" })
driver.path.settle()
equal(type(late), "table", "a journey TomTom's arrival will clear")
local real = { AddWaypoint = function() end }
env.TomTom = real
watcher:OnEvent("ADDON_LOADED", "TomTom")
equal(env.TomTom, real, "the real TomTom's global is left alone")
equal(ns.HasJourney(), false, "the shim's journey is cleared when TomTom arrives")

-- Following TomTom's arrow while it is installed: tests/tomtom_follow_spec.lua.

-- Driving TomTom's arrow from a Shortest Path journey (db.tomtomArrow, #1350).
do
	local Fake = assert(loadfile("tests/tomtom_fake.lua"))()

	---@param opts { tomtomArrow?: boolean, tomtomFollow?: boolean, arrow?: boolean, installed?: boolean }
	local function BootArrow(opts)
		local d = assert(loadfile("tests/journey_driver.lua"))()
		local n, e = d.ns, d.env
		local arrowFrame
		local baseCreate = e.CreateFrame
		e.CreateFrame = function(...)
			local f = baseCreate(...)
			f.SetShown = function(self, shown)
				if shown then
					self:Show()
				else
					self:Hide()
				end
			end
			f.EnableMouse = function(self, enabled)
				self.mouse = enabled
			end
			f.IsMouseEnabled = function(self)
				return self.mouse == true
			end
			f.SetScale = function(self, scale)
				self.scale = scale
			end
			f.GetCenter = function()
				return 500, 500
			end
			return f
		end
		d.load("UI/Looks.lua")
		d.load("UI/Art.lua")
		d.load("UI/Mover.lua")
		d.load("UI/TurnAround.lua")
		d.load("UI/CastButton.lua")
		d.load("UI/Arrow.lua")
		-- Capture the arrow frame lazily when UI/Arrow.lua creates it.
		local arrowCreate = e.CreateFrame
		local watcherFrame
		e.CreateFrame = function(...)
			local f = arrowCreate(...)
			watcherFrame = f
			return f
		end
		d.load("Core/APIInput.lua")
		d.load("Core/APIStops.lua")
		d.load("Core/API.lua")
		d.load("Journey/Itinerary.lua")

		local crazy = { alpha = 0.7, mouse = true, hidden = true }
		function crazy:SetAlpha(v)
			self.alpha = v
		end
		function crazy:EnableMouse(v)
			self.mouse = v
		end
		function crazy:Show()
			self.hidden = false
		end
		function crazy:Hide()
			self.hidden = true
		end
		e.TomTomCrazyArrow = crazy

		local timers = {}
		e.C_Timer = {
			After = function(_, fn)
				timers[#timers + 1] = fn
			end,
			NewTicker = function()
				return { Cancel = function() end }
			end,
		}
		e.InCombatLockdown = function()
			return false
		end
		e.UnitName = function()
			return "Tester"
		end
		e.UnitGUID = function()
			return "Player-1-TESTER"
		end
		e.hooksecurefunc = function(target, key, hook)
			local original = target[key]
			target[key] = function(...)
				local result = original(...)
				hook(...)
				return result
			end
		end
		local hasTomTom = opts.installed ~= false
		e.C_AddOns = {
			DoesAddOnExist = function(name)
				return hasTomTom and name == "TomTom"
			end,
			IsAddOnLoaded = function(name)
				return hasTomTom and name == "TomTom" and e.TomTom ~= nil
			end,
			GetAddOnEnableState = function(name)
				return hasTomTom and name == "TomTom" and 2 or 0
			end,
		}
		n.db.tomtom = true
		n.db.tomtomFollow = opts.tomtomFollow == true
		n.db.tomtomArrow = opts.tomtomArrow == true
		n.db.arrow = opts.arrow ~= false

		d.load("Core/TomTom.lua")
		local tomtomWatcher = watcherFrame
		d.load("Core/TomTomArrow.lua")

		-- Track any frame UI/Arrow.lua creates after load.
		local createdByArrow = e.CreateFrame
		e.CreateFrame = function(...)
			local f = createdByArrow(...)
			arrowFrame = arrowFrame or f
			return f
		end

		local fake
		if hasTomTom then
			fake = Fake.New(nil, crazy)
			function fake:ShowHideCrazyArrow()
				crazy:Show()
				crazy:SetAlpha(self.arrowAlpha or 0.7)
				crazy:EnableMouse(self.arrowMouse ~= false)
			end
			e.TomTom = fake
			tomtomWatcher:OnEvent("ADDON_LOADED", "TomTom")
			fake:Enable()
		end
		tomtomWatcher:OnEvent("PLAYER_ENTERING_WORLD")
		for _, fn in ipairs(timers) do
			fn()
		end
		return {
			driver = d,
			ns = n,
			env = e,
			API = e.ShortestPathForever.API,
			tomtom = fake,
			crazy = crazy,
			arrowFrame = function()
				return arrowFrame
			end,
		}
	end

	-- 1. Set on journey start, hides our arrow and game navigation marker, moves with bends and steps, removed on clear.
	do
		local c = BootArrow({ tomtomArrow = true })
		local adds, removes = 0, 0
		local origAdd, origRemove = c.tomtom.AddWaypoint, c.tomtom.RemoveWaypoint
		function c.tomtom:AddWaypoint(...)
			adds = adds + 1
			return origAdd(self, ...)
		end
		function c.tomtom:RemoveWaypoint(...)
			removes = removes + 1
			return origRemove(self, ...)
		end

		-- Foreign waypoint set beforehand must never be overwritten or removed.
		local foreign = c.tomtom:Way(1, 90, 90, "Player pin")
		adds = 0

		c.driver.move({ map = 1, x = 0, y = 0 })
		c.API.Navigate("Guide", 1, 0.6, 0.5, "Goldshire")
		c.driver.path.settle()
		local first = c.tomtom.Arrow()
		equal(adds, 1, "starting a journey adds one TomTom waypoint")
		equal(type(first), "table", "TomTom's arrow points at our waypoint")
		equal(first ~= foreign, true, "our waypoint is distinct from a foreign waypoint")
		equal(first[1], 1, "driven waypoint map")
		equal(math.abs(first[2] - 0.6) < 1e-6, true, "driven waypoint x")
		equal(math.abs(first[3] - 0.5) < 1e-6, true, "driven waypoint y")
		equal(first.title, "Goldshire", "driven waypoint title")
		equal(first.persistent, false, "driven waypoint is not persistent")
		equal(first.silent, true, "driven waypoint is silent")
		equal(first.crazy, true, "driven waypoint sets the crazy arrow")
		equal(first.cleardistance, 0, "driven waypoint leaves step clearing to Shortest Path")
		equal(c.arrowFrame(), nil, "native arrow frame stays uncreated/hidden while TomTom leads")
		local wp, tracked = c.driver.waypoint()
		equal(wp, nil, "no game navigation user waypoint while TomTom leads")
		equal(tracked, false, "game navigation marker is not super-tracked")
		equal(c.ns.ArrowLeads(), true, "ArrowLeads stays true while TomTom drives the route")
		equal(c.tomtom:IsValidWaypoint(foreign), true, "foreign waypoint stays intact")

		-- Multi-bend walk: points at the bend first, then moves to the step end as the bend passes.
		local start = { map = 1, x = 0, y = 0 }
		local bend = { map = 1, x = 0, y = -5000 }
		local stepEnd = { map = 1, x = 0, y = -10000, label = "Westfall" }
		c.ns.JourneyGuide.To(stepEnd, { start, bend, stepEnd }, stepEnd)
		local atBend = c.tomtom.Arrow()
		equal(atBend ~= first, true, "step update replaces the driven waypoint")
		equal(c.tomtom:IsValidWaypoint(first), false, "previous driven waypoint was removed")
		equal(math.abs(atBend[2] - 0.6) < 1e-6, true, "bend waypoint x")
		equal(atBend.title, "Westfall", "step title follows the new step")
		c.driver.move(bend)
		c.ns.AdvanceGuide()
		local atEnd = c.tomtom.Arrow()
		equal(atEnd ~= atBend, true, "passing a bend updates TomTom to the next bend/step end")
		equal(c.tomtom:IsValidWaypoint(atBend), false, "passed bend waypoint was removed")
		equal(math.abs(atEnd[2] - 0.7) < 1e-6, true, "step end waypoint x")

		-- Guide.Pause and Guide.Cast clear our driven waypoint while leaving foreign waypoints alone.
		c.ns.JourneyGuide.Pause()
		equal(c.tomtom:IsValidWaypoint(atEnd), false, "pausing guidance removes our driven waypoint")
		equal(c.tomtom:IsValidWaypoint(foreign), true, "pausing never removes foreign waypoints")

		-- Step change onto another stop, then clear removes our waypoint and preserves the foreign one.
		c.API.Navigate("Guide", 1, 0.75, 0.4, "Lakeshire")
		c.driver.path.settle()
		local step2 = c.tomtom.Arrow()
		equal(step2.title, "Lakeshire", "new journey step moves TomTom's waypoint")
		equal(math.abs(step2[2] - 0.75) < 1e-6, true, "new step x")
		c.ns.ClearJourney()
		equal(c.tomtom:IsValidWaypoint(step2), false, "clearing the journey removes our driven waypoint")
		equal(c.tomtom:IsValidWaypoint(foreign), true, "clearing never removes a foreign waypoint")
		equal(removes >= 3, true, "old driven waypoints were removed cleanly")
	end

	-- 2. Never loops with tomtomFollow; recognition is by waypoint table identity, not title or coordinates.
	do
		local c = BootArrow({ tomtomArrow = true, tomtomFollow = true })
		local navCalls = 0
		local origNav = c.API.NavigateRoute
		c.API.NavigateRoute = function(...)
			navCalls = navCalls + 1
			return origNav(...)
		end
		c.driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 0, y = -5000 })
		equal(navCalls, 0, "driving TomTom never loops back into tomtomFollow")
		local ours = c.tomtom.Arrow()
		equal(type(ours), "table", "TomTom received our step waypoint")
		-- Re-pointing TomTom's arrow at the exact same table we created is still ignored.
		c.tomtom:SetCrazyArrow(ours, 15, ours.title)
		equal(navCalls, 0, "re-pointing at our own waypoint table does not trigger tomtomFollow")
		-- A distinct foreign table with the exact same map, coordinates and title IS followed.
		local foreignSame = { ours[1], ours[2], ours[3], title = ours.title }
		c.tomtom:SetCrazyArrow(foreignSame, 15, foreignSame.title)
		c.driver.path.settle()
		equal(navCalls, 1, "a distinct foreign table with the same title and coordinates is followed")
		equal(c.API.CurrentStop("TomTom"), 1, "foreign waypoint started a followed journey")
		equal(c.crazy.alpha, 0.7, "TomTom's Crazy Arrow stays visible while tomtomArrow drives it")
		c.ns.ClearJourney()
	end

	-- 3. Never overwrites or removes a foreign waypoint even at the exact same map, coordinates and title.
	do
		local c = BootArrow({ tomtomArrow = true, tomtomFollow = true })
		local foreign = c.tomtom:Way(1, 60, 50, "Goldshire")
		c.driver.path.settle()
		equal(c.API.CurrentStop("TomTom"), 1, "foreign /way started a journey")
		equal(c.tomtom.Arrow(), foreign, "foreign waypoint at the exact same point stays on the arrow")
		equal(c.crazy.alpha, 0.7, "TomTom's Crazy Arrow is not muted while tomtomArrow is on")
		c.ns.ClearJourney()
		equal(c.tomtom:IsValidWaypoint(foreign), true, "clearing the journey never removes the foreign waypoint")
	end

	-- 4. Nothing when tomtomArrow is off (default): native arrow and game navigation marker work normally.
	do
		local c = BootArrow({ tomtomArrow = false })
		local adds = 0
		local origAdd = c.tomtom.AddWaypoint
		function c.tomtom:AddWaypoint(...)
			adds = adds + 1
			return origAdd(self, ...)
		end
		c.driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 0, y = -5000 })
		equal(adds, 0, "with tomtomArrow off, AddWaypoint is never called")
		local wp, tracked = c.driver.waypoint()
		equal(type(wp), "table", "with tomtomArrow off, game navigation marker is placed normally")
		equal(tracked, true, "with tomtomArrow off, game navigation marker is super-tracked")
		equal(c.arrowFrame() ~= nil and c.arrowFrame().hidden == false, true, "native arrow shows normally")
	end

	-- 5. Respects arrow=false (#1301): adds nothing, removes driven waypoint when turned off, preserves mute.
	do
		local c = BootArrow({ tomtomArrow = true, tomtomFollow = true, arrow = false })
		local adds = 0
		local origAdd = c.tomtom.AddWaypoint
		function c.tomtom:AddWaypoint(...)
			adds = adds + 1
			return origAdd(self, ...)
		end
		c.driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 0, y = -5000 })
		equal(adds, 0, "with arrow=false, tomtomArrow never adds a waypoint")
		local wp = c.driver.waypoint()
		equal(wp, nil, "with arrow=false, no game navigation marker either")
		c.ns.ClearJourney()
		-- Following a TomTom waypoint with arrow=false still mutes TomTom's Crazy Arrow (#1301).
		c.tomtom:Way(1, 60, 50, "Muted")
		c.driver.path.settle()
		equal(c.crazy.alpha, 0, "with arrow=false, TomTom's Crazy Arrow stays muted while following")
		c.ns.ClearJourney()
		-- Turning arrow=false mid-journey immediately removes our driven waypoint.
		c.ns.db.arrow = true
		c.ns.JourneyGuide.ArrowChanged()
		c.driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 0, y = -5000 })
		local driven = c.tomtom.Arrow()
		equal(type(driven), "table", "turning arrow back on lets tomtomArrow set a waypoint")
		c.ns.db.arrow = false
		c.ns.JourneyGuide.ArrowChanged()
		equal(c.tomtom:IsValidWaypoint(driven), false, "turning arrow=false mid-journey removes our driven waypoint")
	end

	-- 6. Real TomTom absent (only our shim in _G.TomTom): tomtomArrow stays inactive and never calls the shim.
	do
		local c = BootArrow({ tomtomArrow = true, installed = false })
		equal(c.ns.TomTomArrowActive(), false, "tomtomArrow ignores our own shim when TomTom is absent")
		c.driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 0, y = -5000 })
		equal(next(c.env.TomTom.waypoints), nil, "our shim never receives waypoints from tomtomArrow")
		equal(
			c.arrowFrame() ~= nil and c.arrowFrame().hidden == false,
			true,
			"native arrow shows when TomTom is absent"
		)
	end

	-- 7. Toggling tomtomArrow on/off mid-journey switches cleanly between native arrow and TomTom's arrow.
	do
		local c = BootArrow({ tomtomArrow = false })
		c.driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 0, y = -5000 })
		equal(c.arrowFrame() ~= nil and c.arrowFrame().hidden == false, true, "native arrow starts visible")
		c.ns.db.tomtomArrow = true
		c.ns.RefreshTomTomArrow()
		local driven = c.tomtom.Arrow()
		equal(type(driven), "table", "turning tomtomArrow on mid-journey sets TomTom's waypoint")
		equal(c.arrowFrame().hidden, true, "turning tomtomArrow on hides our native arrow")
		c.ns.db.tomtomArrow = false
		c.ns.RefreshTomTomArrow()
		equal(c.tomtom:IsValidWaypoint(driven), false, "turning tomtomArrow off removes our TomTom waypoint")
		equal(c.arrowFrame().hidden, false, "turning tomtomArrow off restores our native arrow")
	end
end

print("tomtom: ok, " .. checks .. " checks")

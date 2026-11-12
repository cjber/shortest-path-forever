---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local API = ShortestPathForever.API
local OWNER = "Dugi"

-- Dugi Guides publishes no guide-state API. The arrow module keeps the current route in its `waypoints` array, in
-- visit order: the next point is the first entry (SetNextWaypoint takes it), and the guide's own objective is the
-- first entry that is not one of its calculated travel legs. `isRouteDestination` is only set on the smart route,
-- so it is not a reliable flag; `isRouteWaypoint` marks a travel leg after the change callback has fired, which is
-- why a change is read one frame later. The module is a file local in Dugi's source and the viewer publishes it as
-- `DugisGuideViewer.DugisArrow` once it initializes; there is no global `DugisArrow`. Nothing of Dugi's is written:
-- its tables are only read, and its own change callbacks are hooked with hooksecurefunc. A build with a different
-- shape fails closed.

-- A higher-ranked guide keeps its journey when it is the one leading.
local LEADS = { RestedXP = true, AdventureGuideForever = true, Guidelime = true }

---@type string?
local target
-- The label of the running journey's target, which a renamed step may update in place.
---@type string?
local targetTitle
-- The quests and action lines that label stands for, so a step that moved on at the same place updates the stop.
---@type string?
local targetQuests
-- Set while a higher-ranked guide leads, and the exact owner it was, so only that guide's own end hands the step back.
local yielded = false
---@type string?
local leader
-- Set when the player ends a journey another guide led: Dugi stays off until *Resume guide* asks for it.
local stopped = false
-- Set while a leading guide's end reason is being read on the next frame; no Dugi step starts in between.
local waiting = false
-- Invalidates a deferred read when a later journey change has already moved the state on.
local generation = 0
-- Methods already hooked, and the wrapper installed, so a module reload is re-hooked once and a live hook is kept.
local watched = setmetatable({}, { __mode = "k" })
local watcher = CreateFrame("Frame")

local function Forget()
	target, targetTitle, targetQuests = nil, nil, nil
end

local function Clear()
	API.Cancel(OWNER)
	yielded, leader, stopped = false, nil, false
	Forget()
end

---@param value any
---@return boolean
local function Number(value)
	return canaccessvalue(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- A positive whole number: a quest id.
---@param value any
---@return boolean
local function ID(value)
	return Number(value) and value % 1 == 0 and value >= 1
end

-- The step text carries the guide's colour and icon markup; the tracker wants the words alone.
---@param text any
---@return string
local function Title(text)
	if not (canaccessvalue(text) and type(text) == "string") then
		return "Dugi Guides"
	end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("[\r\n]+", " ")
	text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" or text == "..." then
		return "Dugi Guides"
	end
	return text
end

-- The arrow module, under the name the viewer publishes once it initializes. Dugi keeps the module itself in a file
-- local (its only global alias is `DugisArrowGlobal`), so a missing viewer field is an uninitialized module, not a
-- global to find.
---@return SPFDugiArrow?
local function Arrow()
	local viewer = DugisGuideViewer
	if type(viewer) ~= "table" then
		return nil
	end
	local arrow = viewer.DugisArrow
	return type(arrow) == "table" and arrow or nil
end

-- The waypoints of the guide the player is running, or nil when no guide is on. A stored route restored at login is
-- not trusted once the guide is off or its title is no longer a guide the viewer holds.
---@return table? viewer, table? waypoints
local function Current()
	local viewer = DugisGuideViewer
	if type(viewer) ~= "table" or type(viewer.chardb) ~= "table" then
		return nil
	end
	if type(viewer.GuideOn) ~= "function" or not viewer:GuideOn() then
		return nil
	end
	local title = CurrentTitle
	if type(title) ~= "string" or title == "" then
		return nil
	end
	if type(viewer.guides) ~= "table" then
		return nil
	end
	if type(viewer.isValidGuide) == "function" and not viewer:isValidGuide(title) then
		return nil
	end
	local arrow = Arrow()
	return viewer, arrow and arrow.waypoints or nil
end

-- Dugi's next objective: the first waypoint that is not one of its travel legs and stands for a guide step (a guide
-- index, or the quest a POI step carries). The final waypoint is the last coordinate of a multi-stop step, not where
-- the guide wants the player next, so it is never used. Manual and corpse waypoints carry neither, and are skipped.
---@param waypoints any
---@return SPFDugiWaypoint?
local function Destination(waypoints)
	if not (canaccessvalue(waypoints) and type(waypoints) == "table") then
		return nil
	end
	for _, waypoint in ipairs(waypoints) do
		if canaccessvalue(waypoint) and type(waypoint) == "table" then
			local leg = canaccessvalue(waypoint.isRouteWaypoint) and waypoint.isRouteWaypoint == true
			if not leg then
				local guideIndex = canaccessvalue(waypoint.guideIndex) and waypoint.guideIndex or nil
				local quest = canaccessvalue(waypoint.questId) and tonumber(waypoint.questId) or nil
				if guideIndex ~= nil or ID(quest) then
					return waypoint
				end
			end
		end
	end
end

-- The quests a waypoint's step stands for. Travel and flight steps carry a quest id too, so only the actions that
-- are about a quest (accept, turn in, complete, kill or collect) name one; accept and turn in add their action line
-- through the shared collector. A POI waypoint has no guide index and carries the quest itself.
local QUEST_ACTIONS = { A = true, T = true, C = true, K = true }

---@param viewer table
---@param waypoint SPFDugiWaypoint
---@return number[]? quests, string[]? actions, string key
local function StepQuests(viewer, waypoint)
	local collector = ns.StepQuests()
	local quest = canaccessvalue(waypoint.questId) and tonumber(waypoint.questId) or nil
	if not ID(quest) then
		quest = nil
	end
	local guideIndex = canaccessvalue(waypoint.guideIndex) and waypoint.guideIndex or nil
	local action = type(guideIndex) == "number" and type(viewer.actions) == "table" and viewer.actions[guideIndex]
		or nil
	if action and QUEST_ACTIONS[action] then
		collector.add(quest, action == "A" and "accept" or action == "T" and "turnin" or nil)
	elseif guideIndex == nil and quest then
		collector.add(quest)
	end
	return collector.finish()
end

-- Dugi's route for one step, in the shape API.NavigateRoute takes, or nil when the waypoint cannot be planned.
---@param viewer table
---@param waypoint SPFDugiWaypoint
---@return {map: integer, x: number, y: number, title: string, quests: number[]?, actions: string[]?, key: string}?
local function Stop(viewer, waypoint)
	local map, x, y = waypoint.map, waypoint.x, waypoint.y
	if not Number(map) or map <= 0 or map % 1 ~= 0 then
		return nil
	end
	---@cast map integer
	if C_Map and type(C_Map.GetMapInfo) == "function" and not C_Map.GetMapInfo(map) then
		return nil
	end
	if not Number(x) or not Number(y) or x < 0 or x > 100 or y < 0 or y > 100 then
		return nil
	end
	---@cast x number
	---@cast y number
	local quests, actions, key = StepQuests(viewer, waypoint)
	return { map = map, x = x, y = y, title = Title(waypoint.desc), quests = quests, actions = actions, key = key }
end

-- The identity of a guide target: its map and position, not its step or label. A guide that moved on at the same
-- place keeps the journey and updates its stop, as RestedXP and Guidelime do.
---@param map integer
---@param x number
---@param y number
---@return string
local function Key(map, x, y)
	return string.format("%d:%d:%d", map, math.floor(x * 10 + 0.5), math.floor(y * 10 + 0.5))
end

-- Whether Dugi is still calculating a step's route. Its smart route clears the waypoints and fills them in later,
-- so an empty list while this runs is a step in progress, not a guide that stopped. Dugi marks an interrupted routine
-- instead of removing it, and only reaps it on a later scheduler tick, which emits no change of its own: an
-- interrupted routine is no longer calculating anything.
---@return boolean
local function Busy()
	local viewer = DugisGuideViewer
	if type(viewer) ~= "table" or type(viewer.GetRunningAutoroutine) ~= "function" then
		return false
	end
	local routine = viewer.GetRunningAutoroutine("SetSmartWaypoint")
	if not (canaccessvalue(routine) and type(routine) == "table") then
		return false
	end
	return routine.interrupt ~= true
end

local function Sync()
	if not (ns.db and ns.db.dugi and ns.db.journey) then
		Clear()
		return
	end
	if stopped or waiting then
		return
	end
	local viewer, waypoints = Current()
	if not viewer then
		Clear()
		return
	end
	-- RestedXP's step, Adventure Guide's journey and Guidelime's step lead when one is running: following a second
	-- guide back and forth would replan the same route on every step. The player's own journey is replaced by a new
	-- step, as RestedXP does, and *Resume guide* takes the guide back at any time.
	local owner = ns.JourneyOwner()
	if owner and owner ~= OWNER and LEADS[owner] then
		yielded, leader = true, owner
		Forget()
		return
	end
	yielded, leader = false, nil
	if not waypoints then
		if Busy() then
			return
		end
		Clear()
		return
	end
	local waypoint = Destination(waypoints)
	if not waypoint then
		if Busy() then
			return
		end
		Clear()
		return
	end
	local stop = Stop(viewer, waypoint)
	if not stop then
		Clear()
		return
	end
	local key = Key(stop.map, stop.x, stop.y)
	if InCombatLockdown() then
		if key ~= target then
			API.Cancel(OWNER)
			Forget()
		end
		watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if key ~= target then
		-- Dugi decides when its step is complete, including its own arrival radius and triggers: the journey holds
		-- the stop while the guide stays on it.
		local started = API.NavigateRoute(OWNER, {
			{
				map = stop.map,
				x = stop.x / 100,
				y = stop.y / 100,
				title = stop.title,
				hold = true,
				questIDs = stop.quests,
				tooltip = stop.actions and table.concat(stop.actions, "\n") or nil,
			},
		})
		if not started then
			Clear()
			return
		end
		target, targetTitle, targetQuests = key, stop.title, stop.key
	elseif stop.key ~= targetQuests then
		-- The step moved on at the same place (a turn-in at the NPC just left): only its quests changed, so the stop
		-- gets the new live objectives without the route being planned again.
		targetQuests = stop.key
		local index = API.CurrentStop(OWNER)
		if index then
			ns.SetStopQuests(OWNER, index, stop.quests, stop.actions)
		end
	end
	local index = API.CurrentStop(OWNER)
	if index and stop.title ~= targetTitle then
		targetTitle = stop.title
		API.RenameStop(OWNER, index, stop.title)
	end
end

-- A change inside Dugi's own call stack only asks for one read on the next frame: its smart route clears the list
-- and fills it later, and an error inside its coroutine would also skip its own follow-up work.
local pending = false
local function Schedule()
	if pending then
		return
	end
	if not (C_Timer and type(C_Timer.After) == "function") then
		Sync()
		return
	end
	pending = true
	C_Timer.After(0, function()
		pending = false
		Sync()
	end)
end

-- Hook one of Dugi's own methods once, and again if a module reload replaces it. The stored wrapper says whether the
-- live method is still ours.
---@param object table
---@param method string
---@param callback fun()
local function HookOnce(object, method, callback)
	local original = rawget(object, method)
	if type(original) ~= "function" then
		return
	end
	local record = watched[object]
	if not record then
		record = {}
		watched[object] = record
	end
	if record[method] == original then
		return
	end
	hooksecurefunc(object, method, callback) -- taint-ok: Dugi owns this addon table.
	record[method] = rawget(object, method)
end

-- Dugi defines the arrow module's methods inside Initialize, which can run after PLAYER_LOGIN, and an unloaded
-- module answers every missing method with a callable stub. Hooking before the real method exists would wrap the
-- stub or be overwritten, so the real method is found after a module load instead of by name at addon load.
local function TryHook()
	local arrow = Arrow()
	if arrow then
		HookOnce(arrow, "WaypointsChanged", Schedule)
	end
end

local function Watch()
	local viewer = DugisGuideViewer
	if type(viewer) ~= "table" then
		return
	end
	HookOnce(viewer, "ReloadModules", function()
		TryHook()
		Watch()
		Schedule()
	end)
	-- A guide that is cleared or advanced without a waypoint change still ends its journey.
	HookOnce(viewer, "ClearScreen", Schedule)
	HookOnce(viewer, "LoadNextGuide", Schedule)
	TryHook()
end

-- Let the player hand control back after pausing a guide, without waiting for Dugi's next waypoint change. It also
-- clears a journey the player ended while another guide led.
function ns.ResumeDugi()
	generation = generation + 1
	waiting, stopped = false, false
	yielded, leader = false, nil
	Forget()
	Sync()
end

-- The setting, Dugi loading and the addon's own load all call this.
function ns.RefreshDugi()
	Watch()
	if type(DugisGuideViewer) == "table" and ns.db and ns.db.dugi and ns.db.journey then
		Sync()
	else
		Clear()
	end
end

-- A higher-ranked guide taking over is seen here even when Dugi's own arrow never changed, so its exact owner is
-- remembered. When that guide ends, API.Cancel marks it cancelled only after ClearJourney returns; the reason is read
-- on the next frame, where the leader's own cancel is "cancelled" and the player's clear is "cleared". A player clear
-- stays off until *Resume guide*; the leader's own cancel, and its arrival, hand the step back.
hooksecurefunc(ns, "JourneyChanged", function(point)
	local owner = ns.JourneyOwner()
	if owner and owner ~= OWNER and LEADS[owner] then
		generation = generation + 1
		waiting, stopped = false, false
		yielded, leader = true, owner
		Forget()
		return
	end
	if not yielded then
		return
	end
	if point then
		-- Another journey started; a manual owner is replaced by Dugi's next step, as it is without a leader.
		generation = generation + 1
		waiting = false
		yielded, leader = false, nil
		return
	end
	local endedLeader = leader
	yielded, leader = false, nil
	if not endedLeader then
		Schedule()
		return
	end
	generation = generation + 1
	local token = generation
	waiting = true
	local function Check()
		if token ~= generation or not waiting then
			return
		end
		waiting = false
		if ns.JourneyOwner() then
			return
		end
		local reason = API.Ended(endedLeader)
		if reason == "cancelled" or reason == "arrived" then
			stopped = false
			Forget()
			Sync()
		else
			stopped = true
		end
	end
	if C_Timer and type(C_Timer.After) == "function" then
		C_Timer.After(0, Check)
	else
		Check()
	end
end)

ns.Init(function()
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:RegisterEvent("PLAYER_LOGIN")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", function(self, event, name)
		if event == "PLAYER_REGEN_ENABLED" then
			self:UnregisterEvent(event)
			Sync()
		elseif event == "ADDON_LOADED" then
			if name == "DugisGuideViewerZ" then
				ns.RefreshDugi()
			end
		else
			ns.RefreshDugi()
		end
	end)
	ns.RefreshDugi()
end)

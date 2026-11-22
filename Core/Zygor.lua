---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

local API = ShortestPathForever.API
local OWNER = "Zygor"

-- Zygor's guide state is read only where its tables and values have the expected shape.
---@param value any
---@return table?
local function Table(value)
	return canaccessvalue(value) and type(value) == "table" and value or nil
end

-- The Zygor table, under either name its versions publish it.
---@return table?
local function Zygor()
	local env = getfenv()
	return Table(rawget(env, "ZGV"))
		or Table(rawget(_G, "ZGV"))
		or Table(rawget(env, "ZygorGuidesViewer"))
		or Table(rawget(_G, "ZygorGuidesViewer"))
end

-- Whether Zygor's own waypointer is feeding TomTom, which is when a TomTom waypoint is the guide's current step.
---@param zgv table
---@return boolean
local function UsesTomTom(zgv)
	local functions = Table(zgv.WaypointFunctions)
	local tomtom = functions and Table(functions.tomtom)
	if not tomtom then
		return false
	end
	local connected = zgv.ConnectedWaypointer
	if not canaccessvalue(connected) then
		return false
	end
	if connected ~= nil then
		return connected == tomtom
	end
	local db = Table(zgv.db)
	local profile = db and Table(db.profile)
	return profile ~= nil and canaccessvalue(profile.waypointaddon) and profile.waypointaddon == "tomtom"
end

function ns.ZygorUsesTomTom()
	local zgv = Zygor()
	return zgv ~= nil and UsesTomTom(zgv)
end

-- A goal's action replaces the objectives; any other quest-bearing goal keeps them.
---@param zgv table
---@return number[]? quests, string[]? actions, string key
local function StepQuests(zgv)
	local step = Table(zgv.CurrentStep)
	local goals = step and Table(step.goals) or {}
	local collector = ns.StepQuests()
	for _, goal in ipairs(goals) do
		if canaccessvalue(goal) and type(goal) == "table" then
			local questID = ns.QuestID(goal.questid) or ns.QuestID(goal.questID)
			local action = canaccessvalue(goal.action) and goal.action or nil
			collector.add(questID, (action == "turnin" or action == "accept") and action or nil)
		end
	end
	return collector.finish()
end

-- A TomTom waypoint can name Zygor as its source even when a separate bridge forwards it.
---@param explicit? boolean
---@return number[]? quests, string[]? actions
function ns.ZygorStop(explicit)
	local zgv = Zygor()
	if not (zgv and (explicit or UsesTomTom(zgv))) then
		return nil
	end
	local quests, actions = StepQuests(zgv)
	return quests, actions
end

local watcher = CreateFrame("Frame")
---@type table<table, table<string, boolean>>
local hooked = setmetatable({}, { __mode = "k" })
---@type table?
local hiddenPointer
local scheduled = false
local targetMap, targetX, targetY, targetTitle, targetQuests

local function Enabled()
	return ns.db and ns.db.zygor and ns.db.journey
end

-- The same guide point can reach the TomTom integration while this route is already under way.
function ns.ZygorFollows(map, x, y)
	return Enabled()
		and canaccessvalue(map)
		and canaccessvalue(x)
		and canaccessvalue(y)
		and map == targetMap
		and x == targetX
		and y == targetY
		and API.CurrentStop(OWNER) ~= nil
end

local function Clear()
	targetMap, targetX, targetY, targetTitle, targetQuests = nil, nil, nil, nil, nil
	API.Cancel(OWNER)
end

---@param value any
---@return string?
local function Title(value)
	return canaccessvalue(value) and type(value) == "string" and value ~= "" and value or nil
end

---@param waypoint table
---@return string
local function WaypointTitle(waypoint)
	local get = waypoint.GetArrowTitle
	if canaccessvalue(get) and type(get) == "function" then
		local ok, value = pcall(get, waypoint)
		local title = ok and Title(value) or nil
		if title then
			return title
		end
	end
	return Title(waypoint.arrowtitle) or Title(waypoint.title) or OWNER
end

local function Sync()
	if not Enabled() then
		Clear()
		return
	end
	local zgv = Zygor()
	local pointer = zgv and Table(zgv.Pointer)
	local arrow = pointer and pointer ~= hiddenPointer and Table(pointer.ArrowFrame)
	local waypoint = arrow and Table(arrow.waypoint)
	if not zgv or not waypoint then
		Clear()
		return
	end
	-- The arrow's waypoint uses a uiMapID and normalized coordinates.
	local map, x, y = waypoint.m, waypoint.x, waypoint.y
	local input = ns.APIInput
	if not (input.ID(map) and input.Number(x) and x >= 0 and x <= 1 and input.Number(y) and y >= 0 and y <= 1) then
		Clear()
		return
	end
	if ns.TomTomFollowsZygor and ns.TomTomFollowsZygor(map, x, y) then
		Clear()
		return
	end
	local owner = ns.JourneyOwner()
	if ns.HasJourney() and (owner == nil or owner == "Shortest Path Forever") then
		return
	end
	local moved = map ~= targetMap or x ~= targetX or y ~= targetY
	if InCombatLockdown() then
		if moved then
			Clear()
		end
		watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local title = WaypointTitle(waypoint)
	local quests, actions, questKey = StepQuests(zgv)
	if moved then
		local started = API.NavigateRoute(OWNER, {
			{
				map = map,
				x = x,
				y = y,
				title = title,
				hold = true,
				questIDs = quests,
				tooltip = actions and table.concat(actions, "\n") or nil,
			},
		})
		if started then
			targetMap, targetX, targetY, targetTitle, targetQuests = map, x, y, title, questKey
		else
			Clear()
		end
		return
	end
	local stop = API.CurrentStop(OWNER)
	if stop and title ~= targetTitle then
		targetTitle = title
		API.RenameStop(OWNER, stop, title)
	end
	if stop and questKey ~= targetQuests then
		targetQuests = questKey
		ns.SetStopQuests(OWNER, stop, quests, actions)
	end
end

-- One step change can update the pointer several times. Read the settled arrow after Zygor's calls return.
local function Schedule()
	if not Enabled() or scheduled then
		return
	end
	scheduled = true
	C_Timer.After(0, function()
		scheduled = false
		Sync()
	end)
end

---@param object table
---@param method string
---@param callback function
local function Hook(object, method, callback)
	local fn = object[method]
	if not canaccessvalue(fn) or type(fn) ~= "function" then
		return
	end
	local methods = hooked[object] or {}
	if not methods[method] then
		hooked[object], methods[method] = methods, true
		hooksecurefunc(object, method, callback) -- taint-ok: Zygor owns this addon table.
	end
end

-- Another route can replace Zygor's while its arrow stays put. Forget the replaced target so that, once that route
-- ends and no journey is left, the same step starts again even though Zygor's pointer never changed.

local replaced = false
local function JourneyChanged()
	if not ns.HasJourney() then
		if replaced then
			replaced = false
			Schedule()
		end
	elseif targetMap and ns.JourneyOwner() ~= OWNER then
		replaced = true
		targetMap, targetX, targetY, targetTitle, targetQuests = nil, nil, nil, nil, nil
	end
end

function ns.RefreshZygor()
	local zgv = Zygor()
	if zgv then
		Hook(zgv, "SetCurrentStep", Schedule)
		local pointer = Table(zgv.Pointer)
		if pointer then
			Hook(pointer, "ShowArrow", function(_, waypoint)
				if Table(waypoint) then
					hiddenPointer = nil
				end
				Schedule()
			end)
			Hook(pointer, "HideArrow", function(self)
				hiddenPointer = self
				Schedule()
			end)
		end
	end
	Sync()
end

ns.Init(function()
	hooksecurefunc(ns, "JourneyChanged", JourneyChanged)
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:RegisterEvent("PLAYER_LOGIN")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", function(self, event, name)
		if event == "PLAYER_REGEN_ENABLED" then
			self:UnregisterEvent(event)
			Sync()
		elseif
			event ~= "ADDON_LOADED"
			or name == "ZygorGuidesViewer"
			or name == "ZygorGuidesViewerClassic"
			or name == "ZygorGuidesViewerForever"
		then
			ns.RefreshZygor()
		end
	end)
	ns.RefreshZygor()
end)

---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Zygor publishes no API for its guide state, so only the fields its own tables name are read, and only when they hold
-- the types expected. A build with a different shape gives the waypoint its title alone rather than a wrong quest.
-- Zygor reaches Shortest Path by setting a TomTom waypoint: its current step's goals name the quests the stop stands
-- for, and the TomTom shim (or a followed TomTom arrow) carries them into the journey.

---@param value any
---@return table?
local function Table(value)
	return canaccessvalue(value) and type(value) == "table" and value or nil
end

-- A third-party addon's global, read from the environment the addon was loaded in (the game's, or a test's).
---@param name string
---@return any
local function Global(name)
	return rawget(getfenv(), name) or rawget(_G, name)
end

-- The Zygor table, under either name its versions publish it.
---@return table?
local function Zygor()
	local zgv = Global("ZGV")
	if type(zgv) == "table" then
		return zgv
	end
	local named = Global("ZygorGuidesViewer")
	return type(named) == "table" and named or nil
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
	local connected = canaccessvalue(zgv.ConnectedWaypointer) and zgv.ConnectedWaypointer or nil
	if connected ~= nil then
		return connected == tomtom
	end
	local profile = Table(zgv.db) and Table(zgv.db.profile) or nil
	return profile ~= nil and profile.waypointaddon == "tomtom"
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

-- The current step's quests for a TomTom waypoint, which is the stop Zygor's guide stands for.
---@return number[]? quests, string[]? actions
function ns.ZygorStop()
	local zgv = Zygor()
	if not (zgv and UsesTomTom(zgv)) then
		return nil
	end
	local quests, actions = StepQuests(zgv)
	return quests, actions
end

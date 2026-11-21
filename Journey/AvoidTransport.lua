---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- Transport the player chose to avoid from a step's right-click menu (UI/Tracker.lua). The list is saved per character
-- in charDB.avoided and PlanContext.lua drops each entry from the planner's routes, taxi paths and portals. When an
-- avoid leaves the journey no route, the tracker names that step and offers to undo it.

local AvoidTransport = {}
ns.AvoidTransport = AvoidTransport

-- The entry the player avoided last and the goal it was avoided on, kept until a route is found or the journey ends.
---@type SPFAvoidedTransport?
local lastAvoid
---@type SPFPoint?
local avoidGoal

function AvoidTransport.Forget()
	lastAvoid, avoidGoal = nil, nil
end

-- The tracker row for a journey that the last avoid left with no route, or nil.
---@param goal SPFPoint?
function AvoidTransport.Row(goal)
	if not (lastAvoid and goal and avoidGoal == goal) then
		return nil
	end
	return {
		key = "avoided-transport",
		text = L["No route remains without %s. Right-click to undo."]:format(lastAvoid.name),
		undoAvoid = lastAvoid,
	}
end

---@param entries SPFAvoidedTransport[]
local function SetAvoided(entries)
	if not ns.charDB then
		return false
	end
	ns.charDB.avoided = entries
	ns.TransportAvoided()
	return true
end

-- Whether the player may avoid this step: a transport not yet boarded. The ride under way cannot be left, so the
-- planner keeps it and an avoid would never take; that step shows no menu.
---@param leg SPFLeg
---@return boolean
function AvoidTransport.Allowed(leg)
	local result, first, departed = ns.JourneyPlan()
	return result ~= nil and not (departed and result.legs[first] == leg)
end

---@param leg SPFLeg
function ns.AvoidJourneyTransport(leg)
	local goal = ns.JourneyGoal()
	local result, first = ns.JourneyPlan()
	if not (goal and result and AvoidTransport.Allowed(leg)) or (ns.Corpse and ns.Corpse.Active()) then
		return
	end
	for index = first, #result.legs do
		if result.legs[index] == leg then
			local ids = {}
			if leg.route then
				ids[1] = leg.route
			elseif leg.portal then
				local portal = ns.Portals and ns.Portals[leg.portal]
				if portal then
					ids[1] = ns.PlanContext.PortalID(portal)
				end
			elseif leg.mode == "flight" then
				-- A displayed flight may combine several taxi edges. Exclude each edge in its flown direction,
				-- since the planner never searches a combined edge and the reverse ride is a separate connection.
				for _, hop in ipairs(leg.hops or {}) do
					ids[#ids + 1] = ns.PlanContext.TaxiHopID(hop)
				end
			end
			if #ids == 0 then
				return
			end
			local entries = {}
			for i, entry in ipairs(ns.PlanContext.Avoided()) do
				entries[i] = entry
				if entry.kind == leg.mode and table.concat(entry.ids, ",") == table.concat(ids, ",") then
					return
				end
			end
			local entry = { kind = leg.mode, ids = ids, name = ns.LegStep(leg) }
			entries[#entries + 1] = entry
			if SetAvoided(entries) then
				lastAvoid, avoidGoal = entry, goal
			end
			return
		end
	end
end

---@param avoided SPFAvoidedTransport
function ns.UndoAvoidedTransport(avoided)
	local entries = {}
	local found = false
	for _, entry in ipairs(ns.PlanContext.Avoided()) do
		if entry == avoided then
			found = true
		else
			entries[#entries + 1] = entry
		end
	end
	if found and SetAvoided(entries) then
		AvoidTransport.Forget()
	end
end

function ns.ClearAvoidedTransport()
	if #ns.PlanContext.Avoided() > 0 and SetAvoided({}) then
		AvoidTransport.Forget()
	end
end

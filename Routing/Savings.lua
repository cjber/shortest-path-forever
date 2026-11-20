---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- What a Hearthstone or a class teleport must be worth before a plan keeps it: its own minimum saving over the best
-- route without it. Dropping one can surface the other, which is then held to its own minimum, and each is dropped at
-- most once. The planner passes its own bounded search in, so this file holds the policy and not the graph.
local Savings = {}
ns.Savings = Savings

---@class SPFSavingsOptions
---@field hearthMinimum number ms the Hearthstone must save
---@field teleportMinimum number ms a class teleport must save
---@field withoutHearth boolean the journey's own switch keeps the Hearthstone out from the start

---@alias SPFPlanSearch fun(withoutHearth: boolean, withoutTeleports: boolean, cutoff: number): SPFPlan?

-- Whether a leg is a class teleport: its own destination, not a party portal. A bind teleport is the Hearthstone or
-- Astral Recall and follows the Hearthstone's own switch.
---@param leg SPFLeg
---@return boolean
local function ClassTeleport(leg)
	return leg.teleport ~= nil and not leg.partyPortal and not leg.teleport.bind
end

-- Applies both minima to `planned`. Returns the plan that meets them, and the drops it settled on, which the caller
-- keeps for every later search.
---@param planned SPFPlan?
---@param search SPFPlanSearch
---@param options SPFSavingsOptions
---@return SPFPlan?, boolean withoutHearth, boolean withoutTeleports
function Savings.Apply(planned, search, options)
	local withoutHearth, withoutTeleports = options.withoutHearth, false
	while planned do
		local minimum, hearth = nil, false
		for _, leg in ipairs(planned.legs) do
			if options.hearthMinimum > 0 and leg.teleport and leg.teleport.bind and not withoutHearth then
				minimum, hearth = options.hearthMinimum, true
				break
			elseif options.teleportMinimum > 0 and ClassTeleport(leg) and not withoutTeleports then
				minimum = options.teleportMinimum
				break
			end
		end
		if not minimum then
			break
		end
		if hearth then
			withoutHearth = true
		else
			withoutTeleports = true
		end
		-- The admissible bound can prove the saving before the full alternative settles.
		local baseline = search(withoutHearth, withoutTeleports, planned.arrive + minimum)
		if not (baseline and baseline.arrive - planned.arrive < minimum) then
			break
		end
		planned = baseline
	end
	return planned, withoutHearth, withoutTeleports
end

-- Whether a plan rides more than it walks. The planner swaps a long walk for a ride (#86) only when the ride is one:
-- a short flight away from the goal that leaves most of the walk in place is still a long way on foot, and only
-- arrives later (#1102). Leg arrivals are on the planner's clock, from `now`.
---@param plan SPFPlan
---@param now number
---@return boolean
function Savings.MostlyRides(plan, now)
	local walking, at = 0, now
	for _, leg in ipairs(plan.legs) do
		if leg.mode == "walk" then
			walking = walking + leg.arrive - at
		end
		at = leg.arrive
	end
	return walking * 2 < plan.arrive - now
end

---@class SPFNamespace
local ns = select(2, ...)
local L = ns.L

-- With "Other Faction's Routes" off, the journey's goal pin says how much faster the journey would be through the
-- other faction's boats and zeppelins: one line of time, never a word on safety. It shows only for a saving of two
-- minutes or more. The comparison plans as Estimate does (baked walks, no endpoint searches, average waits for boats
-- not yet seen), which can be out by about that much, and one death and graveyard run costs more than that anyway.

local THRESHOLD = 120000
-- A comparison stands this long (ms) for the same goal and much the same place.
local KEEP, MOVED = 30000, 50
local FACTIONS = { Horde = L["Horde"], Alliance = L["Alliance"] }

-- Each policy keeps its own topology: the planner mutates its cache between calls.
local caches = { own = {}, other = {} }
---@type {goal: SPFPoint, at: number, x: number, y: number, map: number, text: string|false}?
local last

-- The other faction's transport a plan rides, if any.
---@param plan SPFPlan
---@param faction string
---@return string?
local function OtherFaction(plan, faction)
	for _, leg in ipairs(plan.legs) do
		local route = leg.route and ns.Routes[leg.route]
		if route and route.faction and route.faction ~= faction then
			return route.faction
		end
	end
end

---@param from SPFPoint
---@param goal SPFPoint
---@return string|false
local function Compare(from, goal)
	local options = ns.PlanContext.Options(from, goal)
	options.waterWalking = ns.JourneyWaterWalking()
	options.cache, options.otherFaction = caches.own, false
	local own = ns.Planner.Plan(options)
	options.cache, options.otherFaction = caches.other, true
	local other = ns.Planner.Plan(options)
	if not other then
		return false
	end
	local faction = OtherFaction(other, options.faction)
	local saving = own and own.arrive - other.arrive or math.huge
	if not faction or saving < THRESHOLD then
		return false
	end
	if saving == math.huge then
		return string.format(L["Through %s transport, there is a way"], FACTIONS[faction] or faction)
	end
	return string.format(
		L["Through %s transport: about %d min faster"],
		FACTIONS[faction] or faction,
		math.floor(saving / 60000 + 0.5)
	)
end

-- The goal pin's line, or nil: only with the setting off, out of combat, for the journey under way.
---@return string?
function ns.OtherFactionHint()
	local goal = ns.JourneyGoal()
	if not goal or ns.db.otherFaction or InCombatLockdown() then
		return nil
	end
	local x, y, _, map = ns.JourneyPosition()
	if not (x and y and map) then
		return nil
	end
	local now = ns.NowMs()
	local kept = last
	if
		not kept
		or kept.goal ~= goal
		or kept.map ~= map
		or now - kept.at > KEEP
		or (kept.x - x) ^ 2 + (kept.y - y) ^ 2 > MOVED ^ 2
	then
		kept = { goal = goal, at = now, x = x, y = y, map = map, text = Compare({ map = map, x = x, y = y }, goal) }
		last = kept
	end
	return kept.text or nil
end

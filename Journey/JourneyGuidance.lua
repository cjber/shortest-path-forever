---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Copy the active guide for companion navigators through the public API's map projection. This is separate from the
-- guide's private waypoint lifecycle because companion addons need the projected route, not the native waypoint state.
---@param project fun(point: SPFPoint): SPFAPIPlace?
---@return SPFAPIGuidance?, SPFAPIGuidanceReason?
function ns.JourneyGuidance(project)
	local guide = ns.JourneyGuide
	-- A corpse run borrows guidance while the journey setting waits, so it still has a point to give.
	local corpse = ns.Corpse ~= nil and ns.Corpse.Active()
	if ns.db.journey == false and not corpse then
		return nil, "disabled"
	end
	if guide and guide.Paused() then
		return nil, "paused"
	end
	if guide and guide.Casting() then
		return nil, "cast"
	end
	local target, source, index
	if ns.GuideState then
		target, source, index = ns.GuideState()
	end
	if not (target and source and index) then
		-- A first plan still being searched has no point to give yet, exactly as the tracker shows a spinner.
		local _, _, _, loading = ns.JourneyStatus()
		if loading then
			return nil, "loading"
		end
		if ns.HasJourney and ns.HasJourney() then
			return nil, "paused"
		end
		return nil, "none"
	end
	local waypoints = {}
	for at = 1, #source do
		local place = project(source[at])
		if not place then
			return nil, "unavailable"
		end
		waypoints[at] = place
	end
	local point = project(target)
	if not (point and index >= 1 and index <= #waypoints) then
		return nil, "unavailable"
	end
	-- A corpse run is the guidance under way while it lasts, and reports itself as the player's own, as Journey does.
	local owner = ns.JourneyOwner()
	local leg
	if ns.Corpse and ns.Corpse.Active() then
		leg, owner = select(4, ns.Corpse.Info()) or 1, nil
	else
		local _, current = ns.JourneyPlan()
		leg = current or 1
	end
	return {
		owner = owner,
		leg = leg,
		point = point,
		waypoints = waypoints,
		index = index,
	}
end

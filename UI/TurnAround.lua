---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- There is no text cue: facing away only dims the compass and the arrow. Past 120 degrees off the next point is
-- behind enough to dim them. Once dimmed they stay dimmed until it is within 100 degrees, so a player turning on the
-- spot gets no flicker as the cue crosses the threshold.
local SHOW, KEEP = 120, 100
-- The same strength DestinationPin.lua gives the goal behind you.
ns.BEHIND_ALPHA = 0.4

---@class SPFTurnAround
local TurnAround = {}
ns.TurnAround = TurnAround

-- Whether the next point is behind you, given whether it already was. `angle` is radians off facing.
---@param angle number
---@param wasBehind boolean?
---@return boolean
function TurnAround.Behind(angle, wasBehind)
	local degrees = math.abs(angle) * 180 / math.pi
	return degrees > SHOW or (wasBehind == true and degrees >= KEEP)
end

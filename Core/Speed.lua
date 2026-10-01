---@class SPFNamespace
local ns = select(2, ...)
local lastSpeed = 7

-- Run speed stays meaningful while standing still. Secret combat values retain the last readable speed.
---@return number
function ns.RunSpeed()
	local _, speed = GetUnitSpeed("player")
	if canaccessvalue(speed) and type(speed) == "number" and speed > 0 and speed < math.huge then
		lastSpeed = speed
	end
	return lastSpeed
end

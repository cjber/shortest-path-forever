---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

---@param yards number
---@param compact? boolean
---@return string
function ns.FormatDistance(yards, compact)
	if compact and yards >= 999.5 then
		return string.format(ns.db.metres and L["%.1f km"] or L["%.1fk yd"], yards / 1000)
	end
	return string.format(ns.db.metres and L["%d m"] or L["%d yd"], math.floor(yards + 0.5))
end

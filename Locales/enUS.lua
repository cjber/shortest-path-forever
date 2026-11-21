---@class SPFNamespace
local ns = select(2, ...)

-- English phrases are the keys, so a phrase with no translation reads as English.
---@type table<string, string>
local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
ns.L = L

L["stop guiding"] = "stop guiding"
L["guide this journey"] = "guide this journey"
L["show it on the map"] = "show it on the map"
L["That guide has no step to follow."] = "That guide has no step to follow."
L["Off-path tolerance"] = "Off-path tolerance"
L["How far you can stray from a walking path before a new one is searched."] =
	"How far you can stray from a walking path before a new one is searched."
L["Rides to spend less time walking through %s (level %s)"] = "Rides to spend less time walking through %s (level %s)"
L["Walk less in zones with a minimum level 4 or more above yours, even at your destination."] =
	"Walk less in zones with a minimum level 4 or more above yours, even at your destination."

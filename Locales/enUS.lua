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
L["Click to use %s"] = "Click to use %s"
L["Click to cast %s"] = "Click to cast %s"
L["The travel action will update after combat."] = "The travel action will update after combat."
L["Avoid this boat"] = "Avoid this boat"
L["Avoid this zeppelin"] = "Avoid this zeppelin"
L["Avoid this lift"] = "Avoid this lift"
L["Avoid this tram"] = "Avoid this tram"
L["Avoid this flight"] = "Avoid this flight"
L["Avoid this portal"] = "Avoid this portal"
L["Avoid this passage"] = "Avoid this passage"
L["Undo"] = "Undo"
L["Allow this transport again and find a new route."] = "Allow this transport again and find a new route."
L["Find a new route without this transport. You can clear avoided transport in Settings."] =
	"Find a new route without this transport. You can clear avoided transport in Settings."
L["No route remains without %s. Right-click to undo."] = "No route remains without %s. Right-click to undo."
L["Avoided transport"] = "Avoided transport"
L["Clear avoided transport"] = "Clear avoided transport"
L["Clear this character's avoided transport so the planner can use it again."] =
	"Clear this character's avoided transport so the planner can use it again."
L["%s-right-click the map to mark a road or wall for a report."] =
	"%s-right-click the map to mark a road or wall for a report."
L["Mark: road missing here"] = "Mark: road missing here"
L["Mark: wall here"] = "Mark: wall here"
L["%s-right-click the map to copy the report or clear its marks."] =
	"%s-right-click the map to copy the report or clear its marks."
L["Save this spot in the report to help fix the walking map."] =
	"Save this spot in the report to help fix the walking map."
L["This spot has no world coordinates. Choose another spot."] =
	"This spot has no world coordinates. Choose another spot."
L["Copy road and wall report"] = "Copy road and wall report"
L["Open the report so you can copy and paste it into a bug report."] =
	"Open the report so you can copy and paste it into a bug report."
L["Clear marks"] = "Clear marks"
L["Remove all saved road and wall marks from the map and report."] =
	"Remove all saved road and wall marks from the map and report."
L["Road and wall report"] = "Road and wall report"
L["Journey start: %s"] = "Journey start: %s"
L["Journey goal: %s"] = "Journey goal: %s"
L["Rides to spend less time walking through %s (level %s)"] = "Rides to spend less time walking through %s (level %s)"
L["Walk less in zones with a minimum level 4 or more above yours, even at your destination."] =
	"Walk less in zones with a minimum level 4 or more above yours, even at your destination."

---@meta

-- Dugi Guides 1.087 (Forever, Interface 16001) publishes no integration API. The viewer's arrow module is a file
-- local in Dugi's source (its only global alias is `DugisArrowGlobal`) and is published as
-- `DugisGuideViewer.DugisArrow` once it initializes; its current route is the `waypoints` array, in visit order.
-- Only these fields are read, and only its own callbacks are hooked.

---@class SPFDugiWaypoint
---@field map? integer the uiMapID
---@field floor? number the map floor, not a world height
---@field x? number percent of the map
---@field y? number percent of the map
---@field desc? string the step's localized description, with colour and icon markup
---@field guideIndex? integer index into the viewer's step tables
---@field questId? integer the step's quest, also on travel and flight steps
---@field isRouteWaypoint? boolean a calculated travel leg, set after the change callback fires
---@field isRouteDestination? boolean the objective, set only on the smart route
---@field isCorpseWaypoint? boolean the player's corpse, not a guide step

---@class SPFDugiArrow
---@field waypoints? SPFDugiWaypoint[]
---@field WaypointsChanged fun(self: SPFDugiArrow, reason?: string)

---@class SPFDugiGuideViewer
---@field DugisArrow? SPFDugiArrow
---@field chardb? {GuideOn: boolean?}
---@field guides? table<string, any>
---@field actions? string[] the action code per guide step
---@field GuideOn fun(self: SPFDugiGuideViewer): boolean?
---@field isValidGuide? fun(self: SPFDugiGuideViewer, title: string): boolean?
---@field GetRunningAutoroutine? fun(key: string): table?
---@field ReloadModules? fun(self: SPFDugiGuideViewer, threading?: boolean): boolean?
---@field ClearScreen? fun(self: SPFDugiGuideViewer)
---@field LoadNextGuide? fun(self: SPFDugiGuideViewer)

---@type SPFDugiGuideViewer?
DugisGuideViewer = nil

-- The current guide's title, set next to `DugisGuideViewer.CurrentTitle`; the viewer clears only this one in places.
---@type string?
CurrentTitle = nil

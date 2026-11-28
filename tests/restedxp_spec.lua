local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API
env.C_QuestLog = {
	GetTitleForQuestID = function(questID)
		return questID == 777 and "The Escape" or nil
	end,
}
local combat = false
env.InCombatLockdown = function()
	return combat
end
env.hooksecurefunc = function(object, method, callback)
	local original = object[method]
	object[method] = function(...)
		original(...)
		callback(...)
	end
end
local watcher
local create = env.CreateFrame
env.CreateFrame = function(...)
	watcher = create(...)
	return watcher
end
ns.db.restedxp = true
driver.load("Core/RestedXP.lua")
assert(not API.CurrentStop("RestedXP"), "missing RestedXP does nothing")
local function Region()
	local region = { shown = true }
	function region:IsShown()
		return self.shown
	end
	function region:SetShown(value)
		self.shown = value
	end
	function region:Hide()
		self.shown = false
	end
	return region
end
local frame = { texture = Region(), text = Region(), mouse = true }
function frame:IsMouseEnabled()
	return self.mouse
end
function frame:EnableMouse(value)
	self.mouse = value
end
local rxp = {
	ResetArrowPosition = function() end,
	arrowFrame = frame,
	settings = { profile = { showEnabled = true } },
	currentGuide = {},
	UpdateMap = function() end,
	UpdateGotoSteps = function() end,
}
env.RXP = rxp
env.RXPGuides = {} -- The public guide catalogue is a different table from RXP.
frame.element = { zone = 1, x = 60, y = 50, title = "RestedXP target", arrow = true, step = { active = true } }
rxp.activeWaypoints = { frame.element }
watcher:OnEvent("ADDON_LOADED", "RXPGuides")
driver.path.settle()
assert(API.CurrentStop("RestedXP") == 1, "late-loaded guide starts a journey")
assert(frame.texture.shown and frame.text.shown, "A standalone RestedXP journey leaves its own arrow visible")
assert(frame.mouse == true, "the guide arrow still takes clicks")

-- The active step's quests reach the stop. A step that kills and then turns in keeps the live objectives; a step that
-- only turns in says so, with the client's quest name.
frame.element.step.elements = {
	{ tag = "complete", questId = 777 },
	{ tag = "turnin", questId = 777 },
}
rxp.UpdateGotoSteps()
assert(ns.JourneyGoal().questIDs[1] == 777, "the step's quest reaches the running stop")
assert(ns.JourneyGoal().details == nil, "a mixed step keeps its objectives rather than an action")
frame.element.step.elements = {
	{ tag = "turnin", questId = 777 },
}
rxp.UpdateGotoSteps()
assert(ns.JourneyGoal().details[1] == "The Escape (turn in)", "a turn-in step says what to do")
ns.db.arrow = false
rxp.UpdateMap()
driver.path.settle()
assert(frame.texture.shown and frame.text.shown, "RestedXP's arrow comes back when our own arrow is off")
assert(API.CurrentStop("RestedXP") == 1, "the journey keeps running without our own arrow")
ns.db.arrow = true
rxp.UpdateMap()
driver.path.settle()
assert(frame.texture.shown, "RestedXP keeps its arrow when Shortest Path's arrow setting is on")
assert(rxp.settings.profile.disableArrow == nil, "guide settings stay untouched")
ns.db.restedxpHideArrow = false
ns.RefreshRestedXP()
assert(API.CurrentStop("RestedXP") == 1, "keeping the guide arrow still follows the guide target")
assert(frame.texture.shown and frame.text.shown, "turning the takeover off leaves RestedXP's arrow shown")
assert(frame.mouse == true, "the visible guide arrow still takes clicks")
ns.db.restedxpHideArrow = true
ns.RefreshRestedXP()
assert(frame.texture.shown and frame.text.shown, "the Adventure Guide setting leaves the standalone arrow visible")
assert(frame.mouse == true, "the guide arrow still takes clicks")
assert(API.CurrentStop("RestedXP") == 1, "the journey keeps following the guide")
local starts = 0
local start = ns.StartJourney
ns.StartJourney = function(...)
	starts = starts + 1
	return start(...)
end
rxp.UpdateGotoSteps()
rxp.UpdateMap()
assert(starts == 0, "unchanged targets do not replan")
API.Cancel("RestedXP")
assert(frame.texture.shown and frame.text.shown, "cancellation restores the original regions")
ns.ResumeRestedXP()
driver.path.settle()
assert(API.CurrentStop("RestedXP") == 1, "resume invalidates the held target and takes control back")
API.Cancel("RestedXP")
starts = 0
frame.element.title = "|cffffffffRestedXP target|r"
rxp.UpdateGotoSteps()
assert(not API.CurrentStop("RestedXP"), "title colour changes respect cancellation")
assert(frame.mouse == true, "cancellation restores mouse input")
frame.element.x = 70
combat = true
rxp.UpdateGotoSteps()
assert(starts == 0, "combat defers planning")
assert(frame.texture.shown, "combat leaves the current guide arrow available")
combat = false
watcher:OnEvent("PLAYER_REGEN_ENABLED")
driver.path.settle()
assert(starts == 1 and API.CurrentStop("RestedXP") == 1, "combat end uses the latest target")
-- A target that changes during combat cancels the stale journey; if it moves back to the original spot before combat
-- ends, ending combat must still restart the journey rather than treating the cancelled target as unchanged (#1349).
starts = 0
combat = true
frame.element.x = 75
rxp.UpdateGotoSteps()
assert(not API.CurrentStop("RestedXP"), "a target change during combat cancels the old journey")
frame.element.x = 70
rxp.UpdateGotoSteps()
combat = false
watcher:OnEvent("PLAYER_REGEN_ENABLED")
driver.path.settle()
assert(
	starts == 1 and API.CurrentStop("RestedXP") == 1,
	"returning to the pre-combat target before combat ends still restarts the cancelled journey"
)
-- A manual cancellation before combat is still respected when the target never moved during combat.
API.Cancel("RestedXP")
starts = 0
combat = true
rxp.UpdateGotoSteps()
combat = false
watcher:OnEvent("PLAYER_REGEN_ENABLED")
driver.path.settle()
assert(starts == 0 and not API.CurrentStop("RestedXP"), "combat does not undo a manual cancel on an unchanged target")
API.Navigate("Other", 1, 0.6, 0.5, "Player destination")
rxp.UpdateGotoSteps()
assert(API.CurrentStop("Other") == 1, "same target does not take over another journey")
assert(frame.texture.shown and frame.text.shown, "another owner restores the arrow")
-- #905: a manual map destination survives the guide advancing its flight step.
local manual = { map = 1, x = 300, y = 200, title = "Manual destination" }
ns.StartJourney(manual)
driver.path.settle()
env.UnitOnTaxi = function()
	return true
end
frame.element.x = 80
rxp.UpdateGotoSteps()
rxp.UpdateMap()
assert(ns.JourneyGoal() == manual, "RXP flight step update must preserve the manual destination")
env.UnitOnTaxi = function()
	return false
end
rxp.UpdateGotoSteps()
assert(ns.JourneyGoal() == manual, "landing keeps the manual destination")
assert(API.Navigate("Shortest Path Forever", 1, 0.3, 0.2, "Nearby destination"))
local nearby = ns.JourneyGoal()
frame.element.x = 81
rxp.UpdateGotoSteps()
assert(ns.JourneyGoal() == nearby, "Nearby manual destinations keep the same priority")
assert(API.NavigateRoute("SPF:Stops:1:1", { { map = 1, x = 0.3, y = 0.25 } }))
local stops = ns.JourneyGoal()
frame.element.x = 82
rxp.UpdateGotoSteps()
assert(ns.JourneyGoal() == stops, "a Journey stops route keeps the same priority")
assert(ns.ResumeRestedXP(), "explicit resume returns control to the guide")
driver.path.settle()
assert(API.CurrentStop("RestedXP") == 1, "resumed guide owns the journey")
ns.db.restedxp = false
ns.RefreshRestedXP()
assert(
	not API.CurrentStop("RestedXP") and frame.texture.shown and frame.text.shown,
	"disabling clears only its journey and restores arrow"
)
ns.db.restedxp = true
ns.RefreshRestedXP()
assert(API.CurrentStop("RestedXP") == 1, "enabling starts the current target")
rxp.hideArrow = true
rxp.UpdateGotoSteps()
assert(not API.CurrentStop("RestedXP"), "hidden or completed guide target clears its journey")
rxp.hideArrow = false
frame.element.x = 150
rxp.UpdateGotoSteps()
assert(
	not API.CurrentStop("RestedXP") and frame.texture.shown and frame.text.shown,
	"invalid target leaves guide arrow available"
)
frame.element.x = 60
rxp.UpdateGotoSteps()
frame.element.skip = true
rxp.UpdateGotoSteps()
assert(not API.CurrentStop("RestedXP"), "a skipped waypoint clears its held journey")
frame.element.skip = false
rxp.UpdateGotoSteps()
frame.element.step.active = false
rxp.UpdateMap()
assert(not API.CurrentStop("RestedXP"), "inactive stale arrow targets cannot restart guidance")
frame.element.step.active = true
rxp.hideArrow = true
frame.wrongContinent = true
rxp.UpdateGotoSteps()
assert(API.CurrentStop("RestedXP") == 1, "cross-continent guide targets still plan travel")
rxp.ResetArrowPosition()
assert(frame.texture.shown, "resetting the arrow keeps it with RestedXP")
rxp.activeWaypoints = {}
rxp.UpdateGotoSteps()
assert(not API.CurrentStop("RestedXP"), "empty waypoints clear stale cross-continent targets")
rxp.activeWaypoints = { frame.element }
rxp.currentGuide = nil
rxp.UpdateMap()
assert(
	not API.CurrentStop("RestedXP") and frame.texture.shown and frame.text.shown,
	"unloading the guide clears stale target"
)
local integrated = true
env.AdventureGuideForever = { API = {
	RestedXPIntegrated = function()
		return integrated
	end,
} }
rxp.currentGuide = {}
rxp.settings.profile.showEnabled = true
rxp.activeWaypoints = { frame.element }
frame.element.hidden, frame.element.completed, frame.element.skip = false, false, false
frame.element.arrow = true
rxp.UpdateMap()
assert(not API.CurrentStop("RestedXP"), "AGF's integrated frontend does not start a competing route")
assert(
	not frame.texture.shown and not frame.text.shown and not frame.mouse,
	"our arrow points at the frontend's step, so RestedXP's own stays hidden"
)
assert(API.NavigateRoute("AdventureGuideForever", { { map = 1, x = 0.6, y = 0.5, title = "Step 28" } }))
rxp.UpdateMap()
assert(not frame.texture.shown, "RestedXP's arrow stays hidden while the frontend's journey runs")
API.Cancel("AdventureGuideForever")
local resumed = 0
env.AdventureGuideForever.API.ResumeRestedXP = function()
	resumed = resumed + 1
	return true
end
ns.ResumeRestedXP()
assert(resumed == 1 and not API.CurrentStop("RestedXP"), "resume delegates to the integrated navigation owner")
rxp.UpdateMap()
assert(not API.CurrentStop("RestedXP"), "engine updates keep navigation with the frontend")
ns.db.restedxp = false
ns.RefreshRestedXP()
assert(not frame.texture.shown, "the frontend's step keeps RXP's arrow hidden with standalone following off")
ns.JourneyChanged()
assert(not frame.texture.shown, "journey changes keep RXP's arrow hidden under the frontend")
ns.db.restedxp = true
integrated = false
ns.RefreshRestedXP()
driver.path.settle()
assert(API.CurrentStop("RestedXP"), "native guide navigation resumes when the frontend is disabled")
env.AdventureGuideForever.API.RestedXPNativeUI = function()
	return true
end
ns.RefreshRestedXP()
assert(
	not API.CurrentStop("RestedXP") and frame.texture.shown and frame.text.shown,
	"the native UI choice restores RXP navigation without changing standalone preferences"
)
assert(ns.db.restedxp, "display choice preserves the standalone preference")

-- #237: RestedXP recalculates element.x/y between its own updates, and near a rested-XP level-up it updates far more
-- often. Guidance must restart only when the guide genuinely points somewhere else.
local nativeUI = env.AdventureGuideForever.API.RestedXPNativeUI
env.AdventureGuideForever.API.RestedXPNativeUI = function()
	return false
end
ns.RefreshRestedXP()
driver.path.settle()
local navigations = 0
local navigate = API.NavigateRoute
API.NavigateRoute = function(...)
	navigations = navigations + 1
	return navigate(...)
end
assert(API.CurrentStop("RestedXP") == 1, "the guide target is guided again")
frame.element.x, frame.element.y = 60, 50
navigations = 0
rxp.UpdateGotoSteps()
rxp.UpdateMap()
assert(navigations == 0, "(a) an identical target plans nothing twice")
frame.element.x = 60.03
rxp.UpdateGotoSteps()
frame.element.x, frame.element.y = 60, 50.04
rxp.UpdateMap()
assert(navigations == 0, "(b) coordinates jittered inside the tolerance plan nothing")
frame.element.step.index = 2
rxp.UpdateGotoSteps()
assert(navigations == 0, "(d) a new step index at the same position plans nothing")
frame.element.title = "RestedXP renamed target"
local trackerVersion = ns.journeyVersion
local relabels = 0
local refreshTracker = ns.RefreshTracker
ns.RefreshTracker = function()
	relabels = relabels + 1
end
rxp.UpdateGotoSteps()
assert(navigations == 0, "(c) a renamed step at the same position plans nothing")
assert(relabels == 1 and ns.journeyVersion == trackerVersion, "the renamed step redraws the tracker, not a journey")
assert(API.RenameStop("RestedXP", 1, "RestedXP renamed target"), "a held stop can be relabelled in place")
frame.element.x = 60.2
rxp.UpdateGotoSteps()
assert(navigations == 1 and API.CurrentStop("RestedXP") == 1, "(c) a target that moves plans once")
-- (e) RestedXP's update arrives while our restart is still running: NavigateRoute calls ns.ItineraryChanged, and
-- RestedXP's own hooks (the map redraw, the step update) run from inside that call.
local reentered = 0
local itineraryChanged = ns.ItineraryChanged
ns.ItineraryChanged = function(...)
	reentered = reentered + 1
	rxp.UpdateGotoSteps()
	rxp.UpdateMap()
	rxp.ResetArrowPosition()
	return itineraryChanged(...)
end
navigations = 0
frame.element.x = 70
rxp.UpdateMap()
assert(reentered > 0, "the restart re-enters the guide's hooks")
assert(navigations == 1, "(e) hooks fired by our own navigation do not plan again")
assert(API.CurrentStop("RestedXP") == 1, "the re-entrant hooks leave the journey under way")
ns.ItineraryChanged = itineraryChanged

-- RestedXP picks the next objective of its step as the player moves, and moves its arrow there. That is the journey's
-- own destination moving, not a new journey: the drawn line, the arrow and the tracker stay while the new plan is
-- searched, so nothing flashes between the two objectives (#693).
local restarted = 0
local restartJourney = ns.StartJourney
ns.StartJourney = function(...)
	restarted = restarted + 1
	return restartJourney(...)
end
rxp.UpdateGotoSteps()
driver.path.settle()
local held = driver.shown()
restarted, navigations = 0, 0
frame.element.x = 70.4
rxp.UpdateGotoSteps()
assert(navigations == 1, "the guide's arrow reports the new objective")
assert(restarted == 0, "a moved objective does not restart the journey")
assert(held and driver.shown(), "the route already drawn stays while the new plan is searched")
assert(ns.IsJourneyGuided(), "guidance is kept, not stopped and started")
assert(API.CurrentStop("RestedXP") == 1, "the guide still owns the journey")
driver.path.settle()
assert(driver.shown() and driver.shown() ~= held, "the new plan replaces the drawn route once")
-- A guide can also move its current stop across continents.
local prior = assert(ns.JourneyPlan())
ns.Portals = {
	{
		name = "Passage",
		kind = "portal",
		from = { map = 1, x = 200, y = 0 },
		to = { map = 2, x = 200, y = 0 },
		seconds = 5,
	},
}
frame.element.zone = 2
rxp.UpdateGotoSteps()
assert(ns.JourneyGoal().map == 2, "the new continent is the active target")
assert(ns.JourneyPlan() == prior and ns.IsJourneyGuided(), "the old guidance remains while crossing maps")
assert(not ns.SkipJourneyStep(), "a retained leg cannot complete the new stop")
driver.path.settle()
local cross = assert(ns.JourneyPlan(), "the new journey has a route")
assert(cross ~= prior and cross.legs[#cross.legs].to.map == 2, "the cross-continent plan takes over")
local onTaxi = true
local unitOnTaxi = env.UnitOnTaxi
env.UnitOnTaxi = function()
	return onTaxi
end
frame.element.zone = 1
rxp.UpdateGotoSteps()
driver.update(0.1)
assert(ns.JourneyPlan() == cross, "a taxi in flight retains its route while the guide moves the target")
onTaxi = false
driver.update(0.1)
local landed = assert(ns.JourneyPlan(), "a replacement is ready after landing")
assert(landed ~= cross and landed.legs[#landed.legs].to.map == 1, "landing resumes planning for the new target")
env.UnitOnTaxi = unitOnTaxi
ns.StartJourney = restartJourney

API.NavigateRoute = navigate
navigations = 0
ns.db.journey = false
ns.RefreshRestedXP()
assert(not API.CurrentStop("RestedXP") and navigations == 0, "the journey setting still clears guidance")
ns.db.journey = true
ns.db.restedxp = false
ns.RefreshRestedXP()
assert(not API.CurrentStop("RestedXP") and navigations == 0, "the guide setting still clears guidance")
ns.db.restedxp = true
env.AdventureGuideForever.API.RestedXPNativeUI = nativeUI
ns.RefreshTracker = refreshTracker

local pin = { zone = 1 }
rxp.RXPFrame = { activeSteps = { { elements = { pin } } } }
local function restedPin(x, y)
	pin.waypointSet, pin.zx, pin.zy = nil, nil, nil
	env.C_Map.SetUserWaypoint(env.UiMapPoint.CreateFromCoordinates(pin.zone, x, y))
	env.C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	local position = env.C_Map.GetUserWaypointPositionForMap(pin.zone)
	pin.waypointSet, pin.zx, pin.zy = true, position.x, position.y
end

local redraw
ns.PointGuideArrow = function(points, place)
	redraw = points and place and function()
		place(points[#points])
	end
	if redraw then
		redraw()
	end
end
env.AdventureGuideForever.API.RestedXPNativeUI = function()
	return false
end
assert(ns.ResumeRestedXP(), "RestedXP guides again")
driver.update(0)
assert(ns.IsJourneyGuided() and driver.waypoint(), "guidance has published a waypoint")
local ownedGoal = ns.JourneyGoal()
ns.db.mapPinRoutes = false
restedPin(0.6, 0.4)
driver.update(0)
assert(ns.IsJourneyGuided() and ns.JourneyGoal() == ownedGoal, "RestedXP's first waypoint write preserves guidance")

ns.db.mapPinRoutes = true
restedPin(0.61, 0.4)
driver.update(0)
assert(ns.JourneyGoal() == ownedGoal, "RestedXP's waypoint never replaces its journey with a player route")

restedPin(0.62, 0.4)
restedPin(0.63, 0.4)
driver.update(0)
assert(ns.IsJourneyGuided() and ns.JourneyGoal() == ownedGoal, "two RestedXP writes in one frame preserve guidance")
assert(driver.waypoint().position.x == 0.63, "the latest RestedXP pin stays in the slot")

local function playerPin(x, y)
	local point = env.UiMapPoint.CreateFromCoordinates(1, x or 0.3, y or 0.45)
	env.C_Map.SetUserWaypoint(point)
	return point
end

ns.db.mapPinRoutes = false
restedPin(0.64, 0.4)
local player = playerPin()
driver.update(0)
assert(not ns.IsJourneyGuided() and ns.JourneyGoal() == ownedGoal, "a later player pin ends guidance with routing off")
assert(driver.waypoint() == player, "ending guidance preserves the player's pin")

ns.db.mapPinRoutes = true
assert(ns.ResumeRestedXP(), "the player resumes the RestedXP route")
driver.update(0)
restedPin(0.65, 0.4)
playerPin()
driver.update(0)
local playerGoal = ns.JourneyGoal()
assert(ns.JourneyOwner() == nil and playerGoal and playerGoal.y > 9999, "a later player pin starts their route")

assert(ns.ResumeRestedXP(), "the player hands navigation back to RestedXP")
driver.update(0)
local originalGuidePin = assert(driver.waypoint(), "the resumed guide marks the map")
ns.db.mapPinRoutes = false
restedPin(0.66, 0.4)
env.C_Map.SetUserWaypoint(originalGuidePin)
driver.update(0)
assert(not ns.IsJourneyGuided(), "repinning the guide's old point still ends guidance after the slot changed")
assert(driver.waypoint() == originalGuidePin, "the guide leaves the player's replacement pin in place")

ns.db.mapPinRoutes = true
assert(ns.ResumeRestedXP(), "RestedXP guides before the journey is cleared")
driver.update(0)
restedPin(0.67, 0.4)
ns.ClearJourney()
driver.update(0)
assert(not ns.HasJourney(), "a pending RestedXP pin cannot restart a journey the player cleared")
restedPin(0.68, 0.4)
driver.update(0)
assert(not ns.HasJourney(), "a RestedXP pin written without a journey starts nothing")

-- The arrow's side of a redraw (tests/arrow_spec.lua): its next tick places the marker again, standing or not.
local stale
ns.RedrawGuideMarker = function()
	stale = true
end
local function tick()
	if stale then
		stale = nil
		redraw()
	end
end

-- RestedXP's own removal: it drops its record, then clears the pin that still matches it.
local function restedClear()
	local position = env.C_Map.GetUserWaypointPositionForMap(pin.zone)
	pin.waypointSet = false
	if position and position.x == pin.zx and position.y == pin.zy then
		env.C_Map.ClearUserWaypoint()
	end
end

local function questJourney()
	env.C_Map.ClearUserWaypoint()
	ns.StartJourney({ map = 1, x = 400, y = 400, label = "quest stop", questID = 777 })
	driver.path.settle()
	driver.update(0)
	assert(driver.waypoint(), "the quest journey marks the map")
	return ns.JourneyGoal()
end

for _, routes in ipairs({ false, true }) do
	ns.db.mapPinRoutes = routes
	local questGoal = questJourney()
	restedPin(0.7, 0.4)
	driver.update(0)
	restedClear()
	driver.update(0)
	assert(ns.JourneyGoal() == questGoal, "RestedXP clearing its pin keeps the player's journey")
	assert(ns.IsJourneyGuided() and not driver.waypoint(), "guidance goes on after RestedXP clears its pin")
	tick()
	assert(driver.waypoint(), "the journey marks the map again, with the player standing still")
	driver.update(0)
	env.C_Map.ClearUserWaypoint()
	driver.update(0)
	assert(not ns.HasJourney(), "the player removing the journey's own marker still ends it")

	questGoal = questJourney()
	restedPin(0.71, 0.4)
	restedClear()
	driver.update(0)
	assert(ns.JourneyGoal() == questGoal and ns.IsJourneyGuided(), "a pin set and cleared in one frame is RestedXP's")

	restedPin(0.72, 0.4)
	driver.update(0)
	restedClear()
	restedPin(0.73, 0.4)
	driver.update(0)
	assert(ns.JourneyGoal() == questGoal and ns.IsJourneyGuided(), "RestedXP's next pin keeps the player's journey")
	assert(driver.waypoint().position.x == 0.73, "RestedXP's next pin stays in the slot")
	ns.ClearJourney()
end

ns.db.mapPinRoutes = true
env.C_Map.ClearUserWaypoint()
rxp.RXPFrame.activeSteps = {}
playerPin()
driver.path.settle()
local pinGoal = assert(ns.JourneyGoal(), "the player's pin starts a route")
rxp.RXPFrame.activeSteps = { { elements = { pin } } }
restedPin(0.74, 0.4)
driver.update(0)
restedClear()
driver.update(0)
assert(ns.JourneyGoal() == pinGoal, "RestedXP clearing its pin keeps the route to the player's earlier pin")
restedPin(0.75, 0.4)
restedClear()
driver.update(0)
assert(ns.JourneyGoal() == pinGoal, "and so does a pin it sets and clears in one frame")

playerPin(0.31)
driver.update(0)
assert(ns.HasJourney() and ns.JourneyGoal() ~= pinGoal, "the player's next pin routes while RestedXP has steps")
env.C_Map.ClearUserWaypoint()
driver.update(0)
assert(not ns.HasJourney(), "and removing it ends that route")

-- Another arrow leads, so the journey marks no pin of its own over the player's.
ns.TomTomArrowActive = function()
	return true
end
playerPin(0.35)
driver.update(0)
assert(ns.HasJourney(), "the player's pin routes while another arrow leads")
env.C_Map.ClearUserWaypoint()
driver.update(0)
assert(not ns.HasJourney(), "removing the pin that stayed the player's ends its route")
ns.TomTomArrowActive = nil

restedPin(0.78, 0.4)
driver.update(0)
rxp.RXPFrame.activeSteps = {}
playerPin(0.32)
driver.update(0)
assert(ns.HasJourney(), "the player's pin over RestedXP's routes once its steps are over")
env.C_Map.ClearUserWaypoint()
driver.update(0)
assert(not ns.HasJourney(), "and removing it ends that route too")
rxp.RXPFrame.activeSteps = { { elements = { pin } } }

restedPin(0.79, 0.4)
driver.update(0)
restedClear()
playerPin(0.79, 0.4)
driver.update(0)
assert(ns.HasJourney(), "the player's pin where a finished step stood is theirs")
ns.ClearJourney()

playerPin(0.33)
playerPin(0.33)
driver.update(0)
assert(ns.HasJourney(), "a pin written twice before it is judged still routes")
ns.ClearJourney()

playerPin()
local replacement = { map = 1, x = 900, y = 900, label = "chosen next" }
ns.StartJourney(replacement)
local chosen = ns.JourneyGoal()
driver.update(0)
assert(ns.JourneyGoal() == chosen, "a pin still being judged cannot replace a journey started after it")

-- The ownership callback, held so a spec can act between a write and its judgement.
local function holdJudgement(body)
	local pending = {}
	local after = env.C_Timer.After
	env.C_Timer.After = function(_, callback)
		pending[#pending + 1] = callback
	end
	body()
	env.C_Timer.After = after
	for _, callback in ipairs(pending) do
		callback()
	end
end

driver.update(0)
ns.ClearJourney()
holdJudgement(function()
	playerPin(0.34)
	driver.fire("PLAYER_ENTERING_WORLD")
end)
assert(not ns.HasJourney(), "a pin still being judged across a loading screen starts nothing")

local loading = questJourney()
holdJudgement(function()
	restedPin(0.76, 0.4)
	driver.fire("PLAYER_ENTERING_WORLD")
end)
assert(not ns.charDB.guideWaypoint, "RestedXP's pin is not remembered as the guide's own")
redraw()
assert(
	ns.JourneyGoal() == loading and driver.waypoint().position.x ~= 0.76,
	"a loading screen leaves the guide marking"
)
ns.ClearJourney()

env.Enum.SuperTrackingMapPinType = { TaxiNode = 1 }
env.C_SuperTrack.GetSuperTrackedMapPin = function() end
ns.TaxiNodes[5] = { map = 1, x = 700, y = 700 }
ns.db.focusedQuest = true
ns.FocusedTrackingReset()
holdJudgement(function()
	env.C_SuperTrack.GetSuperTrackedMapPin = function()
		return 1, 5
	end
	restedPin(0.755, 0.4)
	driver.fire("SUPER_TRACKING_CHANGED")
	assert(not ns.HasJourney(), "a focus chosen while a pin is judged waits for it")
end)
assert(ns.JourneyGoal() and ns.JourneyGoal().x == 700, "and is answered once the pin is judged")
ns.ClearJourney()
env.C_SuperTrack.GetSuperTrackedMapPin = function() end
ns.FocusedTrackingReset()
driver.update(0)
holdJudgement(function()
	env.C_SuperTrack.GetSuperTrackedMapPin = function()
		return 1, 5
	end
	restedPin(0.77, 0.4)
	driver.fire("SUPER_TRACKING_CHANGED")
	ns.ClearJourney()
end)
assert(not ns.HasJourney(), "a focus held back from before a cleared journey starts nothing")
driver.fire("SUPER_TRACKING_CHANGED")
assert(not ns.HasJourney(), "nor does the next report of the same focus")
print("restedxp: ok")

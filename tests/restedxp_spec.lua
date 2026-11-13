local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
driver.load("UI/Looks.lua")
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
assert(not frame.texture.shown and not frame.text.shown, "the guide arrow becomes invisible")
assert(frame.mouse == false, "the invisible arrow does not intercept clicks")

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
assert(not frame.texture.shown, "Shortest Path suppresses RestedXP's arrow again")
assert(rxp.settings.profile.disableArrow == nil, "guide settings stay untouched")
ns.db.restedxpHideArrow = false
ns.RefreshRestedXP()
assert(API.CurrentStop("RestedXP") == 1, "keeping the guide arrow still follows the guide target")
assert(frame.texture.shown and frame.text.shown, "turning the takeover off leaves RestedXP's arrow shown")
assert(frame.mouse == true, "the visible guide arrow still takes clicks")
ns.db.restedxpHideArrow = true
ns.RefreshRestedXP()
assert(not frame.texture.shown and not frame.text.shown, "turning the takeover back on hides the guide arrow")
assert(frame.mouse == false, "the hidden guide arrow takes no clicks")
assert(API.CurrentStop("RestedXP") == 1, "hiding the arrow again keeps the journey running")
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
API.Navigate("Other", 1, 0.6, 0.5, "Player destination")
rxp.UpdateGotoSteps()
assert(API.CurrentStop("Other") == 1, "same target does not take over another journey")
assert(frame.texture.shown and frame.text.shown, "another owner restores the arrow")
frame.element.x = 80
rxp.UpdateGotoSteps()
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
assert(not frame.texture.shown, "resetting the arrow keeps delegated guidance")
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
print("restedxp: ok")

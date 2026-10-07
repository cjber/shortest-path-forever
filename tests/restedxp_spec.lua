local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API
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
assert(rxp.settings.profile.disableArrow == nil, "guide settings stay untouched")
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
assert(not frame.texture.shown and not frame.mouse, "the integrated frontend suppresses the native arrow")
rxp.UpdateMap()
assert(not API.CurrentStop("RestedXP"), "engine updates keep navigation with the frontend")
ns.db.restedxp = false
ns.RefreshRestedXP()
assert(not frame.texture.shown, "AGF suppresses RXP arrow even with standalone integration disabled")
ns.JourneyChanged()
assert(not frame.texture.shown, "journey changes retain AGF arrow suppression")
ns.db.restedxp = true
integrated = false
ns.RefreshRestedXP()
driver.path.settle()
assert(API.CurrentStop("RestedXP"), "native guide navigation resumes when the frontend is disabled")
print("restedxp: ok")

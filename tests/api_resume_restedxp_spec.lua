-- ResumeRestedXP is the tracker's and Settings' own resume through the public API, so a macro can hand the guide
-- back: true when a guide is followed, unavailable with no guide to resume, invalid in combat where guidance cannot
-- start.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = driver.ns, driver.env, 0
driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
local API = env.ShortestPathForever.API
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function why(expected, label, value, reason)
	equal(value, nil, label)
	equal(reason, expected, label .. " reason")
end

-- The global a macro calls: /run ShortestPathForever.API.ResumeRestedXP()
equal(type(env.ShortestPathForever.API.ResumeRestedXP), "function", "the macro's call path exists")

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

-- Nothing to resume before RestedXP is there, and still nothing while it has no guide.
why("unavailable", "RestedXP does not run", API.ResumeRestedXP())
assert(not API.CurrentStop("RestedXP"), "and no guide is followed")

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
env.RXPGuides = {}
frame.element = { zone = 1, x = 60, y = 50, title = "RestedXP target", arrow = true, step = { active = true } }
rxp.activeWaypoints = { frame.element }
watcher:OnEvent("ADDON_LOADED", "RXPGuides")
driver.path.settle()
equal(API.CurrentStop("RestedXP"), 1, "RestedXP's guide starts a journey")

-- After a cancel, resume hands the same guide back and says it did.
equal(API.Cancel("RestedXP"), true, "the guide's journey clears")
equal(API.CurrentStop("RestedXP"), nil, "nothing is followed")
equal(API.ResumeRestedXP(), true, "a guide is followed again")
equal(API.CurrentStop("RestedXP"), 1, "and it is the guide's journey")
driver.path.settle()

-- Combat cannot start guidance: the request is refused and starts nothing.
equal(API.Cancel("RestedXP"), true, "the guide's journey clears again")
combat = true
why("invalid", "resume in combat", API.ResumeRestedXP())
equal(API.CurrentStop("RestedXP"), nil, "combat starts nothing")
combat = false

-- Following RestedXP's guide off leaves nothing to resume.
ns.db.restedxp = false
why("unavailable", "following the guide is off", API.ResumeRestedXP())
ns.db.restedxp = true

-- An integrated frontend owns the guide; its own answer is the API's.
local integrated, accepted = true, true
env.AdventureGuideForever = {
	API = {
		RestedXPIntegrated = function()
			return integrated
		end,
		ResumeRestedXP = function()
			return accepted
		end,
	},
}
equal(API.ResumeRestedXP(), true, "the frontend accepts the request")
accepted = false
why("unavailable", "the frontend refuses", API.ResumeRestedXP())
accepted, integrated = true, false
watcher:OnEvent("ADDON_LOADED", "RXPGuides")
driver.path.settle()
equal(API.CurrentStop("RestedXP"), 1, "the native guide follows again")
env.AdventureGuideForever = nil

-- Before the saved variables load there is nothing to act on.
local db = ns.db
ns.db = nil
why("unavailable", "saved variables are not loaded", API.ResumeRestedXP())
ns.db = db

print(("api_resume_restedxp_spec: ok (%d checks)"):format(checks))

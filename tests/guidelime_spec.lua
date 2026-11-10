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
-- Guidelime publishes no current-step callback (6.017), so the addon follows its arrow on a ticker.
local tick, cancels = nil, 0
env.C_Timer = {
	NewTicker = function(_, callback)
		tick = callback
		return {
			Cancel = function()
				cancels = cancels + 1
				tick = nil
			end,
		}
	end,
}
ns.db.guidelime = true

-- Quest names the guide does not write into its code come from the client, as Guidelime's own step text does.
env.C_QuestLog = {
	GetTitleForQuestID = function(questID)
		return questID == 96394 and "The Restless Dead" or nil
	end,
}

-- Guidelime 6.017's public surface: the addon table, and the arrow frame it publishes as GuidelimeArrow. The
-- element is the current step's target, as the guide hands it to its arrow, in percent coordinates.
local alpha, mouse = 0.8, true
local arrow = {
	element = { t = "GOTO", mapID = 1, x = 60, y = 50, title = "Step 1", step = { text = "Go to the farm" } },
}
function arrow.GetAlpha()
	return alpha
end
function arrow.SetAlpha(_, value)
	alpha = value
end
function arrow.IsMouseEnabled()
	return mouse
end
function arrow.EnableMouse(_, value)
	mouse = value
end
env.Guidelime = { registerGuide = function() end }
env.GuidelimeArrow = arrow
-- The tracker's label for the step the guide plans, captured as the journey is handed its title, its quests and any
-- action line.
local label, quests, tooltip
local planned = API.NavigateRoute
API.NavigateRoute = function(owner, stops)
	if owner == "Guidelime" then
		label = stops[1].title
		quests, tooltip = stops[1].questIDs, stops[1].tooltip
	end
	return planned(owner, stops)
end
driver.load("Core/Guidelime.lua")
assert(API.CurrentStop("Guidelime") == 1, "Guidelime's current step starts a journey")
assert(label == "Step 1", "the arrow's own title names the step")
assert(alpha == 0 and not mouse, "Guidelime's arrow and its clicks step aside while ours draws")
assert(tick ~= nil, "the arrow is followed while Guidelime is installed")

-- A step with no parsed parts and no title of its own is named by the guide, never by its raw line.
arrow.element = { t = "GOTO", mapID = 1, x = 64, y = 45, step = { text = "|cff1eff00Accept|r |T123|t The Farmer" } }
tick()
assert(API.CurrentStop("Guidelime") == 1, "a step named only by its text is guided")
assert(label == "Guidelime", "a step with nothing parsed falls back to the guide's name")

-- The tracker names a step from the parts Guidelime parsed, not the raw line with its guide codes (#650).
arrow.element = {
	t = "GOTO",
	mapID = 1,
	x = 66,
	y = 44,
	step = {
		text = "[A Forever] Outside Hall Of Thanes at [TAR264943] [QA96394]",
		elements = {
			{ t = "APPLIES" },
			{ t = "TEXT", text = "Outside Hall Of Thanes at " },
			{ t = "TARGET", targetNpcId = 264943 },
			{ t = "ACCEPT", questId = 96394, title = "The Restless Dead" },
		},
	},
}
tick()
assert(API.CurrentStop("Guidelime") == 1, "the parsed step is guided")
assert(label == "Outside Hall Of Thanes at The Restless Dead", "the label reads the parsed words: " .. tostring(label))
assert(not label:find("[", 1, true) and not label:find("]", 1, true), "the label carries none of the guide's codes")
assert(quests and quests[1] == 96394 and #quests == 1, "the step names its quest for the live objectives")
assert(tooltip == "The Restless Dead (pick up)", "a pick-up step says what to do: " .. tostring(tooltip))

-- A quest the guide leaves unnamed takes the client's title for it, and a target keeps the name the guide gave.
arrow.element = {
	t = "GOTO",
	mapID = 1,
	x = 68,
	y = 42,
	step = {
		text = "Turn in [QT96394]",
		elements = {
			{ t = "TEXT", text = "Turn in " },
			{ t = "TURNIN", questId = 96394 },
		},
	},
}
tick()
assert(label == "Turn in The Restless Dead", "a quest without a title uses the client's: " .. tostring(label))
assert(quests and quests[1] == 96394, "the turn-in step names its quest too")
assert(tooltip == "The Restless Dead (turn in)", "and says to turn it in: " .. tostring(tooltip))
arrow.element = {
	t = "GOTO",
	mapID = 1,
	x = 70,
	y = 40,
	step = {
		text = "Talk to [TAR264943 Afadra Dunwall]",
		elements = {
			{ t = "TEXT", text = "Talk to " },
			{ t = "TARGET", targetNpcId = 264943, title = "Afadra Dunwall" },
		},
	},
}
tick()
assert(label == "Talk to Afadra Dunwall", "a target uses the name the guide gave: " .. tostring(label))
assert(quests == nil and tooltip == nil, "a step with no quest shows no objective lines")

-- A step that moves on at the same place (a turn-in at the NPC just left) updates the running stop's quests without
-- replanning the route.
arrow.element = {
	t = "GOTO",
	mapID = 1,
	x = 70,
	y = 40,
	title = "Turn in the dead",
	step = { elements = { { t = "TURNIN", questId = 96394, title = "The Restless Dead" } } },
}
tick()
assert(ns.JourneyGoal() and ns.JourneyGoal().questIDs[1] == 96394, "the stop stands for the first turn-in")
arrow.element = {
	t = "GOTO",
	mapID = 1,
	x = 70,
	y = 40,
	title = "Turn in the second",
	step = { elements = { { t = "TURNIN", questId = 96395, title = "The Second Dead" } } },
}
tick()
assert(ns.JourneyGoal().questIDs[1] == 96395, "the same place now stands for the next quest")
assert(ns.JourneyGoal().details[1] == "The Second Dead (turn in)", "with its own action line")
-- An impossible target clears the journey and brings the guide's arrow back.
arrow.element = { t = "GOTO", mapID = 1, x = 150, y = 50, title = "Outside the map" }
tick()
assert(not API.CurrentStop("Guidelime") and alpha == 0.8, "a target outside the map clears its journey")
arrow.element = { t = "GOTO", mapID = 1, x = 60, y = 50, title = "Step 1", step = { text = "Go to the farm" } }
tick()
assert(API.CurrentStop("Guidelime") == 1, "the guide's real step starts guidance again")

-- The guide advances: each new goto target replaces the journey, and nothing else replans it.
local navigations = 0
local navigate = API.NavigateRoute
API.NavigateRoute = function(...)
	navigations = navigations + 1
	return navigate(...)
end
navigations = 0
tick()
tick()
assert(navigations == 0, "an unchanged step plans nothing twice")
for step = 2, 4 do
	arrow.element = { t = "GOTO", mapID = 1, x = 50 + step, y = 40, title = "Step " .. step }
	tick()
	assert(API.CurrentStop("Guidelime") == 1, "step " .. step .. " is guided")
end
assert(navigations == 3, "each advanced step replans once")
local trackerVersion = ns.journeyVersion
local relabels = 0
local refreshTracker = ns.RefreshTracker
ns.RefreshTracker = function()
	relabels = relabels + 1
end
arrow.element.title = "Step 4 renamed"
tick()
assert(navigations == 3, "a renamed step at the same place plans nothing")
assert(relabels == 1 and ns.journeyVersion == trackerVersion, "a renamed step redraws the tracker, not the journey")
ns.RefreshTracker = refreshTracker

-- Combat defers the next step; the guide arrow comes back while the journey waits.
arrow.element = { t = "GOTO", mapID = 1, x = 70, y = 30, title = "Step 5" }
combat = true
tick()
assert(navigations == 3, "combat defers planning")
assert(alpha == 0.8 and mouse, "the guide arrow stays available while combat defers")
combat = false
watcher:OnEvent("PLAYER_REGEN_ENABLED")
driver.path.settle()
assert(navigations == 4 and API.CurrentStop("Guidelime") == 1, "combat end uses the latest step")

-- Our own arrow setting owns the takeover: with it off, Guidelime's arrow leads again.
ns.db.arrow = false
tick()
assert(API.CurrentStop("Guidelime") == 1 and alpha == 0.8 and mouse, "our arrow off leaves the guide's arrow shown")
ns.db.arrow = true
tick()
assert(alpha == 0 and not mouse, "our arrow on hides the guide's arrow again")

-- A completed step clears the journey and restores the arrow; the next step takes over again.
arrow.element.completed = true
tick()
assert(not API.CurrentStop("Guidelime") and alpha == 0.8, "a completed step clears its held journey")
arrow.element.completed = false
tick()
assert(API.CurrentStop("Guidelime") == 1 and alpha == 0, "the next step starts guidance again")

-- An unchanged step does not steal a journey the player or another guide started; a new step does.
API.Navigate("Other", 1, 0.6, 0.5, "Player destination")
tick()
assert(API.CurrentStop("Other") == 1, "an unchanged step leaves another journey alone")
assert(alpha == 0.8, "another owner restores the guide arrow")
arrow.element = { t = "GOTO", mapID = 1, x = 72, y = 32, title = "Step 6" }
tick()
assert(API.CurrentStop("Guidelime") == 1, "a new step plans over the player's journey, as RestedXP does")
assert(alpha == 0)
assert(ns.ResumeGuidelime ~= nil)

-- RestedXP's step leads when both guides are installed: Guidelime neither fights it nor draws its arrow.
assert(API.NavigateRoute("RestedXP", { { map = 1, x = 0.4, y = 0.4, title = "RestedXP step" } }))
arrow.element = { t = "GOTO", mapID = 1, x = 80, y = 20, title = "Step 7" }
tick()
assert(API.CurrentStop("RestedXP") == 1, "Guidelime leaves RestedXP's journey alone")
assert(alpha == 0 and not mouse, "our arrow leads, so Guidelime's steps aside too")
ns.db.arrow = false
tick()
assert(alpha == 0.8 and mouse, "with our arrow off, Guidelime's arrow returns while RestedXP leads")
ns.db.arrow = true
API.Cancel("RestedXP")
ns.ResumeGuidelime()
driver.path.settle()
assert(API.CurrentStop("Guidelime") == 1, "resume takes the current step back")

-- Turning the setting off cancels the journey, restores the arrow and stops the ticker.
local before = cancels
ns.db.guidelime = false
ns.RefreshGuidelime()
assert(not API.CurrentStop("Guidelime") and alpha == 0.8 and mouse, "disabling restores Guidelime's arrow")
assert(cancels == before + 1 and tick == nil, "disabling stops following the arrow")
ns.db.guidelime = true
ns.RefreshGuidelime()
driver.path.settle()
assert(tick ~= nil and API.CurrentStop("Guidelime") == 1, "enabling follows the current step again")

-- Journeys off also stop the follower; turning them back on starts it again.
ns.db.journey = false
ns.RefreshGuidelime()
assert(not API.CurrentStop("Guidelime") and tick == nil, "journeys off stop following")
ns.db.journey = true
ns.RefreshGuidelime()
driver.path.settle()
assert(tick ~= nil and API.CurrentStop("Guidelime") == 1, "journeys on follow again")

-- A missing or unloaded Guidelime leaves nothing behind.
env.GuidelimeArrow = nil
tick()
assert(not API.CurrentStop("Guidelime") and alpha == 0.8, "a guide with no arrow clears its journey")
env.Guidelime = nil
ns.RefreshGuidelime()
assert(tick == nil, "no Guidelime means no ticker")
env.Guidelime = { registerGuide = function() end }
env.GuidelimeArrow = arrow
watcher:OnEvent("ADDON_LOADED", "Guidelime")
driver.path.settle()
assert(API.CurrentStop("Guidelime") == 1, "a late-loaded Guidelime starts following")

print("guidelime: ok")

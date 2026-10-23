-- /path report (UI/Report.lua, Core/Report.lua, Core/SafeCall.lua; the pattern is cjber/adventure-guide-forever
-- docs/report-window.md): one selected block of text with the versions, character, place, the journey and its plan,
-- the ride and its trace, the caught errors and the other addons, never longer than one message.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end
local function has(text, part, label)
	checks = checks + 1
	if not text:find(part, 1, true) then
		error(("%s: %q not in\n%s"):format(label, part, text), 2)
	end
end
local function lacks(text, part, label)
	checks = checks + 1
	if text:find(part, 1, true) then
		error(("%s: %q in\n%s"):format(label, part, text), 2)
	end
end

-- The report window's frames: what the window and its edit box need, with keyboard focus and selection.
local focus, made = nil, 0
local function Widget(kind, name, parent)
	local widget = { kind = kind, name = name, parent = parent, scripts = {}, shown = true, text = "" }
	local methods = {}
	function methods:SetScript(script, fn)
		self.scripts[script] = fn
	end
	function methods:GetParent()
		return self.parent
	end
	function methods:GetObjectType()
		return self.kind
	end
	function methods:Show()
		self.shown = true
	end
	function methods:Hide()
		self.shown = false
	end
	function methods:IsShown()
		return self.shown
	end
	function methods:SetText(text)
		self.text = text
		self.highlighted = nil
	end
	function methods:GetText()
		return self.text
	end
	function methods:SetTitle(title)
		self.title = title
	end
	function methods:SetFocus()
		focus = self
	end
	-- The client's EditBox:HighlightText([start, stop]) errors on a range outside its integer bounds; an
	-- OnEditFocusGained handler is called as handler(self, isUserInput), so handing SetScript the method itself
	-- lands the boolean in `start` (UI/Report.lua:224, #269).
	function methods:HighlightText(start, stop)
		for _, value in ipairs({ start, stop }) do
			if type(value) ~= "number" or value ~= value or value < -2147483648 or value > 2147483647 then
				error(
					"bad argument #2 to '?' (outside of expected range -2147483648 to 2147483647"
						.. " - Usage: self:HighlightText([start, stop]))",
					2
				)
			end
		end
		self.highlighted = self.text
		self.highlightCalls = (self.highlightCalls or 0) + 1
	end
	function methods:GetPortrait()
		self.portrait = self.portrait or Widget("Texture", nil, self)
		return self.portrait
	end
	function methods:CreateFontString()
		return Widget("FontString", nil, self)
	end
	function methods:SetScrollChild(child)
		self.child = child
	end
	return setmetatable(widget, {
		__index = function(_, key)
			return methods[key] or (key:match("^%u") and function() end) or nil
		end,
	})
end
local driverFrame = env.CreateFrame
env.UISpecialFrames = {}
local editBoxes = {}
env.CreateFrame = function(kind, name, parent, template)
	if
		name ~= "ShortestPathForeverReport"
		and name ~= "ShortestPathForeverIssue"
		and not (parent and parent.report)
	then
		return driverFrame(kind, name, parent, template)
	end
	made = made + 1
	local widget = Widget(kind, name, parent)
	widget.report, widget.template = true, template
	if kind == "EditBox" then
		editBoxes[#editBoxes + 1] = widget
	end
	if name then
		env[name] = widget
	end
	return widget
end
local metadata = {
	ShortestPathForever = { Version = "1.16.0", ["X-Website"] = "https://github.com/cjber/shortest-path-forever/" },
	TomTom = { Version = "4.3.12" },
	Questie = {},
}
local function AddonList()
	local names = {}
	for name in pairs(metadata) do
		if name ~= "ShortestPathForever" then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	table.insert(names, 1, "ShortestPathForever")
	return names
end
env.C_AddOns = {
	GetAddOnMetadata = function(name, field)
		return metadata[name] and metadata[name][field]
	end,
	GetNumAddOns = function()
		return #AddonList()
	end,
	GetAddOnInfo = function(index)
		return AddonList()[index]
	end,
	IsAddOnLoaded = function(index)
		return AddonList()[index] ~= nil
	end,
}
env.GetBuildInfo = function()
	return "1.60.1", "70374", "Oct 1 2026", 16001
end
env.GetLocale = function()
	return "enUS"
end
env.UnitClass = function()
	return "Mage", "MAGE"
end
env.UnitRace = function()
	return "Gnome", "Gnome"
end
env.UnitLevel = function()
	return 24
end
env.C_Map.GetPlayerMapPosition = function()
	return env.CreateVector2D(0.421, 0.653)
end
env.C_Map.GetMapInfo = function(uiMap)
	return { mapType = uiMap == 10 and 2 or 3, name = "Elwynn Forest" }
end
local errors = {}
env.geterrorhandler = function()
	return function(message)
		errors[#errors + 1] = message
	end
end
ns.CurrentRide, ns.IsObservingRide = function() end, function() end
ns.charDB.bind = { name = "Goldshire", map = 1, x = 0, y = 0 }

driver.load("UI/Looks.lua")
driver.load("Core/API.lua")
driver.load("Journey/Itinerary.lua")
driver.load("Core/SafeCall.lua")
driver.load("UI/Art.lua")
driver.load("UI/Report.lua")
driver.load("Core/Report.lua")
local API = env.ShortestPathForever.API

equal(ns.Report.Encode("a b&#é~"), "a%20b%26%23%C3%A9~", "URL encoding")
equal(ns.Report.Repo(), "cjber/shortest-path-forever", "repo from X-Website")
metadata.ShortestPathForever["X-Website"] = nil
equal(ns.Report.Repo(), "", "missing X-Website")
metadata.ShortestPathForever["X-Website"] = "https://github.com/cjber/shortest-path-forever/"
local issue = ns.Report.Issue("bug", "Bug: one & two", "details", { "system line" })
has(issue, "template=report.md", "issue template")
has(issue, "labels=bug", "bug label")
has(issue, "title=Bug%3A%20one%20%26%20two", "encoded title")
has(
	ns.Report.Body("bug", "Bug: one", "details", { "system line" }),
	"### System information",
	"markdown system section"
)
equal(#ns.Report.Issue("bug", "Bug: long", ("x"):rep(4000), { "system line" }) < 7000, true, "long detail URL cap")
local previousBugGrabber = _G.BugGrabber
_G.BugGrabber = {
	GetDB = function()
		return {
			{ message = "stale session error", stack = "Old.lua:4", session = 6, counter = 8 },
			{ message = "direct Lua failure", stack = "Addon/Feature.lua:42", session = 7, counter = 2 },
		}
	end,
	GetSessionId = function()
		return 7
	end,
}
local issueBody = ns.Report.Body("bug", "Bug: direct Lua failure", "it broke", {})
has(issueBody, "direct Lua failure", "BugGrabber runtime error in issue body")
has(issueBody, "Addon/Feature.lua:42", "BugGrabber trace in issue body")
lacks(issueBody, "stale session error", "old BugGrabber errors are excluded")
_G.BugGrabber = previousBugGrabber

local function Report()
	local ok, lines = ns.SafeCall("report lines", ns.ReportLines)
	ns.Report.Show(ns.Report.Text(ok and lines or { "Report lines failed: " .. tostring(lines) }))
	local window = env.ShortestPathForeverReport
	return focus:GetText(), window, focus
end

-- No journey: the header, the settings and what is known.
ns.db.teleports, ns.db.tomtom = true, true
local text, window, edit = Report()
has(text, "ShortestPathForever 1.16.0 | WoW 1.60.1 (70374) 16001 | enUS", "versions, build and locale")
has(text, "Character: level 24 Gnome MAGE, Alliance", "character, no name")
has(text, "Place: map 1 (Elwynn Forest) 42.1, 65.3", "place")
has(text, "Settings: journeys on, teleports on (hearth saving 0s), other faction off, TomTom on/follow off", "settings")
has(text, "Bind point: Goldshire, map 1 50.0, 50.0", "the bind point")
has(text, "Journey: none", "no journey")
has(text, "Ride: none", "no ride")
has(text, "Ride trace: off (/path debug keeps one)", "no trace")
has(text, "Errors: none caught", "no errors")
has(text, "Other addons (2): Questie, TomTom 4.3.12", "the other addons")
equal(edit.highlighted, text, "all of it selected")
equal(window.template, "PortraitFrameTemplate", "a stock portrait frame")
equal(window.title, "Shortest Path report", "its title")
equal(window:IsShown(), true, "shown")

-- Read-only, Escape, one window.
edit.text, edit.highlighted = "typed", nil
edit.scripts.OnTextChanged(edit, true)
equal(edit:GetText(), text, "typing restores the report")
equal(edit.highlighted, text, "selected again")
edit.scripts.OnEscapePressed(edit)
equal(window:IsShown(), false, "Escape hides it")
local special = false
for _, name in ipairs(env.UISpecialFrames) do
	special = special or name == "ShortestPathForeverReport"
end
equal(special, true, "Escape closes it without the box's focus too")
local before = made
Report()
equal(made, before, "the window is made once")
equal(window:IsShown(), true, "shown again")

-- Focusing the read-only report box selects the whole text the way the client calls the handler: handler(self,
-- isUserInput). Handing SetScript the HighlightText method itself used to raise
-- "bad argument #2 to '?' (outside of expected range ... Usage: self:HighlightText([start, stop]))" (#269).
edit.highlighted, edit.highlightCalls = nil, 0
equal(type(edit.scripts.OnEditFocusGained), "function", "the report box gains focus through a script")
edit.scripts.OnEditFocusGained(edit, true)
equal(edit.highlighted, text, "focus selects the whole report")
equal(edit.highlightCalls, 1, "HighlightText ran once, in range")

-- The issue composer's read-only address box gains focus the same way.
ns.Report.Compose("bug")
local composer = env.ShortestPathForeverIssue
equal(composer ~= nil and composer:IsShown(), true, "the composer opens")
local composerBox = editBoxes[#editBoxes]
composerBox.highlighted, composerBox.highlightCalls = nil, 0
equal(type(composerBox.scripts.OnEditFocusGained), "function", "the address box gains focus through a script")
composerBox.scripts.OnEditFocusGained(composerBox, true)
equal(composerBox.highlighted, composerBox:GetText(), "focus selects the whole address")
equal(composerBox.highlightCalls, 1, "HighlightText ran once, in range")

-- A journey the player planned: its goal, search and every step, the current one marked.
driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 2000, y = 0 })
text = Report()
has(text, "Journey: ", "a journey")
has(text, "owner player, guided on", "the player's own, guided")
has(text, "Goal: map 1 ", "its goal on the map")
has(text, "Search: settled", "the search")
has(text, "> 1. walk to ", "the current step")

-- An addon's route: its owner and stop.
API.NavigateRoute("AGF", { { map = 1, x = 0.502, y = 0.5, title = "First" }, { map = 1, x = 0.504, y = 0.5 } })
driver.update(0.1)
text = Report()
has(text, "owner AGF, stop 1 of 2", "the owner and stop")
ns.ClearJourney()

-- /path debug keeps the ride trace: the last five samples.
ns.db.debug, ns.db.trace = true, {}
for index = 1, 7 do
	ns.db.trace[index] = { 1000 + index, 0, index * 10, 5, 2, 7, index == 7 and "3:12/14*" or "" }
end
-- Then off the boat, on the dock: samples with no ride.
ns.db.trace[8] = { 1008, 0, 80, 5, 2, 0, "" }
ns.db.trace[9] = { 1009, 0, 80, 5, 2, 0, "" }
ns.CurrentRide = function()
	return 3
end
text = Report()
has(text, "Ride: route 3", "the ride")
has(text, "Ride trace (3 to 7 of 9):", "the trace up to the last sample aboard")
has(text, "  1007 0 70.0, 5.0, 2.0 at 7 3:12/14*", "the newest sample, with its fits")
lacks(text, "  1002 ", "older samples left out")
lacks(text, "  1009 ", "dock samples after the ride left out")
ns.db.debug, ns.db.trace = nil, nil

-- Each step's own time with its wait apart, as the tracker shows them; the trace comes before the steps, so a long
-- plan is what the cap cuts; a corpse run shows its walk, and the journey that waits behind it.
do
	local plan, journeyPlan, journeyGoal =
		{
			legs = {
				{ mode = "walk", depart = 0, arrive = 60000, to = { label = "Ratchet dock" } },
				{ mode = "boat", depart = 360000, arrive = 480000, wait = 300000, to = { label = "Booty Bay" } },
			},
		}, ns.JourneyPlan, ns.JourneyGoal
	ns.JourneyPlan = function()
		return plan, 2
	end
	ns.JourneyGoal = function()
		return { map = 1, x = 0, y = 0, label = "Booty Bay" }
	end
	ns.db.debug, ns.db.trace = true, { { 1, 0, 1, 2, 3, 7, "" } }
	local status = ns.JourneyStatus
	ns.JourneyStatus = function()
		return false, 2, "offmesh"
	end
	ns.Corpse = {
		Info = function()
			local leg = { mode = "walk", depart = 0, arrive = 0, walkError = "offmesh", to = { label = "Your corpse" } }
			return "Corpse run", {}, { legs = { leg } }, 1
		end,
	}
	text = Report()
	has(text, "  1. walk to Ratchet dock, 60s\n", "a walk's time")
	has(text, "> 2. boat to Booty Bay, 120s, waits 300s", "a boat's own time, its wait apart, under way")
	equal(text:find("Ride trace", 1, true) < text:find("1. walk to Ratchet", 1, true), true, "the trace first")
	has(text, "Corpse run: the journey waits behind it", "the corpse run before the journey")
	has(text, "1. walk to Your corpse, 0s, walk failed: offmesh", "its walk and why it failed")
	has(text, "Search: settled, 2 settle rounds, walk failed: offmesh", "why the search found no walk")
	ns.JourneyStatus = status
	ns.JourneyPlan, ns.JourneyGoal, ns.Corpse, ns.db.debug, ns.db.trace = journeyPlan, journeyGoal, nil, nil, nil
end

-- SafeCall: pcall's answers, failures kept and forwarded.
local ok, a, b, c = ns.SafeCall("test", function(x)
	return x, nil, 3
end, 1)
equal(ok and a == 1 and b == nil and c == 3, true, "SafeCall: pcall's answers, nils kept")
local failed, message = ns.SafeCall("test", error, "boom", 0)
equal(failed == false and message == "boom", true, "SafeCall: the failure")
equal(errors[#errors], "boom", "SafeCall: passed to the error handler")
ns.SafeCall("test", error, "boom", 0)
local caught = ns.CaughtErrors()
equal(#caught == 1 and caught[1].count == 2 and caught[1].label == "test", true, "SafeCall: a repeat is counted")
for index = 1, 6 do
	ns.SafeCall("many", error, "error " .. index, 0)
end
caught = ns.CaughtErrors()
equal(#caught == 5 and caught[5].message == "error 6" and caught[1].message == "error 2", true, "SafeCall: last five")
caught[1].message = "changed"
equal(ns.CaughtErrors()[1].message, "error 2", "SafeCall: copies")
ns.SafeCall("outer", function()
	ns.SafeCall("inner", error, "inner failed", 0)
end)
equal(ns.CaughtErrors()[5].label, "inner", "SafeCall: the inner label")
text = Report()
has(text, "Errors (5):", "report: the caught errors")
has(text, "- [inner] x1 inner failed", "report: newest first")

-- The lines failing still open the report with the header and the error.
local lines = ns.ReportLines
ns.ReportLines = function()
	error("lines broke", 0)
end
text = Report()
has(text, "ShortestPathForever 1.16.0", "lines failed: the header")
has(text, "Report lines failed: lines broke", "lines failed: said")
has(text, "- [report lines] x1 lines broke", "lines failed: caught")
ns.ReportLines = lines

-- Many addons: counted, cut to one message.
for index = 1, 300 do
	metadata[("SomeAddon%03d"):format(index)] = { Version = "1.0." .. index }
end
text = Report()
equal(#text <= 2000, true, "one message")
has(text, "Other addons (302): ", "all counted")
has(text, " more", "the rest counted")
lacks(text, "SomeAddon300", "the last left out")

print(("report_spec: %d checks passed"):format(checks))

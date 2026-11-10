-- A stop that names its quests shows their live objectives under the arrow and the arrival pin (#660): done ones
-- marked as the tracker marks them, a finished quest reading as ready to turn in, and a caller's own details winning.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env = driver.ns, driver.env

env.OBJECTIVE_TRACKER_COLOR = { Complete = { r = 0.5, g = 0.95, b = 0.4 } }
env.CreateColor = function(r, g, b)
	return {
		WrapTextInColorCode = function(_, text)
			return string.format("<%.2f,%.2f,%.2f>%s</>", r, g, b, text)
		end,
	}
end
env.QUEST_WATCH_QUEST_READY = "Ready for turn-in"
local complete = { [101] = true }
local objectives = {
	[100] = {
		{ text = "Slay 6 boars: 2/6", finished = false },
		{ text = "Collect 4 tusks: 4/4", finished = true },
	},
	[101] = {
		{ text = "Slay 6 boars: 6/6", finished = true },
		{ text = "Collect 4 tusks: 4/4", finished = true },
	},
}
env.C_QuestLog = {
	GetQuestObjectives = function(questID)
		return objectives[questID]
	end,
	IsComplete = function(questID)
		return complete[questID] == true
	end,
}

local lines = assert(ns.StopObjectiveLines({ questIDs = { 100 } }), "a quest in the log has live lines")
assert(lines[1] == "Slay 6 boars: 2/6", "an unfinished objective reads as the client reports it")
assert(
	lines[2] == "<0.50,0.95,0.40>Collect 4 tusks: 4/4</>",
	"a finished one is marked in the tracker's completed colour"
)
assert(not lines[3], "a quest short of done has no ready line")

local ready = assert(ns.StopObjectiveLines({ questID = 101 }), "a lone questID works too")
assert(ready[1] == "Ready for turn-in", "a quest with nothing left to do reads as ready to turn in")
assert(ready[2] == "<0.50,0.95,0.40>Slay 6 boars: 6/6</>", "its done objectives stay marked under it")

-- The caller's own details win, as Adventure Guide's tooltip does.
local explicit = ns.StopObjectiveLines({ details = { "Slay 6 boars", "Return to camp" }, questIDs = { 100 } })
assert(explicit[1] == "Slay 6 boars" and explicit[2] == "Return to camp", "explicit details win over the quest log")
assert(#explicit == 2, "and the quest's objectives are not appended")

-- A quest the client has no objectives for contributes nothing, and a stop with no quests has no lines to reserve.
assert(ns.StopObjectiveLines({ questIDs = { 999 } }) == nil, "a quest outside the log adds no stale line")
assert(ns.StopObjectiveLines({ label = "A place" }) == nil, "a stop with no quests has no lines")
assert(ns.StopObjectiveLines(nil) == nil, "no stop, no lines")

-- The lines follow the quest log: the next read reports the new progress, never a copy.
objectives[100] = {
	{ text = "Slay 6 boars: 6/6", finished = true },
	{ text = "Collect 4 tusks: 4/4", finished = true },
}
complete[100] = true
local fresh = assert(ns.StopObjectiveLines({ questIDs = { 100 } }))
assert(fresh[1] == "Ready for turn-in", "a quest that finished since the last read says so")

-- Travel: the lines stand under the arrow's distance, before the stop is reached, and repaint on a quest update.
local create, created = env.CreateFrame, {}
local function track(object)
	object.GetText = function(self)
		return self.text
	end
	object.SetText = function(self, text)
		self.text = text
	end
	object.Show = function(self)
		self.hidden = false
	end
	object.Hide = function(self)
		self.hidden = true
	end
	object.SetShown = function(self, shown)
		if shown then
			self:Show()
		else
			self:Hide()
		end
	end
	object.SetAtlas = function(self, atlas)
		self.atlas = atlas
	end
	object.SetTexture = function(self, file)
		self.texture, self.atlas = file, nil
	end
	object.SetTexCoord = function() end
	object.SetSize = function(self, width, height)
		self.width, self.height = width, height
	end
	object.SetPoint = function(self, ...)
		self.point = { ... }
	end
	object.SetWordWrap = function(self, wrap)
		self.wrap = wrap
	end
	object.SetMaxLines = function(self, count)
		self.maxLines = count
	end
	object.SetJustifyH = function(self, justify)
		self.justify = justify
	end
	object.SetColorTexture = function(self, ...)
		self.color = { ... }
	end
	object.SetAlpha = function(self, alpha)
		self.alpha = alpha
	end
	object.GetEffectiveScale = function()
		return 1
	end
	object.SetScale = function(self, scale)
		self.scale = scale
	end
	return object
end
env.CreateFrame = function(...)
	local frame = track(create(...))
	created[#created + 1] = frame
	local texture, font = frame.CreateTexture, frame.CreateFontString
	frame.CreateTexture = function(self, ...)
		return track(texture(self, ...))
	end
	frame.CreateFontString = function(self, ...)
		return track(font(self, ...))
	end
	local show, hide = frame.Show, frame.Hide
	frame.Show = function(self)
		local wasHidden = self.hidden
		show(self)
		if wasHidden and self.OnShow then
			self.OnShow(self)
		end
	end
	frame.Hide = function(self)
		local wasShown = not self.hidden
		hide(self)
		if wasShown and self.OnHide then
			self.OnHide(self)
		end
	end
	return frame
end
env.C_Timer = {
	NewTicker = function(_, callback)
		local ticker = { callback = callback }
		function ticker:Cancel()
			self.cancelled = true
		end
		return ticker
	end,
	After = function(_, callback)
		callback()
	end,
}
for _, file in ipairs({ "UI/Art.lua", "UI/Mover.lua", "UI/TurnAround.lua", "UI/Arrow.lua" }) do
	driver.load(file)
end
ns.db.arrow, ns.db.arrivalPin = true, true

local function arrowFrame()
	for _, frame in ipairs(created) do
		if frame.Lines then
			return frame
		end
	end
end

objectives[102] = {
	{ text = "Speak to Afadra: 0/1", finished = false },
	{ text = "Slay 6 boars: 6/6", finished = true },
}
complete[102] = false
objectives[103] = {
	{ text = "Read the letter", finished = true },
}
complete[103] = true
local travelling = { map = 1, x = 0, y = 0, label = "The Camp", questIDs = { 102, 103 } }
driver.move({ map = 1, x = 1000, y = 0, z = 0 })
assert(ns.StartJourney(travelling))
driver.path.settle()
driver.update(0.1)
local frame = assert(arrowFrame(), "the journey's arrow is built")
assert(not frame.hidden and not frame.arrival, "the arrow leads while the stop is ahead")
assert(
	frame.Lines.text == "Speak to Afadra: 0/1\n<0.50,0.95,0.40>Slay 6 boars: 6/6</>\nReady for turn-in",
	"the same lines stand under the distance: " .. tostring(frame.Lines.text)
)
assert(frame.Lines.maxLines == 3 and frame.Lines.wrap == true, "capped and wrapped like the pin's")

-- A quest update repaints the lines before the next stop; nothing is replanned and nothing is rebuilt per frame.
objectives[102] = {
	{ text = "Speak to Afadra: 1/1", finished = true },
	{ text = "Slay 6 boars: 6/6", finished = true },
}
complete[102] = true
driver.fire("QUEST_LOG_UPDATE")
assert(
	frame.Lines.text
		== "Ready for turn-in\n<0.50,0.95,0.40>Speak to Afadra: 1/1</>\n<0.50,0.95,0.40>Slay 6 boars: 6/6</>",
	"the quest log event repaints the travel lines: " .. tostring(frame.Lines.text)
)

-- No quests, no reserved height: the lines go away rather than leaving a gap under the distance.
assert(ns.StartJourney({ map = 1, x = 500, y = 0, label = "Nowhere" }))
driver.path.settle()
driver.update(0.1)
assert(frame.Lines.hidden, "a stop with no quests keeps the arrow short")

-- Arrival: the pin reads the live quest log too, and a late quest update reaches it.
local held = { map = 1, x = 0, y = 0, hold = true, radius = 50, label = "The Camp", questIDs = { 102 } }
assert(ns.StartJourney(held))
driver.path.settle()
driver.move({ map = 1, x = 0, y = 0, z = 0 })
driver.update(0.1)
assert(ns.ArrivalStop() == held, "standing in the stop's area shows the pin")
assert(
	frame.ArrivalLines.text
		== "Ready for turn-in\n<0.50,0.95,0.40>Speak to Afadra: 1/1</>\n<0.50,0.95,0.40>Slay 6 boars: 6/6</>",
	"the pin names the live ready state and its marked objectives: " .. tostring(frame.ArrivalLines.text)
)
objectives[102] = {
	{ text = "Report to the camp: 1/1", finished = true },
	{ text = "Slay 6 boars: 6/6", finished = true },
}
driver.fire("UNIT_QUEST_LOG_CHANGED", "player")
assert(
	frame.ArrivalLines.text
		== "Ready for turn-in\n<0.50,0.95,0.40>Report to the camp: 1/1</>\n<0.50,0.95,0.40>Slay 6 boars: 6/6</>",
	"the pin follows the log while it stands: " .. tostring(frame.ArrivalLines.text)
)

print("objective_lines_spec: live objective lines, done marks, ready state, travel and pin")

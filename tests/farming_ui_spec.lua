-- Native templates are represented by stateful client stubs, not a client capture.
-- The real shared Core art module is loaded through the same Core harness as other specs.
local frames, timers, tickers = {}, {}, {}
local function region()
	local r = { points = {} }
	function r:SetPoint(...)
		self.points[#self.points + 1] = { ... }
	end
	function r:ClearAllPoints()
		self.points = {}
	end
	function r:SetText(value)
		self.text = value
	end
	function r:GetText()
		return self.text
	end
	function r:SetSize(w, h)
		self.width, self.height = w, h
	end
	function r:SetTexCoord(...)
		self.coords = { ... }
	end
	function r:SetTexture(value)
		self.texture = value
	end
	function r.SetJustifyH() end
	return r
end
local function frame(kind, name, parent, template)
	local f = region()
	f.kind, f.name, f.parent, f.template = kind, name, parent, template
	f.scripts, f.children, f.shown, f.enabled = {}, {}, true, true
	function f:SetScript(event, fn)
		self.scripts[event] = fn
	end
	function f:SetHeight(h)
		self.height = h
	end
	function f:SetWidth(w)
		self.width = w
	end
	function f:SetEnabled(enabled)
		self.enabled = enabled
	end
	function f:SetChecked(checked)
		self.checked = checked
	end
	function f:GetChecked()
		return self.checked
	end
	function f:SetScrollChild(child)
		self.child = child
	end
	function f:SetVerticalScroll(offset)
		self.offset = offset
	end
	function f:GetVerticalScroll()
		return self.offset or 0
	end
	function f:SetTitle(title)
		self.title = title
	end
	function f:GetPortrait()
		self.portrait = self.portrait or region()
		return self.portrait
	end
	function f:SetFrameStrata(value)
		self.strata = value
	end
	function f.SetClampedToScreen() end
	function f:IsShown()
		return self.shown and (not self.parent or not self.parent.IsShown or self.parent:IsShown())
	end
	function f:Show()
		local changed = not self.shown
		self.shown = true
		if changed and self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
	end
	function f:Hide()
		local changed = self.shown
		self.shown = false
		if changed and self.scripts.OnHide then
			self.scripts.OnHide(self)
		end
	end
	function f:Click()
		if not self.enabled or not self:IsShown() then
			return
		end
		if self.kind == "CheckButton" then
			self.checked = not self.checked
		end
		self.scripts.OnClick(self)
	end
	function f:CreateFontString()
		local text = region()
		self.children[#self.children + 1] = text
		return text
	end
	frames[#frames + 1] = f
	return f
end
local env = setmetatable({
	CreateFrame = frame,
	UIParent = {},
	UISpecialFrames = {},
	C_Timer = {
		After = function(_, callback)
			timers[#timers + 1] = callback
		end,
		NewTicker = function(_, callback)
			local ticker = { callback = callback }
			function ticker:Cancel()
				self.cancelled = true
			end
			tickers[#tickers + 1] = ticker
			return ticker
		end,
	},
	InCombatLockdown = function()
		return false
	end,
}, { __index = _G })
local core = dofile("tests/forever_core.lua")
local shared = core.load(env, "ForeverCore", { "UI/Art.lua" })
local state, failure, nextNode, cycles = "idle", nil, 1, 0
local starts, stops, snapshots, jobs = {}, 0, {}, {}
local combat = false
env.InCombatLockdown = function()
	return combat
end
local sourceState, startFailure, world = "ready", nil, { map = 1, x = 10, y = 20 }
local herb = {
	{ nodeID = 1, title = "Peacebloom", uiMapID = 10, x = 0.1, y = 0.2 },
	{ nodeID = 2, title = "Silverleaf", uiMapID = 10, x = 0.2, y = 0.3 },
	{ nodeID = 1, title = "Peacebloom", uiMapID = 10, x = 0.3, y = 0.4 },
}
local mining = { { nodeID = 3, title = "Copper", uiMapID = 10, x = 0.4, y = 0.5 } }
local controller = {}
function controller.Status(_)
	return state, failure, nextNode, cycles
end
function controller.Start(_, nodes)
	starts[#starts + 1] = nodes
	if startFailure then
		return false, startFailure
	end
	state, failure = "running", nil
	return true
end
function controller.Pause(_)
	state = "paused"
	return true
end
function controller.Resume(_)
	state = "running"
	return true
end
function controller.Stop(_)
	stops = stops + 1
	state, failure = "stopped", nil
end
local ns = {
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	Art = shared.Art,
	Farming = {
		new = function()
			return controller
		end,
	},
	GatherMate = {
		CurrentZone = function(kind, selected)
			snapshots[#snapshots + 1] = { kind = kind, selected = selected }
			if sourceState ~= "ready" then
				return nil, sourceState
			end
			local result = {}
			for _, node in ipairs(kind == "Mining" and mining or herb) do
				if selected == nil or selected[node.nodeID] then
					result[#result + 1] = node
				end
			end
			return result, #result > 0 and "ready" or "empty"
		end,
	},
	FarmingOrder = {
		Player = function()
			return world and { map = world.map, x = world.x, y = world.y }
		end,
		Begin = function(nodes, point)
			assert(
				point.map == 1 and point.x == 10 and point.y == 20 and point.z == nil,
				"world point without UI fractions or height"
			)
			local job = { nodes = nodes, steps = 0 }
			function job:Step()
				self.steps = self.steps + 1
				if self.steps == 1 then
					return "working"
				end
				return "ready", self.nodes
			end
			function job:Cancel()
				self.cancelled = true
			end
			jobs[#jobs + 1] = job
			return job
		end,
	},
}
local chunk = assert(loadfile("UI/Farming.lua"))
setfenv(chunk, env)
chunk("ShortestPathForever", ns)
local function find(text)
	for _, f in ipairs(frames) do
		if f.text == text then
			return f
		end
	end
	error("Missing control " .. text)
end
local function flushFrame()
	local pending = timers
	timers = {}
	for _, callback in ipairs(pending) do
		callback()
	end
end
local function status()
	for _, f in ipairs(frames) do
		if f.name == "ShortestPathForeverFarming" then
			for _, text in ipairs(f.children) do
				if text.text and (text.text:find("Ready to start", 1, true) or text.points[1][3] == -400) then
					return text
				end
			end
		end
	end
end
ns.OpenFarming()
local window, scroll
for _, f in ipairs(frames) do
	if f.name == "ShortestPathForeverFarming" then
		window = f
	end
	if f.kind == "ScrollFrame" then
		scroll = f
	end
end
assert(window.template == "PortraitFrameTemplate" and window.height == 520)
assert(window.portrait.texture:find("ShortestPathForever", 1, true))
assert(#env.UISpecialFrames == 1)
assert(snapshots[1].selected == nil and #frames > 8)
assert(not find("Herbs").enabled and find("Mining").enabled)
local checks = {}
for _, f in ipairs(frames) do
	if f.kind == "CheckButton" then
		checks[#checks + 1] = f
	end
end
assert(#checks == 2 and checks[1].Label.text == "Peacebloom", "one checkbox per type, not per coordinate")
checks[1]:Click()
find("Start"):Click()
assert(#jobs == 1 and #jobs[1].nodes == 1 and #starts == 0, "explicit selected IDs")
flushFrame()
assert(#starts == 0 and jobs[1].steps == 1, "one step per later frame")
find("Stop"):Click()
assert(jobs[1].cancelled and stops == 1)
flushFrame()
assert(#starts == 0, "stopped ordering never starts")
find("All"):Click()
find("Start"):Click()
assert(#jobs[2].nodes == 3, "all historical locations retained")
assert(not find("Mining").enabled and not checks[1].enabled)
window:Hide()
assert(jobs[2].cancelled and tickers[#tickers].cancelled)
window:Show()
flushFrame()
assert(#starts == 0, "closed order never starts after reopening")
find("None"):Click()
find("Start"):Click()
assert(#jobs == 2 and snapshots[#snapshots].selected ~= nil, "empty selection is not all")
assert(status().text:find("No recorded locations", 1, true))
find("All"):Click()
find("Start"):Click()
flushFrame()
flushFrame()
assert(#starts == 1 and #starts[1] == 3 and state == "running")
find("Pause"):Click()
assert(state == "paused" and find("Resume").enabled)
find("Resume"):Click()
assert(state == "running")
nextNode, cycles = 2, 4
tickers[#tickers].callback()
assert(status().text:find("Next location: 2. Completed circuits: 4.", 1, true))
state, failure = "stopped", "unreachable"
tickers[#tickers].callback()
assert(#starts == 1 and status().text:find("could not be reached", 1, true), "terminal failures never auto restart")
-- A real overflowing list establishes the scroll offset before switching to a short choice.
for id = 4, 24 do
	herb[#herb + 1] = { nodeID = id, title = "Herb " .. id, uiMapID = 10, x = 0.5, y = 0.5 }
end
find("Mining"):Click()
find("Herbs"):Click()
assert(scroll.child.height >= 23 * 28)
local listHeight = scroll.child.height
scroll:SetVerticalScroll(90)
local height = window.height
find("Mining"):Click()
assert(window.height == height and scroll:GetVerticalScroll() == 90 and scroll.child.height == listHeight)
assert(checks[1].Label.text == "Copper" and not checks[2].shown)
sourceState = "absent"
find("Herbs"):Click()
assert(status().text == "Farming needs the GatherMate2 addon.")
sourceState = "invalid-zone"
find("Mining"):Click()
assert(status().text == "Your current zone is unavailable.")
sourceState = "ready"
find("Herbs"):Click()
world = nil
find("Start"):Click()
assert(status().text == "Your position is unavailable")
world = { map = 1, x = 10, y = 20 }
combat = true
find("Start"):Click()
local pending = jobs[#jobs]
flushFrame()
assert(pending.steps == 0 and status().text == "Waiting for combat to end.")
combat = false
find("Stop"):Click()
flushFrame()
assert(pending.steps == 0 and pending.cancelled)
startFailure = "occupied"
find("Start"):Click()
flushFrame()
flushFrame()
assert(status().text == "Stop your current journey before starting a farming tour.")
-- Lifecycle failures must remain readable and must never trigger an implicit restart.
for _, reason in ipairs({
	"unverified-arrival",
	"ownership-lost",
	"non-walking-plan",
	"nodata",
	"outside",
	"unreachable",
	"error",
	"navigation-error",
	"submission-failed",
	"invalid-input",
	"invalid-world",
	"too-few-locations",
}) do
	state, failure = "stopped", reason
	local before = #starts
	tickers[#tickers].callback()
	assert(not status().text:find(reason, 1, true), "raw reason exposed: " .. reason)
	assert(#starts == before)
end
local count = #frames
ns.OpenFarming()
assert(#frames == count and #env.UISpecialFrames == 1, "reuse window and controller")
window:Hide()
assert(tickers[#tickers].cancelled)
print("farming_ui_spec: passed")

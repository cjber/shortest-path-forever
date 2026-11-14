---@type string, SPFNamespace
local _, ns = ...
if ns.broken then
	return
end
local L = ns.L
local WINDOW_NAME = "ShortestPathForeverFarming"
---@type SPFFarmingWindow
local window
---@type SPFFarmingController
local controller
---@type FontString
local statusText
---@type Button
local startButton, pauseButton, resumeButton, stopButton
---@type ScrollFrame
local scroll
---@type Frame
local list
---@type SPFFarmingChoice[]
local rows = {}
---@type SPFGatherMateKind
local kind = "Herb Gathering"
---@type table<SPFGatherMateKind, table<integer, boolean>>
local selected = {}
---@type SPFGatherMateNode[]
local choices = {}
---@type SPFFarmingOrderJob?
local job
local generation = 0
local listHeight = 224
---@type string?
local notice
---@type table?
local ticker
---@type Button
local herbButton, miningButton, allButton, noneButton

local messages = {
	absent = L["Farming needs the GatherMate2 addon."],
	["invalid-zone"] = L["Your current zone is unavailable."],
	empty = L["No recorded locations for these choices in your current zone."],
	ready = L["Ready to start."],
	ordering = L["Ordering recorded locations..."],
	running = L["Farming tour running."],
	paused = L["Farming tour paused."],
	stopped = L["Farming tour stopped."],
	idle = L["Ready to start."],
	waiting = L["Farming tour waiting."],
	combat = L["Waiting for combat to end."],
	corpse = L["Waiting until you are alive."],
	occupied = L["Stop your current journey before starting a farming tour."],
	["too-few-locations"] = L["Choose at least two different recorded locations."],
	["unverified-arrival"] = L["Arrival could not be confirmed. The farming tour has stopped."],
	["ownership-lost"] = L["Your journey changed. The farming tour has stopped."],
	["non-walking-plan"] = L["No walking route was found. The farming tour has stopped."],
	nodata = L["Walking map data is unavailable. The farming tour has stopped."],
	outside = L["A recorded location is outside the walking map. The farming tour has stopped."],
	unreachable = L["A recorded location could not be reached. The farming tour has stopped."],
	["invalid-input"] = L["These recorded locations could not be ordered."],
	["invalid-world"] = L["Your position is unavailable"],
}
messages.replaced = messages["ownership-lost"]
messages.cleared = messages.stopped
messages.cancelled = messages.stopped
for _, reason in ipairs({
	"unsupported",
	"not-ready",
	"provider-error",
	"invalid-record",
	"unknown-name",
	"invalid-kind",
	"invalid-selection",
}) do
	messages[reason] = L["GatherMate2 recorded locations could not be read."]
end
local function Message(reason)
	return messages[reason] or L["Farming could not continue. Start a new tour when you are ready."]
end

local function CancelOrder()
	generation = generation + 1
	if job then
		job:Cancel()
		job = nil
	end
end

local function Paint()
	local state, reason, nextNode, cycles = controller:Status()
	statusText:SetText(
		notice
			or (
				Message(reason or state)
				.. "\n"
				.. L["Next location: %d. Completed circuits: %d."]:format(nextNode, cycles)
			)
	)
	local active = state == "running" or state == "paused" or state == "waiting"
	herbButton:SetEnabled(not active and not job and kind ~= "Herb Gathering")
	miningButton:SetEnabled(not active and not job and kind ~= "Mining")
	allButton:SetEnabled(not active and not job)
	noneButton:SetEnabled(not active and not job)
	startButton:SetEnabled(not job and not active and #choices > 0)
	pauseButton:SetEnabled(not job and state == "running")
	resumeButton:SetEnabled(not job and state == "paused")
	stopButton:SetEnabled(job ~= nil or active)
	for _, row in ipairs(rows) do
		row:SetEnabled(not active and not job)
	end
end

local function Start()
	CancelOrder()
	local nodes, reason = ns.GatherMate.CurrentZone(kind, selected[kind])
	if not nodes or #nodes == 0 then
		notice = Message(reason)
		Paint()
		return
	end
	-- PlayerPosition is the journey's exact world producer, including its secret-safe map fallback.
	local x, y, _, map = ns.PlayerPosition()
	if not (x and y and map) then
		notice = L["Your position is unavailable"]
		Paint()
		return
	end
	job = ns.FarmingOrder.Begin(nodes, { map = map, x = x, y = y })
	local pending, token = job, generation
	notice = messages.ordering
	Paint()
	local function Step()
		if token ~= generation or job ~= pending or not window:IsShown() then
			return
		end
		if InCombatLockdown() then
			notice = messages.combat
			Paint()
			C_Timer.After(0.1, Step)
			return
		end
		if notice ~= messages.ordering then
			notice = messages.ordering
			Paint()
		end
		local state, ordered = pending:Step()
		if state == "working" then
			C_Timer.After(0, Step)
			return
		end
		job = nil
		if state == "ready" and ordered then
			local ok, failure = controller:Start(ordered)
			notice = not ok and Message(failure) or nil
		else
			notice = Message(state)
		end
		Paint()
	end
	C_Timer.After(0, Step)
end

---@param parent Frame
---@param text string
---@param y number
---@param font? string
---@return FontString
local function Text(parent, text, y, font)
	local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	label:SetPoint("TOPLEFT", 16, y)
	label:SetPoint("TOPRIGHT", -16, y)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

local function Refresh()
	CancelOrder()
	local nodes, reason = ns.GatherMate.CurrentZone(kind)
	choices = {}
	local seen = {}
	for _, node in ipairs(nodes or {}) do
		if not seen[node.nodeID] then
			seen[node.nodeID] = true
			choices[#choices + 1] = node
		end
	end
	table.sort(choices, function(a, b)
		return a.title < b.title or (a.title == b.title and a.nodeID < b.nodeID)
	end)
	for i, node in ipairs(choices) do
		local row = rows[i]
		if not row then
			row = CreateFrame("CheckButton", nil, list, "InterfaceOptionsCheckButtonTemplate") --[[@as SPFFarmingChoice]]
			row.Label = Text(row, "", 0)
			row.Label:ClearAllPoints()
			row.Label:SetPoint("LEFT", row, "RIGHT", 4, 0)
			row.Label:SetPoint("RIGHT", list, "RIGHT", -8, 0)
			rows[i] = row
		end
		row:SetPoint("TOPLEFT", 4, -(i - 1) * 28)
		row.Label:SetText(node.title)
		row:SetChecked(selected[kind] == nil or selected[kind][node.nodeID] == true)
		row:SetScript("OnClick", function(self)
			if selected[kind] == nil then
				selected[kind] = {}
				for _, choice in ipairs(choices) do
					selected[kind][choice.nodeID] = true
				end
			end
			selected[kind][node.nodeID] = self:GetChecked() == true
			notice = nil
			Paint()
		end)
		row:Show()
	end
	for i = #choices + 1, #rows do
		rows[i]:Hide()
	end
	listHeight = math.max(listHeight, #choices * 28)
	list:SetHeight(listHeight)
	local state = controller:Status()
	local active = state == "running" or state == "paused" or state == "waiting"
	notice = not active and reason ~= "ready" and Message(reason) or nil
	Paint()
end

---@param label string
---@param x number
---@param y number
---@param callback fun()
---@return Button
local function Button(label, x, y, callback)
	local button = CreateFrame("Button", nil, window, "SharedButtonSmallTemplate") --[[@as Button]]
	button:SetSize(104, 26)
	button:SetPoint("BOTTOMLEFT", x, y)
	button:SetText(label)
	button:SetScript("OnClick", callback)
	return button
end

local function Build()
	controller = ns.Farming.new()
	window = CreateFrame("Frame", WINDOW_NAME, UIParent, "PortraitFrameTemplate") --[[@as SPFFarmingWindow]]
	window:SetSize(480, 520)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetClampedToScreen(true)
	window:SetTitle(L["Farming tour"])
	ns.Art.Icon(window:GetPortrait(), "Interface\\AddOns\\ShortestPathForever\\media\\Icon", 62)
	table.insert(UISpecialFrames, WINDOW_NAME)
	local description = Text(
		window,
		L["Visit GatherMate2 recorded locations in your current zone. Nodes may be absent or unreachable."],
		-40
	)
	description:ClearAllPoints()
	description:SetPoint("TOPLEFT", 72, -40)
	description:SetPoint("TOPRIGHT", -16, -40)
	herbButton = Button(L["Herbs"], 16, 406, function()
		kind = "Herb Gathering"
		Refresh()
	end)
	miningButton = Button(L["Mining"], 128, 406, function()
		kind = "Mining"
		Refresh()
	end)
	allButton = Button(L["All"], 240, 406, function()
		selected[kind] = nil
		Refresh()
	end)
	noneButton = Button(L["None"], 352, 406, function()
		selected[kind] = {}
		Refresh()
	end)
	local inset = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", 16, -120)
	inset:SetPoint("BOTTOMRIGHT", -16, 130)
	scroll = CreateFrame("ScrollFrame", nil, inset, "ScrollFrameTemplate") --[[@as ScrollFrame]]
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	list = CreateFrame("Frame", nil, scroll)
	list:SetSize(390, 224)
	scroll:SetScrollChild(list)
	scroll:SetScript("OnSizeChanged", function(_, width)
		list:SetWidth(width)
	end)
	statusText = Text(window, "", -400)
	startButton = Button(L["Start"], 16, 16, Start)
	pauseButton = Button(L["Pause"], 128, 16, function()
		controller:Pause()
		notice = nil
		Paint()
	end)
	resumeButton = Button(L["Resume"], 240, 16, function()
		controller:Resume()
		notice = nil
		Paint()
	end)
	stopButton = Button(L["Stop"], 352, 16, function()
		CancelOrder()
		controller:Stop()
		notice = nil
		Paint()
	end)
	window:SetScript("OnHide", function()
		CancelOrder()
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
	end)
	window:SetScript("OnShow", function()
		Refresh()
		ticker = C_Timer.NewTicker(0.5, Paint)
	end)
	window:Hide()
end

function ns.OpenFarming()
	if not window then
		Build()
	end
	window:Show()
end

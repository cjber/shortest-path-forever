---@type string, SPFNamespace
local addonName, ns = ...
if ns.broken then
	return
end
local L = ns.L
local serial = 0
local function Number(value)
	return canaccessvalue(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Validate the entire public-coordinate destination before changing the draft.
---@param point SPFAPIStop
---@return SPFAPIStop?
local function Copy(point)
	if not (canaccessvalue(point) and type(point) == "table" and getmetatable(point) == nil) then
		return nil
	end
	local map, x, y, z, title = point.map, point.x, point.y, point.z, point.title
	if
		not (Number(map) and map > 0 and map % 1 == 0 and Number(x) and Number(y))
		or x < 0
		or x > 1
		or y < 0
		or y > 1
		or not canaccessvalue(z)
		or (z ~= nil and not Number(z))
		or not canaccessvalue(title)
		or (title ~= nil and type(title) ~= "string")
	then
		return nil
	end
	local world = ns.WorldPoint(map, x, y)
	world = world and ns.InstanceEntrance(world)
	if not world then
		return nil
	end
	local location = ns.Locate(world)
	if not location or location.x < 0 or location.x > 1 or location.y < 0 or location.y > 1 then
		return nil
	end
	local info = C_Map.GetMapInfo(location.uiMap)
	if info and info.mapType <= Enum.UIMapType.Continent then
		return nil
	end
	return { map = map, x = x, y = y, z = z, title = title or ns.JourneyTitle(world) }
end

---@param points any
---@param allowEmpty? boolean
---@return SPFAPIStop[]?
local function CopyStops(points, allowEmpty)
	if not (canaccessvalue(points) and type(points) == "table" and getmetatable(points) == nil) then
		return nil
	end
	local count = #points
	if (count == 0 and not allowEmpty) or count > 64 then
		return nil
	end
	for key in pairs(points) do
		if not Number(key) or key % 1 ~= 0 or key < 1 or key > count then
			return nil
		end
	end
	local snapshot = {}
	for i = 1, count do
		local copy = Copy(points[i])
		if not copy then
			return nil
		end
		snapshot[i] = copy
	end
	return snapshot
end

---@return SPFAPIPlace?
local function Origin()
	local x, y, _, map = ns.PlayerPosition()
	if not (Number(x) and Number(y) and Number(map)) then
		return nil
	end
	---@cast map number
	---@cast x number
	---@cast y number
	local uiMap, position = C_Map.GetMapPosFromWorldPos(map, CreateVector2D(x, y))
	if not position then
		return nil
	end
	local px, py = position:GetXY()
	local point = Copy({ map = uiMap, x = px, y = py })
	return point and { map = point.map, x = point.x, y = point.y }
end
local function Blocked()
	if InCombatLockdown() then
		return "combat"
	end
	if UnitIsDeadOrGhost("player") or (ns.Corpse and ns.Corpse.Active()) then
		return "corpse"
	end
end
local function StartBlocked()
	return Blocked() or (not ns.IsPlayerJourney(ns.JourneyOwner()) and "occupied" or nil)
end
---@return SPFPublicAPI
local api = function()
	return ShortestPathForever.API
end

---@param controller SPFJourneyStopsController
local function SaveDraft(controller)
	if ns.charDB then
		ns.charDB.journeyStops = (#controller.stops > 0 or controller.manual)
				and { stops = controller.stops, manual = controller.manual }
			or nil
	end
end

---@param controller SPFJourneyStopsController
---@param snapshot SPFAPIStop[]
---@return boolean
local function Navigate(controller, snapshot)
	controller.generation = controller.generation + 1
	local owner = ns.STOPS_OWNER .. controller.session .. ":" .. controller.generation
	if not api().NavigateRoute(owner, snapshot) then
		controller.state = "failed"
		return false
	end
	controller.owner, controller.activeStops = owner, snapshot
	controller:Observe()
	ns.KeepJourneyStops(owner, snapshot)
	return true
end

local Editor = {}
---@return SPFJourneyStopsController
function Editor.new()
	serial = serial + 1
	local controller = { stops = {}, selected = 0, manual = false, generation = 0, session = serial, state = "idle" }
	---@cast controller SPFJourneyStopsController
	local saved = ns.charDB and ns.charDB.journeyStops
	if saved ~= nil then
		local stops = type(saved) == "table" and type(saved.manual) == "boolean" and CopyStops(saved.stops, true)
		if stops then
			controller.stops, controller.manual = stops, saved.manual
			controller.selected = #stops > 0 and 1 or 0
		else
			ns.charDB.journeyStops = nil
		end
	end
	function controller:CancelOrder()
		self.generation = self.generation + 1
		if self.job then
			self.job:Cancel()
			self.job = nil
			self.state = "idle"
		end
	end
	function controller:Observe()
		if not self.owner then
			return
		end
		local index = api().CurrentStop(self.owner)
		if index then
			self.index = index
			self.state = ns.IsJourneyGuided() and "running" or "paused"
			return
		end
		local ended = api().Ended(self.owner)
		if ended == "arrived" or ended == "cancelled" or ended == "cleared" or ended == "replaced" then
			self.state = ended == "arrived" and "complete" or "changed"
			self.owner, self.activeStops = nil, nil
		else
			self.state = "loading"
		end
	end
	function controller:Editable()
		self:Observe()
		return self.owner == nil
	end
	function controller:Add(point)
		if not self:Editable() then
			return false
		end
		local copy = Copy(point)
		if not copy then
			self.state = "invalid"
			return false
		end
		for index, stop in ipairs(self.stops) do
			if stop.map == copy.map and stop.x == copy.x and stop.y == copy.y and stop.z == copy.z then
				self.selected, self.state = index, "duplicate"
				return false
			end
		end
		if #self.stops >= 64 then
			self.state = "full"
			return false
		end
		self:CancelOrder()
		self.stops[#self.stops + 1] = copy
		self.selected, self.state = #self.stops, "idle"
		SaveDraft(self)
		return true
	end
	function controller:AddWaypoint()
		local waypoint = C_Map.GetUserWaypoint()
		if not (canaccessvalue(waypoint) and type(waypoint) == "table") then
			self.state = "no-pin"
			return false
		end
		local position = waypoint.position
		if not (canaccessvalue(position) and type(position) == "table") then
			self.state = "no-pin"
			return false
		end
		return self:Add({ map = waypoint.uiMapID, x = position.x, y = position.y })
	end
	function controller:Move(delta)
		if not self:Editable() or (delta ~= -1 and delta ~= 1) then
			return false
		end
		local at, to = self.selected, self.selected + delta
		if not self.stops[at] or not self.stops[to] then
			return false
		end
		self:CancelOrder()
		self.stops[at], self.stops[to] = self.stops[to], self.stops[at]
		self.selected, self.manual, self.state = to, true, "idle"
		SaveDraft(self)
		return true
	end
	function controller:Remove()
		if not self:Editable() or not self.stops[self.selected] then
			return false
		end
		self:CancelOrder()
		table.remove(self.stops, self.selected)
		self.selected, self.state = math.min(self.selected, #self.stops), "idle"
		SaveDraft(self)
		return true
	end
	function controller:Clear()
		if not self:Editable() then
			return false
		end
		self:CancelOrder()
		self.stops, self.selected, self.manual, self.state = {}, 0, false, "idle"
		SaveDraft(self)
		return true
	end
	function controller:Submit(points)
		local reason = StartBlocked()
		if reason then
			self.state = reason
			return false
		end
		local snapshot = CopyStops(points)
		if not snapshot then
			self.state = "invalid"
			return false
		end
		if not Navigate(self, snapshot) then
			return false
		end
		-- A route to the place a paused journey already leads to takes it over, pause and all.
		api().Resume(self.owner)
		self:Observe()
		return true
	end
	function controller:Start()
		if not self:Editable() then
			return false
		end
		self:CancelOrder()
		local reason = StartBlocked()
		if reason or #self.stops == 0 then
			self.state = reason or "empty"
			return false
		end
		if self.manual then
			return self:Submit(self.stops)
		end
		local from = Origin()
		if not from then
			self.state = "loading"
			return false
		end
		ns.ForgetKeptJourney()
		self.job = ns.StopOrder.Begin(self.stops, from)
		self.from, self.goal, self.state = from, ns.JourneyGoal(), "ordering"
		return true
	end
	---@param pathJob? SPFPathJob the path job stepping (ns.Path.Run), so an uncached estimate pauses at the frame budget
	function controller:Step(pathJob)
		local job = self.job
		if not job then
			return
		end
		local reason = StartBlocked()
		if reason then
			self:CancelOrder()
			self.state = reason == "combat" and "order-combat" or reason == "corpse" and "order-corpse" or "occupied"
			return
		end
		local state, points = job:Step(pathJob)
		-- Cleared or restarted while its estimate paused: that order no longer owns the editor.
		if self.job ~= job then
			return
		end
		-- A journey started since Start is newer than this order.
		local goal = ns.JourneyGoal()
		if goal and goal ~= self.goal then
			self:CancelOrder()
			self.state = "changed"
			return
		end
		if state == "working" or state == "loading" then
			self.state = state == "working" and "ordering" or "loading"
			return
		end
		local failure = self.job.reason
		self.job = nil
		local from = Origin()
		if state == "ready" and points and self.from then
			if not from or from.map ~= self.from.map or from.x ~= self.from.x or from.y ~= self.from.y then
				self.state = "moved"
				return
			end
			self:Submit(points)
		else
			self.state = failure == "context-changed" and "context-changed" or state
		end
	end
	function controller:Pause()
		if Blocked() then
			return false
		end
		self:Observe()
		if self.owner and api().Pause(self.owner) then
			self.state = "paused"
			return true
		end
		return false
	end
	function controller:Resume()
		if Blocked() then
			return false
		end
		self:Observe()
		if self.owner and api().Resume(self.owner) then
			self.state = "running"
			return true
		end
		return false
	end
	function controller:Stop()
		self:CancelOrder()
		self:Observe()
		if self.owner and not api().Cancel(self.owner) then
			self.state = "loading"
			return
		end
		self.owner, self.activeStops, self.state = nil, nil, "stopped"
	end
	function controller:Attach(callback)
		self:Detach()
		self:Observe()
		self.unsubscribe = api().Subscribe(function()
			self:Observe()
			callback()
		end)
	end
	function controller:Detach()
		self:CancelOrder()
		if self.state == "ordering" then
			self.state = "idle"
		end
		if self.unsubscribe then
			self.unsubscribe()
			self.unsubscribe = nil
		end
	end
	return controller
end

---@type SPFJourneyStopsController?
local editor
function Editor.Current()
	editor = editor or Editor.new()
	return editor
end

-- Starts a kept route again: false when the API refuses it, nil when the kept value is damaged.
function Editor.Restore(points)
	local snapshot = CopyStops(points)
	if snapshot then
		return Navigate(Editor.Current(), snapshot)
	end
end

ns.JourneyStopsEditor = Editor

local messages = {
	idle = L["Place pins on the map to add stops."],
	empty = L["Add at least one stop."],
	ordering = L["Ordering stops by estimated travel time..."],
	["context-changed"] = L["Travel options changed. Start again to order these stops."],
	["order-combat"] = L["Combat interrupted ordering. Start again when combat ends."],
	["order-corpse"] = L["Ordering stopped while you are dead. Start again when you are alive."],
	combat = L["Waiting for combat to end."],
	corpse = L["Waiting until you are alive."],
	occupied = L["Stop your current journey before starting this journey."],
	invalid = L["That destination is unavailable."],
	["no-pin"] = L["no map pin is set."],
	duplicate = L["Already in this journey."],
	full = L["A journey can have up to 64 stops."],
	complete = L["Journey complete."],
	changed = L["Your journey changed."],
	stopped = L["Journey stopped."],
	paused = L["Journey paused."],
	loading = L["Your position is unavailable"],
	moved = L["Your position changed. Start again to order these stops."],
	unreachable = L["A stop could not be reached. Remove it or choose your own order."],
}
---@type SPFJourneyStopsWindow
local window
---@type FontString
local status
---@type Frame
local content
---@type Button[]
local rows, editButtons = {}, {}
---@type Button
local startButton, pauseButton, resumeButton, stopButton
---@type fun()
local refresh
---@type (fun(): boolean)?
local waypointReceiver

-- Each opening accepts new pins until it closes, including reports held while ownership settles.
---@param owned boolean Shortest Path wrote the pin
---@return (fun(): boolean)?
function Editor.WaypointReceiver(owned)
	if not owned and waypointReceiver and C_Map.HasUserWaypoint() and Editor.Current():Editable() then
		return waypointReceiver
	end
end

---@param parent Frame
---@param value string
---@param y number
---@return FontString
local function Text(parent, value, y)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 16, y)
	label:SetPoint("TOPRIGHT", -16, y)
	label:SetJustifyH("LEFT")
	label:SetText(value)
	return label
end
---@param text string
---@param x number
---@param y number
---@param callback fun()
---@param width? number
---@return Button
local function Button(text, x, y, callback, width)
	local button = CreateFrame("Button", nil, window, "SharedButtonSmallTemplate") --[[@as Button]]
	button:SetSize(width or 100, 26)
	button:SetPoint("BOTTOMLEFT", x, y)
	button:SetText(text)
	button:SetScript("OnClick", function()
		callback()
		refresh()
	end)
	return button
end
local function Build()
	local controller = Editor.Current()
	local host = CreateFrame("Frame", "ShortestPathForeverJourneyStops", UIParent, "PortraitFrameTemplate")
	window = host --[[@as SPFJourneyStopsWindow]]
	window:SetSize(560, 560)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	-- Draggable, so it can be moved off the part of the map a pin is wanted on.
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetTitle(L["Journey stops"])
	local icon = C_AddOns.GetAddOnMetadata(addonName, "X-Forever-Icon")
	if icon then
		ns.Art.Icon(window:GetPortrait(), icon, 62)
	end
	table.insert(UISpecialFrames, "ShortestPathForeverJourneyStops")
	local help = Text(window, L["Orders the stops by estimated travel time. You can change the order."], -42)
	help:ClearAllPoints()
	help:SetPoint("TOPLEFT", 72, -42)
	help:SetPoint("TOPRIGHT", -16, -42)
	editButtons[1] = Button(L["Add map waypoint"], 16, 444, function()
		controller:AddWaypoint()
	end, 170)
	editButtons[2] = Button(L["Up"], 194, 444, function()
		controller:Move(-1)
	end, 76)
	editButtons[3] = Button(L["Down"], 278, 444, function()
		controller:Move(1)
	end, 76)
	editButtons[4] = Button(L["Remove"], 362, 444, function()
		controller:Remove()
	end, 84)
	editButtons[5] = Button(L["Clear"], 454, 444, function()
		controller:Clear()
	end, 90)
	local inset = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", 16, -124)
	inset:SetPoint("BOTTOMRIGHT", -16, 136)
	local scroll = CreateFrame("ScrollFrame", nil, inset, "ScrollFrameTemplate") --[[@as ScrollFrame]]
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(480, 288)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(_, width)
		content:SetWidth(width)
	end)
	status = Text(window, "", -436)
	startButton = Button(L["Start"], 16, 16, function()
		controller:Start()
		local generation = controller.generation
		-- One estimate a step, each in a path job: the frame that clicked or the next never plans whole.
		local function Step()
			if generation ~= controller.generation or not window:IsShown() or not controller.job then
				return
			end
			ns.Path.Run(function(pathJob)
				if generation == controller.generation and controller.job then
					controller:Step(pathJob)
				end
			end, function()
				refresh()
				if generation == controller.generation and window:IsShown() and controller.job then
					C_Timer.After(0, Step)
				end
			end)
		end
		if controller.job then
			C_Timer.After(0, Step)
		end
	end)
	pauseButton = Button(L["Pause"], 124, 16, function()
		controller:Pause()
	end)
	resumeButton = Button(L["Resume"], 232, 16, function()
		controller:Resume()
	end)
	stopButton = Button(L["Stop"], 340, 16, function()
		controller:Stop()
	end)
	Button(L["Close"], 448, 16, function()
		window:Hide()
	end, 96)
	refresh = function()
		local editable = controller:Editable()
		for _, button in ipairs(editButtons) do
			button:SetEnabled(editable)
		end
		editButtons[2]:SetEnabled(editable and controller.selected > 1)
		editButtons[3]:SetEnabled(editable and controller.selected > 0 and controller.selected < #controller.stops)
		editButtons[4]:SetEnabled(editable and controller.selected > 0)
		editButtons[5]:SetEnabled(editable and #controller.stops > 0)
		startButton:SetEnabled(editable and not controller.job and #controller.stops > 0 and not StartBlocked())
		pauseButton:SetEnabled(controller.owner ~= nil and controller.state == "running" and not Blocked())
		resumeButton:SetEnabled(controller.owner ~= nil and controller.state == "paused" and not Blocked())
		stopButton:SetEnabled(controller.owner ~= nil or controller.job ~= nil)
		local displayed = controller.activeStops or controller.stops
		local text = messages[controller.state] or L["The journey could not start."]
		if controller.owner then
			text = L["Stop %d of %d."]:format(controller.index or 1, #displayed)
			if controller.state == "paused" then
				text = text .. " " .. L["Journey paused."]
			end
		end
		status:SetText(text .. "\n" .. (controller.manual and L["Your order"] or L["Estimated travel-time order"]))
		for i, stop in ipairs(displayed) do
			local row = rows[i]
			if not row then
				row = CreateFrame("Button", nil, content, "SharedButtonSmallTemplate") --[[@as Button]]
				row:SetHeight(26)
				row:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
				row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
				rows[i] = row
			end
			local map = C_Map.GetMapInfo(stop.map)
			local title = stop.title or (map and map.name) or L["Journey stops"]
			local label = L["%d. %s (%.1f, %.1f)"]:format(i, title, stop.x * 100, stop.y * 100)
			row:SetText(label)
			if (controller.owner and controller.index == i) or (not controller.owner and controller.selected == i) then
				row:LockHighlight()
			else
				row:UnlockHighlight()
			end
			row:SetEnabled(editable)
			row:SetScript("OnClick", function()
				controller.selected = i
				refresh()
			end)
			row:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(label)
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			row:Show()
		end
		for i = #displayed + 1, #rows do
			rows[i]:Hide()
		end
		content:SetHeight(math.max(288, #displayed * 28))
	end
	window:SetScript("OnHide", function()
		waypointReceiver = nil
		window:UnregisterAllEvents()
		controller:Detach()
	end)
	window:SetScript("OnEvent", function()
		if controller.job and Blocked() then
			controller:Step()
		end
		refresh()
	end)
	window:SetScript("OnShow", function()
		window:RegisterEvent("PLAYER_REGEN_ENABLED")
		window:RegisterEvent("PLAYER_REGEN_DISABLED")
		window:RegisterEvent("PLAYER_DEAD")
		window:RegisterEvent("PLAYER_ALIVE")
		window:RegisterEvent("PLAYER_UNGHOST")
		local function CaptureWaypoint()
			if waypointReceiver ~= CaptureWaypoint or not controller:Editable() then
				return false
			end
			controller:AddWaypoint()
			refresh()
			return true
		end
		waypointReceiver = CaptureWaypoint
		controller:Attach(refresh)
		refresh()
	end)
	window:Hide()
end
function ns.ShowJourneyStops()
	if not window then
		Build()
	end
	window:Show()
end

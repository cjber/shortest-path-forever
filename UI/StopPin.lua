---@class SPFNamespace
local ns = select(2, ...)
local L = ns.L

-- The addon's own goal pin: a square file whose point is the bottom centre of the square, gold while Guide tracks
-- the goal and bronze while it does not. 29 tall: the stock pin at the 0.8 scale the map drew it, so the goal sits
-- no heavier on the map than before.
local GOAL_SIZE = 29
-- The map's own quest button (POIButtonTemplate): a 20-unit button whose 32-unit disc art overhangs it. A numbered
-- stop up to 25 wears the addon's numbered marker instead, square and 24 units across.
local STOP_SIZE, NUMBER_SIZE = 20, 24
-- The stop being travelled to wears the button of the quest the game tracks (POIButton.lua): the lit disc. Above 25
-- it keeps the lit button and its font number, while every other stop wears the plain button.
local STOP_ATLAS, CURRENT_ATLAS = "UI-QuestPoi-QuestNumber", "UI-QuestPoi-QuestNumber-SuperTracked"
local NUMBER_YELLOW, NUMBER_DARK = { 1, 0.82, 0.25 }, { 0.1, 0.05, 0 }
-- A lone stop's own mark stands alone at the size of the map's quest marks. A numbered one wears the mark as a badge
-- over the marker's lower right, as Legacy Forever's entrance pins wear the Legacy shield; the pin's hit rect reaches
-- out over the badge.
local LOOK_SIZE, BADGE_SIZE, BADGE_OFFSET, TAG_SIZE = 22, 16, 4, 11
-- A later stop fades by the same amount as the line that leads to it (Strokes.lua's ns.LaterAlpha, read when used
-- because Strokes.lua loads after this file).
-- The numbered marker overhangs its 20-unit pin by 2 on each side.
local MARKER_INSET = 2
-- Route.lua groups stops by the button's size.
ns.StopSize = STOP_SIZE

---@class SPFGoalPin : SPFCanvasPin
---@field Texture Texture
---@field Icon Texture
---@field Disc Texture
---@field Button Texture
---@field HighlightTexture Texture
---@field Number FontString
---@field stopLabels? string[]
---@field stopNumbers? integer[]
---@field stopCount? integer
---@field stopDetails? string[][] a stop's own detail lines, by the stop's place in this pin
---@field later? boolean
---@field current? boolean -- marks the stop being travelled to, whose steps the tooltip lists
local GoalPin = CreateFromMixins(ns.MapCanvas.PinMixin)
-- Route.lua's pool puts it on.
ns.GoalPinMixin = GoalPin

function GoalPin:OnLoad()
	-- The user waypoint's level (WaypointLocationDataProvider), above every quest POI, super-tracked ones included.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
	self:SetIgnoreGlobalPinScale(true)
	self:SetScalingLimits(1, 1, 1)
	self.takesMouse = true
	-- The disc's own silhouette, opaque under a faded button.
	self.Disc:SetVertexColor(0, 0, 0)
	self.Number = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	self.Number:SetPoint("CENTER")
	self.pressRegions = { self.Texture, self.Icon, self.Disc, self.Button, self.Number, self.HighlightTexture }
	self.Button:SetDesaturated(false)
	self.Button:SetVertexColor(1, 0.9, 0.7)
end

-- A lone destination wears the addon's own goal pin; a numbered stop up to 25 wears the numbered marker, and a later
-- stop the map's quest button with its font number.
-- Stops whose buttons would overlap, a place visited twice among them, share one: it shows the first stop's number
-- with the action badge intact, and its tooltip names each.
-- A numbered stop whose caller said what stands there wears that mark as a badge on the marker's lower right, so the
-- pin reads as step 3 at the quest giver or flight master; a lone one wears the mark alone, full size.
---@param numbers integer[]? the stops this pin marks, in order; nil for a lone destination
---@param count? integer the route's stop count
---@param labels? string[] what to do at each stop this pin marks
---@param look? SPFAPIStopKind
---@param details? string[]
---@param pinBadge? boolean
function GoalPin:OnAcquired(x, y, numbers, count, labels, later, look, details, pinBadge)
	self:SetPosition(x, y)
	-- The disc's shadow stays opaque, so a faded button still hides the POI beneath it.
	self:SetStopAlpha(later and ns.LaterAlpha or 1)
	self.stopLabels = labels and labels[1] and labels or nil
	self.stopNumbers = numbers
	self.stopCount = count
	self.stopDetails = details and details[1] and details or nil
	self.later = later
	self.current = not later
	-- A planned route nobody is guided along is an untracked goal: its pin is the bronze twin.
	local goalFile = ns.GoalPinFile()
	local marked = look ~= nil and ns.SetStopLook(self.Icon, look, numbers and BADGE_SIZE or LOOK_SIZE)
	local badge = marked and numbers ~= nil
	self.Icon:SetShown(marked)
	self.Icon:ClearAllPoints()
	self.Icon:SetPoint(badge and "BOTTOMRIGHT" or "CENTER", badge and BADGE_OFFSET or 0, badge and -BADGE_OFFSET or 0)
	local corner = badge and -BADGE_OFFSET or 0
	self:SetHitRectInsets(0, corner, 0, corner)
	local number = numbers and numbers[1]
	local numberArt = number and ns.NumberFile(number)
	local numbered = numberArt ~= nil
	-- Above the numbered markers' 25, the button and its font number return.
	local fonted = numbers ~= nil and not numbered
	self.Texture:SetShown(numbered or (numbers == nil and not marked))
	self.Disc:SetShown(fonted)
	self.Button:SetShown(fonted)
	self.Number:SetText(fonted and tostring(number) or "")
	local current = numbers ~= nil and not later
	if fonted then
		-- art-ok: both quest buttons are 32 by 32, in Map.xml's 32 by 32 box
		self.Button:SetAtlas(current and CURRENT_ATLAS or STOP_ATLAS)
		self.Number:SetTextColor(unpack(current and NUMBER_DARK or NUMBER_YELLOW))
	end
	if numbers then
		self:SetSize(STOP_SIZE, STOP_SIZE)
	elseif marked then
		self:SetSize(LOOK_SIZE, LOOK_SIZE)
	else
		-- The addon's own goal pin, square, so its shape is not stretched.
		self:SetSize(GOAL_SIZE, GOAL_SIZE)
		ns.Art.Icon(self.Texture, goalFile, GOAL_SIZE)
	end
	self.Texture:ClearAllPoints()
	if numbered then
		ns.Art.Icon(self.Texture, numberArt --[[@as string]], NUMBER_SIZE)
		self.Texture:SetPoint("CENTER")
		local right = badge and -BADGE_OFFSET or -MARKER_INSET
		local bottom = badge and -BADGE_OFFSET or -MARKER_INSET
		self:SetHitRectInsets(-MARKER_INSET, right, -MARKER_INSET, bottom)
	elseif pinBadge and not numbers and not marked then
		self:SetSize(LOOK_SIZE, LOOK_SIZE)
		ns.Art.Icon(self.Texture, goalFile, TAG_SIZE)
		self.Texture:SetPoint("CENTER", self, "BOTTOMRIGHT", 0, 0)
		self:SetHitRectInsets(0, -TAG_SIZE / 2, 0, -TAG_SIZE / 2)
	elseif not numbers and not marked then
		-- The pin's point marks the goal: the map centres the frame on it, so the pin stands on the centre and the
		-- hit rect rises with it.
		self.Texture:SetPoint("BOTTOM", self, "CENTER")
		self:SetHitRectInsets(0, 0, -GOAL_SIZE / 2, GOAL_SIZE / 2)
	else
		self.Texture:SetAllPoints()
	end
	-- Hover: the pin's own art again on the HIGHLIGHT layer, drawn with ADD, as BaseHighlightableMapPoiPinTemplate does.
	local highlight = self.HighlightTexture
	highlight:ClearAllPoints()
	if fonted then
		ns.Art.Fit(highlight, current and CURRENT_ATLAS or STOP_ATLAS, 32, 32)
		highlight:SetAllPoints(self.Button)
	elseif numbered then
		ns.Art.Icon(highlight, numberArt --[[@as string]], NUMBER_SIZE)
		highlight:SetAllPoints(self.Texture)
	elseif marked then
		ns.SetStopLook(highlight, look --[[@as SPFAPIStopKind]], numbers and BADGE_SIZE or LOOK_SIZE)
		highlight:SetAllPoints(self.Icon)
	else
		ns.Art.Icon(highlight, goalFile, GOAL_SIZE)
		highlight:SetAllPoints(self.Texture)
	end
	highlight:SetShown(self.highlighted == true)
end

-- The pin's art, faded for a later stop and full while the pointer is on it.
---@param alpha number
function GoalPin:SetStopAlpha(alpha)
	self.Button:SetAlpha(alpha)
	self.Icon:SetAlpha(alpha)
	self.Number:SetAlpha(alpha)
	self.Texture:SetAlpha(alpha)
end

-- A title's right-hand value, as the repo's other tooltips give one (UI/Map.lua, UI/FlightPins.lua).
---@param text string
---@param right? string
local function AddTitleLine(text, right)
	if right then
		GameTooltip_AddColoredDoubleLine(GameTooltip, text, right, HIGHLIGHT_FONT_COLOR, HIGHLIGHT_FONT_COLOR)
	else
		GameTooltip_SetTitle(GameTooltip, text)
	end
end

function GoalPin:OnMouseEnter()
	self:SetStopAlpha(1)
	if ns.HoverStop then
		ns.HoverStop(self.stopNumbers)
	end
	local title, rows, plan, index = ns.JourneyInfo()
	if not title or not rows then
		return
	end
	-- The time and distance left are the journey's, so they sit on the title line, not a line of their own.
	local left
	if self.current then
		local time, distance = ns.JourneyLeft()
		if time then
			left = string.format(L["%s · %s"], time, distance)
		end
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local labels, numbers = self.stopLabels, self.stopNumbers
	local shown = {}
	local function AddDetails(stop)
		for _, detail in ipairs(self.stopDetails and self.stopDetails[stop] or {}) do
			-- A line an earlier stop already gave is the same quest's: show the shared text once.
			if not shown[detail] then
				shown[detail] = true
				GameTooltip_AddNormalLine(GameTooltip, detail)
			end
		end
	end
	if labels and numbers then
		-- Each stop this pin marks: its count, what to do there in white, then only the details it adds.
		for i, label in ipairs(labels) do
			local count = string.format(L["Stop %d of %d"], numbers[i], self.stopCount)
			if i == 1 then
				AddTitleLine(count, left)
			else
				GameTooltip_AddNormalLine(GameTooltip, count)
			end
			GameTooltip_AddColoredLine(GameTooltip, label, HIGHLIGHT_FONT_COLOR)
			AddDetails(i)
		end
	else
		AddTitleLine(title, left)
		AddDetails(1)
	end
	-- The pin you are travelling to lists the steps there, as the tracker does, when the trip has more than one.
	if self.current then
		local hint = ns.OtherFactionHint()
		if hint then
			GameTooltip_AddNormalLine(GameTooltip, hint)
		end
		local trip = plan and #plan.legs - (index or 1) + 1 or #rows
		if trip > 1 then
			for _, row in ipairs(rows) do
				local color = row.warning and RED_FONT_COLOR
					or row.current and HIGHLIGHT_FONT_COLOR
					or row.grey and GRAY_FONT_COLOR
					or NORMAL_FONT_COLOR
				GameTooltip_AddColoredLine(GameTooltip, row.text, color)
			end
		end
		ns.FamilyHints.AddEntranceLine(GameTooltip)
	end
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip_AddNormalLine(GameTooltip, L["Right-click to clear"])
	GameTooltip:Show()
end

function GoalPin:OnMouseLeave()
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
	self:SetStopAlpha(self.later and ns.LaterAlpha or 1)
	if ns.HoverStop then
		ns.HoverStop(nil)
	end
end

-- Pins pass right clicks to the canvas to zoom out (UI/MapCanvas.lua); this one clears instead.
function GoalPin.ShouldMouseButtonBePassthrough()
	return false
end

function GoalPin.OnMouseClickAction(_, button)
	if button == "RightButton" then
		ns.ClearJourney()
	end
end

function GoalPin:OnReleased()
	self:OnMouseLeave()
	self.stopLabels = nil
	self.stopNumbers = nil
	self.stopCount = nil
	self.stopDetails = nil
	self.later = nil
	self.current = nil
end

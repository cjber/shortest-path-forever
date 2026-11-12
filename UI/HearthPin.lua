---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

local MapCanvas = ns.Canvas

-- A button on the world map at the Hearthstone's bind point: click it to keep the Hearthstone out of journeys, or to
-- let them use it again. It and the tracker's journey menu (UI/Tracker.lua) flip the same saved switch
-- (Journey/Journey.lua). The art is the client's innkeeper minimap button, never an item icon.
local HEARTH_SIZE = 22
-- How a saved Hearthstone reads: the stock button faded and greyed, like an option that is off.
local SAVED_ALPHA = 0.75
-- A comparison stands this long (ms) for the same goal and much the same place, as the other-faction hint's does.
local KEEP, MOVED = 30000, 50

---@type SPFCanvasPool?
local hearthPins

---@class SPFHearthPin : SPFCanvasPin
---@field Texture Texture
---@field HighlightTexture Texture
---@field hearth? SPFHearthstone
local HearthPin = CreateFromMixins(MapCanvas.PinMixin)
ns.HearthPinMixin = HearthPin

function HearthPin:OnLoad()
	-- Above the map's town, flight point and dungeon marks, so the pointer finds the button.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_GOSSIP")
	self:SetIgnoreGlobalPinScale(true)
	self:SetScalingLimits(1, 1, 1)
	self.takesMouse = true
	self.Texture = self:CreateTexture(nil, "ARTWORK")
	self.Texture:SetPoint("CENTER")
	self.HighlightTexture = self:CreateTexture(nil, "HIGHLIGHT")
	self.HighlightTexture:SetBlendMode("ADD")
	self.HighlightTexture:SetAlpha(0.4)
	self.HighlightTexture:SetPoint("CENTER")
	self.pressRegions = { self.Texture, self.HighlightTexture }
end

---@param hearth SPFHearthstone
---@param x number
---@param y number
function HearthPin:OnAcquired(hearth, x, y)
	self.hearth = hearth
	self:SetSize(HEARTH_SIZE, HEARTH_SIZE)
	ns.SetStopLook(self.Texture, "innkeeper", HEARTH_SIZE)
	ns.SetStopLook(self.HighlightTexture, "innkeeper", HEARTH_SIZE)
	local saved = not ns.HearthstoneEnabled()
	self.Texture:SetAlpha(saved and SAVED_ALPHA or 1)
	self.Texture:SetDesaturated(saved)
	self.HighlightTexture:SetDesaturated(saved)
	self.HighlightTexture:SetAlpha((saved and SAVED_ALPHA or 1) * 0.4)
	self:SetPosition(x, y)
end

function HearthPin:OnMouseEnter()
	local hearth = self.hearth
	if not hearth then
		return
	end
	local title, lines = ns.HearthPinTooltip(hearth.name, ns.HearthSaving(), ns.HearthstoneEnabled())
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, title)
	for index, text in ipairs(lines) do
		if index == 1 then
			GameTooltip_AddColoredLine(GameTooltip, text, HIGHLIGHT_FONT_COLOR)
		elseif index == #lines then
			GameTooltip_AddColoredLine(GameTooltip, text, GREEN_FONT_COLOR)
		else
			GameTooltip_AddNormalLine(GameTooltip, text)
		end
	end
	GameTooltip:Show()
end

function HearthPin:OnMouseLeave()
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

-- The button takes the left click; the right still passes through to the map to zoom out (UI/Canvas.lua).
function HearthPin.OnMouseClickAction(_, button)
	if button == "LeftButton" then
		ns.ToggleHearthstone()
	end
end

function HearthPin:OnReleased()
	self.hearth = nil
end

-- The tooltip's title and its lines: the bind point, then how the Hearthstone stands for this journey and what a
-- click does. `saving` is in ms and may be nil when no comparison could be made; the time line is left out then.
---@param name string the bind location, as the client names it
---@param saving number? ms the Hearthstone saves on this journey
---@param enabled boolean whether journeys may use it
---@return string title, string[] lines
function ns.HearthPinTooltip(name, saving, enabled)
	local lines = { name }
	if enabled then
		if saving then
			lines[#lines + 1] =
				string.format(L["This journey uses it: %s faster."], ns.FormatCountdown(math.max(0, saving)))
		end
		lines[#lines + 1] = L["Click to save it."]
	else
		lines[#lines + 1] = L["Saved for later."]
		lines[#lines + 1] = L["Click to use it."]
	end
	return L["Hearthstone"], lines
end

-- The last comparison, kept while the player stands near the same place on the same journey.
---@type {goal: SPFPoint, at: number, x: number, y: number, map: number, saving: number?}?
local comparison

-- How much faster the journey is with the Hearthstone, in ms: the planner's answer with it and without it, from where
-- the player stands now, in the same frame of reference. nil without a journey, a readable position or a Hearthstone.
---@return number?
function ns.HearthSaving()
	local goal = ns.JourneyGoal()
	local x, y, _, map = ns.JourneyPosition()
	if not (goal and x and y and map) or InCombatLockdown() then
		return nil
	end
	if ns.Corpse and ns.Corpse.Info() then
		return nil
	end
	local now = ns.NowMs()
	local hearth = ns.Hearthstone(now)
	if not hearth then
		comparison = nil
		return nil
	end
	local kept = comparison
	if
		kept
		and kept.goal == goal
		and kept.map == map
		and now - kept.at <= KEEP
		and (kept.x - x) ^ 2 + (kept.y - y) ^ 2 <= MOVED ^ 2
	then
		return kept.saving
	end
	local options = ns.PlanContext.Options({ map = map, x = x, y = y }, goal)
	-- A topology of this comparison's own: Planner.Plan mutates a cache between calls.
	options.cache = {}
	options.waterWalking = ns.JourneyWaterWalking()
	local teleports = options.teleports or {}
	local listed = false
	for _, place in ipairs(teleports) do
		if place.item == 6948 then
			listed = true
			break
		end
	end
	if not listed then
		-- Copies: UsableTeleports keeps its place array between calls, and the journey's own planning must not see the
		-- Hearthstone this comparison added while the switch is off.
		local copy = {}
		for index, place in ipairs(teleports) do
			copy[index] = place
		end
		copy[#copy + 1] = hearth.place
		options.teleports = copy
		local ready = {}
		for index, at in pairs(options.teleportReady or {}) do
			ready[index] = at
		end
		ready[#copy] = hearth.readyAt
		options.teleportReady = ready
	end
	local with = ns.Planner.Plan(options)
	options.withoutHearth = true
	local without = ns.Planner.Plan(options)
	local saving = with and without and (without.arrive - with.arrive) or nil
	comparison = { goal = goal, at = now, x = x, y = y, map = map, saving = saving }
	return saving
end

-- The bind point's place on the map now shown, or nil when it is off this map.
---@param hearth SPFHearthstone
---@param mapID number
---@return number?, number?
local function MapPlace(hearth, mapID)
	local x, y = ns.JourneyMapPosition(hearth, mapID)
	if x == nil then
		return nil
	end
	if ns.OpenMapAddon.Stitched() or (x >= 0 and x <= 1 and y >= 0 and y <= 1) then
		return x, y
	end
end

-- Draw the button at the bind point, or take it back: it shows while a journey exists, the Hearthstone could be used
-- and its bind point is on the map now shown. The saved switch changes only its look, so it stays clickable.
function ns.RefreshHearthPin()
	if not hearthPins then
		return
	end
	-- The map, the journey or the bind point changed: the next hover makes a fresh comparison.
	comparison = nil
	hearthPins:ReleaseAll()
	local map = WorldMapFrame
	if not (map and map:IsVisible()) then
		return
	end
	local goal = ns.JourneyGoal()
	local hearth = goal and ns.Hearthstone()
	if not (goal and hearth) then
		return
	end
	local mapID = map:GetMapID()
	if not mapID then
		return
	end
	local x, y = MapPlace(hearth, mapID)
	if x then
		hearthPins:Acquire(hearth, x, y)
	end
end

ns.Init(function()
	hearthPins = MapCanvas.Pool(WorldMapFrame, "hearth", HearthPin)
	-- The map's own open, turn and close; the bind point and the journey change through their own callers.
	MapCanvas.Watch(WorldMapFrame, function(_, what)
		if what == "show" or what == "map" or what == "hide" then
			ns.RefreshHearthPin()
		end
	end)
	hooksecurefunc(ns, "JourneyChanged", function()
		ns.RefreshHearthPin()
	end) -- taint-ok: ns is this addon's own namespace table.
end)

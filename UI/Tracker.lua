---@class SPFNamespace
local ns = select(2, ...)
local L = ns.L

---@type SPFTracker
local module
---@class SPFTracker : SPFTrackerModule
---@field journeyTracker? boolean
---@field metres? boolean
---@field riding? number|false
---@field second number
---@field journeyVersion? number
---@field familyVersion? integer
---@field sightingVersion? number
---@field tracker? boolean
---@field otherFaction? boolean
---@field dockID? number
---@field section string
---@field Spinner Frame
---@field mapDock? number
---@field blocks {key: number|string, title: string, rows: SPFRow[]}[]
local ModuleMixin = { headerText = L["Boats"] }
local HEADER = { boat = L["Boats"], zeppelin = L["Boats"], lift = L["Lifts"], tram = L["Deeprun Tram"] }

-- The shared host builds every section header's menu (UI/TrackerHost.lua) and this addon's departures option is not
-- its business, so the one menu opener it calls is decorated here: a section showing departures also offers to hide
-- them. The host's own attach and lock entries are built first and stay as they are.
local function HasDepartures()
	return module ~= nil and (module.dockID ~= nil or module.riding ~= nil)
end

local function HideDepartures()
	ns.SetOption("tracker", false)
end

local openMenu = ns.ContextMenu
if type(openMenu) == "function" then
	---@diagnostic disable-next-line: duplicate-set-field -- the host calls this field; the wrapper adds one entry
	ns.ContextMenu = function(owner, generator)
		return openMenu(owner, function(menuOwner, root)
			generator(menuOwner, root)
			if HasDepartures() and module.GetContextMenuParent and owner == module:GetContextMenuParent() then
				root:CreateButton(L["Hide departures"], HideDepartures)
			end
		end)
	end
end

local function OpenDockMap(dockID)
	local location = dockID and ns.DockLocation(dockID)
	ns.OpenWorldMap(location and location.uiMap)
end

function ModuleMixin:OnBlockHeaderClick(block, button)
	if block.id == "journey" then
		if button == "LeftButton" then
			ns.ToggleJourneyGuide()
		elseif button == "RightButton" then
			ns.ContextMenu(block, function(_, root)
				root:CreateCheckbox(L["Guide me"], ns.IsJourneyGuided, ns.ToggleJourneyGuide)
				root:CreateButton(L["Show on map"], ns.ShowJourneyMap)
				root:CreateButton(L["Resume RestedXP guide"], function()
					ns.ResumeRestedXP()
				end)
				if GuidelimeArrow then
					root:CreateButton(L["Resume Guidelime guide"], function()
						ns.ResumeGuidelime()
					end)
				end
				-- A corpse run ends only when you live again.
				if not ns.Corpse.Active() then
					root:CreateButton(L["Clear journey"], ns.ClearJourney)
				end
				-- The shared column can be dragged anywhere once it is let go of the quest tracker (also in Settings). The
				-- host switches only out of combat, so in combat the entry is left out rather than seeming to do nothing.
				local host = ns.TrackerHost
				if host and host.SetAttached and host.IsAttachedToQuestTracker and not InCombatLockdown() then
					root:CreateCheckbox(L["Attach to quest tracker"], host.IsAttachedToQuestTracker, function()
						host.SetAttached(not host.IsAttachedToQuestTracker())
					end)
				end
			end)
		end
	elseif block.id == "family" then
		if button == "LeftButton" then
			ns.FamilyHints.OpenFooter()
		end
	elseif button == "LeftButton" then
		OpenDockMap(self.mapDock)
	end
end

local function DepartureText(departure)
	local text = ns.DockLabel(departure.to[1]) .. "   " .. ns.Timetable.Status(departure)
	return departure.known and text or GRAY_FONT_COLOR:WrapTextInColorCode(text)
end

local function RowColor(row)
	return row.warning and RED_FONT_COLOR
		or row.grey and GRAY_FONT_COLOR
		or row.current and OBJECTIVE_TRACKER_COLOR.NormalHighlight
		or OBJECTIVE_TRACKER_COLOR.Normal
end

-- The tracker's line font is 12 high, and a row's mark is drawn at that height so it never grows the line. Markup
-- takes whole pixels, so each mark keeps its atlas's native shape within WFA-27's 2%.
local ICON_SIZE = 12
-- SPF's own line template (UI/Tracker.xml), so its pooled lines never come from, or return to, the stock template
-- every other tracker module shares.
local LINE_TEMPLATE = "ShortestPathForeverTrackerLineTemplate"

---@param color colorRGBA
---@param text string
---@return string
local function ColorText(color, text)
	return CreateColor(color.r, color.g, color.b):WrapTextInColorCode(text)
end

-- The place in a step's own sentence, as the tracker's header colours it.
---@param place string
---@return string
local function HeaderPlace(place)
	return ColorText(OBJECTIVE_TRACKER_COLOR.Header, place)
end

-- The mark a row leads with: a teleport's own item or spell icon, else its mode's client art.
---@param row SPFRow
---@return string?
local function RowMark(row)
	return (row.icon and ns.Art.FileMarkup(row.icon, ICON_SIZE))
		or (row.mode and ns.Art.ModeMarkup(row.mode, ICON_SIZE))
end

-- A leg's line: the verb in the row's colour, the place already wrapped by JourneyInfo, and the time in its grey
-- (GRAY_FONT_COLOR). JourneyInfo's plain text stays for the goal pin's tooltip and other addons.
---@param row SPFRow
---@return string
local function LegText(row)
	local text = row.action or row.text
	if row.time then
		text = text .. "   " .. ColorText(GRAY_FONT_COLOR, row.time)
	end
	return text
end

-- The stock line anchors its text to the dash's right edge, so the dash is the line's indent. HIDE hides the dash but
-- keeps its width, which can only indent every line by the dash itself; the client's waypoint line draws its icon in
-- that column and hangs the text after it (QuestObjectiveWaypointLineTemplate). A leg's mark stands there instead of
-- the dash, so the text and every wrapped line hang after it; a note keeps the stock dash.
-- Only SPF's own lines use its template, so the dash text is SPF's to compare and rewrite. AddObjective rewrites it
-- only when a line's dash style changes, which would leave an old mark on a reused line.
---@param line SPFTrackerLine
---@param mark string?
local function SetLineMark(line, mark)
	if not line.Dash then
		return
	end
	local text = mark and (mark .. " ") or QUEST_DASH
	if line.Dash:GetText() ~= text then
		line.Dash:SetText(text)
	end
	line.Dash:Show()
end

-- The journey's title, led by the goal's own pin as the map and the on-screen marker wear it (UI/StopPin.lua,
-- UI/DestinationPin.lua). A corpse run keeps its own title without a pin.
---@param title string
---@return string
local function JourneyTitle(title)
	if ns.Corpse.Active() then
		return title
	end
	return ns.Art.FileMarkup(ns.GoalPinFile(), ICON_SIZE) .. " " .. title
end

local PULSE_SECONDS, PULSE_DIM = 1.6, 0.35

local function StopPulse(line)
	if line.spfPulse then
		line.spfPulse:Stop()
	end
end

local function SetPulse(line, pulsing)
	if not pulsing then
		StopPulse(line)
		return
	end
	if not line.spfPulse then
		local animation = line.Text:CreateAnimationGroup()
		animation:SetLooping("BOUNCE")
		local alpha = animation:CreateAnimation("Alpha")
		alpha:SetFromAlpha(1)
		alpha:SetToAlpha(PULSE_DIM)
		alpha:SetDuration(PULSE_SECONDS)
		alpha:SetSmoothing("IN_OUT")
		line.spfPulse = animation
		line:HookScript("OnHide", StopPulse)
	end
	if not line.spfPulse:IsPlaying() then
		line.spfPulse:Play()
	end
end

function ModuleMixin:LayoutContents()
	for _, entry in ipairs(self.blocks) do
		local block = self:GetBlock(entry.key)
		block:SetHeader(entry.title)
		block.headerHeight = block.HeaderText:GetHeight()
		for _, row in ipairs(entry.rows) do
			local line = block:AddObjective(row.key, row.text, nil, true, nil, RowColor(row))
			SetLineMark(line, RowMark(row))
			SetPulse(line, row.warning == true)
			local family = entry.key == "family"
			local clickable = family or entry.key == "journey" and row.current and not ns.Corpse.Active()
			line:EnableMouse(clickable == true)
			line:SetScript("OnMouseUp", clickable and function(_, button)
				if button ~= "LeftButton" then
					return
				elseif family then
					ns.FamilyHints.OpenFooter()
					return
				end
				ns.ContextMenu(line, function(_, root)
					root:CreateButton(L["Complete this step"], function()
						local index = row.key
						if type(index) == "number" then
							ns.SkipJourneyStep(index)
						end
					end)
				end)
			end or nil)
		end
		if not self:LayoutBlock(block) then
			return
		end
	end
end

-- Waiting at a dock: its departures, one line per destination.
local function DockRows(dockID)
	local departures = ns.Timetable.ByDestination(dockID)
	local rows = {}
	for _, departure in ipairs(departures) do
		rows[#rows + 1] = { key = departure.route, text = DepartureText(departure) }
	end
	return rows, departures[1] and departures[1].kind
end

-- On board, out of sight of any dock: where the boat calls next.
local function RideRows(routeID)
	local dockID, arriveIn = ns.Timetable.NextStop(routeID)
	if not dockID or not arriveIn then
		return nil
	end
	local kind = ns.Routes[routeID].kind
	local text = string.format(L["arrives %s"], ns.FormatCountdown(arriveIn))
	return { { key = routeID, text = text } }, kind, dockID
end

-- The yards left along the journey's legs, kept until the journey or its route changes. The tracker's header and
-- the destination pin's tooltip (StopPin.lua) both read it.
---@type SPFDistanceCache?
local distanceCache

local function JourneyDistance(result, index)
	local cache = distanceCache
	if not cache or cache.result ~= result or cache.version ~= ns.journeyVersion then
		cache = { result = result, version = ns.journeyVersion, legs = {} }
		local total = 0
		for legIndex = #result.legs, index, -1 do
			local leg = result.legs[legIndex]
			local points = ns.PlanContext.LegPoints(leg)
			local after, lengths = {}, {}
			local yards = 0
			for pointIndex = #points, 1, -1 do
				local a, b = points[pointIndex], points[pointIndex + 1]
				local length = 0
				-- Loading screens and portals connect unrelated world coordinates, not walkable yards.
				if b and a.map == b.map and not a.jump and leg.mode ~= "portal" then
					length = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
				end
				yards = yards + length
				after[pointIndex], lengths[pointIndex] = yards, length
			end
			cache.legs[legIndex] = { points = points, after = after, lengths = lengths, yards = yards, later = total }
			total = total + yards
		end
		distanceCache = cache
	end
	local leg, path = result.legs[index], cache.legs[index]
	if not path then
		return 0
	end
	local yards = path.yards
	local active = leg.mode == "walk"
		or leg.aboard
		or (leg.route and ns.CurrentRide() == leg.route)
		or (leg.mode == "flight" and UnitOnTaxi("player"))
	if active and leg.mode ~= "portal" then
		local x, y, _, map = ns.JourneyPosition()
		local nearest
		for pointIndex, a in ipairs(path.points) do
			if x and map == a.map then
				local b, length = path.points[pointIndex + 1], path.lengths[pointIndex]
				local t, px, py = 0, a.x, a.y
				if length > 0 then
					local dx, dy = b.x - a.x, b.y - a.y
					t = math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / length ^ 2))
					px, py = a.x + t * dx, a.y + t * dy
				end
				local off = (x - px) ^ 2 + (y - py) ^ 2
				if not nearest or off < nearest then
					nearest = off
					yards = path.after[pointIndex] - t * length
					if leg.mode == "walk" then
						yards = yards + math.sqrt(off)
					end
				end
			end
		end
	end
	return math.max(0, yards + path.later)
end

-- The time and distance left, as the tracker's header shows them; nil while the journey is still being planned.
---@return string? time, string? distance
local function JourneyLeft(result, index, loading)
	if not result or loading then
		distanceCache = nil
		return nil
	end
	local distance = ns.FormatDistance(JourneyDistance(result, index), true)
	return ns.FormatCountdown(ns.JourneyTime(result.legs, index)), distance
end

---@return string? time, string? distance
function ns.JourneyLeft()
	local _, _, result, index, loading = ns.JourneyInfo()
	return JourneyLeft(result, index, loading)
end

local function JourneyHeader(result, index, loading)
	local time, distance = JourneyLeft(result, index, loading)
	if not time then
		return L["Journey"]
	end
	return string.format(L["Journey  %s · %s"], time, distance)
end

local function RefreshBlockText(blocks)
	-- Countdown ticks reuse Blizzard's lines; only a row that outgrows its line needs a new layout. A row whose
	-- timer sits at the wrapping width would otherwise gain and lose a line each second and shake the column.
	local resized = false
	for _, entry in ipairs(blocks) do
		local block = module:GetExistingBlock(entry.key)
		if block and block.used then
			if block.HeaderText:GetText() ~= entry.title then
				local height = block:SetStringText(
					block.HeaderText,
					entry.title,
					nil,
					OBJECTIVE_TRACKER_COLOR.Header,
					block.isHighlighted
				)
				resized = resized or height ~= block.headerHeight
				block.headerHeight = height
			end
			for _, row in ipairs(entry.rows) do
				local line = block:GetExistingLine(row.key)
				if line and line.used then
					if line.Text:GetText() ~= row.text then
						local height =
							block:SetStringText(line.Text, row.text, true, RowColor(row), block.isHighlighted)
						resized = resized or height > line:GetHeight() + 0.5
					end
					SetLineMark(line, RowMark(row))
				end
			end
		end
	end
	if resized then
		module:MarkDirty()
	end
end

local function RefreshTracker(dockID, yards)
	if not module or InCombatLockdown() then
		return
	end
	local rows, kind, title, blockKey, mapDock
	if ns.db.tracker then
		local radius = module.dockID and 160 or 120
		if not yards or yards > radius then
			dockID = nil
		end
	else
		dockID = nil
	end
	local riding = ns.db.tracker and ns.CurrentRide()
	local journey = ns.HasJourney() and ns.db.journeyTracker ~= false
	local second = (dockID or riding or journey) and math.floor(GetTime()) or 0
	-- After a journey arrives, Hints.Footer (UI/FamilyHints.lua) may add a grey line under it.
	local familyBlock = ns.FamilyHints.Footer()
	-- Compare scalar render inputs before allocating blocks or formatting rows. Unrelated tracker
	-- layouts can replay the saved blocks; they never need to query timetables or rebuild the model.
	if
		module.dockID == dockID
		and module.riding == riding
		and module.second == second
		and module.journeyVersion == ns.journeyVersion
		and module.familyVersion == ns.FamilyHints.Version()
		and module.sightingVersion == ns.Timetable.Version()
		and module.tracker == ns.db.tracker
		and module.otherFaction == ns.db.otherFaction
		and module.journeyTracker == ns.db.journeyTracker
		and module.metres == ns.db.metres
	then
		return
	end
	module.riding, module.second = riding, second
	module.journeyVersion, module.sightingVersion = ns.journeyVersion, ns.Timetable.Version()
	module.familyVersion = ns.FamilyHints.Version()
	module.tracker, module.otherFaction = ns.db.tracker, ns.db.otherFaction
	module.journeyTracker, module.metres = ns.db.journeyTracker, ns.db.metres
	if dockID then
		rows, kind = DockRows(dockID)
		title, blockKey, mapDock = ns.DockTitle(dockID), "dock" .. dockID, dockID
	elseif riding then
		rows, kind, mapDock = RideRows(riding)
		if rows and mapDock then
			title, blockKey = string.format(L["On board to %s"], ns.DockTitle(mapDock)), "ride" .. mapDock
		end
	end
	local blocks = {}
	local journeyTitle, journeyRows, journeyResult, journeyIndex, loading = ns.JourneyInfo(HeaderPlace)
	if not journey then
		journeyTitle = nil
	end
	if journeyTitle then
		for _, row in ipairs(journeyRows or {}) do
			if row.mode then
				row.text = LegText(row)
			end
		end
		blocks[#blocks + 1] = { key = "journey", title = JourneyTitle(journeyTitle), rows = journeyRows }
	elseif familyBlock then
		blocks[#blocks + 1] = familyBlock
	end
	if blockKey then
		blocks[#blocks + 1] = { key = blockKey, title = title, rows = rows }
	end
	module.dockID, module.mapDock = dockID, mapDock
	local section = journeyTitle and L["Journey"]
		or kind and HEADER[kind]
		or familyBlock and L["Journey"]
		or ModuleMixin.headerText
	local header = journeyTitle and JourneyHeader(journeyResult, journeyIndex, loading) or section
	if not journeyTitle then
		distanceCache = nil
	end
	-- The section's identity affects layout; its live totals only change the header's single text line.
	local changed = #blocks ~= #module.blocks or section ~= module.section
	module.section = section
	for index, entry in ipairs(blocks) do
		local previous = module.blocks[index]
		if not previous or entry.key ~= previous.key or #entry.rows ~= #previous.rows then
			changed = true
		else
			for rowIndex, row in ipairs(entry.rows) do
				local old = previous.rows[rowIndex]
				changed = changed or row.key ~= old.key or row.current ~= old.current
			end
		end
	end
	module.blocks = blocks
	if header ~= module.headerText then
		module.headerText = header
		module:SetHeader(header)
	end
	if loading then
		-- The stock header's font string has a fixed width; anchor beside its text, not that box's edge.
		module.Spinner:SetPoint("LEFT", module.Header.Text, "LEFT", module.Header.Text:GetStringWidth() + 6, 0)
	end
	module.Spinner:SetShown(loading == true)
	ns.RefreshJourneyPulse(loading == true)
	if changed then
		module:MarkDirty()
		return
	end
	if module:IsDirty() then
		return
	end
	RefreshBlockText(blocks)
end

function ns.RefreshTracker()
	RefreshTracker(ns.NearestDock())
end

local function Attach()
	ForeverTrackerHost.Attach(module)
end

ns.Init(function()
	if not (ObjectiveTrackerManager and ObjectiveTrackerFrame) then
		ns.Print(L["The objective tracker is unavailable."])
		return
	end
	local tracker =
		CreateFrame("Frame", "ShortestPathForeverObjectiveTracker", UIParent, "ObjectiveTrackerModuleTemplate")
	Mixin(tracker, ModuleMixin)
	---@cast tracker SPFTracker
	module = tracker
	module.lineTemplate = LINE_TEMPLATE
	module.blocks = {}
	-- SharedXML loads Group Finder's ring and sparks, with animation tied to the frame's visibility.
	local spinner = CreateFrame("Frame", nil, module.Header, "SpinnerTemplate")
	---@cast spinner Frame
	module.Spinner = spinner
	module.Spinner:SetSize(16, 16)
	module.Spinner:Hide()
	module.section = ModuleMixin.headerText
	module:SetHeader(ModuleMixin.headerText)
	-- Above quests, SkillUp Forever (-2) and Legacy Forever (0, -1): each needs its own slot.
	module.uiOrder = -3
	module.Header:EnableMouse(true)
	module.Header:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then
			if ns.JourneyInfo() then
				ns.ToggleJourneyGuide()
			elseif not module.mapDock and module.blocks[1] and module.blocks[1].key == "family" then
				ns.FamilyHints.OpenFooter()
			else
				OpenDockMap(module.mapDock)
			end
		end
	end)
	EventUtil.ContinueAfterAllEvents(function()
		C_Timer.After(0, Attach)
	end, "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED")
	Attach()
	ns.Timetable.OnChange(ns.RefreshTracker)
	ns.OnTravelTick(RefreshTracker)
	ns.RefreshTracker()
end)

---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- Guide follows the map's walking path bend by bend, whatever the map marks. Journey places Blizzard's native
-- navigation marker at that bend; with "Mark only where steps end" on it places none, since one marker cannot lead
-- round the walk's bends, and this arrow leads instead. The arrow is also the fallback when the marker is unavailable
-- or the player owns tracking. Camelot omits the navigation setting, but its native super-tracked marker does work
-- while its CVar is on.

-- Polled this often while still; every frame while you move or turn, and while the arrow eases round.
local POLL_EVERY = 0.1
-- How fast the arrow swings to a new bearing, as the compass eases its heading (Compass.lua), and when it has settled.
local TURN, EASE, SETTLED = 2 * math.pi, 18, 0.001
-- The native marker's arrow sits this far from its icon.
local RADIUS = 36
-- The arrow turns around the next step's marker at its native 64 pixels, 32 units, inside the arrow's 36-unit orbit;
-- an arrived stop's goal pin is the pin's own square 36.
local ICON_SIZE, STEP_SIZE = 36, 32
-- A bend this close counts as passed, and the arrow turns to the next one.
local PASSED = 25
-- The stock place, under the top of the screen; the cast prompt stands there too.
local TOP = -120
-- The stop's title and objective lines beneath the pin, wrapped and capped so they stay a summary. The arrow's own
-- lines under the distance use the same cap, so the two surfaces say the same few things.
local ARRIVAL_WIDTH, ARRIVAL_TITLE_LINES, ARRIVAL_LINE_LIMIT = 240, 2, 3
---@class SPFArrowFrame : Frame
---@field Icon Texture
---@field iconFile? string the art drawn at the centre, so it is only reset when the step changes
---@field Arrow Texture
---@field Distance FontString
---@field Progress FontString
---@field Lines FontString
---@field ArrivalTitle FontString
---@field ArrivalLines FontString
---@field linesFor? SPFPoint the goal the travel lines were built from
---@field linesDirty? boolean the next draw reads the quest log again
---@field linesOff? boolean the travel lines are cleared by the switch
---@field arrivalFor? SPFPoint the stop the arrival lines were built from
---@field arrivalText? string the arrival lines already joined for the pin
---@field arrival? boolean the arrived stop's pin and lines show, with the arrow and distance hidden
---@field behind boolean
---@field Mover Texture
---@field MoverHint FontString
---@field metres? boolean
---@field yards? number
---@field label? string the text last shown under the arrow
---@field labelAt? number the second the time in that label was read
---@field labelMode? string the arrowLabel setting it was built for
---@field angle? number the bearing drawn, easing towards the true one
---@field ticker? FunctionContainer
---@field updating? boolean
---@field idle number
---@field x? number
---@field y? number
---@field map? number
---@field facing? number
---@type SPFArrowFrame
local frame
local source, path, index, target, placeTarget, native
local stepEnd, destination
local revision = 0
local moving = false
local OnUpdate
---@type SPFCastPromptFrame?
local castPrompt
-- The stop whose area the player is in, drawn as a pin with what to do there (#627).
---@type SPFPoint?
local arrival
local ShowArrival, RefreshTravelLines

-- Guidance changes that are not a new journey stop or leg: a bend passed, the source walk replaced, or the
-- guideStops setting collapsing what the arrow draws. Core/API.lua turns it into the public Subscribe notice.
local function NotifyGuidance()
	if ns.GuideGuidanceChanged then
		ns.GuideGuidanceChanged()
	end
end

-- Counter-clockwise from north, like GetPlayerFacing: UnitPosition's first value grows north, its second west.
local function Bearing(x, y)
	return math.atan2(target.y - y, target.x - x)
end

-- The shorter way round from a to b, between -pi and pi.
local function Difference(b, a)
	return (b - a + math.pi) % TURN - math.pi
end

-- Whether the game draws its marker. With showInGameNavigation off, which Camelot gives no setting for, the client
-- still has a navigation frame but keeps the marker at no alpha, so the arrow has to lead.
local function NativeMarkerShown()
	return C_Navigation.GetFrame() ~= nil and GetCVarBool("showInGameNavigation")
end

local function Draw(angle)
	frame.Arrow:SetRotation(angle)
	frame.Arrow:SetPoint("CENTER", frame.Icon, "CENTER", -math.sin(angle) * RADIUS, math.cos(angle) * RADIUS)
end

-- The arrow turns around the step it is walking to, wearing that step's numbered marker, the same art the compass
-- shows for it. A target with no step number (a corpse run, a leg with no stop) wears ForeverCore's ring and diamond
-- (#817).
local function StepIcon()
	local file = (stepEnd and ns.NumberFile(stepEnd.number)) or ForeverCore.Art.Diamond()
	if frame.iconFile ~= file then
		frame.iconFile = file
		ns.Art.Icon(frame.Icon, file, STEP_SIZE)
	end
end

-- What the label under the arrow says: the distance to walk, the journey's time left as the tracker's header gives it,
-- or both, time first. Until the journey has a time, every choice shows the distance.
---@param yards number
---@param mode? string
---@return string
local function ArrowLabel(yards, mode)
	local distance = ns.FormatDistance(yards)
	if mode == "time" or mode == "both" then
		local time = ns.JourneyLeft and ns.JourneyLeft()
		if time then
			if mode == "time" then
				return time
			end
			return string.format(L["%s · %s"], time, distance)
		end
	end
	return distance
end

local function SetUpdating(running)
	if frame.updating ~= running then
		frame.updating = running
		frame:SetScript("OnUpdate", running and OnUpdate or nil)
	end
end

-- Every frame while you move or turn and while the arrow eases; once still for a moment, only the slow poll runs.
local function Settle(elapsed, easing, moved)
	frame.idle = moved and 0 or frame.idle + elapsed
	SetUpdating(easing or frame.idle < 0.15)
end

---@param elapsed number seconds since the last update
local function Update(elapsed)
	-- Arrived: the pin stands until the player leaves the stop's area, then the arrow or nothing takes over.
	if arrival then
		if ns.StopInside and not ns.StopInside(arrival) then
			ns.PointArrivalPin(nil)
			return
		end
		frame.behind = false
		frame:SetAlpha(1)
		frame.angle = nil
		SetUpdating(false)
		return
	end
	-- The client may already have queued this tick when another callback stopped guidance.
	if not path or not target then
		frame.behind = false
		SetUpdating(false)
		return
	end
	StepIcon()
	local updating = revision
	local x, y, _, map = ns.JourneyPosition()
	local facing = GetPlayerFacing()
	if not x or not canaccessvalue(facing) then
		-- No position to point from (an instance): nothing drawn, only the slow poll runs.
		frame.behind = false
		frame:SetAlpha(moving and 1 or 0)
		frame.angle = nil
		SetUpdating(false)
		return
	end
	local moved = x ~= frame.x or y ~= frame.y or map ~= frame.map or facing ~= frame.facing
	frame.x, frame.y, frame.map, frame.facing = x, y, map, facing
	ns.AdvanceGuide()
	-- The guide places its native marker at this bend, unless "Mark only where steps end" keeps it off the walk.
	local placed = placeTarget and placeTarget(target, false)
	-- Waypoint callbacks can stop or replace guidance synchronously.
	if revision ~= updating then
		return
	end
	native = placed
	if not (facing and map == target.map) or (native and NativeMarkerShown()) then
		-- The native marker leads; nothing to draw, so only the slow poll runs, moving or not.
		frame.behind = false
		frame:SetAlpha(moving and 1 or 0)
		frame.angle = nil
		SetUpdating(false)
		return
	end
	local angle = Difference(Bearing(x, y), facing)
	-- The arrow still points the way, and dims with the compass when that way is behind you.
	frame.behind = ns.TurnAround.Behind(angle, frame.behind)
	frame:SetAlpha(frame.behind and ns.BEHIND_ALPHA or 1)
	-- Exponential decay is frame-rate independent and swings by the shortest arc.
	local delta = frame.angle and Difference(angle, frame.angle) or 0
	local easing = math.abs(delta) > SETTLED
	frame.angle = easing and (frame.angle + delta * (1 - math.exp(-EASE * elapsed))) % TURN or angle
	Draw(frame.angle)
	-- The distance still to walk: to this bend, then along the rest of the path.
	local distance = math.sqrt((target.x - x) ^ 2 + (target.y - y) ^ 2)
	for i = index + 1, #path do
		distance = distance + math.sqrt((path[i].x - path[i - 1].x) ^ 2 + (path[i].y - path[i - 1].y) ^ 2)
	end
	local yards = math.floor(distance)
	local mode = ns.db.arrowLabel
	-- The time counts down every second while the distance may not move, so read it with the header's own tick. The
	-- final label is cached as a whole, and only written when it changes.
	local timed = mode == "time" or mode == "both"
	local second = timed and math.floor(GetTime()) or nil
	if
		yards ~= frame.yards
		or frame.metres ~= ns.db.metres
		or frame.labelMode ~= mode
		or (second and second ~= frame.labelAt)
	then
		frame.metres = ns.db.metres
		frame.yards = yards
		frame.labelMode = mode
		frame.labelAt = second
		local text = ArrowLabel(yards, mode)
		if text ~= frame.label then
			frame.label = text
			frame.Distance:SetText(text)
		end
	end
	RefreshTravelLines(destination)
	Settle(elapsed, easing, moved)
end

OnUpdate = function(_, elapsed)
	Update(elapsed)
end

local function Poll()
	-- Mouse turns and moving transports need not send a player movement event.
	if not frame.updating then
		Update(POLL_EVERY)
	end
end

local function Wake()
	frame.idle = 0
	SetUpdating(true)
end

-- Where it was dragged (screen pixels from the bottom left), else the stock place under the top of the screen.
---@param placed Frame
local function Anchor(placed)
	local scale = placed:GetEffectiveScale() / UIParent:GetEffectiveScale()
	scale = scale > 0 and scale or 1
	placed:ClearAllPoints()
	local x, y = ns.db.arrowX, ns.db.arrowY
	if type(x) == "number" and type(y) == "number" then
		placed:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	else
		placed:SetPoint("TOP", UIParent, "TOP", 0, TOP / scale)
	end
end

local function Create()
	local arrow = CreateFrame("Frame", nil, UIParent)
	---@cast arrow SPFArrowFrame
	frame = arrow
	frame.idle = 0
	frame:SetSize(100, 100)
	frame:SetScale((ns.db.arrowScale or 100) / 100)
	frame:SetClampedToScreen(true)
	Anchor(frame)
	frame:SetFrameStrata("BACKGROUND")
	-- Drag to move, Shift-drag for fine placing (Mover.lua); right-click puts it back.
	ns.Mover.Attach(frame, function()
		local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local x, y = frame:GetCenter()
		ns.db.arrowX, ns.db.arrowY = x * scale, y * scale
		Anchor(frame)
	end)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then
			ns.db.arrowX, ns.db.arrowY = nil, nil
			Anchor(frame)
		end
	end)
	-- Click-through until it is being placed. Last: the client turns a frame's mouse on when it is given a mouse
	-- script or registered for drag.
	frame:EnableMouse(false)
	frame.Mover = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
	frame.Mover:SetAllPoints()
	frame.Mover:SetColorTexture(0, 0, 0, 0.5)
	frame.Mover:Hide()
	frame.MoverHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.MoverHint:SetPoint("TOP", frame, "BOTTOM", 0, -2)
	frame.MoverHint:SetText(L["Drag to move; Shift-drag or the arrow keys to nudge. Right-click to reset."])
	frame.MoverHint:Hide()
	frame.Icon = frame:CreateTexture(nil, "BACKGROUND")
	-- The next step's numbered marker, or ForeverCore's ring and diamond while it has no number, square at its size.
	frame.iconFile = ForeverCore.Art.Diamond()
	ns.Art.Icon(frame.Icon, frame.iconFile, STEP_SIZE)
	frame.Icon:SetPoint("CENTER")
	frame.Arrow = frame:CreateTexture(nil, "BACKGROUND")
	frame.Arrow:SetAtlas("Navigation-Tracked-Arrow", true)
	Draw(0)
	frame.Distance = frame:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
	frame.Distance:SetPoint("TOP", frame.Icon, "BOTTOM", 0, -8)
	frame.Progress = frame:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
	frame.Progress:SetPoint("TOP", frame.Distance, "BOTTOM", 0, -4)
	-- The same lines the arrival pin shows, under the distance while the arrow leads to the stop.
	frame.Lines = frame:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
	frame.Lines:SetPoint("TOP", frame.Progress, "BOTTOM", 0, -4)
	frame.Lines:SetWidth(ARRIVAL_WIDTH)
	frame.Lines:SetJustifyH("CENTER")
	frame.Lines:SetWordWrap(true)
	frame.Lines:SetMaxLines(ARRIVAL_LINE_LIMIT)
	frame.Lines:Hide()
	frame.ArrivalTitle = frame:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
	frame.ArrivalTitle:SetPoint("TOP", frame.Icon, "BOTTOM", 0, -8)
	frame.ArrivalTitle:SetWidth(ARRIVAL_WIDTH)
	frame.ArrivalTitle:SetJustifyH("CENTER")
	frame.ArrivalTitle:SetWordWrap(true)
	frame.ArrivalTitle:SetMaxLines(ARRIVAL_TITLE_LINES)
	frame.ArrivalTitle:Hide()
	frame.ArrivalLines = frame:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
	frame.ArrivalLines:SetPoint("TOP", frame.ArrivalTitle, "BOTTOM", 0, -4)
	frame.ArrivalLines:SetWidth(ARRIVAL_WIDTH)
	frame.ArrivalLines:SetJustifyH("CENTER")
	frame.ArrivalLines:SetWordWrap(true)
	frame.ArrivalLines:SetMaxLines(ARRIVAL_LINE_LIMIT)
	frame.ArrivalLines:Hide()
	frame:SetScript("OnShow", function()
		frame.ticker = C_Timer.NewTicker(POLL_EVERY, Poll)
		frame:RegisterEvent("PLAYER_STARTED_MOVING")
		frame:RegisterEvent("PLAYER_STARTED_TURNING")
		-- Objectives are live: the client's quest log changes the lines under the arrow and the pin.
		frame:RegisterEvent("QUEST_LOG_UPDATE")
		frame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
		Wake()
	end)
	frame:SetScript("OnHide", function()
		SetUpdating(false)
		if frame.ticker then
			frame.ticker:Cancel()
			frame.ticker = nil
		end
		frame:UnregisterAllEvents()
		frame.angle = nil
		frame.behind = false
	end)
	frame:SetScript("OnEvent", function(_, event)
		if event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
			frame.linesDirty = true
			if arrival then
				ShowArrival(arrival)
			elseif destination then
				RefreshTravelLines(destination)
			end
		end
		Wake()
	end)
	-- Made hidden, so the first Show starts the poll and the movement events.
	frame:Hide()
end

-- The pin, title and lines only while the player stands in the arrived stop's area; the arrow otherwise.
---@param lines? string[]
---@return string
local function Joined(lines)
	if not (lines and lines[1]) then
		return ""
	end
	local shown = {}
	for line = 1, math.min(#lines, ARRIVAL_LINE_LIMIT) do
		shown[line] = lines[line]
	end
	return table.concat(shown, "\n")
end

---@param stop SPFPoint
ShowArrival = function(stop)
	if not frame.arrival then
		frame.arrival = true
		frame.Arrow:Hide()
		frame.Distance:Hide()
		frame.Progress:Hide()
		frame.Lines:Hide()
		-- The same gold goal pin the compass Goal marker and the map draw: arriving puts only the arrow, distance
		-- and progress away, leaving the pin at its normal size.
		frame.iconFile = ns.PIN_FILE
		ns.Art.Icon(frame.Icon, ns.PIN_FILE, ICON_SIZE)
		frame.ArrivalTitle:Show()
		frame.ArrivalLines:Show()
	end
	local title = stop.routeTitle or stop.label or (ns.JourneyTitle and ns.JourneyTitle(stop)) or ""
	if frame.ArrivalTitle:GetText() ~= title then
		frame.ArrivalTitle:SetText(title)
	end
	-- The quest log is read only when the stop or the log changed, not on every tick the pin stands.
	if frame.arrivalFor ~= stop or frame.linesDirty then
		frame.arrivalFor, frame.linesDirty = stop, nil
		frame.arrivalText = Joined(ns.StopObjectiveLines and ns.StopObjectiveLines(stop) or nil)
	end
	local text = frame.arrivalText or ""
	if frame.ArrivalLines:GetText() ~= text then
		frame.ArrivalLines:SetText(text)
	end
	frame.ArrivalLines:SetShown(text ~= "")
end

-- The same lines under the distance while the arrow leads, read again only when the goal or the quest log changes.
---@param goal SPFPoint?
RefreshTravelLines = function(goal)
	if not frame then
		return
	end
	-- The switch hides the stop's objectives under the arrow without touching the arrival pin's own lines.
	if ns.db.arrowObjectives == false then
		frame.linesFor, frame.linesDirty = nil, nil
		if not frame.linesOff then
			frame.linesOff = true
			frame.Lines:SetText("")
			frame.Lines:Hide()
		end
		return
	end
	frame.linesOff = nil
	if frame.linesFor == goal and not frame.linesDirty then
		return
	end
	frame.linesFor, frame.linesDirty = goal, nil
	local text = Joined(ns.StopObjectiveLines and ns.StopObjectiveLines(goal) or nil)
	if frame.Lines:GetText() ~= text then
		frame.Lines:SetText(text)
	end
	frame.Lines:SetShown(text ~= "")
end

-- A guide's step at the same place now stands for other quests: read the lines again without replanning.
function ns.RefreshArrowLines()
	if not frame then
		return
	end
	frame.linesDirty = true
	if arrival then
		ShowArrival(arrival)
	else
		RefreshTravelLines(destination)
		Wake()
	end
end

-- Settings: the travel lines go or come back at once, without a replan. The arrival pin keeps its own lines.
function ns.ArrowObjectivesChanged()
	if not frame then
		return
	end
	frame.linesDirty = true
	RefreshTravelLines(destination)
end

-- Back to the direction arrow, whichever of an arrival, a new stop or leaving the area ended the stop.
local function RestoreArrow()
	if not (frame and frame.arrival) then
		return
	end
	frame.arrival = nil
	-- Back to the step the journey is walking to: its numbered marker, or the ring and diamond while it has no number.
	frame.iconFile = nil
	StepIcon()
	frame.Arrow:Show()
	frame.Distance:Show()
	frame.Progress:Show()
	frame.ArrivalTitle:Hide()
	frame.ArrivalLines:Hide()
	frame.arrivalFor, frame.arrivalText = nil, nil
	-- Leaving the pin rebuilds the travelling lines, whose own stop may have changed while the pin stood.
	frame.linesDirty = true
end

-- End the arrival state without drawing anything else.
local function EndArrival()
	if not arrival then
		return false
	end
	arrival = nil
	RestoreArrow()
	return true
end

-- The arrived stop, if any: the compass keeps its ribbon up and tints it while this is set.
---@return SPFPoint?
function ns.ArrivalStop()
	return arrival
end

-- Journey calls this when the player reaches a held stop's area, and with nil when it leaves or the stop changes.
---@param stop SPFPoint?
function ns.PointArrivalPin(stop)
	if stop and ns.db and (ns.db.arrivalPin == false or ns.db.arrow == false) then
		stop = nil
	end
	if not stop then
		if EndArrival() then
			if frame and not (path and target) then
				frame:SetShown(moving)
			end
			if ns.RefreshCompass then
				ns.RefreshCompass()
			end
		end
		return
	end
	arrival = stop
	if not frame then
		Create()
	end
	ShowArrival(stop)
	frame:Show()
	Wake()
	Update(0)
	if ns.RefreshCompass then
		ns.RefreshCompass()
	end
end

-- Settings: turning the arrival pin off returns a paused guide to the old hide, at once.
function ns.ArrivalPinChanged()
	if not (ns.db and ns.db.arrivalPin) then
		ns.PointArrivalPin(nil)
	end
end

-- Advance the bend under way from where the player stands. This is the guide's one progress step: the arrow, the
-- compass and the public API all read it, so it must not live in a renderer. It runs only from an existing tick or a
-- read, never from a timer of its own.
---@return boolean advanced
function ns.AdvanceGuide()
	if not (path and target) then
		return false
	end
	local x, y, _, map = ns.JourneyPosition()
	if not (x and y) then
		return false
	end
	local advanced = false
	while index < #path and map == target.map and (target.x - x) ^ 2 + (target.y - y) ^ 2 <= PASSED ^ 2 do
		index = index + 1
		target = path[index]
		advanced = true
	end
	if advanced then
		NotifyGuidance()
	end
	return advanced
end

-- Guide follows the walk bend by bend. "Mark only where steps end" thins only the point the map marks, never the
-- walk the arrow follows.
function ns.RefreshGuideStops()
	revision = revision + 1
	local previousPath, previousTarget = path, target
	path = source
	index = 1
	local x, y, _, map = ns.JourneyPosition()
	local nearest
	-- Guide may be restarted halfway along a walk: it resumes at the nearest bend.
	for i = 2, #(path or {}) do
		local a, b = path[i - 1], path[i]
		local dx, dy = b.x - a.x, b.y - a.y
		local length = dx * dx + dy * dy
		if x and map == a.map and map == b.map then
			local t = length > 0 and math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / length)) or 0
			local off = (a.x + t * dx - x) ^ 2 + (a.y + t * dy - y) ^ 2
			if not nearest or off < nearest then
				index, nearest = i, off
			end
		end
	end
	target = path and path[index]
	if path ~= previousPath or target ~= previousTarget then
		NotifyGuidance()
	end
end

-- Settings: "Mark only where steps end" swaps which pointer leads, so the arrow and the guide's own marker change
-- over at once rather than at the next poll.
function ns.GuideStopsChanged()
	ns.RefreshGuideStops()
	if frame then
		Wake()
		Update(0)
	end
	if ns.RefreshCompass then
		ns.RefreshCompass()
	end
end

-- placeBend owns waypoint placement and returns whether native tracking is ours. Progress lives only here.
---@param points SPFWalkPoints?
---@param placeBend? fun(point: SPFPoint, fading: boolean): boolean?
---@param stop SPFPlace?
---@param goal SPFPoint?
function ns.PointGuideArrow(points, placeBend, stop, goal)
	ns.PointCastPrompt(nil)
	-- Any new directions, or none, end an arrival pin: only the stop Journey says was reached wears it.
	EndArrival()
	revision = revision + 1
	if points and #points == 0 then
		points = nil
	end
	if points ~= source then
		source = points
		ns.RefreshGuideStops()
	end
	placeTarget = placeBend
	stepEnd, destination = stop, goal
	local updating = revision
	if ns.RefreshCompass then
		ns.RefreshCompass()
	end
	if revision ~= updating then
		return
	end
	if not points or ns.db.arrow == false then
		native = nil
		if frame then
			frame:SetShown(moving)
		end
		return
	end
	if not frame then
		Create()
	end
	frame.Progress:SetText(goal and goal.routeTitle or "")
	-- Each new leg reads the quest log again: only a leg or a quest event rebuilds the lines, never a frame.
	frame.linesDirty = true
	frame:Show()
	Wake()
	Update(0)
end

---@return boolean
function ns.ArrowMoving()
	return moving
end

-- "Move the arrow": shows the arrow over a dark box to drag, journey or not.
---@param value boolean
function ns.MoveArrow(value)
	moving = value == true
	if not frame then
		Create()
	end
	frame:EnableMouse(moving)
	frame.Mover:SetShown(moving)
	frame.MoverHint:SetShown(moving)
	if moving then
		frame:SetAlpha(1)
		frame:Show()
	elseif (not path and not arrival) or ns.db.arrow == false then
		frame:Hide()
	end
end

-- "Arrow label": a new choice reads at once, without waiting for its second or the next bend.
---@param value? string
function ns.SetArrowLabel(value)
	if type(value) == "string" then
		ns.db.arrowLabel = value
	end
	if frame then
		frame.labelAt, frame.labelMode = nil, nil
		Update(0)
	end
end

---@param value number percent
function ns.SetArrowScale(value)
	if type(value) == "number" then
		ns.db.arrowScale = value
	end
	if frame then
		frame:SetScale((ns.db.arrowScale or 100) / 100)
		Anchor(frame)
	end
	if castPrompt then
		castPrompt:SetScale((ns.db.arrowScale or 100) / 100)
	end
end

-- Read-only targets share Guide's passed bends as the map marks them: with "Mark only where steps end" on, that is
-- the step's end, which the compass marks too, while the arrow itself follows every bend. Reading them advances the
-- bend under way first, so the compass stays current even when the arrow itself is off.
function ns.GuideTargets()
	ns.AdvanceGuide()
	if path then
		if ns.db.guideStops then
			return path[#path], nil, stepEnd, destination
		end
		return target, path[index + 1], stepEnd, destination
	end
end

-- What the public guidance read copies: the target, the canonical source walk, its index in that walk, and the stop
-- and goal it leads to. guideStops changes only which point the map and compass mark, never this walk, so the index
-- always names the target in the full source. The returned points are Guide's own; Core/API.lua makes the public
-- copies.
---@return SPFPoint? target, SPFWalkPoints? source, integer? index, SPFPlace? stop, SPFPoint? goal
function ns.GuideState()
	ns.AdvanceGuide()
	if not (target and source and index) then
		return nil
	end
	local canonical = path == source and index or #source
	return target, source, canonical, stepEnd, destination
end

---@class SPFCastPromptFrame : Frame
---@field Icon Texture
---@field Action FontString
---@type SPFTeleportPlace?
local castTarget

local function RenderCastPrompt()
	if not castPrompt or not castTarget then
		return
	end
	local action, icon = ns.TeleportAction(castTarget)
	castPrompt.Action:SetText(action)
	ns.Art.Icon(castPrompt.Icon, icon or 134400, 36)
end

-- Casting needs an action rather than a bearing, shown in the arrow's usual place.
---@param teleport? SPFTeleportPlace
function ns.PointCastPrompt(teleport)
	castTarget = teleport
	if not teleport then
		if castPrompt then
			castPrompt:UnregisterAllEvents()
			castPrompt:Hide()
		end
		return
	end
	if not castPrompt then
		-- The arrow's frame first: the prompt stands in its place.
		if not frame then
			Create()
		end
		local created = CreateFrame("Frame", nil, UIParent)
		---@cast created SPFCastPromptFrame
		castPrompt = created
		created:SetSize(320, 70)
		created:SetScale((ns.db.arrowScale or 100) / 100)
		-- In the arrow's place, wherever it was dragged, and kept on screen though it is wider.
		created:SetPoint("TOP", frame, "TOP")
		created:SetClampedToScreen(true)
		created:SetFrameStrata("MEDIUM")
		created.Icon = created:CreateTexture(nil, "ARTWORK")
		created.Icon:SetPoint("TOP", created, "TOP")
		created.Action = created:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		created.Action:SetPoint("TOP", created.Icon, "BOTTOM", 0, -6)
		created.Action:SetWidth(320)
		created:SetScript("OnEvent", RenderCastPrompt)
	end
	castPrompt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	castPrompt:RegisterEvent("SPELLS_CHANGED")
	RenderCastPrompt()
	castPrompt:Show()
end

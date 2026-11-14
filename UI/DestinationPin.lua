---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Destination pin: the addon's own gold goal pin, held on screen over the journey's final
-- destination so it can be seen all the way there rather than only on the map.
--
-- The pin is placed by the bearing to the destination and the way you are facing: straight
-- ahead sits it above the middle of the screen, over your shoulder pulls it to the side, and
-- a destination behind you drops it below, fading as it goes. It only draws while a journey
-- runs and only in the zone you are in; on another map the tracker and the map carry it.
--
-- It stands down while Waypoint UI is tracking a navigation of its own: that addon's pin owns
-- the world then, and two pins on one destination is the fight #271 was about.
--
-- Under the distance it carries one short line of the current step's wording (#323), so the pin
-- says what the step is and not only how far it is; the full text of every step stays in the
-- map pin's tooltip, and the line is reread only when the step changes.

-- Pixels from the middle of the screen with the destination dead ahead.
local REACH = 150
-- How much further out a destination behind you sits, as a factor of REACH.
local BEHIND = 2
-- Alpha ahead and behind; the pin is dimmest at your back so it never competes with the fight.
local ALPHA_AHEAD, ALPHA_BEHIND = 1, ns.BEHIND_ALPHA or 0.4
-- Seconds between updates: the arrow rides the same interval, and the pin needs nothing faster.
local POLL = 0.1
local PIN_SIZE = 36

---@class SPFDestinationPinFrame : Frame
---@field Pin Texture
---@field pinFile string the goal pin art drawn now, so a tracked/untracked change repaints it
---@field Distance FontString
---@field Step FontString
---@field step string? the wording the step line shows, so it is only reset when it changes
---@field goal? SPFPoint the goal the pin was last placed for
---@field goalX? number the goal's place when it was last drawn, since a followed goal may move in place
---@field goalY? number
---@field x? number the player position it was last placed from
---@field y? number
---@field facing? number the facing it was last placed with
---@field distanceYards? number the rounded distance its text shows
---@field distanceMetres? boolean the distance setting its text was built for
---@field elapsed number
---@type SPFDestinationPinFrame?
local frame
local polling

-- Where the pin belongs, in pixels from the middle of the screen, and how strong it is.
-- bearing and facing are counter-clockwise from north, like GetPlayerFacing and the arrow.
---@param bearing number? angle to the destination
---@param facing number? the player's facing
---@param distance number? yards to the destination
---@return number? x, number? y, number? alpha
function ns.PinPlace(bearing, facing, distance)
	if type(bearing) ~= "number" or type(facing) ~= "number" or type(distance) ~= "number" then
		return nil
	end
	local angle = (bearing - facing + math.pi) % (2 * math.pi) - math.pi
	local front = math.cos(angle)
	local reach = REACH * (1 + (1 - front) * (BEHIND - 1) / 2)
	local alpha = ALPHA_BEHIND + (ALPHA_AHEAD - ALPHA_BEHIND) * (front + 1) / 2
	return -math.sin(angle) * reach, front * reach, alpha
end

---@return SPFDestinationPinFrame
local function Create()
	local pin = CreateFrame("Frame", "ShortestPathForeverDestinationPin", UIParent) --[[@as SPFDestinationPinFrame]]
	pin:SetSize(PIN_SIZE, PIN_SIZE + 28)
	pin:SetFrameStrata("MEDIUM")
	pin:SetAlpha(1)
	pin.Pin = pin:CreateTexture(nil, "ARTWORK")
	pin.Pin:SetPoint("TOP", pin, "TOP", 0, 0)
	pin.pinFile = ns.GoalPinFile()
	ns.Art.Icon(pin.Pin, pin.pinFile, PIN_SIZE)
	pin.Distance = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	pin.Distance:SetPoint("TOP", pin, "TOP", 0, -PIN_SIZE + 4)
	pin.Distance:SetJustifyH("CENTER")
	pin.Step = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pin.Step:SetPoint("TOP", pin.Distance, "BOTTOM", 0, -2)
	pin.Step:SetJustifyH("CENTER")
	pin.Step:SetWordWrap(false)
	pin.Step:SetMaxLines(1)
	pin.elapsed = 0
	pin:Hide()
	frame = pin
	return pin
end

local function Hide()
	if frame then
		frame:Hide()
	end
end

-- Whether there is anything to draw, before any of the per-frame work: a journey, the pin
-- setting, a destination in the zone the player is in, and no other addon's pin in charge.
---@return boolean
function ns.DestinationPinWanted()
	if not (ns.db and ns.db.destinationPin) then
		return false
	end
	local goal = ns.JourneyGoal()
	local x, _, _, map = ns.JourneyPosition()
	if not goal or not x or goal.map ~= map then
		return false
	end
	if ns.WaypointUIPinOwned and ns.WaypointUIPinOwned() then
		return false
	end
	return true
end

-- Longest step wording the pin shows: one short line under the distance, since the map pin's
-- tooltip carries the full text of every step.
local STEP_MAX = 32

-- The current step's wording, as the tracker and the map pin's tooltip put it, cut to one line.
-- rows are JourneyInfo's, whose current row is the step being walked.
---@param title string?
---@param rows SPFRow[]?
---@return string?
function ns.PinStepText(title, rows)
	local wording
	for _, row in ipairs(rows or {}) do
		if row.current and row.text then
			wording = row.text
			break
		end
	end
	wording = wording or title
	if type(wording) ~= "string" or wording == "" then
		return nil
	end
	if #wording > STEP_MAX then
		wording = (wording:sub(1, STEP_MAX - 3):gsub("%s+%S*$", "")) .. "..."
	end
	return wording
end

-- The step wording costs a JourneyInfo build, so it is read only when the step changes: the goal and the stop index
-- the route is on. The two are held as they are, never joined into a key string, so an unchanged step allocates
-- nothing on the pin's poll (#784).
local stepGoal, stepIndex, stepText

---@param goal SPFPoint
---@return string?
local function StepText(goal)
	if not (ns.JourneyInfo and ns.JourneyStops) then
		return nil
	end
	local _, index = ns.JourneyStops()
	if goal ~= stepGoal or index ~= stepIndex then
		stepGoal, stepIndex = goal, index
		local title, rows = ns.JourneyInfo()
		stepText = ns.PinStepText(title, rows)
	end
	return stepText
end

-- One update of the pin: where it goes, how strong it is and how far there is to go. Nothing moves while the goal,
-- the position, the facing, the distance and the step wording stay put, so that update returns before any text is
-- built (#784). The step is included because the stop index moves on while the player stands still, at a turn-in,
-- and StepText already hands back its cached line, so the check costs no build and no allocation.
function ns.RefreshDestinationPin()
	if not ns.DestinationPinWanted() then
		Hide()
		return
	end
	local goal = ns.JourneyGoal()
	local x, y = ns.JourneyPosition()
	if not (goal and x and y) then
		Hide()
		return
	end
	local facing = GetPlayerFacing() or 0
	local pin = frame
	-- Gold while Guide tracks the goal; bronze while the journey is planned but not guided.
	local pinFile = ns.GoalPinFile()
	local metres = ns.db and ns.db.metres
	local step = StepText(goal)
	if
		pin
		and pin:IsShown()
		and goal == pin.goal
		and goal.x == pin.goalX
		and goal.y == pin.goalY
		and x == pin.x
		and y == pin.y
		and facing == pin.facing
		and pinFile == pin.pinFile
		and metres == pin.distanceMetres
		and step == pin.step
	then
		return
	end
	local dx, dy = goal.x - x, goal.y - y
	local distance = math.sqrt(dx * dx + dy * dy)
	local offsetX, offsetY, alpha = ns.PinPlace(math.atan2(dy, dx), facing, distance)
	if not (offsetX and offsetY and alpha) then
		Hide()
		return
	end
	pin = pin or Create()
	pin.goal, pin.goalX, pin.goalY, pin.x, pin.y, pin.facing = goal, goal.x, goal.y, x, y, facing
	if pin.pinFile ~= pinFile then
		pin.pinFile = pinFile
		ns.Art.Icon(pin.Pin, pinFile, PIN_SIZE)
	end
	pin:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
	pin:SetAlpha(alpha)
	-- The distance string is rebuilt only when its rounded yards or the metres setting changes.
	local yards = math.floor(distance + 0.5)
	if pin.distanceYards ~= yards or pin.distanceMetres ~= metres then
		pin.distanceYards, pin.distanceMetres = yards, metres
		pin.Distance:SetText(ns.FormatDistance(distance, true))
	end
	if pin.step ~= step then
		pin.step = step
		pin.Step:SetText(step or "")
		pin.Step:SetShown(step ~= nil)
	end
	pin:Show()
end

-- The pin only works a frame timer while a journey is being followed, never while idle.
---@param on boolean
local function Poll(on)
	if on and not polling then
		polling = true
		local pin = frame or Create()
		pin:SetScript("OnUpdate", function(self, elapsed)
			self.elapsed = self.elapsed + elapsed
			if self.elapsed < POLL then
				return
			end
			self.elapsed = 0
			ns.RefreshDestinationPin()
		end)
	elseif not on and polling then
		polling = false
		if frame then
			frame:SetScript("OnUpdate", nil)
			frame:Hide()
		end
	end
end

-- Settings: turn the pin on and off from the panel, without a reload.
function ns.DestinationPinChanged()
	if ns.DestinationPinWanted() then
		Poll(true)
		ns.RefreshDestinationPin()
	else
		Poll(false)
	end
end

ns.Init(function()
	-- Only a player who turned the pin on pays for a timer; with the setting off there is no
	-- frame callback at all.
	if ns.db and ns.db.destinationPin then
		Poll(true)
	end
end)

---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Dragging the compass or the arrow into place: a plain drag follows the cursor as any frame does, and a Shift-drag
-- moves it a quarter as far, for placing it to the pixel. The fine drag runs on its own frame's OnUpdate, so the
-- dragged frame keeps its own, and stops with the drag.
-- While the pointer rests on a frame being placed, out of combat, the arrow keys nudge it one step of the screen's
-- units (Shift: ten). Every other key, and the arrow keys anywhere else, reach the game: most players walk with them.

local FINE = 0.25
local NUDGE = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

---@class SPFMover
local Mover = {}
ns.Mover = Mover

---@type Frame?
local driver
---@type {frame: Frame, placed: fun(frame: Frame), cx: number, cy: number, x: number, y: number, scale: number}?
local fine

-- Puts the dragged frame a quarter of the cursor's way from where the drag began.
local function Move(drag)
	local cx, cy = GetCursorPosition()
	drag.frame:ClearAllPoints()
	drag.frame:SetPoint(
		"CENTER",
		UIParent,
		"BOTTOMLEFT",
		drag.x + (cx - drag.cx) / drag.scale * FINE,
		drag.y + (cy - drag.cy) / drag.scale * FINE
	)
end

-- The fine drag ends with its drag, or when the button is let go or the frame hidden without one (a loading screen,
-- Alt-Z): saved where it was left either way.
local function Finish()
	local drag = fine
	if not drag then
		return
	end
	fine = nil
	if driver then
		driver:SetScript("OnUpdate", nil)
	end
	if drag.frame:IsVisible() then
		Move(drag)
	end
	drag.placed(drag.frame)
end

local function Follow()
	local drag = fine
	if not drag then
		return
	end
	if not (drag.frame:IsVisible() and IsMouseButtonDown("LeftButton")) then
		Finish()
		return
	end
	Move(drag)
end

-- The frame under the pointer while it is being placed, and the one holding the keyboard. The keyboard goes back to
-- the game as soon as combat starts (SetPropagateKeyboardInput cannot be called in combat, so a frame holding the
-- keyboard then could keep a movement key) and is taken again when combat ends with the pointer still there.
local hovered, keyboard, dragged, watching

local function ReleaseKeyboard()
	if keyboard then
		keyboard:EnableKeyboard(false)
		keyboard = nil
	end
end

local function TakeKeyboard()
	ReleaseKeyboard()
	-- Never under the gamepad interface, whose own navigation owns input (#158).
	if hovered and hovered:IsMouseEnabled() and not InCombatLockdown() and not ns.GamepadUI() then
		keyboard = hovered
		keyboard:EnableKeyboard(true)
		keyboard:SetPropagateKeyboardInput(true)
	end
end

local function Watch()
	if not driver then
		driver = CreateFrame("Frame")
	end
	if not watching then
		watching = true
		driver:RegisterEvent("PLAYER_REGEN_DISABLED")
		driver:RegisterEvent("PLAYER_REGEN_ENABLED")
		driver:SetScript("OnEvent", function(_, event)
			if event == "PLAYER_REGEN_ENABLED" then
				TakeKeyboard()
			else
				ReleaseKeyboard()
			end
		end)
	end
end

-- An arrow key the frame used is kept from the game, down and up; any other key reaches it. Propagation is set back
-- to on a frame later, so a key pressed after the arrow is never caught by a setting left over from it.
local function Pass(frame, key)
	local step = NUDGE[key]
	frame:SetPropagateKeyboardInput(step == nil)
	if step then
		C_Timer.After(0, function()
			if keyboard == frame and not InCombatLockdown() then
				frame:SetPropagateKeyboardInput(true)
			end
		end)
	end
	return step
end

-- Makes `frame` draggable while its mouse is enabled; `placed(frame)` runs when a drag ends, to save the place.
---@param frame Frame
---@param placed fun(frame: Frame)
function Mover.Attach(frame, placed)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		dragged = self
		if IsShiftKeyDown() then
			local cx, cy = GetCursorPosition()
			local x, y = self:GetCenter()
			fine = { frame = self, placed = placed, cx = cx, cy = cy, x = x, y = y, scale = self:GetEffectiveScale() }
			if not driver then
				driver = CreateFrame("Frame")
			end
			driver:SetScript("OnUpdate", Follow)
		else
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		dragged = nil
		if fine and fine.frame == self then
			Finish()
		else
			self:StopMovingOrSizing()
			placed(self)
		end
	end)
	-- The mouse is only enabled while the frame is being placed, so these run only then.
	frame:SetScript("OnEnter", function(self)
		hovered = self
		Watch()
		TakeKeyboard()
	end)
	frame:SetScript("OnLeave", function(self)
		if hovered == self then
			hovered = nil
		end
		if keyboard == self then
			ReleaseKeyboard()
		end
	end)
	frame:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			ReleaseKeyboard()
			return
		end
		-- Placing ended (move mode off, the frame hidden, or the gamepad interface came up) without the pointer
		-- leaving: the keys are the game's.
		if keyboard ~= self or not self:IsMouseEnabled() or not self:IsVisible() or ns.GamepadUI() then
			self:SetPropagateKeyboardInput(true)
			ReleaseKeyboard()
			return
		end
		local step = Pass(self, key)
		-- A drag already places the frame; a nudge then would fight it.
		if step and not dragged then
			-- One step of the screen's own units, whatever the frame's scale.
			local distance = (IsShiftKeyDown() and 10 or 1) * UIParent:GetEffectiveScale() / self:GetEffectiveScale()
			local x, y = self:GetCenter()
			self:ClearAllPoints()
			self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + step[1] * distance, y + step[2] * distance)
			placed(self)
		end
	end)
	frame:SetScript("OnKeyUp", function(self, key)
		if keyboard == self and not InCombatLockdown() then
			Pass(self, key)
		end
	end)
end

-- The game's quest tracker and ForeverCore's column, which stands left of it or wherever the player dragged it. A
-- frame at its stock place keeps clear of both, read from where they are now, so the column's place and size and an
-- Edit Mode move of the tracker are all followed.
local GAP = 8
-- Each frame's offset as last set, so an unchanged poll sets no point.
local stocked = setmetatable({}, { __mode = "k" })

-- A region's box in UIParent's units, nil while it is hidden or not yet laid out.
---@param region Region?
---@param scale number? the region's scale relative to UIParent; a frame's own when nil
---@return number? left, number? right, number? bottom, number? top
local function Box(region, scale)
	if not (region and region:IsVisible()) then
		return nil
	end
	local left, bottom, width, height = region:GetRect()
	if not left then
		return nil
	end
	scale = scale or region--[[@as Frame]]:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return left * scale, (left + width) * scale, bottom * scale, (bottom + height) * scale
end

-- Whether a box centred at `x` meets `blocker`.
local function Meets(blocker, x, y, half, depth)
	local l, r, b, t = Box(blocker)
	return l ~= nil and b < y and t > y - depth and l < x + half + GAP and r > x - half - GAP
end

-- Whether a box centred at `x` fits on the screen clear of both.
local function Fits(x, y, half, depth, width)
	return x - half >= 0
		and x + half <= width
		and not Meets(_G.ForeverTrackerCompanion, x, y, half, depth)
		and not Meets(_G.ObjectiveTrackerFrame, x, y, half, depth)
end

-- The place beside `blocker` nearest the centre that fits, or `best` when that is nearer.
local function Beside(blocker, best, y, half, depth, width)
	local l, r = Box(blocker)
	if not l then
		return best
	end
	local centre = width / 2
	local left, right = l - half - GAP, r + half + GAP
	if Fits(left, y, half, depth, width) and (not best or math.abs(left - centre) < math.abs(best - centre)) then
		best = left
	end
	if Fits(right, y, half, depth, width) and (not best or math.abs(right - centre) < math.abs(best - centre)) then
		best = right
	end
	return best
end

-- Anchors `frame` by its top centre `top` units under the top of the screen, centred unless the quest tracker or the
-- column would cover it; then it stands beside them, as near the centre as fits. `parts` are the regions
-- it draws beyond its own box (text hanging under it), so their extent counts too. Sets the point only when it moves,
-- so a caller may run this on every poll; `force` sets it anyway, after ClearAllPoints or a saved place.
---@param frame Frame
---@param top number
---@param parts Region[]?
---@param force boolean?
function Mover.Stock(frame, top, parts, force)
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	scale = scale > 0 and scale or 1
	local half, depth = frame:GetWidth() * scale / 2, frame:GetHeight() * scale
	local left, right, _, ceiling = Box(frame, scale)
	if left and parts then
		local centre = (left + right) / 2
		for index = 1, #parts do
			local l, r, b = Box(parts[index], scale)
			if l then
				half, depth = math.max(half, centre - l, r - centre), math.max(depth, ceiling - b)
			end
		end
	end
	local width = UIParent:GetWidth()
	local x, y = width / 2, UIParent:GetHeight() + top
	-- Centred when it fits, else the nearest place beside the column or the tracker that is clear of both. With none,
	-- it stays centred: the screen is too narrow for anything else.
	if not Fits(x, y, half, depth, width) then
		local best = Beside(_G.ForeverTrackerCompanion, nil, y, half, depth, width)
		x = Beside(_G.ObjectiveTrackerFrame, best, y, half, depth, width) or x
	end
	local offset = (x - width / 2) / scale
	if force or stocked[frame] ~= offset then
		stocked[frame] = offset
		frame:ClearAllPoints()
		frame:SetPoint("TOP", UIParent, "TOP", offset, top / scale)
	end
end

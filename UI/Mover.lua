---@class SPFNamespace
local ns = select(2, ...)

-- Dragging the compass or the arrow into place: a plain drag follows the cursor as any frame does, and a Shift-drag
-- moves it a quarter as far, for placing it to the pixel. The fine drag runs on its own frame's OnUpdate, so the
-- dragged frame keeps its own, and stops with the drag.
-- While the pointer rests on a frame being placed, out of combat, the arrow keys nudge it a pixel at a time (Shift:
-- ten). Every other key, and the arrow keys anywhere else, reach the game as before: most players walk with them.

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

-- The keyboard goes back to the game as soon as combat starts: SetPropagateKeyboardInput cannot be called in combat,
-- so a frame holding the keyboard then could keep a movement key.
local keyboard
local function ReleaseKeyboard()
	if keyboard then
		keyboard:EnableKeyboard(false)
		keyboard = nil
	end
end

-- Makes `frame` draggable while its mouse is enabled; `placed(frame)` runs when a drag ends, to save the place.
---@param frame Frame
---@param placed fun(frame: Frame)
function Mover.Attach(frame, placed)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
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
		if fine and fine.frame == self then
			Finish()
		else
			self:StopMovingOrSizing()
			placed(self)
		end
	end)
	-- The mouse is only enabled while the frame is being placed, so these run only then.
	frame:SetScript("OnEnter", function(self)
		if not InCombatLockdown() then
			ReleaseKeyboard()
			if not driver then
				driver = CreateFrame("Frame")
			end
			driver:RegisterEvent("PLAYER_REGEN_DISABLED")
			driver:SetScript("OnEvent", ReleaseKeyboard)
			keyboard = self
			self:EnableKeyboard(true)
			self:SetPropagateKeyboardInput(true)
		end
	end)
	frame:SetScript("OnLeave", function(self)
		if keyboard == self then
			ReleaseKeyboard()
		end
	end)
	frame:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			ReleaseKeyboard()
			return
		end
		local step = NUDGE[key]
		self:SetPropagateKeyboardInput(step == nil)
		if step then
			local distance = IsShiftKeyDown() and 10 or 1
			local x, y = self:GetCenter()
			self:ClearAllPoints()
			self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + step[1] * distance, y + step[2] * distance)
			placed(self)
		end
	end)
end

---@class SPFNamespace
local ns = select(2, ...)

-- Dragging the compass or the arrow into place: a plain drag follows the cursor as any frame does, and a Shift-drag
-- moves it a quarter as far, for placing it to the pixel. Arrow keys are left alone: most players walk with them.
-- The fine drag runs on its own frame's OnUpdate, so the dragged frame keeps its own, and stops with the drag.

local FINE = 0.25

---@class SPFMover
local Mover = {}
ns.Mover = Mover

---@type Frame?
local driver
---@type {frame: Frame, cx: number, cy: number, x: number, y: number, scale: number}?
local fine

local function Follow()
	local drag = fine
	if not drag then
		return
	end
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
			fine = { frame = self, cx = cx, cy = cy, x = x, y = y, scale = self:GetEffectiveScale() }
			if not driver then
				driver = CreateFrame("Frame")
			end
			driver:SetScript("OnUpdate", Follow)
		else
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		if fine and fine.frame == self and driver then
			Follow()
			fine = nil
			driver:SetScript("OnUpdate", nil)
		else
			self:StopMovingOrSizing()
		end
		placed(self)
	end)
end

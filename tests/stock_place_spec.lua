-- A frame's stock place under the top of the screen (Mover.Stock) stands clear of ForeverCore's column and the game's
-- quest tracker, read from their frames where they are now: centred when they are out of the way, beside them when they
-- reach it, the text hanging under it counted, and its point set only when the place moves.
local env = setmetatable({}, { __index = _G })
env._G = env
local function box(left, bottom, width, height, scale)
	return {
		left = left,
		bottom = bottom,
		width = width,
		height = height,
		scale = scale or 1,
		IsVisible = function(self)
			return not self.hidden
		end,
		GetRect = function(self)
			return self.left, self.bottom, self.width, self.height
		end,
		GetEffectiveScale = function(self)
			return self.scale
		end,
		GetWidth = function(self)
			return self.width
		end,
		GetHeight = function(self)
			return self.height
		end,
	}
end
env.UIParent = box(0, 0, 1366, 768)
local points = 0
local arrow = box(0, 0, 100, 100)
arrow.ClearAllPoints = function() end
-- The client lays the frame out where its point puts it; the spec does the same for the frame and the text under it.
function arrow:SetPoint(point, owner, relative, x, y)
	assert(point == "TOP" and owner == env.UIParent and relative == "TOP")
	points = points + 1
	self.left, self.bottom = 683 + x * self.scale - self.width / 2, 768 + y * self.scale - self.height
	self.point = { x, y }
end
local lines = box(0, 0, 240, 40)
local function stock(force)
	local mover = env.SPFMover
	mover.Stock(arrow, -120, { lines }, force)
	lines.left, lines.bottom = arrow.left + arrow.width / 2 - 120, arrow.bottom - 40
	return arrow.left + arrow.width / 2
end
local ns = {}
setfenv(assert(loadfile("UI/Mover.lua")), env)("ShortestPathForever", ns)
env.SPFMover = ns.Mover

-- Nothing in the way: centred, 120 under the top.
assert(stock(true) == 683 and arrow.point[2] == -120, "centred under the top of the screen")
-- The column pinned left of the tracker on a narrow screen reaches the centre: the arrow and its 240-wide lines stand
-- left of it.
local column = box(700, 300, 260, 400)
local tracker = box(960, 100, 260, 600)
env.ForeverTrackerCompanion, env.ObjectiveTrackerFrame = column, tracker
local x = stock()
assert(x + 120 <= column.left, "the lines clear the column: " .. x)
assert(x + 120 > column.left - 20, "and stand just beside it")
-- Unchanged: no new point.
local before = points
stock()
assert(points == before, "the place is set only when it moves")
-- The column dragged over the stock place from the left, too close to the tracker for the arrow between them: it stands
-- left of the column.
column.left = 500
x = stock()
assert(x - 120 >= column.left + column.width or x + 120 <= column.left, "clear of the dragged column")
assert(x + 120 <= tracker.left or x - 120 >= tracker.left + tracker.width, "and of the tracker")
-- Below the arrow's text: out of the way, centred again.
column.left, column.bottom, column.height = 600, 100, 300
assert(stock() == 683, "a column below the arrow leaves it centred")
-- Hidden (no section to show): centred.
column.bottom, column.height, column.hidden = 300, 400, true
assert(stock() == 683, "a hidden column leaves it centred")
-- A scaled arrow: its offset is in its own units, its place on screen the same.
column.hidden = false
arrow.scale = 2
x = stock()
assert(x + 120 <= column.left and arrow.point[2] == -60, "a scaled arrow keeps clear in screen units")
print("stock_place_spec: centred, beside the column and tracker, scaled, set only on a move ok")

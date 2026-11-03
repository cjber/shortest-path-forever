---@class SPFNamespace
local ns = select(2, ...)
local L = ns.L

-- Following a player: a journey whose destination is a party or raid member, refreshed as
-- they walk, so the arrow, compass, tracker and map keep pointing at where they are now.
--
-- The client only reports a player's position as a 0-1 fraction of a zone map, and a map
-- pixel is yards wide, so a party member's position arrives coarse and late. Refreshing
-- every frame would replan the journey for jitter the player cannot see, so a refresh is
-- due on a throttle and only when the member has actually moved a visible distance.

-- How often a refresh is considered, in seconds: an arrow turn the eye cannot follow faster
-- than this, and the planner's own cost is paid once per refresh (tests/follow_bench.lua).
local THROTTLE = 0.5
-- A member who has moved less than this since the last refresh is treated as standing still.
local MOVED = 10
-- Within this distance of the member, following is over: you are together.
local ARRIVE = 40
-- A member this far away and on another map is still a target; the planner finds the way.

---@class SPFFollowState
---@field unit string
---@field throttle number
---@field point? SPFPoint the member's position the journey was last planned to
---@field waiting number seconds until the next refresh is considered
---@field arrived boolean

---@type SPFFollowState?
local following

-- The member's position as a journey point, or nil while the client cannot say: a member on
-- another map, a member who has not loaded, or a position the client keeps back in an
-- instance. The map fraction is converted the same way a map click is (JourneyInput.lua's
-- WorldPoint), so the point is in the frame the planner already uses.
---@param unit string
---@return SPFPoint?
function ns.FollowPoint(unit)
	local map = C_Map.GetBestMapForUnit(unit)
	if not map then
		return nil
	end
	local position = C_Map.GetPlayerMapPosition(map, unit)
	if not position then
		return nil
	end
	local x, y = position:GetXY()
	if not x or not y or (x == 0 and y == 0) then
		-- The client answers 0, 0 for a unit it cannot place on that map.
		return nil
	end
	return ns.WorldPoint(map, x, y)
end

-- The distance between two journey points, in yards, or nil when they are on different maps.
---@param a SPFPoint
---@param b SPFPoint
---@return number?
local function Distance(a, b)
	if a.map ~= b.map then
		return nil
	end
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

-- Where the player stands, in the same frame as a follow point.
---@return SPFPoint?
local function Here()
	local x, y, _, map = ns.JourneyPosition()
	return x and { map = map, x = x, y = y }
end

local function Name(unit)
	local name = UnitName(unit)
	return name or L["Party member"]
end

-- Point the journey at the member now, whether or not the throttle has come round.
local function Refresh(point)
	following.point = point
	point.label = Name(following.unit)
	point.routeTitle = point.label
	ns.StartJourney(point)
end

---@param unit string
---@param throttle? number seconds between refreshes, defaulting to THROTTLE
---@return boolean started
function ns.StartFollowing(unit, throttle)
	if not _G.UnitExists(unit) or _G.UnitIsUnit(unit, "player") then
		return false
	end
	local point = ns.FollowPoint(unit)
	if not point then
		ns.Print(L["That player is not on a map you can see."])
		return false
	end
	following = {
		unit = unit,
		throttle = throttle or THROTTLE,
		waiting = 0,
		arrived = false,
	}
	Refresh(point)
	return true
end

function ns.StopFollowing()
	following = nil
end

---@return boolean active
function ns.IsFollowing()
	return following ~= nil
end

-- One frame of following, called from the follow driver's OnUpdate. The throttle is counted
-- down in this frame time rather than a wall clock, so it follows the game's own clock and
-- stops with it while the game is paused.
---@param elapsed number seconds since the last frame
function ns.FollowTick(elapsed)
	if not following then
		return
	end
	local unit = following.unit
	if not _G.UnitExists(unit) then
		ns.StopFollowing()
		return
	end
	local point = ns.FollowPoint(unit)
	if not point then
		-- A member who steps into an instance or off the map is left where they were last
		-- seen rather than ending the journey under the player's feet.
		return
	end
	following.waiting = following.waiting - elapsed
	local moved = following.point and Distance(following.point, point)
	local here = Here()
	local close = here and Distance(here, point)
	if close and close <= ARRIVE then
		if not following.arrived then
			following.arrived = true
			ns.Print(L["You have caught up with %s."]:format(Name(unit)))
		end
		return
	end
	following.arrived = false
	if following.waiting > 0 then
		return
	end
	if moved and moved < MOVED then
		-- Nothing the player could see has changed; wait without replanning.
		following.waiting = 0
		return
	end
	following.waiting = following.throttle
	Refresh(point)
end

ns.Init(function()
	local driver = CreateFrame("Frame", "ShortestPathForeverFollowDriver", UIParent)
	driver:SetScript("OnUpdate", function(_, elapsed)
		ns.FollowTick(elapsed)
	end)
end)

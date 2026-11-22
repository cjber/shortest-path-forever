---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- OpenMap (the seamless world map addon) offers other addons a small read-only API, OpenMapAPI: major 1, version 2
-- and up. It says where a point in the game's world sits on the stitched map's canvas (CanvasFromWorldPos, in
-- canvas fractions that run past 0..1 wherever the stitched view does), how high its stitched art reaches
-- (ArtTopLevel), whether the map on screen is stitched (IsStitched), and where the cursor is on that map.
-- UI/Canvas.lua watches the canvas while the map is shown, including when stitching starts or stops.
--
-- Every call is a read: nothing here writes to OpenMap, to its settings or to Blizzard's map. An OpenMap that is
-- absent, older than version 2, or of another major version leaves every caller on its own map fractions, exactly
-- as before, and the same applies whenever OpenMap is loaded but not stitching (dungeons and battlegrounds, or the
-- player turned stitching off).

local OpenMap = {}
ns.OpenMapAddon = OpenMap
-- OpenMap also submits Shift-clicks directly as "OpenMap". Only its TomTom handoff has a pin of its own.
OpenMap.PinOwner = "OpenMap:Pin"

-- The API version CanvasFromWorldPos and ArtTopLevel arrived in.
local CANVAS_VERSION = 2

-- OpenMapAPI when it is loaded and new enough for the stitched canvas; nil otherwise.
---@return OpenMapAPI?
function OpenMap.API()
	local api = OpenMapAPI
	if type(api) ~= "table" or api.major ~= 1 or (api.version or 0) < CANVAS_VERSION then
		return nil
	end
	return api
end

-- Whether the world map is showing OpenMap's stitched map now.
---@return boolean
function OpenMap.Stitched()
	local api = OpenMap.API()
	return api ~= nil and api.IsStitched ~= nil and api.IsStitched() == true
end

function OpenMap.ShowsFollowedPin()
	return ns.JourneyOwner() == OpenMap.PinOwner and OpenMap.Stitched()
end

-- Blizzard clamps its cursor fractions to the host map. On a stitched view the cursor can be
-- over a different zone even when that host map stays where it was.
---@param map SPFMapCanvas
---@return number? uiMapID, number? x, number? y
function OpenMap.CursorMapPoint(map)
	local api = OpenMap.API()
	if api and api.CursorPosition and api.MapAt and api.MapFromWorld and OpenMap.Stitched() then
		local u, v = api.CursorPosition()
		if u == nil or v == nil then
			return nil
		end
		local uiMapID = api.MapAt(u, v)
		if uiMapID then
			local x, y = api.MapFromWorld(uiMapID, u, v)
			return uiMapID, x, y
		end
		return nil
	end
	local x, y = map:GetNormalizedCursorPosition()
	return map:GetMapID(), x, y
end

-- At the same point, ownership can change while the journey keeps its drawn route.
---@param refresh fun()
function OpenMap.WatchPinOwner(refresh)
	local followed = false
	ShortestPathForever.API.Subscribe(function(changes)
		if changes.stop then
			local current = ns.JourneyOwner() == OpenMap.PinOwner
			if current ~= followed then
				followed = current
				refresh()
			end
		end
	end)
end

-- The frame level OpenMap's stitched art reaches, or nil when it is not stitching (or not built yet): a frame of
-- ours at a fixed level shows over the art only above this.
---@return number?
function OpenMap.TopLevel()
	local api = OpenMap.API()
	if not (api and api.ArtTopLevel and OpenMap.Stitched()) then
		return nil
	end
	return api.ArtTopLevel()
end

-- Places a journey's world point (continent and yards) on the stitched canvas. Fractions outside 0..1
-- reach into neighbouring zones. Returns nil when OpenMap is not stitching or cannot place the point.
---@param point SPFPoint
---@return number?, number?
function OpenMap.Canvas(point)
	local api = OpenMap.API()
	if not (api and api.IsStitched and api.IsStitched()) or type(point) ~= "table" then
		return nil
	end
	local map, x, y = point.map, point.x, point.y
	if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	-- The API is another addon's code: a failure there leaves this addon on its own map fractions.
	local placed, canvasX, canvasY = pcall(api.CanvasFromWorldPos, map, x, y)
	if placed and type(canvasX) == "number" and type(canvasY) == "number" then
		return canvasX, canvasY
	end
	return nil
end

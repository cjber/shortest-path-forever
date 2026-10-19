-- Run from the repository root: luajit tests/openmap_spec.lua
-- UI/OpenMap.lua against OpenMap's published API (release v0.5.0-beta: OpenMapAPI major 1, version 2): an absent
-- OpenMap, an older one and another major leave the addon on its own map fractions; a stitched one places a world
-- point on the canvas by the API, keeps the fractions past 0..1 that the stitched view reaches, and reports the top
-- of its art. A failing API is the same as none at all.
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end

local function Vector(x, y)
	return {
		GetXY = function()
			return x, y
		end,
	}
end
_G.CreateVector2D = function(x, y)
	return { x = x, y = y }
end

-- The game's world position of a map point: the fixture puts map 1 under continent 2, and map 2 under nothing.
local worldCalls = 0
_G.C_Map = {
	GetWorldPosFromMapPos = function(map, position)
		worldCalls = worldCalls + 1
		if map == 1 then
			return 2, Vector(position.x * 10, position.y * 20)
		end
		return nil
	end,
}

local ns = {}
assert(loadfile("UI/OpenMap.lua"))("ShortestPathForever", ns)
local OpenMap = ns.OpenMap
check(OpenMap ~= nil, "the module is on the namespace")

-- No OpenMap at all: nothing changes.
_G.OpenMapAPI = nil
check(OpenMap.API() == nil, "no API")
check(OpenMap.Stitched() == false, "not stitched")
check(OpenMap.TopLevel() == nil, "no art level")
check(OpenMap.Canvas({ map = 1, x = 1, y = 2 }) == nil, "no canvas placement")
check(worldCalls == 0, "the client is not asked where anything is when OpenMap is absent")

-- Version 1 has no canvas or art level, and another major is not ours to read.
_G.OpenMapAPI = {
	major = 1,
	version = 1,
	IsStitched = function()
		return true
	end,
}
check(OpenMap.API() == nil, "version 1 is too old")
_G.OpenMapAPI = {
	major = 2,
	version = 2,
	IsStitched = function()
		return true
	end,
}
check(OpenMap.API() == nil, "a new major version is not read")

-- Version 2, loaded but not stitching: still the addon's own map fractions.
_G.OpenMapAPI = {
	major = 1,
	version = 2,
	IsStitched = function()
		return false
	end,
	ArtTopLevel = function()
		return 4000
	end,
	CanvasFromWorldPos = function()
		return 0.25, 0.75
	end,
}
check(OpenMap.API() ~= nil, "version 2 is read")
check(OpenMap.Stitched() == false, "loaded but not stitching")
check(OpenMap.TopLevel() == nil, "no art level while not stitching")
check(OpenMap.Canvas({ map = 1, x = 1, y = 2 }) == nil, "no canvas placement while not stitching")
check(worldCalls == 0, "and the client is still not asked")

-- Stitching: the world point goes through the client's own projection to the API's canvas fractions.
local given = {}
_G.OpenMapAPI = {
	major = 1,
	version = 2,
	IsStitched = function()
		return true
	end,
	ArtTopLevel = function()
		return 4000
	end,
	CanvasFromWorldPos = function(continent, x, y)
		given[#given + 1] = { continent = continent, x = x, y = y }
		return -0.5, 1.25
	end,
}
check(OpenMap.Stitched() == true, "stitching")
check(OpenMap.TopLevel() == 4000, "the top of the art")
local x, y = OpenMap.Canvas({ map = 1, x = 3, y = 4 })
check(given[1] and given[1].continent == 2, "the continent the map point is on")
check(given[1].x == 30 and given[1].y == 80, "the world yards the client gave")
check(x == -0.5 and y == 1.25, "canvas fractions past the host map are kept, so neighbours draw")
-- A point the client cannot place, a point of the wrong shape, and one the API fails on.
check(OpenMap.Canvas({ map = 2, x = 1, y = 1 }) == nil, "a point off the world")
check(OpenMap.Canvas({ map = 1 }) == nil, "a point without its yards")
check(OpenMap.Canvas("nowhere") == nil, "not a point at all")
_G.OpenMapAPI.CanvasFromWorldPos = function()
	error("OpenMap broke")
end
check(OpenMap.Canvas({ map = 1, x = 3, y = 4 }) == nil, "an API that fails leaves the addon on its own map")

print(("openmap_spec: %d checks: API gating, canvas placement, art level, failures ok"):format(checks))

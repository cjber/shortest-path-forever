-- /way reads TomTom's line (an optional #mapID or zone, x and y as percentages, a title) and plans a journey there
-- the way a Shift-click on the world map does. It takes /way only while TomTom and every other addon leave it free.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = driver.ns, driver.env, 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- A world (1) holding a continent (10) whose zones are Elwynn Forest (1) and Westfall (2), plus a city that shares
-- its name with a micro map, and two zones with a common start.
local maps = {
	[1] = { mapID = 1, name = "Elwynn Forest", mapType = 3, parentMapID = 10 },
	[2] = { mapID = 2, name = "Westfall", mapType = 3, parentMapID = 10 },
	[3] = { mapID = 3, name = "Stormwind City", mapType = 5, parentMapID = 1 },
	[4] = { mapID = 4, name = "Stormwind City", mapType = 3, parentMapID = 10 },
	[5] = { mapID = 5, name = "Duskwood", mapType = 3, parentMapID = 10 },
	[6] = { mapID = 6, name = "Dun Morogh", mapType = 3, parentMapID = 10 },
	[10] = { mapID = 10, name = "Eastern Kingdoms", mapType = 2, parentMapID = 100 },
	[100] = { mapID = 100, name = "Azeroth", mapType = 1, parentMapID = 0 },
}
env.Enum.UIMapType.Zone = 3
env.C_Map.GetMapInfo = function(id)
	return maps[id]
end
local childrenAsked = 0
env.C_Map.GetMapChildrenInfo = function(id, mapType, all)
	childrenAsked = childrenAsked + 1
	equal(id, 100, "the zones are listed from the top of the world")
	equal(mapType, nil, "every kind of map is listed")
	equal(all, true, "the whole tree is listed")
	local list = {}
	for mapID, info in pairs(maps) do
		if mapID ~= 100 then
			list[#list + 1] = info
		end
	end
	table.sort(list, function(a, b)
		return a.mapID < b.mapID
	end)
	return list
end
local loaded = {}
env.C_AddOns = {
	IsAddOnLoaded = function(name)
		return loaded[name] == true
	end,
}
env.SlashCmdList = {}
local printed = {}
ns.Print = function(message)
	printed[#printed + 1] = message
end

local created = {}
local baseFrame = env.CreateFrame
env.CreateFrame = function(...)
	local frame = baseFrame(...)
	created[#created + 1] = frame
	return frame
end
driver.load("Core/Way.lua")
local login = created[#created]

-- Each answer as a table, so a check reads only the parts it names.
local function parse(line)
	local map, x, y, title, err = ns.ParseWay(line)
	return { map = map, x = x, y = y, title = title, err = err }
end

-- The point on the map you stand on, TomTom's separators and all.
local way = parse("45 67")
equal(way.map, 1, "no zone means the map you stand on")
equal(way.x, 0.45, "x is a percentage")
equal(way.y, 0.67, "y is a percentage")
equal(way.title, nil, "no title")
way = parse("45.5 67.25 The   inn")
equal(way.x, 0.455, "decimal points are kept")
equal(way.y, 0.6725, "decimal points are kept for y")
equal(way.title, "The inn", "the title is every word after the point")
way = parse("45,5 67,25")
equal(way.x, 0.455, "a decimal comma reads as a point")
equal(way.y, 0.6725, "a decimal comma reads as a point for y")
way = parse("45, 67")
equal(way.x, 0.45, "a comma after x separates it from y")
equal(way.y, 0.67, "y after the comma")
way = parse("45.5, 67.5")
equal(way.x, 0.455, "a comma after a decimal x separates it from y")
equal(way.y, 0.675, "y after a decimal x's comma")

-- A map ID, a zone by name, or a zone by the start of its name.
way = parse("#2 10 20 Sentinel Hill")
equal(way.map, 2, "#mapID names the map")
equal(way.x, 0.1, "x after the map ID")
equal(way.title, "Sentinel Hill", "title after a map ID")
way = parse("Westfall 56.3 47.6 Sentinel Hill")
equal(way.map, 2, "a zone named in full")
equal(way.title, "Sentinel Hill", "title after a zone")
equal(parse("westfall 56 47").map, 2, "zone names ignore case")
equal(parse("Elwynn 42 65").map, 1, "the one zone a name begins")
equal(parse("stormwind city 60 70").map, 4, "a zone wins over a micro map with its name")
equal(childrenAsked, 1, "the zone list is built once")
way = parse("Du 50 50")
equal(way.map, nil, "a name two zones begin is refused")
equal(way.err, "Du could be Dun Morogh, Duskwood.", "and both are named")
way = parse("Atlantis 50 50")
equal(way.map, nil, "an unknown zone is refused")
equal(way.err, "no zone called Atlantis.", "and said so")
way = parse("#99 50 50")
equal(way.map, nil, "an unknown map ID is refused")
equal(way.err, "no map #99.", "and said so")
for _, bad in ipairs({ "", "45", "abc def", "101 50", "50 -1", "#2 50", "#2 x 50" }) do
	way = parse(bad)
	equal(way.map ~= nil and way.x ~= nil and way.y ~= nil, false, "a bad line plans nothing: " .. bad)
	equal(type(way.err), "string", "a bad line says why: " .. bad)
end

-- /way plans a journey to the spot through the map's own Shift-click path.
ns.Way("Westfall 56.3 47.6 Sentinel Hill")
driver.path.settle()
equal(ns.HasJourney(), true, "/way starts a journey")
equal(ns.JourneyInfo(), "Journey to Sentinel Hill", "the title names the destination")
ns.ClearJourney()
ns.Way("Atlantis 50 50")
equal(ns.HasJourney(), false, "a bad line starts nothing")
equal(printed[#printed], "no zone called Atlantis.", "and says why")
ns.db.journey = false
ns.Way("45 67")
equal(ns.HasJourney(), false, "journeys switched off start nothing")
equal(printed[#printed]:find("Shift-click to plan journeys", 1, true) ~= nil, true, "and names the setting")
ns.db.journey = true

-- /way is claimed at login, and only while it is free.
equal(env.SLASH_SHORTESTPATHFOREVERWAY1, nil, "nothing is claimed before login")
loaded.TomTom = true
login:OnEvent("PLAYER_LOGIN")
equal(env.SLASH_SHORTESTPATHFOREVERWAY1, nil, "TomTom keeps its own /way")
equal(env.SlashCmdList.SHORTESTPATHFOREVERWAY, nil, "no handler while TomTom is loaded")
loaded.TomTom = false
_G.SLASH_OTHERWAY1 = "/WAY"
login:OnEvent("PLAYER_LOGIN")
equal(env.SLASH_SHORTESTPATHFOREVERWAY1, nil, "another addon's /way is left alone")
_G.SLASH_OTHERWAY1 = nil
login:OnEvent("PLAYER_LOGIN")
equal(env.SLASH_SHORTESTPATHFOREVERWAY1, "/way", "a free /way is claimed")
equal(env.SlashCmdList.SHORTESTPATHFOREVERWAY, ns.Way, "and plans journeys")
env.SlashCmdList.SHORTESTPATHFOREVERWAY("#1 30 40 Goldshire")
driver.path.settle()
equal(ns.JourneyInfo(), "Journey to Goldshire", "the command plans the journey")
ns.ClearJourney()

print("way: ok, " .. checks .. " checks")

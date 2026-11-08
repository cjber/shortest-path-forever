-- /way reads TomTom's line (an optional #mapID or zone, x and y as percentages, a title) and plans a journey there
-- the way a Shift-click on the world map does. It takes /way only while TomTom and every other addon leave it free.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = driver.ns, driver.env, 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- A world (1) holding a continent (10) whose zones are Elwynn Forest (1) and Westfall (2), plus a city that shares
-- its name with a micro map, two zones with a common start, a zone whose name starts with "The", and dungeons inside
-- them, one behind a micro map and two sharing a start.
local maps = {
	[1] = { mapID = 1, name = "Elwynn Forest", mapType = 3, parentMapID = 10 },
	[2] = { mapID = 2, name = "Westfall", mapType = 3, parentMapID = 10 },
	[3] = { mapID = 3, name = "Stormwind City", mapType = 5, parentMapID = 1 },
	[4] = { mapID = 4, name = "Stormwind City", mapType = 3, parentMapID = 10 },
	[5] = { mapID = 5, name = "Duskwood", mapType = 3, parentMapID = 10 },
	[6] = { mapID = 6, name = "Dun Morogh", mapType = 3, parentMapID = 10 },
	[7] = { mapID = 7, name = "The Hinterlands", mapType = 3, parentMapID = 10 },
	[8] = { mapID = 8, name = "The Barrens", mapType = 3, parentMapID = 10 },
	[20] = { mapID = 20, name = "Wailing Caverns", mapType = 4, parentMapID = 8 },
	[21] = { mapID = 21, name = "Shadowfang Keep", mapType = 4, parentMapID = 8 },
	[22] = { mapID = 22, name = "Shadow Labyrinth", mapType = 4, parentMapID = 5 },
	[23] = { mapID = 23, name = "The Stockade", mapType = 4, parentMapID = 3 },
	[10] = { mapID = 10, name = "Eastern Kingdoms", mapType = 2, parentMapID = 100 },
	[100] = { mapID = 100, name = "Azeroth", mapType = 1, parentMapID = 0 },
}
env.Enum.UIMapType.Zone = 3
env.Enum.UIMapType.Dungeon = 4
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
-- Core/TomTom.lua's answer, whether TomTom loads after Shortest Path: not installed here.
ns.TomTomEnabled = function()
	return loaded.TomTom == true
end
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
-- As TomTom reads it (TomTom.lua:1480-1486), a name may be any part of the zone's: "hinterlands" is The Hinterlands.
equal(parse("hinterlands 30 40").map, 7, "a name inside the zone's own")
equal(parse("The Hinterlands 30 40").map, 7, "the zone's full name")
equal(parse("west 30 40").map, 2, "a name a zone begins wins over one inside another's")
way = parse("or 30 40")
equal(way.map, nil, "a name inside several zones is refused")
equal(way.err, "or could be Dun Morogh, Elwynn Forest, Stormwind City.", "and each is named")
-- Dungeon names mean the outdoor zone holding their entrance.
equal(parse("wail 50 50").map, 8, "a dungeon a name begins means its outdoor zone")
equal(parse("Wailing Caverns 50 50").map, 8, "a dungeon named in full means its outdoor zone")
way = parse("shadow 50 50")
equal(way.map, nil, "a name two dungeons begin is refused")
equal(way.err, "shadow could be Shadow Labyrinth, Shadowfang Keep.", "and both dungeons are named")
equal(parse("stockade 50 50").map, 1, "a dungeon through a micro map still means a zone")
way = parse(".5 50.")
equal(way.x, 0.005, "a leading point reads as TomTom's tonumber reads it")
equal(way.y, 0.5, "a trailing point too")
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

-- /way is claimed as Shortest Path loads, while it is free, and given up at login to TomTom or another addon.
equal(env.SLASH_SHORTESTPATHFOREVERWAY1, "/way", "a free /way is claimed as Shortest Path loads")
equal(env.SlashCmdList.SHORTESTPATHFOREVERWAY, ns.Way, "with its handler")
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

-- /way reset, as TomTom's own reads it: all, away, a zone, or any zone but one, ends the journey /way started and
-- leaves a journey planned since from elsewhere alone.
local planned, current, cleared = nil, nil, 0
ns.JourneyToMapPoint = function(map, x, y, title)
	planned = { map = map, x = x, y = y, title = title }
	current = planned
	return true
end
ns.JourneyGoal = function()
	return current
end
ns.ClearJourney = function()
	cleared = cleared + 1
	current = nil
end
local function plan(map)
	ns.Way("#" .. map .. " 50 50")
	cleared = 0
end
local function say(line)
	local before = #printed
	ns.Way(line)
	return #printed > before and printed[#printed] or nil
end

plan(1)
equal(say("reset all"), nil, "reset all says nothing")
equal(cleared, 1, "reset all clears the /way journey")
equal(current, nil, "and the journey is gone")
current = { map = 2 }
cleared = 0
say("RESET ALL")
equal(cleared, 1, "reset all clears a journey /way did not start")
equal(current, nil, "whatever planned it")
cleared = 0
equal(say("reset all"), nil, "reset all with no journey says nothing")
equal(cleared, 0, "and does nothing")

plan(1)
say("reset Elwynn Forest")
equal(cleared, 1, "reset <zone> clears the /way journey in that zone")
equal(current, nil, "and the journey is gone")
plan(2)
say("reset Elwynn Forest")
equal(cleared, 0, "reset <zone> keeps a /way journey in another zone")
equal(current, planned, "the other journey stays")

plan(2)
say("reset not Elwynn Forest")
equal(cleared, 1, "reset not <zone> clears a /way journey outside the zone")
equal(current, nil, "and the journey is gone")
plan(1)
say("reset not Elwynn Forest")
equal(cleared, 0, "reset not <zone> keeps a /way journey in the zone")
equal(current, planned, "the other journey stays")

plan(2)
driver.move({ map = 1, x = 0, y = 0, z = 0 })
say("reset away")
equal(cleared, 1, "reset away clears a /way journey on another map")
equal(current, nil, "and the journey is gone")
plan(1)
say("reset away")
equal(cleared, 0, "reset away keeps a /way journey on this map")
equal(current, planned, "the journey stays")
plan(2)
driver.move({ map = 1, x = 0, y = 0, z = 0 })
current = { map = 1 }
cleared = 0
say("reset away")
equal(cleared, 0, "reset away leaves a journey planned since")
equal(current.map, 1, "wherever it goes")

plan(1)
equal(say("reset Atlantis"), "no zone called Atlantis.", "an unknown zone says so")
equal(cleared, 0, "and clears nothing")
equal(current, planned, "the journey stays")

plan(1)
current = { map = 1 }
cleared = 0
say("reset Elwynn Forest")
equal(cleared, 0, "reset <zone> leaves a journey planned since")
say("reset not Westfall")
equal(cleared, 0, "reset not <zone> leaves it too")
equal(current.map, 1, "and it stays where it goes")

plan(1)
equal(say("reset"), "/way reset all, away, <zone> or not <zone>", "bare reset prints the usage")
equal(cleared, 0, "and clears nothing")

plan(1)
ns.db.journey = false
say("reset all")
equal(cleared, 1, "a reset works with journeys turned off")
ns.db.journey = true

print("way: ok, " .. checks .. " checks")

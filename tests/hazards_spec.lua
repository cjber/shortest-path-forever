-- Walks keep away from zones far above your level and from the other faction's towns (Journey/Hazards.lua): the
-- profile's costs, the walking search going round them on the shipped maps, baked walks weighed the same way, and the
-- lines a journey's walk shows.
local strings = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", strings)
local L = strings.L

local function near(actual, expected, what)
	assert(math.abs(actual - expected) < 1e-6, string.format("%s: %s, expected %s", what, actual, expected))
end

-- The client a profile asks: your level and side, zone names, and a frame for PLAYER_LEVEL_UP.
local level, faction, created = 10, "Alliance", {}
local env = setmetatable({
	UnitLevel = function()
		return level
	end,
	UnitFactionGroup = function()
		return faction
	end,
	C_Map = {
		GetMapInfo = function(id)
			return { name = "Zone " .. id }
		end,
	},
	CreateFrame = function()
		local frame = {}
		frame.RegisterEvent = function() end
		function frame:SetScript(_, fn)
			self.OnEvent = fn
		end
		created[#created + 1] = frame
		return frame
	end,
}, { __index = _G })

-- A strip of zones along x, 2000 yards deep: 100 (levels 1-10) west of x = 0, 200 (18-30) up to x = 1000, 300
-- (13-20) up to 2000 and a Horde capital beyond.
local policy = 0
local journey = false
local ns = {
	L = L,
	db = { avoidHighZones = true },
	charDB = {},
	Init = function(fn)
		fn()
	end,
	HasJourney = function()
		return journey
	end,
	TravelPolicyChanged = function()
		policy = policy + 1
	end,
	ZoneMap = function(map, x, y)
		if map ~= 1 or math.abs(y) > 1000 then
			return nil
		end
		return x < 0 and 100 or x < 1000 and 200 or x < 2000 and 300 or 400
	end,
}
ns.Zones = {
	[100] = { low = 1, high = 10, map = 1, minX = -1000, minY = -1000, maxX = 0, maxY = 1000 },
	[200] = { low = 18, high = 30, map = 1, minX = 0, minY = -1000, maxX = 1000, maxY = 1000 },
	[300] = { low = 13, high = 20, map = 1, minX = 1000, minY = -1000, maxX = 2000, maxY = 1000 },
	[400] = { city = "Horde", map = 1, minX = 2000, minY = -1000, maxX = 3000, maxY = 1000 },
}
-- 1 is a Horde town on its own; 2 shares its spot with 3, an Alliance flight master, like Booty Bay's two.
ns.TaxiNodes = {
	[1] = { map = 1, x = -500, y = 500, name = "Crossroads, The Barrens", faction = "Horde" },
	[2] = { map = 1, x = -500, y = -500, name = "Booty Bay, Stranglethorn", faction = "Horde" },
	[3] = { map = 1, x = -450, y = -500, name = "Booty Bay, Stranglethorn", faction = "Alliance" },
	[4] = { map = 1, x = -800, y = 0, name = "Goldshire", faction = "Alliance" },
}
ns.Docks = { [1] = { map = 1, x = 5000, y = 5000, walk = { map = 1, x = 5010, y = 5000 } } }
ns.TaxiName = function(id)
	return ns.TaxiNodes[id].name
end
setfenv(assert(loadfile("Journey/Hazards.lua")), env)("ShortestPathForever", ns)
local Hazards = ns.Hazards

do
	local west, east = { map = 1, x = -900, y = 0 }, { map = 1, x = -100, y = 0 }
	local profile = Hazards.Profile(west, east)
	-- At level 10 the zone whose lowest level is 18 is avoided; 13 is fewer than four above, so it is not.
	assert(profile.zones[200] == 4 and not profile.zones[300] and not profile.zones[100], "levels four or more above")
	assert(profile.zones[400] == 6, "the other faction's capital")
	-- One hostile town: the Horde flight master with no Alliance one beside it. Your own side's are never towns.
	assert(#profile.towns == 1 and profile.towns[1].id == 1, "a shared town is no hostile town")
	near(profile.Point(1, 500, 0), 4, "inside the avoided zone")
	near(profile.Point(1, 1500, 0), 1, "a zone not far enough above")
	near(profile.Point(1, -500, 450), 6, "inside a hostile town")
	near(profile.Point(1, -500, -500), 1, "a shared town")
	near(profile.Point(1, 2500, 0), 6, "a hostile capital")
	near(profile.Point(2, 500, 0), 1, "another continent")
	near(profile.Chord(1, -700, 500, -300, 500), 1 + 0.75 * 5, "300 of its 400 yards in the town")
	near(profile.Chord(1, -700, 200, -300, 200), 1, "a walk past it")
	assert(profile.Near(1, -400, 600, -300, 700) and not profile.Near(1, 0, 0, 100, 100), "a town near a box")
	-- A straight walk half in the avoided zone weighs about half way between 1 and its factor.
	local half = profile.Segment(1, -500, 0, 500, 0)
	assert(half > 2.3 and half < 2.7, half)
	near(profile.Segment(1, -900, -900, -800, -900), 1, "a walk near no hazard")
	assert(
		profile.ConnectorWalk({ map = 1, x = -700, y = 0 }, { map = 1, x = -600, y = 0 }),
		"short walks beside a flight master are connectors"
	)
	assert(
		profile.ConnectorWalk({ map = 1, x = 5010, y = 5000 }, { map = 1, x = 5110, y = 5000 }),
		"short walks beside a dock's walking point are connectors"
	)
	assert(
		not profile.ConnectorWalk({ map = 1, x = -700, y = 0 }, { map = 1, x = -490, y = 0 }),
		"over 200 yards is not a connector"
	)
	assert(
		not profile.ConnectorWalk({ map = 1, x = -700, y = 0 }, { map = 2, x = -650, y = 0 }),
		"connectors stay on one map"
	)

	-- Where the journey starts or ends is never avoided: a goal in the high zone, or in the town.
	profile = Hazards.Profile(west, { map = 1, x = 500, y = 0 })
	assert(not profile.zones[200], "the goal's zone")
	near(profile.Point(1, 500, 0), 1, "the goal's zone costs nothing extra")
	profile = Hazards.Profile(west, { map = 1, x = -510, y = 480 })
	assert(profile.towns[1].exempt, "the goal's town")
	near(profile.Point(1, -500, 450), 1, "the goal's town costs nothing extra")
	local exemptKey = profile.key
	profile = Hazards.Profile(west, east)
	assert(profile.key ~= exemptKey, "the exemptions are part of the costs")

	-- Level 14 grows into the 18 zone's reach; the setting off avoids no zone, though towns stay.
	level = 11
	local eleven = Hazards.Profile(west, east).key
	level = 12
	assert(Hazards.Profile(west, east).key == eleven, "a level-up that crosses no threshold keeps every search")
	level = 14
	assert(Hazards.Profile(west, east).zones[200], "18 is still four above 14")
	level = 15
	local grown = Hazards.Profile(west, east)
	assert(not grown.zones[200] and grown.key ~= profile.key, "18 is three above 15")
	level = 10
	ns.db.avoidHighZones = false
	local off = Hazards.Profile(west, east)
	assert(not off.zones[200] and off.zones[400] and #off.towns == 1, "the setting is only about zones")
	ns.db.avoidHighZones = true

	-- The lines under a walk: towns it passes, avoided zones it crosses, and avoided zones the straight way crossed that
	-- it went round. A town where the journey ends is still named.
	local hz = Hazards.Profile(west, { map = 1, x = 1500, y = 0 })
	local leg = { from = west, to = { map = 1, x = 1500, y = 0 } }
	local through = { west, { map = 1, x = -500, y = 500 }, { map = 1, x = 1500, y = 0 } }
	local notes = Hazards.Notes(hz, leg, through)
	assert(notes and #notes == 2, notes and table.concat(notes, " | "))
	assert(notes[1] == L["Hostile town: %s"]:format("Crossroads"), notes[1])
	assert(notes[2] == L["Crosses %s (level %s)"]:format("Zone 200", "18-30"), notes[2])
	local around = { west, { map = 1, x = -100, y = 2000 }, { map = 1, x = 1500, y = 2000 }, leg.to }
	notes = Hazards.Notes(hz, leg, around)
	assert(
		notes and #notes == 1 and notes[1] == L["Avoids %s (level %s)"]:format("Zone 200", "18-30"),
		notes and notes[1]
	)
	assert(not Hazards.Notes(hz, { from = west, to = east }, { west, east }), "nothing to say")
	assert(not Hazards.Notes(nil, leg, through), "no profile")
	local town = { map = 1, x = -500, y = 520 }
	hz = Hazards.Profile(west, town)
	notes = Hazards.Notes(hz, { from = west, to = town }, { west, town })
	assert(notes and notes[1] == L["Hostile town: %s"]:format("Crossroads"), "the goal's own town is still named")
	local capital = { map = 1, x = 2500, y = 0 }
	hz = Hazards.Profile({ map = 1, x = 1500, y = 0 }, capital)
	notes = Hazards.Notes(
		hz,
		{ from = { map = 1, x = 1500, y = 0 }, to = capital },
		{ { map = 1, x = 1500, y = 0 }, capital }
	)
	assert(notes and notes[1] == L["Hostile town: %s"]:format("Zone 400"), "a hostile capital, even as the goal")
	-- A level-up plans again during a journey, before UnitLevel has caught up.
	local events = created[1]
	events:OnEvent("PLAYER_LEVEL_UP", 11)
	assert(policy == 0, "no journey, no replan")
	journey = true
	events:OnEvent("PLAYER_LEVEL_UP", 15)
	assert(policy == 1 and Hazards.Level() == 15, "plans again for the new level")
	assert(not Hazards.Profile(west, east).zones[200], "the event's level counts")
	ns.db.avoidHighZones = false
	events:OnEvent("PLAYER_LEVEL_UP", 16)
	assert(policy == 1, "with the setting off a level-up changes nothing")
	ns.db.avoidHighZones, journey = true, false
	level = 10
	-- The level a profile plans for never drops below the last level-up's.
	assert(Hazards.Level() == 16)

	print("hazards: profile: ok")
end

-- The walking search goes round a hazard on the shipped maps where the way allows, and every search agrees on its cost.
do
	local walking = {}
	assert(loadfile("tools/load_nav.lua"))(0)
	for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
		assert(loadfile(file))("ShortestPathForever", walking)
	end
	local Path = walking.Path
	local function closest(points, x, y)
		local best = math.huge
		for i = 2, #points do
			local a, b = points[i - 1], points[i]
			local dx, dy = b.x - a.x, b.y - a.y
			local length2 = dx * dx + dy * dy
			local t = length2 > 0 and math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / length2)) or 0
			best = math.min(best, math.sqrt((a.x + t * dx - x) ^ 2 + (a.y + t * dy - y) ^ 2))
		end
		return best
	end
	-- A town of 120 yards on the road from Northshire down to Goldshire.
	local cx, cy, r = -9070.6, -43.8, 120
	local inside = function(x, y)
		return (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r
	end
	local town = {
		key = "town",
		Point = function(_, x, y)
			return inside(x, y) and 6 or 1
		end,
		Chord = function(_, ax, ay, bx, by)
			for i = 0, 20 do
				if inside(ax + (bx - ax) * i / 20, ay + (by - ay) * i / 20) then
					return 6
				end
			end
			return 1
		end,
		Near = function(_, minX, minY, maxX, maxY)
			return cx >= minX - r and cx <= maxX + r and cy >= minY - r and cy <= maxY + r
		end,
	}
	local northshire, goldshire = { x = -8914, y = -135 }, { x = -9459, y = 43 }
	local plain, plainCost = Path.FindSync(0, northshire, goldshire)
	assert(closest(plain, cx, cy) < 10, "the road runs through the town")
	local round, roundCost = Path.FindSync(0, northshire, goldshire, nil, town)
	assert(closest(round, cx, cy) > r, "goes round the town")
	assert(roundCost > plainCost and roundCost < plainCost * 1.5, roundCost)
	local drawn = 0
	for i = 2, #round do
		local dx, dy = round[i].x - round[i - 1].x, round[i].y - round[i - 1].y
		drawn = drawn + math.sqrt(dx * dx + dy * dy)
	end
	assert(
		roundCost >= drawn and roundCost < drawn * 1.1,
		"reported yards are real travel cost, without the hazard multiplier"
	)
	-- The plain search after the hazard one is not answered from its cache, nor the other way round.
	assert(select(2, Path.FindSync(0, northshire, goldshire)) == plainCost)
	assert(select(2, Path.FindSync(0, northshire, goldshire, nil, town)) == roundCost)
	near(Path.FindManySync(0, northshire, { goldshire }, nil, nil, town)[1], roundCost, "FindMany")
	near(Path.FindManySync(0, goldshire, { northshire }, nil, true, town)[1], roundCost, "a reverse batch")
	local connectorTo = { x = northshire.x + 100, y = northshire.y }
	local connectorHazard = {}
	for key, value in pairs(town) do
		connectorHazard[key] = value
	end
	connectorHazard.ConnectorWalk = function()
		return true
	end
	local _, connectorCost = Path.FindSync(0, northshire, connectorTo, nil, connectorHazard)
	near(connectorCost, select(2, Path.FindSync(0, northshire, connectorTo)), "a connector uses its real cost")
	near(
		Path.FindManySync(0, northshire, { connectorTo }, nil, nil, connectorHazard)[1],
		connectorCost,
		"FindMany keeps connector costs real"
	)
	local sliced
	local frames = {}
	Path.after = function(fn)
		frames[#frames + 1] = fn
	end
	Path.FindCost(0, northshire, goldshire, function(cost)
		sliced = cost
	end, nil, town)
	while #frames > 0 do
		table.remove(frames, 1)()
	end
	near(sliced, roundCost, "the sliced probe")
	print("hazards: walking search: ok")
end

-- The shipped data: walking north through the Barrens as Alliance, the walk goes round the Crossroads, the Horde's
-- town, and says nothing; a goal in the Crossroads is walked to and named.
do
	local data = {
		L = L,
		db = { avoidHighZones = true },
		charDB = {},
		Init = function() end,
	}
	assert(loadfile("Data/Taxi.lua"))("ShortestPathForever", data)
	assert(loadfile("Data/Zones.lua"))("ShortestPathForever", data)
	data.TaxiName = function(id)
		return data.TaxiNodes[id].name
	end
	-- Zone boxes overlap; the smallest one holding a point stands in for the client's answer.
	data.ZoneMap = function(map, x, y)
		local best, area
		for id, zone in pairs(data.Zones) do
			if zone.map == map and x >= zone.minX and x <= zone.maxX and y >= zone.minY and y <= zone.maxY then
				local size = (zone.maxX - zone.minX) * (zone.maxY - zone.minY)
				if not area or size < area then
					best, area = id, size
				end
			end
		end
		return best
	end
	level, faction = 60, "Alliance"
	setfenv(assert(loadfile("Journey/Hazards.lua")), env)("ShortestPathForever", data)
	local walking = {}
	assert(loadfile("tools/load_nav.lua"))(1)
	for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
		assert(loadfile(file))("ShortestPathForever", walking)
	end
	local crossroads = data.TaxiNodes[25]
	assert(crossroads.name:find("^Crossroads"), crossroads.name)
	local south, north = { map = 1, x = -1000, y = -2550 }, { map = 1, x = 150, y = -2650 }
	local hz = data.Hazards.Profile(south, north)
	local points = walking.Path.FindSync(1, south, north, nil, hz)
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		for t = 0, 1, 0.05 do
			local x, y = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
			assert((x - crossroads.x) ^ 2 + (y - crossroads.y) ^ 2 > 100 ^ 2, "keeps out of the Crossroads")
		end
	end
	assert(not data.Hazards.Notes(hz, { from = south, to = north }, points), "nothing to say")
	local inside = { map = 1, x = crossroads.x + 20, y = crossroads.y }
	hz = data.Hazards.Profile(south, inside)
	points = walking.Path.FindSync(1, south, inside, nil, hz)
	local notes = data.Hazards.Notes(hz, { from = south, to = inside }, points)
	assert(notes and notes[1] == L["Hostile town: %s"]:format("Crossroads"), notes and notes[1])
	-- Booty Bay and Gadgetzan have a flight master for each side: no hostile town.
	for _, town in ipairs(hz.towns) do
		local name = data.TaxiNodes[town.id].name
		assert(not name:find("Booty Bay") and not name:find("Gadgetzan") and not name:find("Everlook"), name)
	end
	print("hazards: shipped data: ok")
end

-- A walk baked without hazards between two fixed places weighs the hazards on its straight way, so a flight that
-- was slower than the walk wins once the walk crosses a hostile town.
do
	local planning = {}
	assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", planning)
	assert(loadfile("Transport/Model.lua"))("ShortestPathForever", planning)
	assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", planning)
	local nodes = { [1] = { map = 1, x = 0, y = 0 }, [2] = { map = 1, x = 2000, y = 0 } }
	local function plan(hazards)
		return planning.Planner.Plan({
			from = nodes[1],
			to = nodes[2],
			now = 0,
			walkSpeed = 7,
			faction = "Alliance",
			taxiNodes = nodes,
			taxiKnown = { true, true },
			taxiPaths = { { from = 1, to = 2, seconds = 400, points = {} } },
			walks = {
				{ from = nodes[1], to = nodes[1], cost = 0 },
				{ from = nodes[2], to = nodes[2], cost = 0 },
				{ from = nodes[1], to = nodes[2], cost = false },
			},
			baked = { [1] = { ["taxi1 taxi2"] = { 2100, 2100 } } },
			hazards = hazards,
		})
	end
	local walked = plan(nil)
	assert(#walked.legs == 1 and walked.legs[1].mode == "walk" and walked.legs[1].yards == 2100, "300 s on foot")
	local crossing = {
		key = "crossing",
		Segment = function(map, ax, ay, bx, by)
			assert(map == 1 and ax == 0 and ay == 0 and bx == 2000 and by == 0)
			return 2
		end,
	}
	local flown = plan(crossing)
	local modes = {}
	for _, leg in ipairs(flown.legs) do
		modes[#modes + 1] = leg.mode
	end
	assert(table.concat(modes, ",") == "flight", table.concat(modes, ","))
	print("hazards: baked walks: ok")
end

-- A journey searches with the profile, shows its walk's lines under the step, and replans when the setting changes.
do
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local jns, walking = driver.ns, driver.path
	jns.db.avoidHighZones = true
	jns.level = 10
	jns.Zones = ns.Zones
	jns.TaxiNodes = { [1] = ns.TaxiNodes[1] }
	jns.zoneAt = ns.ZoneMap
	jns.TaxiName = function(id)
		return jns.TaxiNodes[id].name
	end
	jns.charDB.taxi = {}
	local mapInfo = driver.env.C_Map.GetMapInfo
	driver.env.C_Map.GetMapInfo = function(id)
		local info = mapInfo(id)
		info.name = "Zone " .. id
		return info
	end
	walking.draw = function(a, b)
		return { { map = a.map, x = a.x, y = a.y }, { map = 1, x = -500, y = 500 }, b }
	end
	driver.begin({ map = 1, x = -900, y = 0, z = 0 }, { map = 1, x = 1500, y = 0 })
	for _, list in ipairs({ walking.batches, walking.finds }) do
		for _, searched in ipairs(list) do
			assert(searched.hazards and searched.hazards.zones[200], "every search keeps away from the 18 zone")
		end
	end
	local _, rows = jns.JourneyInfo()
	local texts = {}
	for _, row in ipairs(rows) do
		texts[#texts + 1] = row.text
	end
	assert(
		rows[2] and rows[2].grey and rows[2].text == L["Hostile town: %s"]:format("Crossroads"),
		table.concat(texts, " | ")
	)
	assert(
		rows[3] and rows[3].text == L["Crosses %s (level %s)"]:format("Zone 200", "18-30"),
		table.concat(texts, " | ")
	)
	-- Walking on into another zone and an unrelated policy change keep the journey's costs: the start it exempts is
	-- where the journey began.
	local key = walking.batches[#walking.batches].hazards.key
	driver.move({ map = 1, x = 1200, y = 0, z = 0 })
	jns.TravelPolicyChanged()
	driver.update(0.1)
	assert(walking.batches[#walking.batches].hazards.key == key, "the same costs from wherever you are now")
	driver.move({ map = 1, x = -900, y = 0, z = 0 })
	-- Turning the setting off searches again without the zone.
	local before = #walking.batches
	jns.db.avoidHighZones = false
	jns.TravelPolicyChanged()
	driver.update(0.1)
	assert(#walking.batches > before, "searches again")
	assert(not walking.batches[#walking.batches].hazards.zones[200], "no zone avoided with the setting off")
	_, rows = jns.JourneyInfo()
	assert(rows[2] and rows[2].text == L["Hostile town: %s"]:format("Crossroads") and not rows[3], "the town stays")
	jns.ClearJourney()
	print("hazards: journey: ok")
end
print("hazards_spec: ok")

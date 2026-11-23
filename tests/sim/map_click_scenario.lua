-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")
-- A journey-key click on the world map canvas, through Blizzard's own scroll container and click registry, beside a
-- map addon that takes left clicks first. OpenMap zooms in on every plain or Alt left click at priority 1000, so
-- with Alt as the journey key the map zoomed and no journey was planned (#1076).

-- An OpenMap stand-in: its canvas handler leaves Shift-clicks to other addons and takes every other left click.
local OPENMAP = [[
local zooms = 0
WorldMapFrame:AddCanvasClickHandler(function(_, button)
	if button == "LeftButton" and not IsShiftKeyDown() then
		zooms = zooms + 1
		return true
	end
	return false
end, 1000)
function OpenMapStandInZooms()
	return zooms
end
]]

-- A journey-key click at (u, v) of the scroll container, from its left and bottom edges (0.4, 0.6 unless given). The
-- hover comes first: hovering a new frame puts the pointer at its middle.
local function Click(sim, key, u, v)
	local sc = sim.G.WorldMapFrame.ScrollContainer
	sim:hover(sc)
	local left, bottom, width, height = sc:GetRect()
	local scale = sc:GetEffectiveScale()
	sim.mouseX, sim.mouseY = (left + width * (u or 0.4)) * scale, (bottom + height * (v or 0.6)) * scale
	sim.modifiers[key] = true
	sim:input(function()
		sim.widgets.dispatch(sc, "OnMouseDown", "LeftButton")
	end)
	sim:input(function()
		sim.widgets.dispatch(sc, "OnMouseUp", "LeftButton", true)
	end)
	sim.modifiers[key] = nil
	sim:advance(0.2)
end

for _, key in ipairs({ "shift", "alt" }) do
	scenario("a " .. key .. "-click on the map plans a journey before another map addon's click handler", {
		addons = ForeverCore.addons(),
	}, function(sim)
		local player = sim.world.player
		player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
		player.map, player.x, player.y = 1429, 0.42, 0.65
		player.worldX, player.worldY, player.instance = -9449, 64, 0
		sim.world.maps[947] = { name = "Azeroth", mapType = 1 }
		sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
		sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
		sim:login()
		local ns
		for _, entry in ipairs(sim.loader.addons) do
			if entry.name == ADDON then
				ns = entry.ns
			end
		end
		assert(ns, "full addon namespace loaded")
		sim:runAs("OpenMap", OPENMAP)
		ns.db.journeyKey = key
		sim:openWorldMap(1429)
		sim:advance(0.5)
		-- The planner itself needs world data the simulator stands in for; the click reaching it is what matters.
		local planned
		local plan = ns.JourneyToMapPoint
		ns.JourneyToMapPoint = function(mapID, x, y)
			planned = { mapID = mapID, x = x, y = y }
		end
		Click(sim, key)
		ns.JourneyToMapPoint = plan
		assert(planned and planned.mapID == 1429, key .. "-click reached the journey planner")
		assert(sim.G.OpenMapStandInZooms() == 0, key .. "-click was not also taken as a zoom")
	end)
end

scenario("a journey-key click with journeys off says so on screen and leaves the map its click (#1076)", {
	addons = ForeverCore.addons(),
}, function(sim)
	local player = sim.world.player
	player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
	player.map, player.x, player.y = 1429, 0.42, 0.65
	player.worldX, player.worldY, player.instance = -9449, 64, 0
	sim.world.maps[947] = { name = "Azeroth", mapType = 1 }
	sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
	sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
	sim:login()
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns, "full addon namespace loaded")
	sim:runAs("OpenMap", OPENMAP)
	ns.db.journey = false
	sim:openWorldMap(1429)
	sim:advance(0.5)
	-- Blizzard's own UIErrorsFrame, with the client's colour constants: what reaches it is the line on screen.
	local errors, shown = sim.G.UIErrorsFrame, {}
	local add = errors.AddMessage
	errors.AddMessage = function(self, text, ...)
		shown[#shown + 1] = text
		return add(self, text, ...)
	end
	local chat = #sim.chat
	Click(sim, "shift")
	errors.AddMessage = add
	assert(
		shown[1] == "Journeys are off. Turn on Enable journeys in settings.",
		"the click says journeys are off on screen"
	)
	assert(#sim.chat == chat, "and nothing goes to chat")
	assert(not ns.HasJourney(), "nothing is planned")
end)

-- A map addon that draws the zones around the shown map lets the view scroll past that map's edge: it widens the
-- scroll extents, which Blizzard keeps inside the map (CalculateScrollExtentsAtScale), and scrolls there. It plans a
-- Shift-click there itself, as OpenMap's own handler does through ShortestPathForever.API.Navigate.
local ATLAS = [[
hooksecurefunc(WorldMapFrame.ScrollContainer, "CalculateScrollExtents", function(self)
	self.scrollXExtentsMin, self.scrollXExtentsMax = -1, 2
	self.scrollYExtentsMin, self.scrollYExtentsMax = -1, 2
end)
local taken = 0
WorldMapFrame:AddCanvasClickHandler(function(_, button)
	if button == "LeftButton" and IsShiftKeyDown() then
		taken = taken + 1
		return true
	end
	return false
end, 1000)
function AtlasStandInShiftClicks()
	return taken
end
-- Moves the view's centre east by a share of the map's width, at once: the simulator's GetTickTime is 0, so
-- Blizzard's eased pan (SetPanTarget, then FrameDeltaLerp each frame) never moves.
function AtlasStandInScrollEast(share)
	local sc = WorldMapFrame.ScrollContainer
	sc:InstantPanAndZoom(
		sc:GetCanvasScale(),
		sc:GetNormalizedHorizontalScroll() + share,
		sc:GetNormalizedVerticalScroll(),
		true
	)
end
]]

scenario("a shift-click past the map's edge is left to the map addon that scrolled the view there", {
	addons = ForeverCore.addons(),
}, function(sim)
	local player = sim.world.player
	player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
	player.map, player.x, player.y = 1429, 0.42, 0.65
	player.worldX, player.worldY, player.instance = -9449, 64, 0
	sim.world.maps[947] = { name = "Azeroth", mapType = 1 }
	sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
	sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
	sim:login()
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns, "full addon namespace loaded")
	sim:runAs("Atlas", ATLAS)
	local map = sim:openWorldMap(1429)
	sim:advance(0.5)
	-- The view's centre moves a quarter of the map's width east, so the view's right side shows past the map's edge.
	sim:runAs("Atlas", "AtlasStandInScrollEast(0.25)")
	sim:advance(0.5)
	assert(map.ScrollContainer:GetNormalizedHorizontalScroll() > 0.7, "the stand-in scrolled the view east")
	local planned
	local plan = ns.JourneyToMapPoint
	ns.JourneyToMapPoint = function(mapID, x, y)
		planned = { mapID = mapID, x = x, y = y }
	end
	Click(sim, "shift", 0.9, 0.5)
	-- There Blizzard clamps its own cursor position onto the edge (MapCanvasScrollControllerMixin:NormalizeUIPosition).
	assert(map:GetNormalizedCursorPosition() == 1, "past the edge, the game's cursor position is the map's edge")
	assert(not planned, "no journey is planned to the edge of the shown map")
	assert(sim.G.AtlasStandInShiftClicks() == 1, "the click goes on to the addon that drew past the edge")
	Click(sim, "shift", 0.1, 0.5)
	local x, y = map:GetNormalizedCursorPosition()
	assert(x < 1, "this click is on the shown map")
	assert(planned and planned.mapID == 1429 and planned.x == x and planned.y == y, "a click on the map plans there")
	assert(sim.G.AtlasStandInShiftClicks() == 1, "and stays this addon's")
	ns.JourneyToMapPoint = plan
end)

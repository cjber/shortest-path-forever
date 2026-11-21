-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")

-- A RestedXP stand-in, written from what the addon does in public: an arrow frame with a texture and a label, the
-- guide's active waypoints, and a ticker that re-runs its goto update and shows its arrow, as the addon's loop does.
local RXP_STANDIN = [[
RXP = { settings = { profile = { showEnabled = true } }, currentGuide = { name = "Elwynn" }, activeWaypoints = {} }
local af = CreateFrame("Frame", "RXPG_ARROW", UIParent)
RXP.arrowFrame = af
af:SetSize(32, 32)
af:SetPoint("TOP")
af:EnableMouse(true)
af.texture = af:CreateTexture()
af.texture:SetAllPoints()
af.text = af:CreateFontString(nil, "OVERLAY")
af.text:SetPoint("TOP", af, "BOTTOM", 0, -5)
function RXP.UpdateMap() end
function RXP.UpdateGotoSteps()
	if #RXP.activeWaypoints == 0 then
		RXP.hideArrow = true
		af:Hide()
		return
	end
	RXP.hideArrow = false
	af.element = RXP.activeWaypoints[1]
	af:Show()
end
function RXP.ResetArrowPosition() end
local ticker = CreateFrame("Frame")
local elapsed = 0
ticker:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed > 0.2 then
		elapsed = 0
		RXP.UpdateGotoSteps()
	end
end)
]]

local ELWYNN = 1429
local GOLDSHIRE = { zone = ELWYNN, x = 48, y = 60, title = "Goldshire", arrow = true, step = { active = true } }

local function LoginWithRestedXP(sim)
	local player = sim.world.player
	player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
	player.map, player.x, player.y = 1429, 0.42, 0.65
	-- The simulator answers UnitPosition with worldY first: north, then west.
	player.worldY, player.worldX, player.instance = -9449, 64, 0
	sim.world.maps[947] = { name = "Azeroth", mapType = 1 }
	sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
	sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
	-- Elwynn Forest's own bounds in world yards, so guide coordinates land on the walking maps.
	local LEFT, RIGHT, TOP, BOTTOM = 1535.42, -1935.42, -7939.58, -10254.2
	sim.impl["C_Map.GetWorldPosFromMapPos"] = function(_, position)
		local x, y = position:GetXY()
		return 0, sim.G.CreateVector2D(TOP - y * (TOP - BOTTOM), LEFT - x * (LEFT - RIGHT))
	end
	sim.impl["C_Map.GetMapPosFromWorldPos"] = function(_, world)
		local x, y = world:GetXY()
		return 1429, sim.G.CreateVector2D((LEFT - y) / (LEFT - RIGHT), (TOP - x) / (TOP - BOTTOM))
	end
	-- A player out in the world has a facing; without one the arrow has nothing to draw and leaves RestedXP's up.
	sim.impl["GetPlayerFacing"] = function()
		return 0
	end
	-- The client's own decoders, which the walking maps unpack with.
	local encoding = dofile("tools/nav_encoding.lua")
	sim.impl["C_EncodingUtil.DecodeBase64"] = encoding.DecodeBase64
	sim.impl["C_EncodingUtil.DecompressString"] = encoding.DecompressString
	sim:login()
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns, "full addon namespace loaded")
	sim:runAs("RXPGuides", RXP_STANDIN)
	local rxp = sim.G.RXP
	local element = sim.G.CopyTable(GOLDSHIRE)
	sim:input(function()
		rxp.activeWaypoints = { element }
	end)
	local API = sim.G.ShortestPathForever.API
	return ns, rxp, API
end

-- A journey's arrow waits for its proved route, which takes many frames of search. Until then RestedXP's own arrow
-- leads, so the player is never left with no arrow (#1124).
scenario("a RestedXP step always has an arrow: RestedXP's until the route lands, then Shortest Path's", {
	addons = ForeverCore.addons(),
}, function(sim)
	local ns, rxp, API = LoginWithRestedXP(sim)
	sim:event("ADDON_LOADED", "RXPGuides")
	local function Ours()
		return ns.GuideState() ~= nil
	end
	local function Theirs()
		return rxp.arrowFrame:IsShown() and rxp.arrowFrame.texture:IsShown()
	end
	-- RestedXP's own loop picks the step up and shows its arrow.
	sim:advance(0.5)
	local searched, landed = 0, false
	for _ = 1, 4000 do
		sim:advance(0.05)
		assert(API.CurrentStop("RestedXP") == 1, "the guide step is a journey")
		local ours, theirs = Ours(), Theirs()
		assert(ours ~= theirs, ours and "two arrows at once" or "no arrow at all")
		if ours then
			landed = true
			break
		end
		searched = searched + 1
	end
	assert(searched > 0, "the route took frames to search, RestedXP's arrow leading meanwhile")
	assert(landed, "Shortest Path's arrow took over once the route landed")
	assert(ns.GuideState(), "and it has a bend to point at")
	sim:expectNoErrors(ADDON)
end)

scenario("RestedXP walk hints stay faded on both maps while the route is searched", {
	addons = ForeverCore.addons(),
}, function(sim)
	-- The simulator does not supply a minimap radius. Use a view that contains the walk's first bend.
	sim.impl["C_Minimap.GetViewRadius"] = function()
		return 200
	end
	local ns, _, API = LoginWithRestedXP(sim)
	sim:openWorldMap(ELWYNN)
	local _, goalPosition =
		sim.impl["C_Map.GetWorldPosFromMapPos"](ELWYNN, sim.G.CreateVector2D(GOLDSHIRE.x / 100, GOLDSHIRE.y / 100))
	local goalX, goalY = goalPosition:GetXY()
	local goal, route
	local setRoute = ns.SetJourneyRoute
	ns.SetJourneyRoute = function(destination, plan)
		goal, route = destination, plan
		return setRoute(destination, plan)
	end
	local painters = ns.Strokes
	local probe = painters.New()
	local seen = {}

	local function Observe(surface)
		local draw = painters[surface]
		local state = { mostFull = 0 }
		seen[surface] = state
		painters[surface] = function(buffer, paths, view)
			local full = 0
			state.measuredFromPlayer = false
			local hereX, hereY, _, hereMap = ns.JourneyPosition()
			for index, path in ipairs(paths) do
				local first, last = path.points[1], path.points[#path.points]
				if
					path.mode == "walk"
					and first
					and last
					and first.map == hereMap
					and last.map == hereMap
					and math.abs(last.x - goalX) < 0.01
					and math.abs(last.y - goalY) < 0.01
				then
					-- Draw each matching path with its original layer priority to attribute the dots to that path.
					local pathView = setmetatable(
						{ current = index <= (view.current or 0) and 1 or 0 },
						{ __index = view }
					)
					draw(probe, { path }, pathView)
					local bright = false
					for stroke = 1, probe.n do
						bright = bright or probe.dot[stroke] and probe.alpha[stroke] == 1
					end
					full = full + (bright and 1 or 0)
					if #path.points == 2 and probe.n > 0 then
						state.brightHint = state.brightHint or bright
						state.fadedHint = state.fadedHint or not bright
					elseif bright and first.x == hereX and first.y == hereY then
						state.measuredFromPlayer = true
					end
				end
			end
			state.mostFull = math.max(state.mostFull, full)
			return draw(buffer, paths, view)
		end
	end

	Observe("Map")
	Observe("Minimap")
	sim:event("ADDON_LOADED", "RXPGuides")
	local function WaitForWalk()
		for _ = 1, 4000 do
			sim:advance(0.05)
			if seen.Map.measuredFromPlayer and seen.Minimap.measuredFromPlayer then
				return true
			end
		end
		return false
	end
	assert(WaitForWalk(), "both maps drew one measured walk from the player to Goldshire")
	assert(API.CurrentStop("RestedXP") == 1, "the guide step became a journey")

	-- Stage the overlap with a deferred walk to the same stop alongside the real measured leg. Give the deferred
	-- leg its own height key so it cannot reuse the measured leg's cached geometry.
	local measured = route.legs[1]
	local pending = {
		mode = "walk",
		from = measured.from,
		to = setmetatable({ z = (measured.to.z or 0) + 1 }, { __index = measured.to }),
		yards = measured.yards,
	}
	ns.JourneySearch.Walks.Prepare({ legs = { pending } }, nil, nil, function() end, 2)
	assert(pending.walkDeferred, "the second walk is still awaiting its geometry")
	local function CheckForDuplicates()
		assert(
			seen.Map.mostFull <= 1 and seen.Minimap.mostFull <= 1,
			("full-strength walks to Goldshire in one draw (world map: %d, minimap: %d)"):format(
				seen.Map.mostFull,
				seen.Minimap.mostFull
			)
		)
	end
	setRoute(goal, { legs = { measured, pending } })
	CheckForDuplicates()
	assert(seen.Map.fadedHint and seen.Minimap.fadedHint, "both maps drew a faded hint while a walk was pending")
	assert(not (seen.Map.brightHint or seen.Minimap.brightHint), "both maps reserve full strength for measured walks")
	setRoute(goal, route)

	local player = sim.world.player
	player.worldX = player.worldX + 100
	local _, position = sim.impl["C_Map.GetMapPosFromWorldPos"](0, sim.G.CreateVector2D(player.worldY, player.worldX))
	player.x, player.y = position:GetXY()
	seen.Map.measuredFromPlayer, seen.Minimap.measuredFromPlayer = false, false
	assert(WaitForWalk(), "both maps drew a measured walk from the player's new position")
	CheckForDuplicates()
	assert(not (seen.Map.brightHint or seen.Minimap.brightHint), "the replan never drew a full-strength hint")
	sim:expectNoErrors(ADDON)
end)

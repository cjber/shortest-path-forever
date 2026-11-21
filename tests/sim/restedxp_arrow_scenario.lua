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

-- A journey's arrow waits for its proved route, which takes many frames of search. Until then RestedXP's own arrow
-- leads, so the player is never left with no arrow (#1124).
scenario("a RestedXP step always has an arrow: RestedXP's until the route lands, then Shortest Path's", {
	addons = ForeverCore.addons(),
}, function(sim)
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
	local element = { zone = 1429, x = 48, y = 60, title = "Goldshire", arrow = true, step = { active = true } }
	sim:input(function()
		rxp.activeWaypoints = { element }
	end)
	sim:event("ADDON_LOADED", "RXPGuides")
	local API = sim.G.ShortestPathForever.API
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

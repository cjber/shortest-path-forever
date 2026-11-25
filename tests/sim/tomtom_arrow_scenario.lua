-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")
local FakeTomTom = assert(loadfile("tests/tomtom_fake.lua"))()

scenario("TomTom arrow option drives TomTom without native marker or loops", {
	addons = ForeverCore.addons(),
}, function(sim)
	local player = sim.world.player
	player.map, player.x, player.y = 1429, 0.1, 0.1
	player.worldY, player.worldX, player.instance = 100, 100, 0
	sim.world.maps[1429] = { name = "Elwynn Forest", mapType = 3 }
	sim.impl["GetPlayerFacing"] = function()
		return 0
	end
	sim.impl["C_Map.GetMapPosFromWorldPos"] = function(_, world)
		local x, y = world:GetXY()
		return 1429, sim.G.CreateVector2D(x / 1000, y / 1000)
	end
	local nativeWaypoint, superTracked = nil, false
	sim.impl["C_Map.SetUserWaypoint"] = function(point)
		nativeWaypoint = point
		return true
	end
	sim.impl["C_Map.GetUserWaypoint"] = function()
		return nativeWaypoint
	end
	sim.impl["C_Map.ClearUserWaypoint"] = function()
		nativeWaypoint = nil
	end
	sim.impl["C_SuperTrack.SetSuperTrackedUserWaypoint"] = function(value)
		superTracked = value == true
	end
	sim.impl["C_SuperTrack.IsSuperTrackingUserWaypoint"] = function()
		return superTracked
	end

	local crazy = { alpha = 0.7, mouse = true, hidden = true }
	function crazy:SetAlpha(value)
		self.alpha = value
	end
	function crazy:EnableMouse(value)
		self.mouse = value
	end
	function crazy:Show()
		self.hidden = false
	end
	function crazy:Hide()
		self.hidden = true
	end
	sim.G.TomTomCrazyArrow = crazy

	local isLoaded = sim.impl["C_AddOns.IsAddOnLoaded"]
	local exists = sim.impl["C_AddOns.DoesAddOnExist"]
	local enableState = sim.impl["C_AddOns.GetAddOnEnableState"]
	local tomtomLoaded = false
	sim.impl["C_AddOns.DoesAddOnExist"] = function(name)
		return name == "TomTom" or (exists and exists(name))
	end
	sim.impl["C_AddOns.IsAddOnLoaded"] = function(name)
		if name == "TomTom" then
			return tomtomLoaded
		end
		return isLoaded and isLoaded(name)
	end
	sim.impl["C_AddOns.GetAddOnEnableState"] = function(name, character)
		if name == "TomTom" then
			return 2
		end
		return enableState and enableState(name, character)
	end

	sim:login()
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns and ns.db.tomtomArrow == false, "tomtomArrow defaults off")

	local tomtom = FakeTomTom.New(nil, crazy)
	function tomtom.ShowHideCrazyArrow()
		crazy:Show()
		crazy:SetAlpha(0.7)
		crazy:EnableMouse(true)
	end
	sim.G.TomTom = tomtom
	tomtomLoaded = true
	sim:event("ADDON_LOADED", "TomTom")
	tomtom:Enable()
	sim:advance(0.1)

	local foreign = tomtom:Way(1429, 90, 90, "Foreign pin")
	ns.SetOption("tomtomFollow", true)
	ns.SetOption("tomtomArrow", true)

	local start = { map = 0, x = 100, y = 100 }
	local bend = { map = 0, x = 250, y = 250 }
	local goal = { map = 0, x = 500, y = 400, routeTitle = "Goldshire" }
	ns.JourneyGuide.Start()
	ns.JourneyGuide.To(goal, { start, bend, goal }, goal)

	local first = tomtom.Arrow()
	assert(type(first) == "table" and first ~= foreign, "TomTom arrow points at our bend waypoint")
	assert(math.abs(first[2] - 0.25) < 1e-6 and math.abs(first[3] - 0.25) < 1e-6, "bend coordinates match")
	assert(nativeWaypoint == nil and not superTracked, "native navigation marker stays hidden")
	assert(crazy.alpha == 0.7, "TomTom arrow stays visible")

	player.worldY, player.worldX = bend.x, bend.y
	ns.AdvanceGuide()
	local second = tomtom.Arrow()
	assert(second ~= first and not tomtom:IsValidWaypoint(first), "advancing replaces the old bend waypoint")
	assert(math.abs(second[2] - 0.5) < 1e-6 and math.abs(second[3] - 0.4) < 1e-6, "goal coordinates match")

	ns.JourneyGuide.Stop("cleared")
	assert(not tomtom:IsValidWaypoint(second), "stopping removes our driven waypoint")
	assert(tomtom:IsValidWaypoint(foreign), "foreign waypoint is untouched")
	sim:expectNoErrors(ADDON)
end)

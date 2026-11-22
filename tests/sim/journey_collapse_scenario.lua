-- luacheck: read globals scenario ADDON
local core = dofile("tests/forever_core.lua")

scenario("Journey stays collapsed when the last quest is untracked", { addons = core.addons() }, function(sim)
	local G = sim.G
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
	assert(ns, "SPF loaded")
	sim:input(function()
		ns.StartJourney(ns.DockPoint(5))
	end)
	sim:advance(1)
	assert(ns.JourneyGoal(), "the journey started")

	local tracker = sim:openObjectiveTracker()
	-- The sim has no quest-watch data. Stand in for the quest module inside the real native container.
	local questList = G.CreateFrame("Frame", nil, tracker)
	questList.uiOrder, questList.leftMargin = 1, 0
	questList.SetContainer = function() end
	questList.Update = function(frame)
		frame:SetSize(240, 60)
		frame:Show()
		return 60, false
	end
	questList.GetContentsHeight = function()
		return 60
	end
	questList.IsTruncated = function()
		return false
	end
	tracker:AddModule(questList)
	sim:advance(1)
	assert(tracker:IsShown(), "the watched quest shows the native tracker")
	local journey = assert(G.ShortestPathForeverObjectiveTracker)
	assert(journey:GetExistingBlock("journey").used, "SPF produced the journey block")
	sim:click(journey.Header.MinimizeButton)
	sim:advance(0.1)
	assert(journey:IsCollapsed(), "the player collapsed the Journey section")

	tracker:RemoveModule(questList)
	sim:event("QUEST_WATCH_LIST_CHANGED", 1, false)
	sim:event("QUEST_LOG_UPDATE")
	sim:advance(1)
	assert(not tracker:IsShown(), "the last untrack hid the native tracker")
	assert(journey:IsCollapsed(), "Journey stays collapsed after the native tracker hides")
	assert(journey.firstBlock == nil, "the collapsed Journey only displays its header")

	local previousTitle = journey.blocks[1].title
	sim:input(function()
		ns.StartJourney(ns.DockPoint(6))
	end)
	sim:advance(1)
	assert(journey.blocks[1].title ~= previousTitle, "SPF produced a different journey while the tracker was hidden")
	assert(journey:IsCollapsed() and journey.firstBlock == nil, "the producer refresh leaves Journey collapsed")

	local column = assert(G.ForeverTrackerCompanion)
	column:MarkDirty()
	sim:advance(1)
	assert(journey:IsCollapsed() and journey.firstBlock == nil, "a full rebuild leaves Journey collapsed")
	tracker:AddModule(questList)
	sim:event("QUEST_WATCH_LIST_CHANGED", 1, true)
	sim:advance(1)
	assert(tracker:IsShown(), "retracking restores the native tracker")
	assert(journey:IsCollapsed() and journey.firstBlock == nil, "retracking leaves Journey collapsed")
	sim:click(journey.Header.MinimizeButton)
	sim:advance(0.1)
	assert(not journey:IsCollapsed() and journey.firstBlock, "the player can reopen Journey")
	sim:expectNoErrors(ADDON)
	sim:expectNoErrors("ForeverCore")
end)

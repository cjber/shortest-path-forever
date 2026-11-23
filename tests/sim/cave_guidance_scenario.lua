-- luacheck: read globals scenario ADDON
local core = dofile("tests/forever_core.lua")
scenario(
	"The journey's current walking row gives one cave entrance instruction",
	{ addons = core.addons() },
	function(sim)
		local player = sim.world.player
		player.faction, player.race, player.raceFile = "Alliance", "Human", "Human"
		player.map, player.x, player.y = 1429, 0.6, 0.5
		player.worldY, player.worldX, player.instance = -9106.57, -545.27, 0
		sim.world.maps[947] = { name = "Azeroth", mapType = 1 }
		sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
		sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
		sim.impl.GetPlayerFacing = function()
			return 0
		end
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
		assert(ns, "Shortest Path loaded")
		local hint = "Descend underground"
		sim:openObjectiveTracker()
		sim:input(function()
			ns.StartJourney({ map = 0, x = -9046.57, y = -545.27, z = 62, label = "Jasperlode Mine" })
		end)
		local path
		for _ = 1, 100 do
			sim:advance(0.25)
			local _, points = ns.GuideState()
			if points and points[1].x == player.worldY then
				path = points
				break
			end
		end
		assert(path, "the walking route arrived")
		local entrance
		for i = 1, #path - 1 do
			local point = path[i]
			sim:input(function()
				player.worldY, player.worldX = point.x, point.y
			end)
			sim:advance(0.3)
			if not point.depth and path[i + 1].depth then
				entrance = path[i + 1]
				break
			end
		end
		assert(entrance, "the route enters the cave")
		assert(ns.GuideInstruction() == hint, "walking arrow cues descent before the cave")
		local tracker = assert(sim.G.ShortestPathForeverObjectiveTracker)
		local function hints()
			local count = 0
			for _, block in ipairs(tracker.blocks) do
				for _, row in ipairs(block.rows or {}) do
					if row.text and row.text:find(hint, 1, true) then
						assert(row.current and row.mode == "walk", "only the current walk gives the cue")
						count = count + 1
					end
				end
			end
			return count
		end
		sim:advance(1)
		assert(hints() == 1, "the tracker includes the cue once")
		sim:input(function()
			player.worldY, player.worldX = entrance.x, entrance.y
		end)
		sim:advance(1)
		assert(not ns.GuideInstruction(), "crossing the entrance clears the cue")
		assert(hints() == 0, "the tracker clears the cue after entering")
		sim:expectNoErrors(ADDON)
	end
)

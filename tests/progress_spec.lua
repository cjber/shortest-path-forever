local TOC = dofile("tests/toc_fields.lua").read("ShortestPathForever.toc")
local now, x, moving = 0, 0, true
local tick, taxi, ride
local chat, notices = {}, {}
local ns = {
	db = { stats = true },
	charDB = {},
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	CurrentRide = function()
		return ride
	end,
	OnTravelTick = function(fn)
		tick = fn
	end,
	Init = function(fn)
		fn()
	end,
	JourneyPosition = function()
		return x, 0, nil, 1
	end,
	Print = function(message)
		chat[#chat + 1] = message
	end,
	Notice = function(message)
		notices[#notices + 1] = message
	end,
	core = {
		SafeCall = function(_, fn, ...)
			return pcall(fn, ...)
		end,
	},
}
local frames = {}
local env = setmetatable({
	BreakUpLargeNumbers = function(value)
		return value == 1000 and "1,000" or tostring(value)
	end,
	GetTime = function()
		return now
	end,
	GetServerTime = function()
		return math.floor(now)
	end,
	UnitPosition = function()
		return x, 0, 0, 1
	end,
	IsPlayerMoving = function()
		return moving
	end,
	UnitOnTaxi = function()
		return taxi
	end,
	C_AddOns = {
		GetAddOnMetadata = function(name, field)
			return name == "ShortestPathForever" and TOC[field] or nil
		end,
	},
	C_Timer = { After = function() end },
	CreateFrame = function()
		local frame = {}
		frame.RegisterEvent = function() end
		frame.SetScript = function(self, _, fn)
			self.OnEvent = fn
		end
		frames[#frames + 1] = frame
		return frame
	end,
}, { __index = _G })
env._G = env
local core = dofile("tests/forever_core.lua")
env.ForeverCore = {
	API = 1,
	Open = core.load(env, "ForeverCore", { "Core/Open.lua" }).Open,
	APIKit = { Hub = function() end, NotReady = function() end },
	TrackerSection = { Create = function() end, UpdateText = function() end },
	TrackerLine = { SetInteractive = function() end },
	TrackerHost = { HandleBlockHeaderClick = function() end },
	Art = { minor = 2, Marker = function() end, Ring = function() end, Diamond = function() end },
	QuestLogTabs = { SetTabShown = function() end },
}
setfenv(assert(loadfile("Core/ForeverRequire.lua")), env)("ShortestPathForever", ns)
setfenv(assert(loadfile("Core/Require.lua")), env)("ShortestPathForever", ns)
setfenv(assert(loadfile("Core/Progress.lua")), env)("ShortestPathForever", ns)

assert(not env.ForeverCore.PeerStats, "progress does not require the retired peer API")
assert(not ns.TravelBoard and not ns.OpenTravelLeaderboard, "leaderboard integration is removed")
tick()
now, x = 1, 7
tick()
assert(ns.TravelStats().walkedYards == 7, "local movement remains recorded")
ns.ProgressJourneyChanged(nil, "arrived")
assert(ns.TravelStats().routesCompleted == 1, "completed journeys remain local")
assert(ns.TravelStats().peers == nil, "snapshots no longer expose peer data")
ns.charDB.progress.walkedYards = 993
now, x = 2, 14
tick()
now, x = 3, 21
tick()
-- Older saves that already announced a first milestone only show the next threshold.
local stats = ns.charDB.progress
stats.transportsUsed, stats.flightsTaken, stats.portalsUsed = 9, 9, 9
for _, marker in ipairs({ "transports:1", "flights:1", "portals:1" }) do
	stats.milestones[marker] = 1
end
ride = 42
tick()
ride, taxi = nil, true
tick()
local portalPlan = { legs = { { mode = "portal" } } }
ns.JourneyPlan = function()
	return portalPlan, 1
end
frames[1]:OnEvent("ZONE_CHANGED_NEW_AREA")
frames[1]:OnEvent("ZONE_CHANGED_NEW_AREA")

assert(#chat == 0, "travel milestones must stay out of chat: " .. table.concat(chat, ", "))
assert(#notices == 5, "each reached milestone is shown once")
assert(notices[1] == "You've completed your first journey.", notices[1])
assert(notices[2] == "You've walked 1,000 yards.", notices[2])
assert(notices[3] == "You've taken 10 transport rides.", notices[3])
assert(notices[4] == "You've taken 10 flights.", notices[4])
assert(notices[5] == "You've used 10 portals or passages.", notices[5])
assert(ns.TravelStats().milestones["distance:1000"] == 2, "the saved milestone key and timestamp are preserved")
print("progress_spec: local journal works without peer or leaderboard APIs")

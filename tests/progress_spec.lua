local TOC = dofile("tests/toc_fields.lua").read("ShortestPathForever.toc")
local now, x, moving = 0, 0, true
local tick
local ns = {
	db = { stats = true },
	charDB = {},
	L = setmetatable({}, { __index = function(_, key) return key end }),
	OnTravelTick = function(fn) tick = fn end,
	Init = function(fn) fn() end,
	JourneyPosition = function() return x, 0, nil, 1 end,
	Print = function() end,
	core = { SafeCall = function(_, fn, ...) return pcall(fn, ...) end },
}
local frames = {}
local env = setmetatable({
	GetTime = function() return now end,
	GetServerTime = function() return math.floor(now) end,
	UnitPosition = function() return x, 0, 0, 1 end,
	IsPlayerMoving = function() return moving end,
	UnitOnTaxi = function() return false end,
	C_AddOns = { GetAddOnMetadata = function(name, field) return name == "ShortestPathForever" and TOC[field] or nil end },
	C_Timer = { After = function() end },
	CreateFrame = function()
		local frame = {}
		function frame:RegisterEvent() end
		frame.SetScript = function(frame, _, fn) frame.OnEvent = fn end
		frames[#frames + 1] = frame
		return frame
	end,
}, { __index = _G })
env._G = env
dofile("tests/forever_core.lua")
env.ForeverCore = {
	API = 1,
	APIKit = { Hub = function() end, NotReady = function() end },
	TrackerSection = { Create = function() end, UpdateText = function() end },
	TrackerLine = { SetInteractive = function() end },
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
print("progress_spec: local journal works without peer or leaderboard APIs")

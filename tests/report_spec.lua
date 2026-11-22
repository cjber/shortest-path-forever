-- Exercise SPF's report producer and the real shared report export, without opening a window or searching.
local env = setmetatable({
	C_AddOns = {
		GetAddOnMetadata = function()
			return "test-version"
		end,
		GetNumAddOns = function()
			return 0
		end,
	},
	GetBuildInfo = function()
		return "1.60.1", "70938", "", 16001
	end,
	GetLocale = function()
		return "enUS"
	end,
	UnitClass = function()
		return nil, "Mage"
	end,
	UnitRace = function()
		return nil, "Human"
	end,
	UnitLevel = function()
		return 60
	end,
	UnitFactionGroup = function()
		return "Alliance"
	end,
	UnitOnTaxi = function()
		return false
	end,
	C_Map = { GetBestMapForUnit = function() end },
	geterrorhandler = function()
		return function() end
	end,
	seterrorhandler = function() end,
	GetTime = function()
		return 1
	end,
	date = function()
		return "date"
	end,
}, { __index = _G })
local shared = dofile("tests/forever_core.lua").load(env, "ForeverCore", {
	"Core/SafeCall.lua",
	"Core/Log.lua",
	"UI/Report.lua",
})
local leg = {
	mode = "walk",
	from = { map = 0, x = 1.123456789012345, y = 2 },
	to = { map = 0, x = 3, y = 4, z = 0 },
	depart = 0,
	arrive = 1000,
	measured = false,
	walkDrawn = false,
	walkPlaceholder = true,
	walkDeferred = true,
	estimated = false,
}
local plan = { legs = { leg }, waterMode = false }
local ns = {
	core = { Report = shared.ReportFor("ShortestPathForever") },
	db = { journey = true, avoidHighZones = true, followRoads = false, roadDetour = 50, useWaterWalking = false },
	charDB = { avoided = { { kind = "flight", ids = { "1:2", "2:3" }, name = "Fly to Test" } } },
	Locate = function() end,
	KnownFlightPointsByContinent = function()
		return {}
	end,
	CurrentRide = function() end,
	IsObservingRide = function()
		return false
	end,
	JourneyGoal = function()
		return leg.to
	end,
	JourneyOwner = function()
		return "player"
	end,
	JourneyStops = function() end,
	IsJourneyGuided = function()
		return true
	end,
	PlaceLabel = function()
		return "Goal"
	end,
	JourneyStatus = function()
		return false, 1
	end,
	JourneyPlan = function()
		return plan, 1
	end,
	LegLabel = function()
		return "Goal"
	end,
}
env.ShortestPathForeverPathData = { [0] = { format = 3, cells = 67, zstep = 2, steep = true, climbChecked = true } }
local chunk = assert(loadfile("Core/Report.lua"))
setfenv(chunk, env)("ShortestPathForever", ns)
local function contains(text, expected)
	assert(text:find(expected, 1, true), "missing report evidence: " .. expected .. "\n" .. text)
end
local function report()
	return ns.core.Report.Text(ns.ReportLines())
end
local text = report()
contains(text, "ShortestPathForever test-version | WoW 1.60.1 (70938) 16001")
contains(text, "avoidHighZones true, followRoads false, roadDetour 50, useWaterWalking false")
contains(text, ("x %.17g y 2 z unknown"):format(leg.from.x))
contains(text, "map 0 x 3 y 4 z 0")
contains(text, "measured false, drawn false, placeholder true, deferred true; estimated cost false")
contains(text, "format 3, cells 67, zstep 2, steep true, climbChecked true; revision unknown")
contains(text, "Plan water walking: false")
contains(text, "Avoided transport: 1\n  flight 1:2, 2:3 (Fly to Test)")
assert(not text:find("Search first route", 1, true), "no timings before a journey search has any")
-- The client's own timings, to compare with the simulator's: wall time, frames that ran path work, and their cost.
local status = ns.JourneyStatus
local first = { ms = 5020, frames = 120, cpu = 301.4, fps = 24.2 }
ns.JourneyStatus = function()
	return false, 1, nil, false, { first = first, last = { ms = 6100, frames = 150, cpu = 380, fps = 30 } }
end
text = report()
contains(text, "Search first route: 5.02 s, 120 work frames, 301 ms path work, 24 fps")
contains(text, "Search last route: 6.10 s, 150 work frames, 380 ms path work, 30 fps")
ns.JourneyStatus = status
leg.from.z, leg.to.z = 0, nil
leg.measured, leg.walkDrawn, leg.walkPlaceholder, leg.walkDeferred = true, true, nil, nil
text = report()
contains(text, ("x %.17g y 2 z 0"):format(leg.from.x))
contains(text, "map 0 x 3 y 4 z unknown")
contains(text, "measured true, drawn true, placeholder unknown, deferred unknown")
-- A retained older drawing is not proof that the current search has measured this leg.
leg.measured = false
contains(report(), "measured false, drawn true")
env.ShortestPathForeverPathData = nil
ns.db.roadDetour, plan.waterMode, leg.estimated = nil, nil, nil
text = report()
contains(text, "roadDetour unknown")
contains(text, "Plan water walking: unknown")
contains(text, "estimated cost unknown")
contains(text, "Nav map 0: unknown")
-- Completed walks must not crowd the active fifth leg out of the shared 1000-character section.
leg.from.x, leg.from.y = -8949.951171875, -132.4931640625
leg.to.x, leg.to.y, leg.to.z = -8833.37890625, 628.5546875, 94.375
local active = {}
for key, value in pairs(leg) do
	active[key] = value
end
active.from = { map = 0, x = -9000.123456789012, y = 700.5, z = 0 }
active.to = { map = 0, x = -9100.987654321098, y = 800.25 }
active.walkError = "unreachable"
local taxi = { mode = "taxi", from = leg.to, to = leg.from, depart = 1000, arrive = 2000 }
plan.legs = { leg, taxi, leg, taxi, active }
ns.JourneyPlan = function()
	return plan, 5
end
text = report()
for index, mode in ipairs({ "walk", "taxi", "walk", "taxi", "walk" }) do
	contains(text, ("%d. %s to Goal, 1s"):format(index, mode))
end
contains(text, "> 5. walk to Goal, 1s, walk failed: unreachable")
contains(text, "Walk 5:")
contains(text, ("map 0 x %.17g y 700.5 z 0"):format(active.from.x))
contains(text, ("map 0 x %.17g y 800.25 z unknown"):format(active.to.x))
contains(text, "measured false, drawn true, placeholder unknown, deferred unknown; estimated cost unknown")
contains(text, "Nav map 0: unknown")
env.ShortestPathForeverPathData = { [0] = { format = 3, cells = 67, zstep = 2, steep = true, climbChecked = true } }
text = report()
contains(text, "> 5. walk to Goal, 1s, walk failed: unreachable")
contains(text, ("Walk 5: map 0 x %.17g y 700.5 z 0"):format(active.from.x))
contains(text, ("map 0 x %.17g y 800.25 z unknown"):format(active.to.x))
contains(text, "format 3, cells 67, zstep 2, steep true, climbChecked true; revision unknown")
print("report_spec: passed")

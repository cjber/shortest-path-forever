local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns, env, checks = driver.ns, driver.env, 0
driver.load("UI/Looks.lua")
driver.load("Core/APIInput.lua")
driver.load("Core/APIStops.lua")
driver.load("Core/API.lua")
driver.load("Journey/StopOrder.lua")
local API = env.ShortestPathForever.API
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function point(x, map, title)
	return { map = map or 1, x = x, y = 0.5, title = title }
end
local from = point(0.5)
-- Observe real API calls without replacing any ns function or the API producer.
local calls = 0
debug.sethook(function(event)
	if event == "call" and debug.getinfo(2, "f").func == API.Estimate then
		calls = calls + 1
	end
end, "c")
local function begin(stops, origin)
	local before = calls
	local job = ns.StopOrder.Begin(stops, origin or from)
	equal(calls, before, "Begin never estimates")
	return job
end
local function step(job)
	local before = calls
	local status, points = job:Step()
	equal(calls - before <= 1, true, "at most one estimate per Step")
	equal(status, job.status, "returned status")
	equal(points, job.points, "returned published points")
	return status
end
local function finish(job)
	for _ = 1, 2080 do
		step(job)
		if job.status ~= "working" then
			return job
		end
	end
	error("ordering did not finish within the API capacity's 2080 estimates")
end
local function invalid(stops, origin)
	local job = begin(stops, origin)
	equal(job.status, "invalid", "invalid input rejected before work")
	local before = calls
	step(job)
	equal(calls, before, "invalid job cannot estimate")
	equal(job.points, nil, "invalid job publishes nothing")
end
invalid({})
invalid(false)
invalid({ point(0.51), false })
invalid({ [1] = point(0.51), [3] = point(0.52) })
invalid({ point(0.51), extra = point(0.52) })
invalid({ point(0.51) }, driver.secret)
invalid({ driver.secret })
equal(ns.StopOrder.Begin({ point(0.51) }, nil).status, "invalid", "missing origin")
equal(ns.StopOrder.Begin({ point(0.51) }, false).status, "invalid", "false origin")
local projection = env.C_Map.GetWorldPosFromMapPos
env.C_Map.GetWorldPosFromMapPos = function()
	return nil
end
invalid({ point(0.51) })
env.C_Map.GetWorldPosFromMapPos = projection
for _, value in ipairs({ driver.secret, 0 / 0, math.huge, -math.huge, "0.5", false, -0.1, 1.1 }) do
	invalid({ { map = 1, x = value, y = 0.5 } })
	invalid({ point(0.51) }, { map = 1, x = 0.5, y = value })
end
for _, value in ipairs({ 0, 1.5, math.huge, driver.secret }) do
	invalid({ { map = value, x = 0.5, y = 0.5 } })
end
for _, field in ipairs({
	"title",
	"tooltip",
	"kind",
	"hold",
	"radius",
	"z",
	"questID",
	"npc",
	"questIDs",
	"handins",
	"shapes",
}) do
	local stop = point(0.51)
	stop[field] = driver.secret
	invalid({ stop })
end
invalid({ setmetatable(point(0.51), { __index = from }) })
invalid({ { map = 1, x = 0.51, y = 0.5, questIDs = { [2] = 7 } } })
invalid({ { map = 1, x = 0.51, y = 0.5, shapes = { point(0.51) } } })
local many = {}
for index = 1, 65 do
	many[index] = point(0.5 + index / 10000)
end
invalid(many)
many[65] = nil
local before = calls
local capacity = finish(begin(many))
equal(capacity.status, "ready", "64 stops accepted")
equal(#capacity.points, 64, "all stops retained")
equal(calls - before, 2080, "64-stop worst case spread across 2080 steps")
local one = finish(begin({ point(0.5) }))
equal(one.status, "ready", "one stop and zero-time estimate valid")
equal(#one.points, 1, "single destination")
local stops = { point(0.53, 1, "Far"), point(0.51, 1, "Near"), point(0.52, 1, "Middle") }
stops[2].z, stops[2].tooltip, stops[2].kind = 42, "Details", "vendor"
stops[2].questIDs, stops[2].handins = { 7 }, { 8 }
stops[2].shapes = { { map = 1, x = 0.51, y = 0.5, radius = 20 } }
local origin = point(0.5)
local job = begin(stops, origin)
stops[2].x, stops[2].title, stops[2].questIDs[1], stops[2].shapes[1].radius = 0.9, "Changed", 100, 999
origin.x, stops[1] = 0.95, false
step(job)
equal(job.points, nil, "no partial order")
finish(job)
equal(job.points[1].title, "Near", "nearest first from copied origin")
equal(job.points[2].title, "Middle", "next from chosen destination")
equal(job.points[3].title, "Far", "far last")
equal(job.points[1].z, 42, "height retained")
equal(job.points[1].tooltip, "Details", "tooltip retained")
equal(job.points[1].kind, "vendor", "kind retained")
equal(job.points[1].questIDs[1], 7, "nested quest list copied")
equal(job.points[1].shapes[1].radius, 20, "nested shape copied")
local tied = finish(begin({ point(0.51, 1, "First"), point(0.51, 1, "Second") }))
equal(tied.points[1].title, "First", "input-index ties stable")
equal(tied.points[2].title, "Second", "duplicates retained")
local absent = begin({ point(0.51) })
local exported = env.ShortestPathForever
env.ShortestPathForever = nil
equal(step(absent), "loading", "missing API waits")
env.ShortestPathForever = exported
equal(step(absent), "ready", "published API retries pending candidate")
local blocked = begin({ point(0.51) })
local db = ns.db
ns.db = nil
equal(step(blocked), "loading", "loading waits")
equal(blocked.points, nil, "loading publishes nothing")
ns.db = db
env.InCombatLockdown = function()
	return true
end
equal(step(blocked), "combat", "combat waits")
env.InCombatLockdown = function()
	return false
end
equal(step(blocked), "ready", "pending candidate retries after combat/loading")
local unreachable = begin({ point(0.5, 2), point(0.51) })
equal(step(unreachable), "working", "unreachable first candidate skipped")
equal(step(unreachable), "working", "reachable candidate selected")
equal(step(unreachable), "unreachable", "fails only when every remaining candidate unreachable")
equal(unreachable.points, nil, "failed order publishes no partial list")
-- The real planner's hearth makes the farther point quicker, and does not apply
-- that hearth to subsequent origins. This distinguishes travel time from geometry.
ns.teleports = { { map = 1, x = 0, y = 4990, spell = 8690, item = 6948, cast = 10000, bind = true } }
ns.teleportReady = { ns.NowMs() }
driver.move({ map = 1, x = 0, y = 0 })
local directed = finish(begin({ point(0.49, 1, "Near walk"), point(0.4, 1, "Hearth") }))
equal(directed.points[1].title, "Hearth", "estimated transport beats nearer walk")
equal(directed.points[2].title, "Near walk", "later origin uses conservative public estimate")
ns.teleports, ns.teleportReady = nil, nil
for _, state in ipairs({ "working", "ready", "loading", "combat" }) do
	local cancelled = begin({ point(0.51), point(0.52) })
	if state == "ready" then
		finish(cancelled)
	elseif state == "loading" then
		ns.db = nil
		step(cancelled)
		ns.db = db
	elseif state == "combat" then
		env.InCombatLockdown = function()
			return true
		end
		step(cancelled)
		env.InCombatLockdown = function()
			return false
		end
	end
	cancelled:Cancel()
	local previous = calls
	for _ = 1, 3 do
		step(cancelled)
	end
	equal(calls, previous, "cancelled " .. state .. " does no more work")
	equal(cancelled.points, nil, "cancelled " .. state .. " never publishes")
end
local previous = calls
step(one)
equal(calls, previous, "ready job does no more work")
-- Bundled network fixture from api_spec: Auberdine to Eastern Plaguelands
-- crosses continents by boat and flight, preserving public UI-map coordinates.
for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
}) do
	driver.load(file)
end
local project = env.C_Map.GetWorldPosFromMapPos
env.C_Map.GetWorldPosFromMapPos = function(map, position)
	return project(map == 2 and 0 or map, position)
end
ns.known = {}
for id in pairs(ns.TaxiNodes) do
	ns.known[id] = true
end
local function taxi(id)
	local node = ns.TaxiNodes[id]
	return { map = node.map == 0 and 2 or node.map, x = 0.5 - node.y / 50000, y = 0.5 - node.x / 50000 }
end
local cross = finish(begin({ taxi(67), taxi(27) }, taxi(26)))
equal(cross.status, "ready", "real cross-continent transport order settles")
equal(cross.points[1].map, 1, "nearby Kalimdor stop first")
equal(cross.points[2].map, 2, "Eastern Kingdoms UI map retained")
equal(ns.HasJourney(), false, "ordering never starts guidance")

-- Canonical API context invalidation must discard previously accepted candidates.
do
	local changedContext = begin({ point(0.51), point(0.52), point(0.53) })
	equal(step(changedContext), "working", "first context candidate")
	local known = ns.known or {}
	ns.known = known
	known[987654] = true
	equal(step(changedContext), "invalid", "in-place taxi discovery invalidates partial work")
	equal(changedContext.reason, "context-changed", "explicit context change")
	equal(changedContext.points, nil, "no mixed-context points published")
	local callsBefore = calls
	step(changedContext)
	equal(calls, callsBefore, "invalidated job cannot continue")
	known[987654] = nil
end

-- The real party-portal producer deliberately omits portals from later origins.
-- This endpoint policy must not look like an external routing-input change.
driver.load("Data/Teleports.lua")
driver.load("Data/Zones.lua")
env._G = env
env.UNKNOWN = "Unknown"
env.IsInGroup = function()
	return true
end
env.IsInRaid = function()
	return false
end
env.GetNumGroupMembers = function()
	return 2
end
env.UnitIsUnit = function(a, b)
	return a == b
end
env.UnitClass = function(unit)
	if unit == "party1" then
		return "Mage", "MAGE"
	end
end
local mageName = "Fixture mage"
env.UnitName = function(unit)
	if unit == "party1" then
		return mageName
	end
end
ns.db.partyMagePortals = true
driver.load("Transport/PartyPortals.lua")
driver.move({ map = 1, x = 0, y = 0, z = 0 })
equal(#ns.PartyPortalPlaces({ map = 1, x = 0, y = 0 }) > 0, true, "real declared party portal fixture")
equal(#ns.PartyPortalPlaces(ns.WorldPoint(1, 0.51, 0.5)), 0, "later origins cannot ask party mage")
local partyOrder = finish(begin({ point(0.51), point(0.52) }))
equal(partyOrder.status, "ready", "later-origin portal omission is not changed context")
local declaredOrder = begin({ point(0.51), point(0.52) })
equal(step(declaredOrder), "working", "party declaration baseline")
ns.db.partyMageStormwind = false
equal(step(declaredOrder), "invalid", "actual declared portal change invalidates")
equal(declaredOrder.reason, "context-changed", "declaration change reason")
equal(declaredOrder.points, nil, "changed party declaration publishes nothing")
local mageOrder = begin({ point(0.51), point(0.52) })
equal(step(mageOrder), "working", "party mage baseline")
mageName = "Other fixture mage"
equal(step(mageOrder), "invalid", "actual party mage change invalidates")
equal(mageOrder.reason, "context-changed", "mage change reason")

debug.sethook()
print("stop_order_spec: " .. checks .. " checks passed")

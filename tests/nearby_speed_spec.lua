-- Drive the real Nearby panel on Eastern Kingdoms nav. Copy this file and services_panel_frames.lua to main and
-- run with --bench for a comparison without assertions. Add --reload to measure only a cold reload.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
for _, f in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
	"Data/TownAreas.lua",
	"Data/Heights.lua",
	"Data/IdleSpawns.lua",
	"Data/Services.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
}) do
	driver.load(f)
end
assert(loadfile("tools/load_nav.lua"))(0)
driver.load("Core/APIInput.lua")
driver.load("Core/API.lua")
driver.env._G = driver.env
local project = driver.env.C_Map.GetWorldPosFromMapPos
driver.env.C_Map.GetWorldPosFromMapPos = function(map, point)
	local _, world = project(map, point)
	return 0, world
end
driver.env.C_Timer = { After = function() end }
for _, f in ipairs({
	"UI/MenuModifier.lua",
	"UI/NearbyGroups.lua",
	"UI/NearbyQuestie.lua",
	"UI/NearbyEntrances.lua",
	"UI/NearbyRoles.lua",
	"UI/NearbyProfessions.lua",
	"UI/NearbyRank.lua",
	"UI/Nearby.lua",
}) do
	driver.load(f)
end
local nextFrame
ns.Path.after = function(fn, delay)
	-- All three positions are visited within the terrain cache's 30-second linger.
	if not delay then
		nextFrame = fn
	end
end
ns.faction, ns.water, ns.speed, ns.known = "Alliance", false, 7, {}
for id in pairs(ns.TaxiNodes) do
	ns.known[id] = true
end
ns.teleports, ns.teleportReady = {}, {}
driver.load("Routing/Floor.lua")

local function ui(x, y)
	return 0.5 - y / 50000, 0.5 - x / 50000
end
local rows = {}
local function add(key, id, x, y)
	rows[key] = rows[key] or {}
	local p = { map = 1453, id = id, name = key .. id, world = { map = 0, x = x, y = y } }
	p.x, p.y = ui(x, y)
	table.insert(rows[key], p)
end
local spawns = ns.IdleSpawns[0]
for _, tbl in ipairs({ { "class", ns.ClassTrainers }, { "prof", ns.ProfessionTrainers } }) do
	for npc, what in pairs(tbl[2]) do
		local s = spawns[npc]
		if s then
			local x, y = s:match("^(%S+) (%S+)")
			add(tbl[1] .. tostring(what), npc, tonumber(x), tonumber(y))
		end
	end
end
for id, node in pairs(ns.TaxiNodes) do
	if node.map == 0 then
		add("flight", id, node.x, node.y)
	end
end

local function shortlist(list, at)
	table.sort(list, function(a, b)
		local da = (a.world.x - at.x) ^ 2 + (a.world.y - at.y) ^ 2
		local db = (b.world.x - at.x) ^ 2 + (b.world.y - at.y) ^ 2
		return da < db or da == db and a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(5, #list) do
		out[i] = list[i]
	end
	return out
end

local frame, region, frames = assert(loadfile("tests/services_panel_frames.lua"))()
local env = driver.env
env.CreateFrame = frame
env.QuestMapFrame = frame("Frame")
env.QuestMapFrame.ContentsAnchor = frame("Frame")
env.EventUtil = {
	ContinueOnAddOnLoaded = function(_, attach)
		attach()
	end,
}
env.GetZoneText = function()
	return "Stormwind City"
end
env.GetSubZoneText = function()
	return "Trade District"
end
env.NORMAL_FONT_COLOR = { r = 1, g = 1, b = 1 }
local tab, tick, tickSeconds
env.ForeverCore = setmetatable({
	QuestLogTabs = {
		Register = function(_, spec)
			tab = spec
			return { Icon = region() }
		end,
		SetTabShown = function() end,
	},
}, { __index = env.ForeverCore })
env.C_Timer.NewTicker = function(seconds, callback)
	tick, tickSeconds = callback, seconds
	return { Cancel = function() end }
end
ns.Art = {
	Icon = function() end,
	Fit = function() end,
	RowArt = function() end,
	Band = function() end,
	CoverFrame = function() end,
}
ns.Init = function() end
ns.core = { SafeCall = function() end }
ns.TownServiceFilterable = function()
	return false
end
ns.FormatCountdown = tostring

local at
local services = ns.NearbyServices
services.Request = function() end
services.OnReady = function() end
services.State = function()
	return "ready"
end
services.PlayerWorld = function()
	return at
end
services.PlayerUi = function()
	local x, y = ui(at.x, at.y)
	return 1453, x, y
end
services.Goods = function() end
services.Detail = function(_, place)
	return place.name
end
local rowsInOrder = {}
for key in pairs(rows) do
	rowsInOrder[#rowsInOrder + 1] = key
end
table.sort(rowsInOrder)
local currentFrame, decided
services.Sections = function()
	-- Queue's final Refresh is called only when all rows decide. The initial and ticker refresh are outside a pump.
	if currentFrame > 0 then
		decided = currentFrame
	end
	local entries = {}
	for _, key in ipairs(rowsInOrder) do
		local group = { key = key, label = key, icon = "Banker", section = "trainers" }
		entries[#entries + 1] = { id = key, group = group, npc = shortlist(rows[key], at)[1] }
	end
	return { { section = "trainers", label = "Trainers", count = #entries, rows = entries } }
end
services.Shortlist = function(key, world, limit)
	assert(limit == 5)
	return shortlist(rows[key], world)
end

local jobs = {}
local findMany = ns.Path.FindMany
ns.Path.FindMany = function(...)
	local job = findMany(...)
	jobs[#jobs + 1] = job
	return job
end
local function pump()
	local fn = nextFrame
	nextFrame = nil
	fn()
end
driver.load("UI/ServicesPanel.lua")

local origin = { map = 0, x = -8832.076, y = 595.038 }
local steps = {
	{ "reload", origin },
	{ "move 5 yd", { map = 0, x = origin.x + 5, y = origin.y } },
	{ "move 10 yd", { map = 0, x = origin.x + 15, y = origin.y } },
}
local bench, reloadOnly = arg[1] == "--bench", arg[2] == "--reload"
local passed, movementPassed = true, true
local function times()
	local shown = {}
	for _, row in ipairs(frames) do
		if row.Time and row:IsShown() then
			shown[row.id] = row.Time:GetText()
		end
	end
	return shown
end

print("Nearby                First  All fresh  Decided  Walk frames  CPU (s)  Tick (s)")
for index, step in ipairs(steps) do
	local before = times()
	at = step[2]
	driver.move(at)
	ns.Floor.Sample(0, at.x, at.y)
	while nextFrame do
		pump()
	end
	jobs, currentFrame, decided = {}, 0, nil
	local start = os.clock()
	if index == 1 then
		tab.shown(true)
	else
		-- The move happened just after the preceding tick. Advance to the next movement check.
		tick()
	end
	local first, allShown, walkFrames, slices = nil, nil, 0, 0
	while currentFrame < 3000 do
		local shown = 0
		for key, value in pairs(times()) do
			if value ~= "" and value ~= before[key] then
				shown = shown + 1
			end
		end
		if shown > 0 then
			first = first or currentFrame
		end
		if shown == #rowsInOrder then
			allShown = allShown or currentFrame
		end
		if not nextFrame then
			break
		end
		currentFrame = currentFrame + 1
		pump()
		local total = 0
		for _, job in ipairs(jobs) do
			total = total + job.frames
		end
		if total > slices then
			walkFrames, slices = walkFrames + 1, total
		end
	end
	print(
		string.format(
			"%-20s %5s %10s %8s %12d %8.2f %9s",
			step[1],
			tostring(first),
			tostring(allShown),
			tostring(decided),
			walkFrames,
			os.clock() - start,
			index == 1 and "-" or tostring(tickSeconds)
		)
	)
	-- Every row decides once the walking search reaches its nearest NPC, which is bound by the search speed of the
	-- machine: like the journey bench budgets, the decision limit is checked only under SPF_BENCH_STRICT=1.
	local decidedLimit = os.getenv("SPF_BENCH_STRICT") == "1" and 400 or math.huge
	passed = passed
		and allShown ~= nil
		and allShown <= 10
		and decided ~= nil
		and decided <= decidedLimit
		and not nextFrame
	if index > 1 then
		movementPassed = movementPassed and tickSeconds <= 1 and allShown ~= nil and allShown <= 60 and #jobs > 0
	end
	if reloadOnly then
		break
	end
end
tab.shown(false)
if not bench then
	assert(movementPassed, "movement must refresh every row within a one-second check and 60 path frames")
	assert(
		passed,
		"expected fresh row times within 10 frames and every row decided (within 400 frames under SPF_BENCH_STRICT)"
	)
end

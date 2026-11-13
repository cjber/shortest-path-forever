-- The guided waypoint's tooltip: the leg's destination in place of the client's generic "Map Pin", on the minimap and
-- the world map, with the journey's goal under an intermediate hop, and only while Guide owns the waypoint.
local dir = arg[0]:match("^(.*)/") or "tests"

-- The whole-client layer runs against checksum-pinned Blizzard source, which tests/ui.sh fetches.
local probe = "tools/.cache/blizzard-ui/Interface/AddOns/Blizzard_SharedXML/Spinner.lua"
do
	local handle = io.open(probe)
	if handle then
		handle:close()
	else
		local ok = os.execute("bash tools/fetch_blizzard_ui.sh")
		assert(
			ok == true or ok == 0,
			"could not fetch the pinned Blizzard UI fixture for tests/waypoint_label_spec.lua"
		)
	end
end

local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end

local setup = [[
setMapShown(true)
posX, posY, posMap, facing = 0, 0, 1, 0
ns.CurrentRide = noop
local mid = { map=1, x=300, y=100, label="Dock" }
ns.Planner.Plan = function(o)
 return {now=o.now, arrive=o.now+200000, legs={
  {mode="walk", from=o.from, to=mid, yards=300, depart=o.now, arrive=o.now+100000},
  {mode="walk", from=mid, to=o.to, yards=300, depart=o.now+100000, arrive=o.now+200000},
 }}
end
path.draw = function(a, b)
 return {a, {map=1,x=150,y=100}, mid, b}
end
local function start()
 posX, posY, posMap = 0, 0, 1
 mapID, cursorX, cursorY = 1414, 0.5, 0.452
 assert(clickHandlers[1](map, "LeftButton"))
 settle()
 assert(ns.IsJourneyGuided() and waypoint and supertracked)
end
]]

local fixture = source:gsub('fireEvent%("ADDON_LOADED", "ShortestPathForever"%)', function()
	return '\nwaypointProvider:RefreshAllData()\nfireEvent("ADDON_LOADED", "ShortestPathForever")'
		-- Login reads TOC metadata; the remaining checks retain the client addon-loading API.
		.. '\n_G.C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end,'
		.. " IsAddOnLoaded = function() return false end }"
		.. '\nfireEvent("PLAYER_LOGIN")\n_G.C_AddOns = { IsAddOnLoaded = function() return false end }'
end, 1)

local body = [[
local guide = ns.JourneyGuide
assert(type(guide.WaypointNames) == "function", "JourneyGuide must name the waypoint it owns")
local callbacks = tooltipCallbacks[Enum.TooltipDataType.MinimapMouseover]
assert(callbacks and #callbacks > 0, "the minimap waypoint tooltip must be hooked")

start()
local title, goalTitle = guide.WaypointNames()
assert(title == "Dock", "the waypoint names the leg's destination, got " .. tostring(title))
assert(goalTitle and goalTitle:find("^Journey to "), "an intermediate hop also names the journey's goal")

GameTooltip_SetTitle(GameTooltip, MAP_PIN_SHARING)
guide.NameWaypointTooltip(GameTooltip, true)
assert(GameTooltipTextLeft1:GetText() == "Dock", "the map's waypoint title names the leg's destination")
assert(tip[#tip] == "  " .. goalTitle, "the map's waypoint adds the journey's goal under a hop")

-- The minimap's client tooltip is the real "Map Pin" (MAP_PIN), not the map pin's "Map Pin Sharing".
GameTooltip_SetTitle(GameTooltip, MAP_PIN)
for _, post in ipairs(callbacks) do
 post(GameTooltip)
end
assert(GameTooltipTextLeft1:GetText() == "Dock", "the minimap's waypoint title names the leg's destination")
assert(tip[#tip] == "  " .. goalTitle, "the minimap's waypoint adds the journey's goal under a hop")

-- 1.60.1 hands the minimap's title over as a secret value: readable, never comparable. Nothing readable says that
-- tooltip is the waypoint, so the client's title stays and no error reaches the player (#824). Both sides of the
-- addon's compare are secret objects here so Lua reaches __eq, as the client's own comparison of a secret does.
local readablePin = MAP_PIN
local secretTitle = setmetatable({}, {
	__eq = function()
		error("attempt to compare a secret string value", 0)
	end,
})
MAP_PIN = setmetatable({}, getmetatable(secretTitle))
GameTooltipTextLeft1:SetText(secret(secretTitle))
for _, post in ipairs(callbacks) do
	post(GameTooltip)
end
assert(rawequal(GameTooltipTextLeft1:GetText(), secretTitle), "a secret minimap title keeps the client's tooltip")
MAP_PIN = readablePin

-- A pin the player places is not Guide's, so the client's own title and lines stay.
ns.ClearJourney()
C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(1414, 0.7, 0.8, 42))
GameTooltip_SetTitle(GameTooltip, MAP_PIN)
for _, post in ipairs(callbacks) do
 post(GameTooltip)
end
assert(GameTooltipTextLeft1:GetText() == MAP_PIN, "a player's own pin keeps the minimap's title")
assert(#tip == 1, "a player's own pin keeps the client's lines")

-- The final leg already ends where our own goal pin stands, so only the destination line is needed.
start()
local goal = ns.JourneyGoal()
guide.To(goal, nil, goal, { mode="walk", from=goal, to=goal })
local finalTitle, finalGoal = guide.WaypointNames()
assert(finalTitle and not finalGoal, "a leg ending at the goal adds no second line")
]]

local run = assert(
	loadstring(
		"_G.ShortestPathForeverDB, _G.ShortestPathForeverCharDB = nil, nil\n"
			.. fixture
			.. setup
			.. body
			.. '\nassert(#errors == 0, table.concat(errors, "\\n"))',
		"waypoint label"
	)
)
local ok, err = pcall(run)
assert(ok, err)
print("waypoint label: ok")

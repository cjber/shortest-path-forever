-- The minimap route button as the addon really builds it: a journey through the public API, the button turning
-- the game's gold, and its click running Journey's own Guide toggle through the tracker's refresh seam.
local dir = arg[0]:match("^(.*)/") or "tests"
local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [[
visible, WorldMapFrame.shown = true, true
posX, posY, posMap, facing = 0, 0, 1, 0
mapID = 1414
zoom = 1
ns.Docks, ns.Routes, ns.TaxiNodes, ns.TaxiPaths, ns.Portals, ns.Landmasses = {}, {}, {}, {}, {}, {}
local api = ShortestPathForever.API
local button = assert(ShortestPathForeverRouteButton, "the route button is built with its setting on")
assert(not button.hidden, "and shown")
assert(button.anchor[1] == "CENTER" and button.anchor[2] == Minimap and button.anchor[3] == "CENTER")
assert(button.Plate.atlas == "ui-hud-minimap-button", "the game's own minimap button plate")
local function plate() return button.Plate.color or { 1, 1, 1 } end
local function neutral() return plate()[1] == 1 and plate()[2] == 1 and plate()[3] == 1 end
local function gold() return plate()[1] == 1 and plate()[2] == 0.82 and plate()[3] == 0 end
assert(neutral(), "no route yet: the plate's own colours")

-- A real journey: Guide is on from the start of one, so the button wears the gold at once.
assert(api.NavigateRoute("RouteButton", { { map = 1414, x = 0.51, y = 0.5 }, { map = 1414, x = 0.55, y = 0.5 } }))
assert(ns.IsJourneyGuided() and ns.HasJourney())
assert(gold(), "gold while a route is on")

-- The click is Journey's own toggle: the route stops, the journey stays, and the tracker's refresh repaints.
button.scripts.OnClick(button, "LeftButton")
assert(not ns.IsJourneyGuided(), "the click stopped the route")
assert(ns.HasJourney(), "and left the journey itself alone")
assert(neutral(), "the plate returns to its own colours")
button.scripts.OnClick(button, "LeftButton")
assert(ns.IsJourneyGuided(), "clicking again starts the route")
assert(gold(), "gold again")
api.Cancel("RouteButton")
assert(not ns.HasJourney() and not ns.IsJourneyGuided() and neutral(), "a cleared journey leaves no gold behind")

-- The setting hides the button, and the same one shows it again.
ns.SetOption("routeButton", false)
assert(button.hidden, "the setting off hides the button")
ns.SetOption("routeButton", true)
assert(not button.hidden, "and back on shows it")
assert(#errors == 0, table.concat(errors, "\n"))
print("route button ui: journey, gold, click toggle, clear and setting: ok")
]]))()

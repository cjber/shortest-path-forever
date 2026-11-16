-- Minimap transport pins: placement, rim, tooltips, the tracking menu and idle polling.
local dir = arg[0]:match("^(.*)/") or "tests"
local source = ""
for _, part in ipairs({ "ui_client.lua", "ui_map.lua" }) do
	local file = assert(io.open(dir .. "/" .. part))
	source = source .. file:read("*a")
	file:close()
end
assert(loadstring(source .. [[
local layer = ShortestPathForeverMinimapPins
local ZEPPELIN = "Interface\\AddOns\\ShortestPathForever\\media\\Zeppelin"
local function shown()
 local list = {}
 for _, pin in ipairs(layer.children or {}) do
  if pin:IsShown() then list[#list + 1] = pin end
 end
 return list
end
-- Only timers created by this transport layer are advanced here.
local transportTimers = {}
local newTicker = C_Timer.NewTicker
C_Timer.NewTicker = function(interval, fn)
 local ticker = newTicker(interval, fn)
 transportTimers[#transportTimers + 1] = ticker
 return ticker
end
local function polling()
 local count = 0
 for _, ticker in ipairs(transportTimers) do
  if not ticker.cancelled then count = count + 1 end
 end
 return count
end
local function frame(seconds)
 for _ = 1, seconds * 60 do
  T = T + 1 / 60
  for _, ticker in ipairs(transportTimers) do
   if not ticker.cancelled and T >= ticker.next then
    ticker.next = ticker.next + ticker.every
    ticker.fn()
   end
  end
  if layer.scripts.OnUpdate then layer.scripts.OnUpdate(layer, 1 / 60) end
 end
end

-- Beside Rut'theran Village's pier: its ferry shows, and nothing a continent away does.
local dock = ns.Docks[7].walk or ns.Docks[7]
posX, posY, posZ, posMap = dock.x + 60, dock.y, dock.z or 0, dock.map
ns.RefreshMinimapPins()
local pins = shown()
local ferry
for _, pin in ipairs(pins) do
 if pin.entry.cluster and pin.entry.cluster.docks[1].id == 7 then ferry = pin end
end
assert(ferry and ferry.Texture.atlas == "flightmasterferry", "the pier's ferry shows on the minimap")
-- 60 yards north of the player on a 200-yard radius, 200-pixel minimap: 30 pixels down.
local anchor = ferry.anchor
assert(math.abs(anchor[4]) < 0.01 and math.abs(anchor[5] + 30) < 0.01, "projected like the route")
for _, pin in ipairs(pins) do
 assert(pin.entry.map == posMap and math.abs(pin.entry.x - posX) < 200, "only places in view")
end

ns.db.minimapPinScale = 50
ns.RefreshMinimapPins()
assert(ferry:GetWidth() == 8 and math.abs(ferry.anchor[5] + 30) < 0.01,
 "smaller minimap icons retain their projected position")
ns.db.minimapPinScale = 100
ns.RefreshMinimapPins()

-- Stationary nearby docks must never retain a layer callback; polling still detects eventless motion.
assert(not layer.scripts.OnUpdate and polling() == 1, "stationary dock uses one timer, no per-frame driver")
frame(1)
assert(not layer.scripts.OnUpdate and polling() == 1, "stationary dock remains settled")
local oldY = ferry.anchor[5]
posX = posX + 10
frame(0.2)
assert(ferry.anchor[5] ~= oldY, "passive movement redraws without a movement event")
posX = posX - 10
frame(0.2)

-- The world map's tooltip, refreshed each second while hovered.
ferry.scripts.OnEnter(ferry)
assert(GameTooltip:IsOwned(ferry) and tip[1]:find("Boat to", 1, true), "the dock's departures tooltip")
assert(ferry.scripts.OnUpdate, "hover keeps its separate tooltip callback")
ferry.scripts.OnUpdate(ferry, 1)
assert(GameTooltip:IsOwned(ferry), "hover refresh preserves tooltip ownership")
ferry.scripts.OnLeave(ferry)
assert(not GameTooltip:IsOwned(ferry) and not ferry.scripts.OnUpdate, "leaving stops hover updates")

-- A zeppelin uses the addon's own file, not the ferry atlas its boat neighbours use.
local wasX, wasY, wasZ, wasMap = posX, posY, posZ, posMap
local zeppelinDock = ns.Docks[13]
ns.db.otherFaction = true
posX, posY, posZ, posMap = zeppelinDock.x, zeppelinDock.y, zeppelinDock.z or 0, zeppelinDock.map
ns.RefreshMinimapPins()
local zeppelin
for _, pin in ipairs(shown()) do
 if pin.entry.cluster and pin.entry.cluster.docks[1].id == 13 then zeppelin = pin end
end
assert(zeppelin and zeppelin.Texture.texture == ZEPPELIN, "the tower's zeppelin shows its own art on the minimap")
assert(zeppelin.Texture.atlas == nil, "not the ferry atlas")
ns.db.otherFaction = false
posX, posY, posZ, posMap = wasX, wasY, wasZ, wasMap
ns.RefreshMinimapPins()

-- The rim: a place just inside the view but under the frame's edge is hidden, never clamped.
posX = dock.x + 195
frame(0.2)
for _, pin in ipairs(shown()) do
 assert(pin.entry.cluster == nil or pin.entry.cluster.docks[1].id ~= 7, "a pier at the rim hides")
end
assert(not layer.scripts.OnUpdate and polling() == 1, "near the rim keeps timer polling only")

-- Far from every place: pins hide and the owned polling timer stops.
posX, posY = 0, 0
frame(0.2)
assert(#shown() == 0 and not layer.scripts.OnUpdate and polling() == 0, "far away cancels polling")

-- The tracking menu's Transport checkbox mirrors the setting.
local entries, initializer = {}, nil
local root = {CreateCheckbox = function(_, text, get, set)
 entries[text] = {get = get, set = set}
 return {AddInitializer = function(_, fn) initializer = fn end}
end}
menus.MENU_MINIMAP_TRACKING(nil, root)
local transport = assert(entries.Transport, "a Transport entry in minimap tracking")
local icon = {SetSize = noop, SetPoint = noop, SetAtlas = function(self, atlas) self.atlas = atlas end}
local width = initializer({AttachTexture = function() return icon end,
 fontString = {SetPoint = noop, GetUnboundedStringWidth = function() return 50 end}})
assert(icon.atlas == "flightmasterferry" and width == 110, "the tracking menu's icon style")
posX, posY = dock.x + 60, dock.y
assert(transport.get())
transport.set()
assert(not ns.db.minimapPins and #shown() == 0 or not layer:IsVisible(), "off hides the pins")
transport.set()
assert(ns.db.minimapPins and #shown() > 0, "on shows them again")

-- Portals settle too, independently of dock clustering.
local portal
for _, candidate in ipairs(ns.Portals) do
 if ns.PortalShown(candidate) then portal = candidate; break end
end
assert(portal, "a visible portal fixture")
posX, posY, posMap = portal.from.x + 60, portal.from.y, portal.from.map
ns.RefreshMinimapPins()
local portalPin
for _, pin in ipairs(shown()) do
 if pin.entry.portal == portal then portalPin = pin end
end
assert(portalPin and not layer.scripts.OnUpdate and polling() == 1, "stationary portal uses timer only")
-- Warm caches, then measure stationary polling independently of callback absence.
frame(1)
jit.off()
jit.flush()
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
frame(1)
local kb = collectgarbage("count") - before
collectgarbage("restart")
assert(kb == 0, "settled unhovered transport polling allocates nothing in the fixture")
assert(not layer.scripts.OnUpdate, "stationary portal remains free of per-frame callbacks")

-- Effective visibility follows the parent, even while the layer itself remains shown.
local journeyPosition, samples = ns.JourneyPosition, 0
ns.JourneyPosition = function(...)
 samples = samples + 1
 return journeyPosition(...)
end
Minimap:Hide()
assert(layer:IsShown() and not layer:IsVisible(), "hidden parent leaves the layer shown but invisible")
assert(polling() == 0, "hidden minimap cancels transport polling")
frame(1)
assert(samples == 0, "hidden minimap takes no position samples")
fireEvent("MINIMAP_UPDATE_ZOOM")
ns.RefreshMinimapPins()
assert(polling() == 0 and samples == 0, "wake and refresh while hidden cannot sample or start polling")
local hiddenY = portalPin.anchor[5]
posX = posX + 10
Minimap:Show()
assert(polling() == 1 and samples == 1 and portalPin.anchor[5] ~= hiddenY,
 "show redraws the moved view and resumes exactly one timer")
frame(0.2)
assert(samples > 1 and polling() == 1, "shown minimap continues polling")
Minimap:Hide()
combat = true
Minimap:Show()
assert(polling() == 0, "show during combat cannot resume polling")
combat = false
fireEvent("PLAYER_REGEN_ENABLED")
assert(polling() == 1, "combat end resumes polling after show")
Minimap:Hide()
ns.db.minimapPins = false
ns.RefreshMinimapPins()
Minimap:Show()
fireEvent("MINIMAP_UPDATE_ZOOM")
assert(polling() == 0 and not layer:IsVisible(), "show preserves disabled minimap pins")
ns.db.minimapPins = true
ns.RefreshMinimapPins()
assert(polling() == 1, "enabling visible pins resumes one timer")
ns.JourneyPosition = journeyPosition

local previous = transportTimers[#transportTimers]
ns.RefreshMinimapPins()
assert(previous.cancelled and polling() == 1, "refresh replaces the owned timer")
combat = true
fireEvent("PLAYER_REGEN_DISABLED")
assert(polling() == 0, "combat cancels polling")
combat = false
fireEvent("PLAYER_REGEN_ENABLED")
assert(polling() == 1, "combat end resumes nearby polling")
ns.HideMinimapPins()
assert(polling() == 0 and #shown() == 0, "hide cancels polling")
-- View events wake the same poller after it has stopped.
fireEvent("MINIMAP_UPDATE_ZOOM")
assert(polling() == 1 and #shown() > 0, "view event wakes nearby polling")
ns.db.minimapPins = false
ns.RefreshMinimapPins()
assert(polling() == 0, "disabled setting cancels polling")
ns.db.minimapPins = true
ns.RefreshMinimapPins()
-- The focused lifecycle invocation avoids the existing redraw benchmark.
if arg[1] ~= "idle" then
 posX, posY, posMap = dock.x + 60, dock.y, dock.map
 ns.RefreshMinimapPins()
 -- Bench: a minute running past the pier at 60 fps, redrawn every tenth of a second, after one warm-up run has
 -- grown the pin pool. The harness's own SetPoint records its anchor in a new table, so it is replaced to count
 -- only the addon's allocations.
 local function run()
  for i = 1, 3600 do
   posX = dock.x + 60 + 7 * i / 60
   frame(1 / 60)
  end
 end
 run()
 for _, pin in ipairs(layer.children) do pin.SetPoint = noop end
 -- The interpreter, as in the game: JIT traces allocate on their own schedule.
 jit.off()
 jit.flush()
 collectgarbage("collect")
 collectgarbage("stop")
 local before, start = collectgarbage("count"), os.clock()
 run()
 local ms, kb = (os.clock() - start) * 1000, collectgarbage("count") - before
 collectgarbage("restart")
 print(string.format("minimap_ui: 60 s past a pier: %.2f ms, %.4f ms/redraw, %.2f KB allocated", ms, ms / 600, kb))
 assert(ms / 600 < 0.2, "a redraw stays well under a fifth of a millisecond")
 assert(kb < 1, "with the pool grown, redraws reuse pins and allocate next to nothing")
end
ns.HideMinimapPins()
C_Timer.NewTicker = newTicker
assert(#errors == 0, table.concat(errors, "\n"))
print("minimap_ui: placement, hover, passive movement, stationary dock/portal and timer lifecycle ok")
]]))()

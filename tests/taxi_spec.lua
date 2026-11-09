local ns = {}
function ns.Init(fn)
	ns.init = fn
end

local current, reachable, unreachable = 0, 1, 2
local mapNodes = {
	{ nodeID = 103, slotIndex = 1, state = reachable, name = "Sturmwind" },
	{ nodeID = 101, slotIndex = 3, state = current },
	{ nodeID = 102, slotIndex = 4, state = reachable },
	-- The flight master reports this node reachable, but the client gives its slot type NONE, so it is not shown.
	{ nodeID = 104, slotIndex = 5, state = reachable, name = "Ghostlands" },
	{ nodeID = 105, slotIndex = 2, state = reachable, name = "Kharanos" },
	-- The new query returns this undiscovered node and this client still gives its slot a non-NONE type, but the
	-- classic list ends at five entries, so the character does not really have it.
	{ nodeID = 106, slotIndex = 6, state = reachable, name = "Light's Hope" },
}
local nodeTypes = { "REACHABLE", "DISTANT", "CURRENT", "REACHABLE", "NONE" }
local staleTypes = { [6] = "REACHABLE" }
local nodeNames = {
	[1] = "Sturmwind",
	[2] = "Kharanos",
	[3] = "Ironforge",
	[4] = "Menethil Harbor",
	[5] = "Ghostlands",
	[6] = "Light's Hope",
}
local numNodes = #nodeTypes
-- The client's chosen route deliberately differs from the planner's intermediate hop.
local routes = { [1] = { { 3, 2 }, { 2, 1 } }, [4] = { { 3, 4 } } }
local textures, eventFrame = {}, nil
local tooltip, stockDraws, routeQueries = false, 0, 0
local region = {}
region.__index = region
local function widget(fields)
	local value = fields or {}
	value.scripts, value.hooks = {}, {}
	return setmetatable(value, region)
end
function region:SetScript(event, fn)
	assert(event ~= "OnUpdate", "taxi guidance must not poll")
	self.scripts[event] = fn
end
function region:HookScript(event, fn)
	assert(not self.hooks[event], "hook each button only once")
	self.hooks[event] = fn
end
function region:Run(event, ...)
	if self.scripts[event] then
		self.scripts[event](self, ...)
	end
	if self.hooks[event] then
		self.hooks[event](self, ...)
	end
end
function region:RegisterEvent(event)
	self.events = self.events or {}
	self.events[event] = true
end
function region:IsShown()
	return self.shown
end
function region:Show()
	if not self.shown then
		self.shown = true
		self:Run("OnShow")
	end
end
function region:Hide()
	if self.shown then
		self.shown = false
		self:Run("OnHide")
	end
end
function region:GetID()
	return self.id
end
function region:GetPoint()
	return "CENTER", "TaxiMap", "BOTTOMLEFT", self.x, self.y
end
function region:LockHighlight()
	self.locked = true
end
function region:UnlockHighlight()
	self.locked = false
end
function region:SetTexture(path)
	self.path = path
end
function region.CreateTexture(_, name, layer)
	assert(name == nil and layer == "BACKGROUND", "addon lines do not replace stock named textures")
	local texture = widget()
	textures[#textures + 1] = texture
	return texture
end

local env = setmetatable({
	Enum = { FlightPathState = { Current = current, Reachable = reachable, Unreachable = unreachable } },
	C_TaxiMap = {
		GetAllTaxiNodes = function(map)
			assert(map == 99, "only query the current flight master's map")
			return mapNodes
		end,
	},
	GetTaxiMapID = function()
		return 99
	end,
	NumTaxiNodes = function()
		return numNodes
	end,
	TaxiNodeGetType = function(slot)
		return staleTypes[slot] or nodeTypes[slot]
	end,
	GetNumRoutes = function(slot)
		routeQueries = routeQueries + 1
		return #(routes[slot] or {})
	end,
	TaxiGetNodeSlot = function(slot, hop, source)
		return routes[slot][hop][source and 1 or 2]
	end,
	TaxiNodeName = function(slot)
		return nodeNames[slot] or ""
	end,
	TaxiNodePosition = function()
		error("never guess a slot from unverified coordinates")
	end,
	TakeTaxiNode = function()
		error("never fly automatically")
	end,
	TaxiFrame = widget(),
	TaxiRouteMap = widget(),
	NUM_TAXI_ROUTES = 1,
	TAXIROUTE_LINEFACTOR = 32 / 30,
	TaxiRoute1 = widget(),
	CreateFrame = function()
		eventFrame = widget()
		return eventFrame
	end,
	DrawLine = function(line, canvas, sx, sy, dx, dy, width, factor)
		assert(canvas == "TaxiRouteMap" and width == 32 and factor == 32 / 30, "stock line drawing parameters")
		line.points = { sx, sy, dx, dy }
	end,
	hooksecurefunc = function(target, key, fn)
		assert(
			target == ns and (key == "SetJourneyRoute" or key == "JourneyChanged"),
			"only hook journey notifications"
		)
		local original = assert(target[key])
		target[key] = function(...)
			original(...)
			fn(...)
		end
	end,
}, { __index = _G })
env._G = env
function env.DrawOneHopLines()
	stockDraws = stockDraws + 1
	env.TaxiRoute1:Show()
	for slot, kind in ipairs(nodeTypes) do
		if kind == "DISTANT" then
			env["TaxiButton" .. slot]:Hide()
		end
	end
end
for slot = 1, #nodeTypes do
	local button = widget({ id = slot, x = slot * 20, y = slot * 30 })
	env["TaxiButton" .. slot] = button
	button:SetScript("OnEnter", function()
		tooltip = true
		if nodeTypes[slot] ~= "DISTANT" then
			env.DrawOneHopLines()
		end
	end)
	button:SetScript("OnLeave", function()
		tooltip = false
		env.TaxiRoute1:Hide()
	end)
end
env.TaxiFrame:SetScript("OnShow", function()
	for slot, kind in ipairs(nodeTypes) do
		local button = env["TaxiButton" .. slot]
		if kind ~= "DISTANT" and kind ~= "NONE" then
			button:Show()
		end
	end
	env.DrawOneHopLines()
end)

setfenv(assert(loadfile("Transport/Taxi.lua")), env)("ShortestPathForever", ns)
local flight = {
	mode = "flight",
	from = { id = 101 },
	to = { id = 103 },
	hops = { { from = 101, to = 102 }, { from = 102, to = 103 } },
}
local walk = { mode = "walk" }
assert(ns.TaxiDestination({ flight }, 101) == 103, "origin on route selects the merged leg's final node")
assert(ns.TaxiDestination({ flight }, 102) == 103, "origin midway through merged hops selects the final node")
assert(ns.TaxiDestination({ flight }, 999) == nil, "origin off the route selects nothing")
assert(ns.TaxiDestination({ flight }, 103) == nil, "already at the final node")
assert(ns.TaxiDestination({ walk, flight }, 101) == 103, "the approach walk can still be current")
assert(ns.TaxiDestination({ walk, walk, flight }, 101) == nil, "a later flight is not the next step")
assert(ns.TaxiDestination({ { mode = "boat" }, flight }, 101) == nil, "do not skip a transport to offer a flight")
assert(ns.TaxiDestination(nil, 101) == nil and ns.TaxiDestination({}, 101) == nil)

ns.db = { taxiRoute = true }
ns.TaxiNodes = {
	[101] = { name = "Ironforge" },
	[102] = {},
	[103] = { name = "Stormwind" },
	[104] = { name = "Ghostlands" },
	[105] = { name = "Kharanos" },
	[106] = { name = "Light's Hope" },
}
ns.TaxiNodes[101].faction, ns.TaxiNodes[103].faction = "Alliance", "Horde"
ns.SetJourneyRoute = function() end
ns.JourneyChanged = function() end
-- A version 3 list was built from node slots that claimed undiscovered nodes, so init starts it again from empty.
env.ShortestPathForeverCharDB = {
	taxi = { [101] = true, [106] = true },
	taxiNames = { [101] = "Ironforge", [106] = "Light's Hope" },
	taxiVersion = 3,
}
ns.init()
assert(next(env.ShortestPathForeverCharDB.taxi) == nil, "a version 3 list is emptied on init")
assert(env.ShortestPathForeverCharDB.taxiVersion == 4, "the list is stamped with the new version")
env.ShortestPathForeverCharDB.taxi = {}
env.ShortestPathForeverCharDB.taxiNames = {}
ns.charDB = env.ShortestPathForeverCharDB
env.UnitFactionGroup = function()
	return "Alliance"
end
assert(ns.SetTaxiKnown(101, true), "manual toggle accepts a valid faction node")
assert(ns.KnownTaxiNodes()[101], "manual toggle persists the known node")
assert(ns.SetTaxiKnown(101, false), "manual toggle clears a valid node")
assert(not ns.KnownTaxiNodes()[101], "manual clear removes the node")
assert(not ns.SetTaxiKnown(103, true), "manual toggle rejects the opposing faction")
assert(not ns.SetTaxiKnown(999, true), "manual toggle rejects an unknown node")
local function event(name)
	assert(eventFrame.events[name])
	eventFrame:Run("OnEvent", name)
end
local function publish(legs, destination)
	ns.SetJourneyRoute(destination or {}, { legs = legs or { walk, flight } })
end
local function visibleLines()
	local count = 0
	for _, texture in ipairs(textures) do
		if texture:IsShown() then
			count = count + 1
		end
	end
	return count
end
local target = env.TaxiButton1
publish()
assert(routeQueries == 0, "a closed map does no route work")
-- A zone change or a login fires this with no flight master's map open, so nothing may be learned from it.
event("TAXI_NODE_STATUS_CHANGED")
assert(next(ns.KnownTaxiNodes()) == nil, "a status change with no flight master open learns nothing")
-- A flight point reads by its shipped name until a flight map has named it, in the game's language.
ns.L = setmetatable({}, {
	__index = function(_, phrase)
		return phrase
	end,
})
assert(loadfile("Journey/JourneySteps.lua"))("ShortestPathForever", ns)
assert(ns.PlaceLabel({ kind = "taxi", id = 103 }) == "Stormwind")
event("TAXIMAP_OPENED")
env.TaxiFrame:Show()
assert(ns.PlaceLabel({ kind = "taxi", id = 103 }) == "Sturmwind" and ns.TaxiName(101) == "Ironforge")
assert(
	visibleLines() == 2 and target.locked and not tooltip,
	"opening draws all hops and lights the destination without a tooltip"
)
assert(
	not env.TaxiRoute1:IsShown() and env.TaxiButton2:IsShown(),
	"replace stock one-hop lines and reveal a distant connection"
)
assert(ns.KnownTaxiNodes()[103], "flight discovery still runs")
assert(
	ns.KnownTaxiNodes()[101] and ns.KnownTaxiNodes()[102] and ns.KnownTaxiNodes()[105],
	"current, reachable and distant slots are all known flight points"
)
assert(not ns.KnownTaxiNodes()[104], "a node whose slot type is NONE is never learned")
assert(not env.ShortestPathForeverCharDB.taxiNames[104], "an unlearned node keeps its name out of the list")
assert(
	not ns.KnownTaxiNodes()[106],
	"an undiscovered node beyond the classic list is never learned, even with a non-NONE slot type"
)
assert(not env.ShortestPathForeverCharDB.taxiNames[106], "an undiscovered node keeps its name out of the list")
assert(ns.TaxiName(105) == "Kharanos", "a learned node keeps the client's name")
assert(textures[1].path == "Interface\\TaxiFrame\\UI-Taxi-Line")
assert(table.concat(textures[1].points, ",") == "60,90,40,60", "first client hop uses displayed button anchors")
assert(
	table.concat(textures[2].points, ",") == "40,60,20,30",
	"second client hop reaches the mapped slot, not the first planner hop"
)

local other = env.TaxiButton4
other:Run("OnEnter")
assert(tooltip and visibleLines() == 0 and env.TaxiRoute1:IsShown(), "stock hover owns the lines and tooltip")
local before = stockDraws
publish()
assert(stockDraws == before and visibleLines() == 0 and tooltip, "a journey refresh does not fight hover")
other:Run("OnLeave")
assert(not tooltip and visibleLines() == 2 and target.locked, "restore after the stock leave handler clears lines")
assert(#textures == 2, "reuse the line pool")

env.TaxiButton2:Run("OnEnter")
assert(visibleLines() == 2, "stock distant-node hover retains the existing route")
ns.JourneyChanged({})
assert(visibleLines() == 0 and not target.locked, "a replacement clears even during distant-node hover")
env.TaxiButton2:Run("OnLeave")
assert(env.TaxiRoute1:IsShown() and not env.TaxiButton2:IsShown(), "restore stock nodes after a cleared hovered route")
publish()
ns.db.taxiRoute = false
ns.RefreshTaxiRoute()
assert(visibleLines() == 0 and not target.locked and env.TaxiRoute1:IsShown(), "setting off restores the stock map")
ns.db.taxiRoute = true
ns.RefreshTaxiRoute()
assert(visibleLines() == 2 and target.locked)

publish({ { mode = "flight", from = { id = 101 }, to = { id = 102 } } })
assert(visibleLines() == 1 and not target.locked and other.locked, "a changed leg clears the old glow and surplus hop")
ns.SetJourneyRoute(nil)
assert(visibleLines() == 0 and not other.locked, "ending the journey clears everything")
publish(nil, { corpse = true })
assert(visibleLines() == 0, "a corpse route does not revive a waiting flight")
ns.SetJourneyRoute({}, { legs = { flight }, preview = true })
assert(visibleLines() == 0, "a preview is not a committed flight")
publish()

mapNodes[1].slotIndex = nil
mapNodes[1].name, mapNodes[1].x, mapNodes[1].y = "Same name", 0.2, 0.3
event("TAXI_NODE_STATUS_CHANGED")
assert(visibleLines() == 0 and not target.locked, "missing slot never falls back to a name or unrelated coordinates")
mapNodes[1].slotIndex = 1
mapNodes[1].state = unreachable
event("TAXI_NODE_STATUS_CHANGED")
assert(visibleLines() == 0, "an unreachable destination is not offered")
mapNodes[1].state = reachable
nodeTypes[1] = "UNREACHABLE"
event("TAXI_NODE_STATUS_CHANGED")
assert(visibleLines() == 0, "both client views must say reachable")
nodeTypes[1] = "REACHABLE"
mapNodes[2].nodeID = 999
event("TAXI_NODE_STATUS_CHANGED")
assert(visibleLines() == 0, "an unrelated flight master draws nothing")
mapNodes[2].nodeID = 101
routes[1] = {}
event("TAXI_NODE_STATUS_CHANGED")
assert(visibleLines() == 0 and not target.locked, "no client route means no highlight")
routes[1] = { { 3, 2 }, { 0, 1 } }
ns.RefreshTaxiRoute()
assert(visibleLines() == 0 and not target.locked, "an incomplete client route is never partially drawn")
routes[1] = { { 3, 2 }, { 2, 1 } }
ns.RefreshTaxiRoute()
assert(visibleLines() == 2)

event("TAXIMAP_CLOSED")
assert(visibleLines() == 0 and not target.locked, "closed event clears before the frame hides")
-- A zone change after leaving the flight master fires this too: the list describes no open map any more.
local learned = env.ShortestPathForeverCharDB.taxi
env.ShortestPathForeverCharDB.taxi = {}
event("TAXI_NODE_STATUS_CHANGED")
assert(next(ns.KnownTaxiNodes()) == nil, "a status change after the flight master is left learns nothing")
env.ShortestPathForeverCharDB.taxi = learned
env.TaxiFrame:Hide()
env.TaxiFrame:Show()
event("TAXIMAP_OPENED")
assert(visibleLines() == 2 and target.locked, "also support open events after the stock OnShow")
env.TaxiFrame:Hide()
assert(visibleLines() == 0 and not target.locked, "hiding the frame clears without waiting for the event")

-- An empty classic list is not a reason to fall back to the new query's nodes.
numNodes = 0
env.ShortestPathForeverCharDB.taxi = {}
env.ShortestPathForeverCharDB.taxiNames = {}
event("TAXI_NODE_STATUS_CHANGED")
assert(next(ns.KnownTaxiNodes()) == nil, "an empty classic list learns nothing")
assert(next(env.ShortestPathForeverCharDB.taxiNames) == nil, "an empty classic list names nothing")

print("taxi_spec: ok")

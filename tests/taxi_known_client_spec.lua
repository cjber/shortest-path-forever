-- #593: a flight master's classic list holds a slot for every point on the continent, not only the ones the
-- character has. This runs the recorded Stormwind scan (build 70862) through TAXIMAP_OPENED and the frame's
-- OnShow, from a saved list that wrongly holds every slot, and checks only CURRENT and REACHABLE slots survive.
local fixture = assert(loadfile("tests/fixtures/taxi_stormwind_1463.lua"))()

local ns = {
	db = { taxiRoute = false },
	SetJourneyRoute = function() end,
	JourneyChanged = function() end,
}
ns.Init = function(fn)
	fn()
end
assert(loadfile("Data/Taxi.lua"))("ShortestPathForever", ns)

local eventFrame
local region = {}
region.__index = region
local function widget(fields)
	local value = fields or {}
	value.scripts, value.hooks = {}, {}
	return setmetatable(value, region)
end
function region:SetScript(event, fn)
	self.scripts[event] = fn
end
function region:HookScript(event, fn)
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

local nodesBySlot = {}
local nodes = {}
for _, entry in ipairs(fixture.slots) do
	nodesBySlot[entry.slot] = entry
	nodes[#nodes + 1] = {
		nodeID = entry.nodeID,
		slotIndex = entry.slot,
		name = entry.name,
		state = entry.state,
	}
end

local env = setmetatable({
	GetTaxiMapID = function()
		return fixture.uiMap
	end,
	NumTaxiNodes = function()
		return #fixture.slots
	end,
	TaxiNodeGetType = function(slot)
		local entry = nodesBySlot[slot]
		return entry and entry.type or "NONE"
	end,
	TaxiNodeName = function(slot)
		local entry = nodesBySlot[slot]
		return entry and entry.name or ""
	end,
	C_TaxiMap = {
		GetAllTaxiNodes = function(uiMap)
			assert(uiMap == fixture.uiMap, "scan the flight master's recorded map")
			return nodes
		end,
	},
	TaxiFrame = widget(),
	GetServerTime = function()
		return 0
	end,
	CreateFrame = function()
		eventFrame = widget()
		return eventFrame
	end,
	hooksecurefunc = function(target, key, fn)
		local original = assert(target[key])
		target[key] = function(...)
			original(...)
			fn(...)
		end
	end,
}, { __index = _G })
env._G = env

-- The wrongly saved points: every slot's node but the quest/test 3207, including the 12 undiscovered ones.
local saved = { 2, 4, 6, 7, 8, 5, 12, 14, 16, 19, 43, 45, 66, 67, 71, 74, 3276 }
env.ShortestPathForeverCharDB = { taxi = {}, taxiNames = {} }
for _, nodeID in ipairs(saved) do
	env.ShortestPathForeverCharDB.taxi[nodeID] = true
end

setfenv(assert(loadfile("Transport/Taxi.lua")), env)("ShortestPathForever", ns)
assert(eventFrame.events.TAXIMAP_OPENED, "the scan listens for the flight master opening")
assert(env.ShortestPathForeverCharDB.taxi[19], "the saved list starts with the undiscovered Booty Bay")

eventFrame:Run("OnEvent", "TAXIMAP_OPENED")
env.TaxiFrame:Show()

local known = {}
for nodeID in pairs(ns.KnownTaxiNodes()) do
	known[#known + 1] = nodeID
end
table.sort(known)
assert(table.concat(known, ",") == "2,4,6,7,8", "only the recorded CURRENT and REACHABLE slots stay known")
for _, nodeID in ipairs({ 5, 12, 14, 16, 19, 43, 45, 66, 67, 71, 74, 3276 }) do
	assert(not ns.KnownTaxiNodes()[nodeID], "a DISTANT slot is not a flight point the character has: " .. nodeID)
	assert(not ns.charDB.taxiNames[nodeID], "a DISTANT slot keeps its name out of the list: " .. nodeID)
end

print("taxi known client: the recorded Stormwind scan keeps only CURRENT and REACHABLE points: ok")

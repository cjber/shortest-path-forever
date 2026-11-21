-- A Horde character who knows Undercity's network and, separately, Booty Bay and Grom'gol opened Booty Bay's flight
-- master, and SPF forgot every Undercity point (CurseForge thread 8761729). With Kargath undiscovered no known
-- point links the two networks, so the client lists Undercity's points DISTANT just like undiscovered ones. The
-- scan may forget only a point one flight path from a listed one, which the client would have listed if known.
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

-- Booty Bay's scan as this client gives it: the two linked known points, every other Horde point DISTANT.
local slots = {
	{ nodeID = 18, name = "Booty Bay", type = "CURRENT" },
	{ nodeID = 20, name = "Grom'gol", type = "REACHABLE" },
	{ nodeID = 21, name = "Kargath", type = "DISTANT" },
	{ nodeID = 56, name = "Stonard", type = "DISTANT" },
	{ nodeID = 11, name = "Undercity", type = "DISTANT" },
	{ nodeID = 10, name = "The Sepulcher", type = "DISTANT" },
	{ nodeID = 13, name = "Tarren Mill", type = "DISTANT" },
	{ nodeID = 17, name = "Hammerfall", type = "DISTANT" },
}
local nodes = {}
for slot, entry in ipairs(slots) do
	entry.slot = slot
	nodes[slot] = { nodeID = entry.nodeID, slotIndex = slot, name = entry.name }
end

local env = setmetatable({
	GetTaxiMapID = function()
		return 1434
	end,
	NumTaxiNodes = function()
		return #slots
	end,
	TaxiNodeGetType = function(slot)
		return slots[slot] and slots[slot].type or "NONE"
	end,
	TaxiNodeName = function(slot)
		return slots[slot] and slots[slot].name or ""
	end,
	C_TaxiMap = {
		GetAllTaxiNodes = function()
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
	hooksecurefunc = function() end,
}, { __index = _G })
env._G = env

-- Undercity's network and the two Stranglethorn points, plus Kargath saved by mistake.
local names = {
	[11] = "Undercity",
	[10] = "The Sepulcher",
	[13] = "Tarren Mill",
	[18] = "Booty Bay",
	[20] = "Grom'gol",
	[21] = "Kargath",
}
env.ShortestPathForeverCharDB = {
	taxi = { [11] = true, [10] = true, [13] = true, [18] = true, [20] = true, [21] = true },
	taxiNames = names,
}
local policyChanges = 0
ns.TravelPolicyChanged = function()
	policyChanges = policyChanges + 1
end

setfenv(assert(loadfile("Transport/Taxi.lua")), env)("ShortestPathForever", ns)
eventFrame:Run("OnEvent", "TAXIMAP_OPENED")

local known = {}
for nodeID in pairs(ns.KnownTaxiNodes()) do
	known[#known + 1] = nodeID
end
table.sort(known)
assert(
	table.concat(known, ",") == "10,11,13,18,20",
	"Undercity's network survives Booty Bay's scan: " .. table.concat(known, ",")
)
assert(ns.charDB.taxiNames[11] == "Undercity", "a point on the other network keeps its name")
assert(not ns.KnownTaxiNodes()[21], "Kargath, one flight from Booty Bay and not listed, is forgotten")
assert(not ns.charDB.taxiNames[21], "a forgotten point loses its saved name")
assert(policyChanges == 1, "forgetting a point alone replans once")
eventFrame:Run("OnEvent", "TAXIMAP_OPENED")
assert(policyChanges == 1, "a scan that changes nothing does not replan")

print("taxi separate network: a flight master forgets only points its own network rules out: ok")

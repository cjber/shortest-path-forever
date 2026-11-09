-- #588: a flight master's map that leaves Booty Bay out corrects the saved list, and the journey on screen stops
-- flying there on the very next frame instead of keeping the route it planned before the map opened.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
for _, file in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
}) do
	driver.load(file)
end
ns.NowMs = function()
	return 0
end
-- Journey notifications as Taxi.lua hooks them.
ns.JourneyChanged = ns.JourneyChanged or function() end
driver.env.hooksecurefunc = function(target, key, fn)
	local original = target[key]
	target[key] = function(...)
		original(...)
		fn(...)
	end
end
-- The classic flight-master list, slots 1 to NumTaxiNodes(): the client's own entries, no Booty Bay.
local listed = { 2, 5, 4, 12, 6, 8, 7 } -- Stormwind, Lakeshire, Sentinel Hill, Darkshire, Ironforge,
-- Thelsamar and Menethil Harbor.
driver.env.GetTaxiMapID = function()
	return 0
end
driver.env.NumTaxiNodes = function()
	return #listed
end
driver.env.TaxiNodeGetType = function()
	return "REACHABLE"
end
driver.env.TaxiNodeName = function(slot)
	return ns.TaxiNodes[listed[slot]].name
end
driver.env.C_TaxiMap = {
	GetAllTaxiNodes = function()
		local nodes = {}
		for slot, nodeID in ipairs(listed) do
			nodes[#nodes + 1] = { nodeID = nodeID, slotIndex = slot, name = ns.TaxiNodes[nodeID].name }
		end
		return nodes
	end,
}
-- The wrongly saved list: every Eastern Kingdoms Alliance flight point, including Booty Bay (19).
local taxi = {}
for nodeID, node in pairs(ns.TaxiNodes) do
	if node.map == 0 and node.faction == "Alliance" then
		taxi[nodeID] = true
	end
end
assert(taxi[19], "the saved list starts with Booty Bay known")
driver.env.ShortestPathForeverCharDB = { taxi = taxi, taxiNames = {} }
driver.load("Transport/Taxi.lua")

local function FlightNodes(plan)
	local nodes = {}
	for _, leg in ipairs(plan and plan.legs or {}) do
		if leg.mode == "flight" then
			nodes[#nodes + 1] = leg.from.id
			nodes[#nodes + 1] = leg.to.id
			for _, hop in ipairs(leg.hops or {}) do
				nodes[#nodes + 1] = hop.from
				nodes[#nodes + 1] = hop.to
			end
		end
	end
	return nodes
end

local STORMWIND = { map = 0, x = -8800, y = 800 }
local RATCHET = ns.TaxiNodes[80]
driver.begin(STORMWIND, RATCHET)
local planned = assert(driver.shown(), "the journey planned a route")
local flewToBootyBay = false
for _, nodeID in ipairs(FlightNodes(planned)) do
	flewToBootyBay = flewToBootyBay or nodeID == 19
end
assert(flewToBootyBay, "the journey first flies to Booty Bay")

-- The flight master's map opens with the classic list above. Its scan changes the list once, and opening the same
-- map again changes nothing, so no search restarts needlessly.
local policyChanges = 0
local policyChanged = ns.TravelPolicyChanged
ns.TravelPolicyChanged = function(...)
	policyChanges = policyChanges + 1
	return policyChanged(...)
end
driver.fire("TAXIMAP_OPENED")
assert(policyChanges == 1, "the scan that dropped a flight point tells the journey to plan again")
assert(not ns.KnownTaxiNodes()[19], "Booty Bay is no longer known after the scan")
assert(ns.KnownTaxiNodes()[2] and ns.KnownTaxiNodes()[7], "the listed points stay known")
driver.fire("TAXIMAP_OPENED")
assert(policyChanges == 1, "opening the same flight master again changes nothing so notifies no one")

-- The very next frame, before the five-second timed replan, the shown route drops the flight.
driver.update(0.1)
local shown = assert(driver.shown(), "the journey still shows a route")
for _, nodeID in ipairs(FlightNodes(shown)) do
	assert(nodeID ~= 19, "the next frame's route does not fly to Booty Bay")
end

print("scan replan: a flight master's scan drops the stale flight on the next frame: ok")

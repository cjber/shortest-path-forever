-- Synthetic provider records only. No GatherMate source, data, icons or fixtures.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks = checks + 1
end
local ns = {}
local currentZone = 77
local env = setmetatable({
	C_Map = {
		GetBestMapForUnit = function(unit)
			assert(unit == "player")
			return currentZone
		end,
	},
}, { __index = _G })
local chunk = assert(loadfile("Core/GatherMate.lua"))
setfenv(chunk, env)("ShortestPathForever", ns)
local adapter = ns.GatherMate
local function status(expected, ...)
	local nodes, reason = adapter.Snapshot(...)
	check(nodes == nil and reason == expected, expected .. ": " .. tostring(reason))
end
status("absent", 77, "Mining")
env.GatherMate2 = {}
status("unsupported", 77, "Mining")
local records, filtered = {}, {}
local calls = 0
local provider = {
	GetNodesForZone = function(self, zone, kind, ignoreFilter)
		assert(self == env.GatherMate2 and zone == 77)
		assert(kind == "Mining" or kind == "Herb Gathering")
		assert(ignoreFilter == false, "must respect provider filters")
		calls = calls + 1
		local function iter(_, previous)
			local coord, id = next(records, previous)
			while coord and filtered[id] do
				coord, id = next(records, coord)
			end
			return coord, id
		end
		return iter, nil, nil
	end,
	DecodeLoc = function(_, coord)
		-- Deliberately different from the provider's packing. Adapter must call it.
		return coord / 1000, 1 - coord / 1000
	end,
	GetNameForNode = function(_, kind, id)
		return kind .. " synthetic " .. id
	end,
}
env.GatherMate2 = provider
status("not-ready", 77, "Mining")
provider.gmdbs = {}
status("not-ready", 77, "Mining")
-- Opaque storage: adapter must never inspect or change a zone's backing table.
local storage = setmetatable({}, {
	__index = function()
		error("provider storage accessed")
	end,
	__newindex = function()
		error("provider storage mutated")
	end,
})
provider.gmdbs.Mining = storage
provider.gmdbs["Herb Gathering"] = storage
local empty, reason = adapter.CurrentZone("Mining")
check(#empty == 0 and reason == "empty", "empty ready provider")
for i = 1, 300 do
	records[i] = i % 3 + 1
end
local nodes
nodes, reason = adapter.CurrentZone("Herb Gathering")
check(#nodes == 300 and reason == "ready", "all 300 retained")
for i, node in ipairs(nodes) do
	check(
		node.uiMapID == 77
			and node.kind == "Herb Gathering"
			and node.coord == i
			and node.nodeID == records[i]
			and node.x == i / 1000
			and node.y == 1 - i / 1000
			and node.title == "Herb Gathering synthetic " .. records[i],
		"flat identity and provider fractions"
	)
	for _, value in pairs(node) do
		check(type(value) ~= "table", "scalar copy only")
	end
end
nodes[1].title = "owned edit"
check(records[1] == 2, "snapshot mutation leaves source intact")
local again = adapter.Snapshot(77, "Herb Gathering")
check(again[1].title ~= nodes[1].title and again[1] ~= nodes[1], "fresh owned snapshots")
records[301] = 1
check(#nodes == 300, "source changes do not change old snapshot")
records = {}
for i = 1, 192 do
	records[i] = i % 2 + 1
end
nodes = adapter.CurrentZone("Mining")
check(#nodes == 192, "all 192 retained")
filtered[1] = true
nodes = adapter.CurrentZone("Mining", { [1] = true, [2] = true })
check(#nodes == 96, "provider filters still win over explicit selection")
local selection = { [1] = true, [2] = false }
nodes, reason = adapter.CurrentZone("Mining", selection)
check(#nodes == 0 and reason == "empty", "false and filtered IDs omitted")
check(selection[1] and selection[2] == false, "selection not mutated")
nodes = adapter.CurrentZone("Mining", {})
check(#nodes == 0, "empty selection means none")
filtered = {}
local before = calls
status("invalid-zone", nil, "Mining")
status("invalid-zone", 0, "Mining")
status("invalid-zone", 1.5, "Mining")
status("invalid-kind", 77, "Fishing")
status("invalid-selection", 77, "Mining", { [1] = "yes" })
status("invalid-selection", 77, "Mining", { [0] = true })
status("invalid-selection", 77, "Mining", false)
check(calls == before, "invalid requests do not invoke provider")
currentZone = nil
local missing, missingReason = adapter.CurrentZone("Mining")
check(missing == nil and missingReason == "invalid-zone", "no player zone")
currentZone = 77
records = { [1] = 1, [2] = 2 }
local decode = provider.DecodeLoc
provider.DecodeLoc = function()
	return 0, 1
end
nodes, reason = adapter.CurrentZone("Mining")
check(#nodes == 2 and nodes[1].x == 0 and nodes[1].y == 1 and reason == "ready", "inclusive fraction boundaries")
provider.DecodeLoc = function(_, coord)
	return coord == 2 and 1.01 or 0, 0
end
status("invalid-record", 77, "Mining")
provider.DecodeLoc = function()
	return 0 / 0, 0
end
status("invalid-record", 77, "Mining")
provider.DecodeLoc = decode
records = { [1] = 0 }
status("invalid-record", 77, "Mining")
records = { [-1] = 1 }
status("invalid-record", 77, "Mining")
records = { [1] = 1 }
provider.GetNameForNode = function() end
status("unknown-name", 77, "Mining")
provider.GetNameForNode = function()
	return ""
end
status("unknown-name", 77, "Mining")
provider.GetNodesForZone = function()
	return function()
		error("optional provider failed during iteration")
	end
end
status("provider-error", 77, "Mining")
provider.GetNodesForZone = function()
	error("optional provider failed before iteration")
end
status("provider-error", 77, "Mining")
local broken = { broken = true }
assert(loadfile("Core/GatherMate.lua"))("ShortestPathForever", broken)
check(broken.GatherMate == nil, "broken addon does not publish adapter")
print("GatherMate: " .. checks .. " checks passed")

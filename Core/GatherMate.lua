---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

-- Runtime interoperability only: no GatherMate source, database or art is bundled.
-- Verified contract: GatherMate2 1.52.7, commit b8a6ff4dc6f39bdf39f7f1fb619cc9c67886e831.
local adapter = {}

local function Number(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function ID(value)
	return Number(value) and value > 0 and value % 1 == 0
end

-- Query on each request, so an optional addon loaded later is immediately usable.
---@param kind SPFGatherMateKind
---@return SPFGatherMateProvider? provider, SPFGatherMateStatus status
local function Provider(kind)
	local provider = GatherMate2
	if provider == nil then
		return nil, "absent"
	end
	if
		type(provider) ~= "table"
		or type(provider.GetNodesForZone) ~= "function"
		or type(provider.DecodeLoc) ~= "function"
		or type(provider.GetNameForNode) ~= "function"
	then
		return nil, "unsupported"
	end
	if type(provider.gmdbs) ~= "table" or type(provider.gmdbs[kind]) ~= "table" then
		return nil, "not-ready"
	end
	return provider, "ready"
end

-- Explicit zone input, normally captured by CurrentZone when the chooser opens. No
-- subscription or cache: a running tour keeps this snapshot until an explicit restart.
-- nil selection includes every provider-filtered type; an empty set selects nothing.
-- Failure returns no partial snapshot. Unknown labels and malformed records are not
-- guessed or silently discarded. Records describe historical locations, not live nodes,
-- gathering eligibility, rank, height or reachability.
---@param uiMapID integer
---@param kind SPFGatherMateKind
---@param selectedIDs? table<integer, boolean>
---@return SPFGatherMateNode[]? nodes, SPFGatherMateStatus status
function adapter.Snapshot(uiMapID, kind, selectedIDs)
	if not ID(uiMapID) then
		return nil, "invalid-zone"
	end
	if kind ~= "Herb Gathering" and kind ~= "Mining" then
		return nil, "invalid-kind"
	end
	if selectedIDs ~= nil then
		if type(selectedIDs) ~= "table" then
			return nil, "invalid-selection"
		end
		for id, selected in pairs(selectedIDs) do
			if not ID(id) or type(selected) ~= "boolean" then
				return nil, "invalid-selection"
			end
		end
	end
	local provider, status = Provider(kind)
	if not provider then
		return nil, status
	end
	local ok, nodes, result = pcall(function()
		---@type SPFGatherMateNode[]
		local copy = {}
		-- false is essential: true bypasses GatherMate's per-node profile filters.
		for coord, nodeID in provider:GetNodesForZone(uiMapID, kind, false) do
			if not Number(coord) or coord < 0 or coord % 1 ~= 0 or not ID(nodeID) then
				return nil, "invalid-record"
			end
			if selectedIDs == nil or selectedIDs[nodeID] == true then
				local x, y = provider:DecodeLoc(coord)
				if not Number(x) or not Number(y) or x < 0 or x > 1 or y < 0 or y > 1 then
					return nil, "invalid-record"
				end
				local name = provider:GetNameForNode(kind, nodeID)
				if type(name) ~= "string" or name == "" then
					return nil, "unknown-name"
				end
				copy[#copy + 1] = {
					uiMapID = uiMapID,
					kind = kind,
					coord = coord,
					nodeID = nodeID,
					x = x,
					y = y,
					title = name,
				}
			end
		end
		-- Provider iteration order is unspecified. Identity order is stable and makes
		-- no spatial visiting-order or optimal-route claim.
		table.sort(copy, function(a, b)
			return a.coord < b.coord or (a.coord == b.coord and a.nodeID < b.nodeID)
		end)
		return copy, #copy == 0 and "empty" or "ready"
	end)
	if not ok then
		return nil, "provider-error"
	end
	return nodes, result
end

-- Capture the player's zone, never the map the player happens to be browsing.
---@param kind SPFGatherMateKind
---@param selectedIDs? table<integer, boolean>
---@return SPFGatherMateNode[]? nodes, SPFGatherMateStatus status
function adapter.CurrentZone(kind, selectedIDs)
	return adapter.Snapshot((C_Map.GetBestMapForUnit("player") or 0), kind, selectedIDs)
end

ns.GatherMate = adapter

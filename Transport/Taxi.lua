---@class SPFNamespace
local ns = select(2, ...)

-- The flight points this character knows, for the journey planner and the map's flight master pins. Only the
-- classic flight-master list says which nodes a character can fly to: slots 1 to NumTaxiNodes(), each with
-- TaxiNodeGetType and TaxiNodeName, are the entries the stock TaxiFrame draws and only contain nodes the character
-- really has. The new node query reports every node on the continent as reachable here, so its presence is not a
-- source.

-- Lists built from the new node query claimed undiscovered nodes, so start again from empty.
local KNOWN_VERSION = 4

---@type SPFLeg[]?
local journeyLegs
---@type TaxiNodeInfo[]
local mapNodes = {}
---@type Texture[]
local lines = {}
---@type Button?
local highlighted, hovered
local ownsMap = false
-- Set by TAXIMAP_OPENED and cleared by TAXIMAP_CLOSED (and the map hiding): the only window in which the classic
-- list describes a flight master's map, so the only window in which a scan may learn a node.
local taxiMapOpen = false
local hookedFrame
local hookedButtons = {}

-- The displayed legs already start at the journey's progress. Only the flight being taken, or the one
-- immediately after its approach walk, belongs on this flight master's map.
---@param legs SPFLeg[]?
---@param origin number
---@return number?
function ns.TaxiDestination(legs, origin)
	if not legs then
		return nil
	end
	local leg = legs[1]
	if leg and leg.mode == "walk" then
		leg = legs[2]
	end
	if not leg or leg.mode ~= "flight" or leg.to.id == origin then
		return nil
	end
	if leg.from.id == origin then
		return leg.to.id
	end
	for _, hop in ipairs(leg.hops or {}) do
		if hop.from == origin then
			return leg.to.id
		end
	end
	return nil
end

local function HideLines()
	for _, line in ipairs(lines) do
		line:Hide()
	end
end

local function ClearRoute(restore)
	HideLines()
	if highlighted then
		highlighted:UnlockHighlight()
		highlighted = nil
	end
	if ownsMap and not hovered then
		ownsMap = false
		if restore and TaxiFrame:IsShown() then
			DrawOneHopLines()
		end
	end
end

local function DestinationSlot()
	local origin
	for _, node in ipairs(mapNodes) do
		if node.state == Enum.FlightPathState.Current then
			if origin or not node.slotIndex or TaxiNodeGetType(node.slotIndex) ~= "CURRENT" then
				return nil
			end
			origin = node.nodeID
		end
	end
	local destination = origin and ns.TaxiDestination(journeyLegs, origin)
	for _, node in ipairs(mapNodes) do
		if node.nodeID == destination and node.state == Enum.FlightPathState.Reachable then
			-- World-map positions and TaxiNodePosition have no verified shared coordinate provenance here.
			-- Without the current flight master's slotIndex, neither names nor proximity identify a button.
			local slot = node.slotIndex
			if
				slot
				and slot >= 1
				and slot <= NumTaxiNodes()
				and slot % 1 == 0
				and TaxiNodeGetType(slot) == "REACHABLE"
			then
				return slot
			end
		end
	end
	return nil
end

---@param slot number
---@return Button?, number?, number?
local function ButtonPosition(slot)
	if not slot or slot < 1 or slot > NumTaxiNodes() or TaxiNodeGetType(slot) == "NONE" then
		return nil
	end
	local button = _G["TaxiButton" .. slot]
	if not button then
		return nil
	end
	-- TaxiFrame_OnShow displaces overlapping nodes, then anchors their centres here. Its private
	-- taxiNodePositions table is inaccessible; these anchors keep lines on the displayed buttons.
	local point, _, relativePoint, x, y = button:GetPoint(1)
	if point == "CENTER" and relativePoint == "BOTTOMLEFT" then
		return button, x, y
	end
	return nil
end

function ns.RefreshTaxiRoute()
	if not TaxiFrame or not TaxiFrame:IsShown() then
		return
	end
	local slot = ns.db.taxiRoute and DestinationSlot()
	if not slot then
		ClearRoute(true)
		return
	end
	local button = _G["TaxiButton" .. slot]
	if not button or not button:IsShown() or GetNumRoutes(slot) == 0 then
		ClearRoute(true)
		return
	end
	-- TaxiNodeOnButtonEnter also opens GameTooltip. Use its hop query, DrawLine and line art alone,
	-- in our own texture pool so the stock route globals and click handler remain untouched.
	local segments = {}
	local previous
	for hop = 1, GetNumRoutes(slot) do
		local from, to = TaxiGetNodeSlot(slot, hop, true), TaxiGetNodeSlot(slot, hop, false)
		local source, sx, sy = ButtonPosition(from)
		local target, dx, dy = ButtonPosition(to)
		if
			not source
			or not target
			or (previous and from ~= previous)
			or (not previous and TaxiNodeGetType(from) ~= "CURRENT")
		then
			ClearRoute(true)
			return
		end
		segments[#segments + 1] = { sx = sx, sy = sy, dx = dx, dy = dy, slot = to, button = target }
		previous = to
	end
	if previous ~= slot then
		ClearRoute(true)
		return
	end
	if highlighted ~= button then
		ClearRoute(true)
		highlighted = button
		button:LockHighlight()
	end
	if hovered then
		return
	end
	HideLines()
	DrawOneHopLines()
	for index = 1, NUM_TAXI_ROUTES do
		_G["TaxiRoute" .. index]:Hide()
	end
	for index, segment in ipairs(segments) do
		local line = lines[index]
		if not line then
			line = TaxiRouteMap:CreateTexture(nil, "BACKGROUND")
			-- art-ok: the flight map's own route line, a segment DrawLine lays between two nodes
			line:SetTexture("Interface\\TaxiFrame\\UI-Taxi-Line")
			lines[index] = line
		end
		DrawLine(line, "TaxiRouteMap", segment.sx, segment.sy, segment.dx, segment.dy, 32, TAXIROUTE_LINEFACTOR)
		line:Show()
		if TaxiNodeGetType(segment.slot) == "DISTANT" then
			segment.button:Show()
		end
	end
	ownsMap = true
end

-- `/path debug`: what the game's taxi queries return, to check how this client reports known flight points.
local function Log(key, uiMap, nodes)
	if not ns.db.debug then
		return
	end
	local rows = {}
	for _, node in ipairs(nodes) do
		rows[#rows + 1] = string.format(
			"%d %s type=%s undiscovered=%s state=%s",
			node.nodeID,
			node.name,
			tostring(node.slotIndex and TaxiNodeGetType(node.slotIndex)),
			tostring(node.isUndiscovered),
			tostring(node.state)
		)
	end
	local count = NumTaxiNodes()
	local slots = {}
	for index = 1, count do
		slots[#slots + 1] =
			string.format("%d %s type=%s", index, tostring(TaxiNodeName(index)), tostring(TaxiNodeGetType(index)))
	end
	ns.db.taxiLog = ns.db.taxiLog or {}
	ns.db.taxiLog[key .. uiMap] = {
		seen = GetServerTime(),
		showsNodes = C_TaxiMap.ShouldMapShowTaxiNodes(uiMap),
		numTaxiNodes = count,
		nodes = rows,
		slots = slots,
	}
end

-- At a flight master, only the classic list's entries are nodes the character really has. Walk slots 1 to
-- NumTaxiNodes() and learn those whose type is not "NONE", using the new query only to resolve the slot to its
-- nodeID. An empty list learns nothing: absence never unlearns a node, and an empty answer is not a guess.
local function ScanFlightMaster()
	local uiMap = GetTaxiMapID and GetTaxiMapID()
	local nodes = uiMap and C_TaxiMap.GetAllTaxiNodes(uiMap) or {}
	mapNodes = nodes
	if uiMap then
		Log("master", uiMap, nodes)
	end
	local bySlot = {}
	for _, node in ipairs(nodes) do
		if node.slotIndex and ns.TaxiNodes[node.nodeID] then
			bySlot[node.slotIndex] = node
		end
	end
	for slot = 1, NumTaxiNodes() do
		local node = bySlot[slot]
		if node and TaxiNodeGetType(slot) ~= "NONE" then
			ns.charDB.taxi[node.nodeID] = true
			local name = TaxiNodeName(slot)
			if not name or name == "" then
				name = node.name
			end
			if name and name ~= "" then
				ns.charDB.taxiNames[node.nodeID] = name
			end
		end
	end
end

-- Empty until the character opens a flight master: the planner then walks rather than guessing at flights.
---@return table<number, boolean>
function ns.KnownTaxiNodes()
	return ns.charDB.taxi
end

---@param nodeID number
---@param known boolean
---@return boolean
function ns.SetTaxiKnown(nodeID, known)
	local node = ns.TaxiNodes[nodeID]
	if not node or type(known) ~= "boolean" then
		return false
	end
	local faction = UnitFactionGroup("player")
	if node.faction and node.faction ~= faction then
		return false
	end
	ns.charDB.taxi[nodeID] = known or nil
	if not known then
		ns.charDB.taxiNames[nodeID] = nil
	end
	if ns.TravelPolicyChanged then
		ns.TravelPolicyChanged()
	end
	return true
end

local function Closed()
	taxiMapOpen = false
	hovered, mapNodes = nil, {}
	ClearRoute(false)
end

local function Shown()
	ScanFlightMaster()
	for slot = 1, NumTaxiNodes() do
		local button = _G["TaxiButton" .. slot]
		if button and not hookedButtons[button] then
			hookedButtons[button] = true
			button:HookScript("OnEnter", function(self)
				hovered = self
				-- Stock hover leaves the previous route in place for a distant, non-clickable node.
				if TaxiNodeGetType(self:GetID()) ~= "DISTANT" then
					HideLines()
					ownsMap = false
				end
			end)
			button:HookScript("OnLeave", function(self)
				if hovered == self then
					hovered = nil
				end
				ns.RefreshTaxiRoute()
			end)
		end
	end
	ns.RefreshTaxiRoute()
end

local function HookTaxiFrame()
	if TaxiFrame and hookedFrame ~= TaxiFrame then
		hookedFrame = TaxiFrame
		TaxiFrame:HookScript("OnShow", Shown)
		TaxiFrame:HookScript("OnHide", Closed)
	end
end

ns.Init(function()
	ShortestPathForeverCharDB = ShortestPathForeverCharDB or {}
	ns.charDB = ShortestPathForeverCharDB
	if ns.charDB.taxiVersion ~= KNOWN_VERSION then
		ns.charDB.taxi, ns.charDB.taxiScanned, ns.charDB.taxiVersion = {}, nil, KNOWN_VERSION
	end
	ns.charDB.taxiNames = ns.charDB.taxiNames or {}
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("TAXIMAP_OPENED")
	-- Learning a node fires this while the flight master's map is open.
	frame:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
	frame:RegisterEvent("TAXIMAP_CLOSED")
	frame:SetScript("OnEvent", function(_, event)
		if event == "TAXIMAP_CLOSED" then
			Closed()
			return
		end
		if event == "TAXIMAP_OPENED" then
			taxiMapOpen = true
		elseif not taxiMapOpen then
			-- A status change away from a flight master (a zone change, a /reload) describes no flight map.
			return
		end
		HookTaxiFrame()
		if TaxiFrame and TaxiFrame:IsShown() then
			Shown()
		else
			ScanFlightMaster()
		end
	end)
	HookTaxiFrame()
	hooksecurefunc(ns, "SetJourneyRoute", function(destination, route)
		journeyLegs = destination and not destination.corpse and route and not route.preview and route.legs or nil
		ns.RefreshTaxiRoute()
	end)
	hooksecurefunc(ns, "JourneyChanged", function()
		journeyLegs = nil
		ClearRoute(true)
	end)
end)

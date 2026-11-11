---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L
local Art = ns.Art
local Canvas = ns.Canvas

-- The town services on the world map: every trainer, vendor, banker and the rest the Nearby services list finds,
-- drawn at the NPC's own place. Zoomed out, the pins that would overlap share one town icon with the services in its
-- tooltip; zoomed in they separate, the way UI/Map.lua groups the docks of a harbour. The setting chooses which
-- towns show: the capitals, the capitals and the services worth a detour, every town, or none.
local TEMPLATE = "ShortestPathForeverServicePinTemplate"
local PIN_SIZE = 20
-- The client's own town and city marks (UiTextureAtlas, 32 by 32).
local CAPITAL_ATLAS, TOWN_ATLAS = "poi-majorcity", "poi-town"
-- The groups that make a town worth showing under "Capitals and important services": every trainer, the profession
-- supplies (fishing, cooking and first aid included), books and recipes, the bank, the flight master and the inn.
local IMPORTANT = { innkeeper = true, flight = true, bank = true, trade = true, reagents = true, books = true }
-- A town's service icon: the most useful thing the NPC offers, by section and then by the list's own order.
local RANK = { services = 1, trainers = 2, vendors = 3 }
-- An item's own icon, which the client holds for every item without it being cached; the question mark if it has
-- no such item. The same fallback UI/ServicesPanel.lua uses.
local QUESTION_MARK = 134400

---@type SPFTownServiceChoice[]
ns.TownServiceChoices = {
	{ key = "capitals", label = L["Capitals only"] },
	{ key = "important", label = L["Capitals and important services"] },
	{ key = "all", label = L["All towns"] },
	{ key = "off", label = OFF },
}

---@class SPFTownService
---@field id integer the NPC's id
---@field key string the NPC and spawn, which a re-read of the database can change
---@field name string
---@field title? string
---@field world SPFPoint
---@field map integer the zone map the spawn is on
---@field groups SPFNearbyGroup[] what the NPC offers, in the list's order
---@field primary SPFNearbyGroup the mark the NPC wears
---@field capitalUiMap? integer the capital the NPC stands in

---@class SPFTownServicePoint
---@field entry SPFTownService
---@field id string the entry's key
---@field x number
---@field y number

---@class SPFTownServiceCluster
---@field services SPFTownServicePoint[]
---@field x number
---@field y number
---@field key string the members' keys joined, which identifies the cluster across redraws
---@field capital boolean any member stands in a capital

local entries = {}
-- The index table the entries were built from, so a late QuestieDB read is picked up.
local sourceIndex
-- The map fraction of each entry on each map it has been asked for; nil until asked, false when off the map.
local projections = {}
local capitalNames = {}
local zoneNames = {}

---@param itemID integer
---@return integer
local function ItemIcon(itemID)
	return C_Item.GetItemIconByID(itemID) or QUESTION_MARK
end

-- The capital whose own map region holds a world point. The regions come from Data/Zones.lua, the same data a
-- capital portal and a dock at the capital's gates use, so no city is typed in here.
---@param world SPFPoint
---@return integer?
local function Capital(world)
	for uiMap, zone in pairs(ns.Zones or {}) do
		if
			zone.city
			and zone.map == world.map
			and world.x >= zone.minX
			and world.x <= zone.maxX
			and world.y >= zone.minY
			and world.y <= zone.maxY
		then
			return uiMap
		end
	end
end

---@param uiMap integer
---@return string?
local function CapitalName(uiMap)
	local name = capitalNames[uiMap]
	if name == nil then
		local info = C_Map.GetMapInfo(uiMap)
		name = info and info.name ~= "" and info.name or false
		capitalNames[uiMap] = name
	end
	return name or nil
end

---@param mapID integer
---@return string?
local function ZoneName(mapID)
	local name = zoneNames[mapID]
	if name == nil then
		local info = C_Map.GetMapInfo(mapID)
		name = info and info.name ~= "" and info.name or false
		zoneNames[mapID] = name
	end
	return name or nil
end

-- A town's name by the flight master that serves it, as Journey/Hazards.lua already names a town, minus the zone
-- after the comma. Falls back to the spawn's own zone when no flight master shares its continent.
---@param entry SPFTownService
---@return string?
local function TownName(entry)
	local best, gap
	for id, node in pairs(ns.TaxiNodes or {}) do
		if node.map == entry.world.map then
			local distance = (node.x - entry.world.x) ^ 2 + (node.y - entry.world.y) ^ 2
			if not gap or distance < gap then
				best, gap = id, distance
			end
		end
	end
	local name = best and ns.TaxiName and ns.TaxiName(best)
	if name and name ~= "" then
		return (name:gsub(",.*$", ""))
	end
	return ZoneName(entry.map)
end

---@param entry SPFTownService
---@return string?
local function EntryTown(entry)
	if entry.capitalUiMap then
		return CapitalName(entry.capitalUiMap)
	end
	return TownName(entry)
end

---@param groups SPFNearbyGroup[]
---@return SPFNearbyGroup
local function Primary(groups)
	local best
	for _, group in ipairs(groups) do
		if not best or (RANK[group.section] or 0) < (RANK[best.section] or 0) then
			best = group
		end
	end
	return best
end

-- The NPCs the list knows, one entry each, with every group the NPC serves. The same spawn is indexed under each of
-- its groups, so the key merges them into one pin.
local function Build()
	local index, groups = ns.NearbyServices.Index(), ns.NearbyServices.Groups()
	sourceIndex = index
	entries, projections = {}, {}
	local byKey = {}
	for _, group in ipairs(groups) do
		if group.section ~= "entrances" then
			for _, place in ipairs(index[group.key] or {}) do
				local key = place.id .. ":" .. place.map .. ":" .. place.x .. ":" .. place.y
				local entry = byKey[key]
				if not entry then
					entry = {
						id = place.id,
						key = key,
						name = place.name,
						title = place.title,
						world = place.world,
						map = place.map,
						groups = {},
						capitalUiMap = Capital(place.world),
					}
					byKey[key] = entry
					entries[#entries + 1] = entry
				end
				entry.groups[#entry.groups + 1] = group
			end
		end
	end
	for _, entry in ipairs(entries) do
		entry.primary = Primary(entry.groups)
	end
end

---@param entry SPFTownService
---@param level string
---@return boolean
local function Shown(entry, level)
	if level == "all" then
		return true
	elseif level == "capitals" then
		return entry.capitalUiMap ~= nil
	elseif level == "important" then
		if entry.capitalUiMap then
			return true
		end
		for _, group in ipairs(entry.groups) do
			if group.section == "trainers" or IMPORTANT[group.key] then
				return true
			end
		end
	end
	return false
end

-- A world point's position on this map, asked once per map and kept: the projection never changes, and a zoom
-- redraws many times without asking the client again.
---@param entry SPFTownService
---@param mapID integer
---@return number?, number?
local function Position(entry, mapID)
	local byMap = projections[mapID]
	if not byMap then
		byMap = {}
		projections[mapID] = byMap
	end
	local cached = byMap[entry.key]
	if cached ~= nil then
		return cached and cached[1], cached and cached[2]
	end
	local x, y = ns.MapPinPosition(entry.world, mapID)
	byMap[entry.key] = x and { x, y } or false
	return x, y
end

---@param mapID integer
---@param level string
---@return SPFTownServicePoint[]
local function Points(mapID, level)
	local points = {}
	for _, entry in ipairs(entries) do
		if Shown(entry, level) then
			local x, y = Position(entry, mapID)
			if x and y then
				points[#points + 1] = { entry = entry, id = entry.key, x = x, y = y }
			end
		end
	end
	return points
end

-- The service pins that would overlap at this zoom share one town pin, at their middle, through the same grouping
-- UI/Map.lua uses for docks.
---@param map SPFMapCanvas
---@param points SPFTownServicePoint[]
---@return SPFTownServiceCluster[]
local function Clusters(map, points)
	local zoom = Saturate(map:GetCanvasZoomPercent() or 0)
	local clusters = {}
	local groups = ns.OverlapGroups(map, points, PIN_SIZE * map:GetGlobalPinScale() * Lerp(1, 1.2, zoom))
	for i, group in ipairs(groups) do
		local x, y, ids, capital = 0, 0, {}, false
		for _, point in ipairs(group) do
			x, y = x + point.x, y + point.y
			ids[#ids + 1] = point.id
			capital = capital or point.entry.capitalUiMap ~= nil
		end
		clusters[i] = {
			services = group,
			x = x / #group,
			y = y / #group,
			key = table.concat(ids, ","),
			capital = capital,
		}
	end
	return clusters
end

---@param texture Texture
---@param group SPFNearbyGroup
local function PaintGroup(texture, group)
	if type(group.icon) == "number" then
		Art.Icon(texture, ItemIcon(group.icon --[[@as integer]]), PIN_SIZE)
	else
		Art.Fit(texture, group.icon --[[@as string]], PIN_SIZE, PIN_SIZE)
	end
end

---@param cluster SPFTownServiceCluster
---@return string
local function ClusterTown(cluster)
	local names, seen = {}, {}
	for _, point in ipairs(cluster.services) do
		local name = EntryTown(point.entry)
		if name and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	return table.concat(names, ", ")
end

---@param cluster SPFTownServiceCluster
local function AddTooltip(cluster)
	if #cluster.services == 1 then
		local entry = cluster.services[1].entry
		GameTooltip_SetTitle(GameTooltip, entry.primary.label)
		local who = entry.title and L["%s · %s"]:format(entry.name, entry.title) or entry.name
		GameTooltip_AddColoredLine(GameTooltip, who, HIGHLIGHT_FONT_COLOR)
		for _, group in ipairs(entry.groups) do
			if group ~= entry.primary then
				GameTooltip_AddNormalLine(GameTooltip, group.label)
			end
		end
		return
	end
	local town = ClusterTown(cluster)
	GameTooltip_SetTitle(GameTooltip, town ~= "" and town or L["Town services"])
	local seen = {}
	for _, point in ipairs(cluster.services) do
		for _, group in ipairs(point.entry.groups) do
			if not seen[group.key] then
				seen[group.key] = true
				GameTooltip_AddNormalLine(GameTooltip, group.label)
			end
		end
	end
end

---@class SPFServicePin : SPFCanvasPin
---@field Texture Texture
---@field HighlightTexture Texture
---@field cluster? SPFTownServiceCluster
local ServicePin = CreateFromMixins(Canvas.PinMixin)

function ServicePin:OnLoad()
	-- Above town, flight point and dungeon icons, as a dock pin is, so a service beside one still takes the hover.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_GOSSIP")
	self:SetScalingLimits(1, 1, 1.2)
	self:SetSize(PIN_SIZE, PIN_SIZE)
	self.takesMouse = true
	self.pressRegions = { self.Texture, self.HighlightTexture }
end

function ServicePin:OnAcquired(cluster)
	self.cluster = cluster
	local scale = (ns.db.mapPinScale or 100) / 100
	self:SetScalingLimits(1, scale, scale * 1.2)
	local atlas
	if #cluster.services == 1 then
		PaintGroup(self.Texture, cluster.services[1].entry.primary)
		PaintGroup(self.HighlightTexture, cluster.services[1].entry.primary)
	else
		atlas = cluster.capital and CAPITAL_ATLAS or TOWN_ATLAS
		Art.Fit(self.Texture, atlas, PIN_SIZE, PIN_SIZE)
		Art.Fit(self.HighlightTexture, atlas, PIN_SIZE, PIN_SIZE)
	end
	self:SetPosition(cluster.x, cluster.y)
end

function ServicePin:OnMouseEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	AddTooltip(self.cluster)
	GameTooltip:Show()
end

function ServicePin:OnMouseLeave()
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

function ServicePin:OnReleased()
	self:OnMouseLeave()
	self.cluster = nil
end

---@type SPFCanvasPool?
local servicePins

---@class SPFTownServicesLayer
---@field pins? table<string, SPFServicePin>
---@field mapID? number
local Services = {}

function Services:RemoveAllData()
	if servicePins then
		servicePins:ReleaseAll()
	end
	self.pins = {}
end

function Services:RefreshAllData()
	if InCombatLockdown() then
		ns.QueueMapRefresh()
		return
	end
	if not servicePins then
		return
	end
	local pins = servicePins
	local map = WorldMapFrame
	local mapID = map:GetMapID()
	local level = ns.db and ns.db.townServices or "capitals"
	local nearby = ns.NearbyServices
	if not (mapID and map:IsVisible() and level ~= "off" and nearby and nearby.State() == "ready") then
		self:RemoveAllData()
		self.mapID = nil
		return
	end
	local rebuilt = false
	local index = nearby.Index()
	if index ~= sourceIndex then
		Build()
		rebuilt = true
	end
	local clusters = Clusters(map, Points(mapID, level))
	local wanted = {}
	for _, cluster in ipairs(clusters) do
		wanted[cluster.key] = cluster
	end
	local previousMapID, previousPins = self.mapID, self.pins
	local same = not rebuilt and previousPins ~= nil and mapID == previousMapID
	if previousPins then
		for key, pin in pairs(previousPins) do
			same = same and pin.cluster ~= nil and wanted[key] ~= nil
		end
		for key in pairs(wanted) do
			same = same and previousPins[key] ~= nil
		end
	end
	self.mapID = mapID
	if same then
		return
	end
	-- A zoom or a setting re-clusters the pins. Carry the hover to the new pin for the first service still shown,
	-- as the dock layer does, so a tooltip stays open through a wheel step.
	local hovered
	if mapID == previousMapID then
		for _, pin in pairs(previousPins or {}) do
			if pin.cluster and GameTooltip:IsOwned(pin) and GameTooltip:IsShown() then
				hovered = {}
				for _, point in ipairs(pin.cluster.services) do
					hovered[#hovered + 1] = point.entry.key
				end
			end
		end
	end
	self:RemoveAllData()
	local pinOf = {}
	for _, cluster in ipairs(clusters) do
		local pin = pins:Acquire(cluster) --[[@as SPFServicePin]]
		self.pins[cluster.key] = pin
		for _, point in ipairs(cluster.services) do
			pinOf[point.entry.key] = pin
		end
	end
	if hovered then
		for _, key in ipairs(hovered) do
			local pin = pinOf[key]
			if pin then
				pin:OnMouseEnter()
				break
			end
		end
	end
end

-- Redraws the town services, as the map's own layers redraw after a zoom, a setting or combat.
function ns.RefreshTownServices()
	if servicePins then
		Services:RefreshAllData()
	end
end

-- The world map's Map Filter ("Show:") menu gets the same four levels as the settings page.
local function AddFilter(_, root)
	root:CreateDivider()
	local submenu = root:CreateButton(L["Town services"])
	-- menu-scroll-ok: the four town levels are fixed
	for _, choice in ipairs(ns.TownServiceChoices) do
		submenu:CreateRadio(choice.label, function()
			return ns.db.townServices == choice.key
		end, function()
			ns.SetOption("townServices", choice.key)
		end)
	end
end

ns.Init(function()
	servicePins = Canvas.Pool(WorldMapFrame, TEMPLATE, ServicePin, { template = TEMPLATE })
	Canvas.Watch(WorldMapFrame, function(_, what)
		if what == "show" or what == "map" or what == "scale" then
			Services:RefreshAllData()
		end
	end)
	if ns.NearbyServices and ns.NearbyServices.OnReady then
		ns.NearbyServices.OnReady(function()
			if WorldMapFrame:IsVisible() then
				Services:RefreshAllData()
			end
		end)
	end
	ns.ModifyMenu("MENU_WORLD_MAP_TRACKING", "townservices", AddFilter)
	Services:RefreshAllData()
end)

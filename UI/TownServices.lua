---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L
local Art = ns.Art
local Canvas = ns.Canvas

-- The town services on the world map: every trainer, vendor, banker and the rest the Nearby services list finds,
-- drawn at the NPC's own place in the client's minimap tracking icon for that service (a bank's money bags, a
-- repairer's anvil), never a town or city mark. Zoomed out, the pins that would overlap share one pin: since it
-- stands for several services at once, it wears the addon's own market stall (media/TownGroup.tga), with every
-- service in its tooltip; zoomed in they separate, the way UI/Map.lua groups the docks of a harbour. A click plans a
-- journey to the NPC. The setting chooses which towns show: the capitals, the capitals and the services worth a
-- detour, every town, or none.
local TEMPLATE = "ShortestPathForeverServicePinTemplate"
local PIN_SIZE = 20
-- The groups that make a town worth showing under "Capitals and important services": every trainer, the profession
-- supplies (fishing, cooking and first aid included), books and recipes, the bank, the flight master and the inn.
local IMPORTANT = { innkeeper = true, flight = true, bank = true, trade = true, reagents = true, books = true }
-- A town's service icon: the most useful thing the NPC offers, by section and then by the list's own order.
local RANK = { services = 1, trainers = 2, vendors = 3 }

-- The Map Filter's checkboxes: one for every service a pin can wear, in the list's own order. Food and drink are one
-- service to a player, ammunition covers both arrows and bullets, and bags and trade supplies share one switch; every
-- profession trainer group joins the one Profession trainers switch. A dungeon entrance group is not a service here
-- and gets no checkbox.
---@class SPFTownServiceFilter
---@field option string the saved setting, true while the service shows
---@field label string
---@field groups? table<string, boolean> the group keys it hides
---@field profession? boolean every profession trainer group

---@type SPFTownServiceFilter[]
local FILTERS = {
	{ option = "townServiceInnkeeper", label = L["Innkeeper"], groups = { innkeeper = true } },
	{ option = "townServiceFlight", label = L["Flight master"], groups = { flight = true } },
	{ option = "townServiceStable", label = L["Stable master"], groups = { stable = true } },
	{ option = "townServiceRepair", label = L["Repair"], groups = { repair = true } },
	{ option = "townServiceBank", label = L["Bank"], groups = { bank = true } },
	{ option = "townServiceAuction", label = L["Auction house"], groups = { auction = true } },
	{ option = "townServiceClass", label = L["Class trainer"], groups = { class = true } },
	{ option = "townServiceProfessions", label = L["Profession trainers"], profession = true },
	{ option = "townServiceFood", label = L["Food and drink"], groups = { food = true, drink = true } },
	{ option = "townServiceAmmunition", label = L["Ammunition"], groups = { arrows = true, bullets = true } },
	{ option = "townServiceBags", label = L["Bags and trade supplies"], groups = { bags = true, trade = true } },
	{ option = "townServiceReagents", label = L["Reagents"], groups = { reagents = true } },
	{ option = "townServiceBooks", label = L["Books and recipes"], groups = { books = true } },
	{ option = "townServiceGear", label = L["Weapons and armour"], groups = { gear = true } },
}

-- The filter a group belongs to, by its key; a profession trainer group uses the shared Profession trainers switch.
local FILTER_OF_KEY, PROFESSION_FILTER = {}, nil
for _, filter in ipairs(FILTERS) do
	if filter.profession then
		PROFESSION_FILTER = filter
	end
	for key in pairs(filter.groups or {}) do
		FILTER_OF_KEY[key] = filter
	end
end

---@param group SPFNearbyGroup
---@return SPFTownServiceFilter?
local function FilterOf(group)
	if group.key:sub(1, 11) == "profession:" then
		return PROFESSION_FILTER
	end
	return FILTER_OF_KEY[group.key]
end

---@param group SPFNearbyGroup
---@return boolean
local function GroupShown(group)
	local filter = FilterOf(group)
	return not filter or ns.db[filter.option] ~= false
end

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

local entries = {}
-- The index table the entries were built from, so a late QuestieDB read is picked up.
local sourceIndex
-- The map fraction of each entry on each map it has been asked for; nil until asked, false when off the map.
local projections = {}
local capitalNames = {}
local zoneNames = {}

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

-- The NPC's own mark: the most useful service it offers that still shows, so hiding one leaves the next best icon.
---@param entry SPFTownService
---@return SPFNearbyGroup?
local function Primary(entry)
	local best
	for _, group in ipairs(entry.groups) do
		if GroupShown(group) and (not best or (RANK[group.section] or 0) < (RANK[best.section] or 0)) then
			best = group
		end
	end
	return best
end

-- The NPCs the list knows, one entry each, with every group the NPC serves. The same spawn is indexed under each of
-- its groups, so the key merges them into one pin. The read holds only NPCs this character's side can use
-- (UI/NearbyQuestie.lua), so the map never shows the other faction's.
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
			if (group.section == "trainers" or IMPORTANT[group.key]) and GroupShown(group) then
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
		if Shown(entry, level) and Primary(entry) then
			local x, y = Position(entry, mapID)
			if x and y then
				points[#points + 1] = { entry = entry, id = entry.key, x = x, y = y }
			end
		end
	end
	return points
end

-- The service pins that would overlap at this zoom share one service pin, at their middle, through the same grouping
-- UI/Map.lua uses for docks.
---@param map SPFMapCanvas
---@param points SPFTownServicePoint[]
---@return SPFTownServiceCluster[]
local function Clusters(map, points)
	local zoom = Saturate(map:GetCanvasZoomPercent() or 0)
	local clusters = {}
	local groups = ns.OverlapGroups(map, points, PIN_SIZE * map:GetGlobalPinScale() * Lerp(1, 1.2, zoom))
	for i, group in ipairs(groups) do
		local x, y, ids = 0, 0, {}
		for _, point in ipairs(group) do
			x, y = x + point.x, y + point.y
			ids[#ids + 1] = point.id
		end
		clusters[i] = {
			services = group,
			x = x / #group,
			y = y / #group,
			key = table.concat(ids, ","),
		}
	end
	return clusters
end

---@param texture Texture
---@param cluster SPFTownServiceCluster
local function PaintPin(texture, cluster)
	if #cluster.services > 1 then
		-- A pin for several NPCs speaks for no one service, so it wears the addon's own stall, square as file art is.
		Art.Icon(texture, Art.TOWN_GROUP_FILE, PIN_SIZE)
		return
	end
	local primary = Primary(cluster.services[1].entry) --[[@as SPFNearbyGroup]]
	Art.Fit(texture, primary.tracking, PIN_SIZE, PIN_SIZE)
end

-- The service a pin stands for: its most useful NPC's primary service, by the same ranking a single NPC's pin uses.
-- One service's pin is the NPC's own primary; a group's is the best of its members.
---@param cluster SPFTownServiceCluster
---@return SPFTownServicePoint
local function Representative(cluster)
	local best, bestRank
	for _, point in ipairs(cluster.services) do
		local primary = Primary(point.entry)
		local rank = primary and RANK[primary.section] or 0
		if not best or rank < bestRank then
			best, bestRank = point, rank
		end
	end
	return best
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
		local primary = Primary(entry) --[[@as SPFNearbyGroup]]
		GameTooltip_SetTitle(GameTooltip, primary.label)
		local who = entry.title and L["%s · %s"]:format(entry.name, entry.title) or entry.name
		GameTooltip_AddColoredLine(GameTooltip, who, HIGHLIGHT_FONT_COLOR)
		for _, group in ipairs(entry.groups) do
			if group ~= primary and GroupShown(group) then
				GameTooltip_AddNormalLine(GameTooltip, group.label)
			end
		end
	else
		local town = ClusterTown(cluster)
		GameTooltip_SetTitle(GameTooltip, town ~= "" and town or L["Town services"])
		-- The pin wears the stall, not a service, so every shown service of the group's NPCs is listed once, in the
		-- list's own order.
		local seen = {}
		for _, point in ipairs(cluster.services) do
			for _, group in ipairs(point.entry.groups) do
				if GroupShown(group) and not seen[group.key] then
					seen[group.key] = true
					GameTooltip_AddNormalLine(GameTooltip, group.label)
				end
			end
		end
	end
	if ns.db.journey then
		GameTooltip_AddInstructionLine(GameTooltip, L["Click to plan a journey here."])
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
	PaintPin(self.Texture, cluster)
	PaintPin(self.HighlightTexture, cluster)
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

-- A left click plans a journey to the service this pin stands for (a group's most useful one), through the same
-- Nearby services journey its rows and the tracking menu start. Unlike our other map pins, a plain click is enough:
-- a service pin has no other left-click action, and the tooltip says so.
function ServicePin:OnMouseClickAction(button)
	if button ~= "LeftButton" or not ns.db.journey then
		return
	end
	local entry = Representative(self.cluster).entry
	local primary = Primary(entry) --[[@as SPFNearbyGroup]]
	ns.NearbyServices.Navigate(primary.key, entry --[[@as SPFNearbyPlace]])
end

function ServicePin:OnReleased()
	self:OnMouseLeave()
	self.cluster = nil
end

---@type SPFCanvasPool?
local servicePins

-- The town services belong on a zone or city map, where a place on the map is a place in the world. A continent or
-- the world map only marks where the town is, and the client's own town marks already do that.
---@param mapID integer
---@return boolean
local function ServiceMap(mapID)
	local info = C_Map.GetMapInfo(mapID)
	if not info then
		return false
	end
	return info.mapType == Enum.UIMapType.Zone or info.mapType == Enum.UIMapType.Micro
end

---@class SPFTownServicesLayer
---@field pins? table<string, SPFServicePin>
---@field mapID? number
---@field shown? string which services show, so hiding one repaints its pins even when the clusters stay put
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
	if
		not (
			mapID
			and ServiceMap(mapID)
			and map:IsVisible()
			and level ~= "off"
			and nearby
			and nearby.State() == "ready"
		)
	then
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
	local flags = {}
	for _, filter in ipairs(FILTERS) do
		flags[#flags + 1] = ns.db[filter.option] == false and "0" or "1"
	end
	local shown = table.concat(flags)
	local clusters = Clusters(map, Points(mapID, level))
	local wanted = {}
	for _, cluster in ipairs(clusters) do
		wanted[cluster.key] = cluster
	end
	local previousMapID, previousPins = self.mapID, self.pins
	local same = not rebuilt and previousPins ~= nil and mapID == previousMapID and self.shown == shown
	if previousPins then
		for key, pin in pairs(previousPins) do
			same = same and pin.cluster ~= nil and wanted[key] ~= nil
		end
		for key in pairs(wanted) do
			same = same and previousPins[key] ~= nil
		end
	end
	self.mapID, self.shown = mapID, shown
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

-- Shows or hides one service on every pin, as the Map Filter's checkbox does, and redraws the map at once.
---@param option string
---@param shown boolean
function ns.SetTownServiceShown(option, shown)
	ns.SetOption(option, shown)
	ns.RefreshTownServices()
end

-- The world map's Map Filter ("Show:") menu gets the same four levels as the settings page, then a checkbox for each
-- service the pins can wear.
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
	submenu:CreateDivider()
	-- menu-scroll-ok: one checkbox per fixed service
	for _, filter in ipairs(FILTERS) do
		submenu:CreateCheckbox(filter.label, function()
			return ns.db[filter.option] ~= false
		end, function()
			ns.SetTownServiceShown(filter.option, ns.db[filter.option] == false)
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

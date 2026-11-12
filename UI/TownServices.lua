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
-- repairer's anvil), never a town or city mark. Zoomed out, pins of the same service merge first into one pin wearing
-- that service's own icon, with every member in its tooltip; pins of different services merge only where they truly
-- overlap, into a pin wearing the addon's own market stall (media/TownGroup.tga) with every service in its tooltip.
-- Each zoom step merges less, the way UI/Map.lua separates the docks of a harbour, and full zoom splits every NPC into
-- its own pin. A click plans a journey to the NPC. The setting chooses which towns show: the capitals, the capitals
-- and the services worth a detour, every town, or none.
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
-- and gets no checkbox, and neither does a flight master: its pin is its flight point's (Drawn).
---@class SPFTownServiceFilter
---@field option string the saved setting, true while the service shows
---@field label string
---@field groups? table<string, boolean> the group keys it hides
---@field profession? boolean every profession trainer group

---@type SPFTownServiceFilter[]
local FILTERS = {
	{ option = "townServiceInnkeeper", label = L["Innkeeper"], groups = { innkeeper = true } },
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
---@field key string the NPC and map, which a re-read of the database can change
---@field name string
---@field title? string
---@field world SPFPoint the spawn nearest the middle of the NPC's route on that map
---@field map integer the zone map the spawn is on
---@field x number the chosen spawn's map fraction
---@field y number the chosen spawn's map fraction
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

-- A group the town layer draws. A flight master is not one: QuestieDB's FLIGHT_MASTER flag is what puts an NPC in
-- the flight group, and that NPC is the flight point's own master, so its taxi node already wears a flight point pin
-- (UI/FlightPins.lua, and the client's own provider where it draws them). Drawing the NPC as well stood a second
-- "Flight master" pin beside the flight point pin (#816). The group still counts when a town is "important", since a
-- flight point is what makes a small town worth the detour.
---@param group SPFNearbyGroup
---@return boolean
local function Drawn(group)
	return group.key ~= "flight"
end

-- The NPC's own mark: the most useful service it offers that still shows, so hiding one leaves the next best icon.
---@param entry SPFTownService
---@return SPFNearbyGroup?
local function Primary(entry)
	local best
	for _, group in ipairs(entry.groups) do
		if
			Drawn(group)
			and GroupShown(group)
			and (not best or (RANK[group.section] or 0) < (RANK[best.section] or 0))
		then
			best = group
		end
	end
	return best
end

-- The spot a wandering NPC stands on: QuestieDB lists every spawn along its route, so the town layer draws the NPC
-- once on each map, at the spawn nearest the mean of its spawns there. That keeps the pin on a real spawn point near
-- the middle of the route, and a journey from the pin still goes to a real place on its map.
---@param spawns SPFNearbyPlace[]
---@return SPFNearbyPlace
local function Middle(spawns)
	local sumX, sumY = 0, 0
	for _, spawn in ipairs(spawns) do
		sumX, sumY = sumX + spawn.world.x, sumY + spawn.world.y
	end
	local meanX, meanY = sumX / #spawns, sumY / #spawns
	local best, gap
	for _, spawn in ipairs(spawns) do
		local distance = (spawn.world.x - meanX) ^ 2 + (spawn.world.y - meanY) ^ 2
		if not gap or distance < gap then
			best, gap = spawn, distance
		end
	end
	return best --[[@as SPFNearbyPlace]]
end

-- The NPCs the list knows, one entry each on each map they stand on, with every group the NPC serves. Every spawn
-- is indexed under each of its groups, so the key merges them into one pin per NPC per map rather than one per spawn.
-- The read holds only NPCs this character's side can use (UI/NearbyQuestie.lua), so the map never shows the other
-- faction's.
local function Build()
	local index, groups = ns.NearbyServices.Index(), ns.NearbyServices.Groups()
	sourceIndex = index
	entries, projections = {}, {}
	local byKey = {}
	for _, group in ipairs(groups) do
		if group.section ~= "entrances" then
			for _, place in ipairs(index[group.key] or {}) do
				local key = place.id .. ":" .. place.map
				local entry = byKey[key]
				if not entry then
					entry = {
						id = place.id,
						key = key,
						name = place.name,
						title = place.title,
						map = place.map,
						groups = {},
						spawns = {},
					}
					byKey[key] = entry
					entries[#entries + 1] = entry
				end
				entry.spawns[#entry.spawns + 1] = place
				-- Every spawn of the NPC is listed under the group, so the group joins the entry once.
				if entry.groups[#entry.groups] ~= group then
					entry.groups[#entry.groups + 1] = group
				end
			end
		end
	end
	for _, entry in ipairs(entries) do
		local spot = Middle(entry.spawns)
		entry.spawns = nil
		entry.world, entry.x, entry.y = spot.world, spot.x, spot.y
		entry.capitalUiMap = Capital(spot.world)
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

-- At full zoom every NPC gets its own pin, even one standing in the same doorway. The NPCs whose pins would still
-- overlap spread around their shared centre, one pin width apart, so each can be hovered and clicked.
---@param map SPFMapCanvas
---@param points SPFTownServicePoint[]
---@return SPFTownServiceCluster[]
local function Spread(map, points)
	local scale = map:GetGlobalPinScale()
	local canvas = map:GetCanvas()
	local size = PIN_SIZE * scale / map:GetCanvasScale()
	local reachX, reachY = size / canvas:GetWidth(), size / canvas:GetHeight()
	local clusters = {}
	for _, group in ipairs(ns.OverlapGroups(map, points, PIN_SIZE * scale)) do
		if #group == 1 then
			local point = group[1]
			clusters[#clusters + 1] = { services = { point }, x = point.x, y = point.y, key = point.id }
		else
			local centreX, centreY = 0, 0
			for _, point in ipairs(group) do
				centreX, centreY = centreX + point.x, centreY + point.y
			end
			centreX, centreY = centreX / #group, centreY / #group
			local radius = 0.5 / math.sin(math.pi / #group)
			for i, point in ipairs(group) do
				local angle = 2 * math.pi * (i - 1) / #group
				clusters[#clusters + 1] = {
					services = { point },
					x = centreX + math.cos(angle) * reachX * radius,
					y = centreY + math.sin(angle) * reachY * radius,
					key = point.id,
				}
			end
		end
	end
	return clusters
end

-- The service pins that would overlap at this zoom share one service pin, at their middle, through the same grouping
-- UI/Map.lua uses for docks. Pins of the same service merge first, at a margin that shrinks as the map is zoomed in,
-- so three leatherworking trainers become one leatherworking icon. Different services then merge only where their
-- pins truly overlap, at the plain pin size when zoomed out and less as the map closes in, so they stay apart while
-- they fit side by side. Both reaches fall to nothing at full zoom, where every NPC is shown apart.
---@param map SPFMapCanvas
---@param points SPFTownServicePoint[]
---@return SPFTownServiceCluster[]
local function Clusters(map, points)
	local zoom = Saturate(map:GetCanvasZoomPercent() or 0)
	if zoom >= 1 then
		return Spread(map, points)
	end
	local scale = map:GetGlobalPinScale()
	local byService, services = {}, {}
	for _, point in ipairs(points) do
		local primary = Primary(point.entry) --[[@as SPFNearbyGroup]]
		local same = byService[primary.key]
		if not same then
			same = { points = {} }
			byService[primary.key] = same
			services[#services + 1] = same
		end
		same.points[#same.points + 1] = point
	end
	local merged = {}
	local sameReach = PIN_SIZE * scale * Lerp(1.2, 0, zoom)
	for _, same in ipairs(services) do
		for _, group in ipairs(ns.OverlapGroups(map, same.points, sameReach)) do
			local x, y = 0, 0
			for _, point in ipairs(group) do
				x, y = x + point.x, y + point.y
			end
			merged[#merged + 1] = {
				services = group,
				x = x / #group,
				y = y / #group,
			}
		end
	end
	local clusters = {}
	local mixedReach = PIN_SIZE * scale * Lerp(1, 0, zoom)
	for i, group in ipairs(ns.OverlapGroups(map, merged, mixedReach)) do
		local member = {}
		for _, same in ipairs(group) do
			for _, point in ipairs(same.services) do
				member[point] = true
			end
		end
		-- Keep the entries' own order, so a tooltip lists a town's services in the list's order, not the order the
		-- passes happened to visit them.
		local members, x, y, ids = {}, 0, 0, {}
		for _, point in ipairs(points) do
			if member[point] then
				members[#members + 1] = point
				x, y = x + point.x, y + point.y
				ids[#ids + 1] = point.id
			end
		end
		clusters[i] = {
			services = members,
			x = x / #members,
			y = y / #members,
			key = table.concat(ids, ","),
		}
	end
	return clusters
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

-- The one service every member of a cluster shows, when they all show the same one; nil for a mixed cluster.
---@param cluster SPFTownServiceCluster
---@return SPFNearbyGroup?
local function SharedService(cluster)
	local shared = Primary(cluster.services[1].entry)
	for i = 2, #cluster.services do
		local primary = Primary(cluster.services[i].entry)
		if not shared or not primary or primary.key ~= shared.key then
			return nil
		end
	end
	return shared
end

---@param texture Texture
---@param cluster SPFTownServiceCluster
local function PaintPin(texture, cluster)
	local shared = SharedService(cluster)
	if shared then
		Art.Fit(texture, shared.tracking, PIN_SIZE, PIN_SIZE)
	else
		-- A pin for different services speaks for no one service, so it wears the addon's own stall, square as file
		-- art is, with every service in its tooltip.
		Art.Icon(texture, Art.TOWN_GROUP_FILE, PIN_SIZE)
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

---@param entry SPFTownService
---@return string
local function EntryLine(entry)
	return entry.title and L["%s · %s"]:format(entry.name, entry.title) or entry.name
end

---@param cluster SPFTownServiceCluster
local function AddTooltip(cluster)
	if #cluster.services == 1 then
		local entry = cluster.services[1].entry
		local primary = Primary(entry) --[[@as SPFNearbyGroup]]
		GameTooltip_SetTitle(GameTooltip, primary.label)
		GameTooltip_AddColoredLine(GameTooltip, EntryLine(entry), HIGHLIGHT_FONT_COLOR)
		for _, group in ipairs(entry.groups) do
			if group ~= primary and Drawn(group) and GroupShown(group) then
				GameTooltip_AddNormalLine(GameTooltip, group.label)
			end
		end
	else
		local shared = SharedService(cluster)
		if shared then
			-- One service stands for several NPCs, so the pin names that service and then every member it stands for.
			GameTooltip_SetTitle(GameTooltip, shared.label)
			local seen = { [shared.key] = true }
			for _, point in ipairs(cluster.services) do
				GameTooltip_AddColoredLine(GameTooltip, EntryLine(point.entry), HIGHLIGHT_FONT_COLOR)
			end
			for _, point in ipairs(cluster.services) do
				for _, group in ipairs(point.entry.groups) do
					if group ~= shared and Drawn(group) and GroupShown(group) and not seen[group.key] then
						seen[group.key] = true
						GameTooltip_AddNormalLine(GameTooltip, group.label)
					end
				end
			end
		else
			local town = ClusterTown(cluster)
			GameTooltip_SetTitle(GameTooltip, town ~= "" and town or L["Town services"])
			-- A mixed pin wears the stall, not a service, so every shown service of the group's NPCs is listed once,
			-- in the list's own order.
			local seen = {}
			for _, point in ipairs(cluster.services) do
				for _, group in ipairs(point.entry.groups) do
					if Drawn(group) and GroupShown(group) and not seen[group.key] then
						seen[group.key] = true
						GameTooltip_AddNormalLine(GameTooltip, group.label)
					end
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
		-- The pin set is unchanged, but the clusters were worked out again for this zoom. Adopt them, so a pin stands
		-- on the place this zoom gives it: full zoom spreads NPCs sharing a doorway one pin apart, and every step out
		-- brings them back onto their own spots. Keying only by the members and leaving the old pins in place kept a
		-- pin on the previous zoom's spot, which could be off the map at the next step (#816).
		for key, pin in pairs(previousPins or {}) do
			local cluster = wanted[key]
			if cluster then
				pin.cluster = cluster
				pin:SetPosition(cluster.x, cluster.y)
			end
		end
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

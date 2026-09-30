---@type string, SPFNamespace
local _, ns = ...
local L = ns.L
local SERVICES = {
	{ key = "class", label = L["Class trainer"] },
	{ key = "trainer", flag = "TRAINER", label = L["Trainers by specialty"] },
	{ key = "repair", flag = "REPAIR", label = L["Repair"] },
	{ key = "reagents", flag = "VENDOR", label = L["Reagents"] },
	{ key = "vendor", flag = "VENDOR", label = L["Vendors by specialty"] },
	{ key = "innkeeper", flag = "INNKEEPER", label = L["Innkeeper"] },
	{ key = "bank", flag = "BANKER", label = L["Bank"] },
	{ key = "auction", flag = "AUCTIONEER", label = L["Auction house"] },
	{ key = "flight", flag = "FLIGHT_MASTER", label = L["Flight master"] },
	{ key = "stable", flag = "STABLEMASTER", label = L["Stable master"] },
}
local index, state, panel, rows = {}, "idle", nil, {}
local Open
local function Table(source)
	local chunk = type(source) == "string" and loadstring(source)
	if not chunk then
		return {}
	end
	setfenv(chunk, {})
	local ok, value = pcall(chunk)
	return ok and type(value) == "table" and value or {}
end
local function Nearest(key, world, specialty)
	local best, distance
	for _, place in ipairs(index[key] or {}) do
		if place.world.map == world.map and (not specialty or place.specialty == specialty) then
			local d = (place.world.x - world.x) ^ 2 + (place.world.y - world.y) ^ 2
			if not distance or d < distance or (d == distance and place.id < best.id) then
				best, distance = place, d
			end
		end
	end
	return best
end
local function Navigate(key, place)
	if not place then
		return false
	end
	local kind = (key == "trainer" or key == "class") and "trainer"
		or key == "innkeeper" and "innkeeper"
		or key == "flight" and "flightmaster"
		or nil
	return ShortestPathForever.API.Navigate("Shortest Path Forever", place.map, place.x, place.y, place.name, kind)
end
local function Build()
	if state == "building" or state == "ready" then
		return
	end
	local lib = rawget(_G, "LibQuestieDB")
	if not lib or not lib.RequireContract or not lib.RequireContract(2) then
		state = "unavailable"
		return
	end
	local zones = lib.Support.Get("ZoneDB")
	local expansion = lib.Enum and lib.Enum.byExpansion and lib.Enum.byExpansion.Classic
	local constants = expansion and expansion.npcFlags
	if not zones or not zones.private or not constants or not lib.Npc then
		state = "unavailable"
		return
	end
	index = {}
	state = "building"
	local co = coroutine.create(function()
		local area = Table(zones.private.areaIdToUiMapId)
		local override = Table(zones.private.areaIdToUiMapIdOverride)
		local parents = Table(zones.private.subZoneToParentZone)
		local parentOverride = Table(zones.private.subZoneToParentZoneOverride)
		local faction = UnitFactionGroup("player") == "Alliance" and "A" or "H"
		local tweaks = rawget(_G, "TweaksForever")
		local classIds = {}
		if
			tweaks
			and tweaks.API
			and type(tweaks.API.version) == "number"
			and tweaks.API.version >= 2
			and tweaks.API.Trainers
		then
			for _, trainer in ipairs(tweaks.API.Trainers()) do
				classIds[trainer.npc] = true
			end
		end
		local fields = { "name", "subName", "spawns", "friendlyToFaction", "npcFlags" }
		for _, id in ipairs(lib.Npc.GetAllIds()) do
			local values = lib.Npc.GetAll(id, fields)
			if values then
				local name, specialty, spawns, friendly, flags = unpack(values, 1, values.n)
				if type(name) == "string" and (friendly == "AH" or friendly == faction) and type(flags) == "number" then
					local keys = {}
					for _, service in ipairs(SERVICES) do
						if service.flag and bit.band(flags, constants[service.flag]) ~= 0 then
							if
								service.key ~= "reagents"
								or specialty == L["Reagents"]
								or specialty == L["Reagent Vendor"]
							then
								keys[#keys + 1] = service.key
							end
						end
					end
					if classIds[id] then
						keys[#keys + 1] = "class"
					end
					if #keys > 0 then
						for zone, points in pairs(spawns or {}) do
							local parent = parentOverride[zone] or parents[zone]
							local map = override[zone] or area[zone] or (parent and (override[parent] or area[parent]))
							for _, spot in ipairs(points) do
								local x, y = spot[1], spot[2]
								if
									map
									and type(x) == "number"
									and type(y) == "number"
									and x >= 0
									and x <= 100
									and y >= 0
									and y <= 100
								then
									local world = ns.WorldPoint(map, x / 100, y / 100)
									if world then
										local place = {
											id = id,
											name = name,
											specialty = specialty,
											map = map,
											x = x / 100,
											y = y / 100,
											world = world,
										}
										for _, key in ipairs(keys) do
											index[key] = index[key] or {}
											index[key][#index[key] + 1] = place
										end
									end
								end
								coroutine.yield()
							end
						end
					end
				end
			end
			coroutine.yield()
		end
	end)
	local function Pump()
		if InCombatLockdown() or ns.Path.Busy() then
			C_Timer.After(0.1, Pump)
			return
		end
		local finish = debugprofilestop() + 1
		repeat
			local ok, err = coroutine.resume(co)
			if not ok then
				state = "unavailable"
				geterrorhandler()(err)
				return
			end
			if coroutine.status(co) == "dead" then
				state = "ready"
				if panel and panel:IsShown() then
					Open()
				end
				return
			end
		until debugprofilestop() >= finish
		C_Timer.After(0, Pump)
	end
	C_Timer.After(0, Pump)
end
local function PlayerWorld()
	local map = C_Map.GetBestMapForUnit("player")
	local point = map and C_Map.GetPlayerMapPosition(map, "player")
	if map and point then
		return ns.WorldPoint(map, point:GetXY()) -- multi-value: x and y
	end
end
Open = function(key)
	Build()
	if not panel then
		panel = CreateFrame("Frame", "ShortestPathForeverNearby", UIParent, "BasicFrameTemplateWithInset")
		panel:SetSize(380, 400)
		panel:SetPoint("CENTER")
		panel:SetFrameStrata("DIALOG")
		panel:SetClampedToScreen(true)
		panel.TitleText:SetText(L["Nearby services"])
		panel:EnableKeyboard(true)
		panel:SetScript("OnKeyDown", function(self, pressed)
			self:SetPropagateKeyboardInput(pressed ~= "ESCAPE")
			if pressed == "ESCAPE" then
				self:Hide()
			end
		end)
		local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 20, -36)
		scroll:SetPoint("BOTTOMRIGHT", -36, 18)
		local content = CreateFrame("Frame", nil, scroll)
		content:SetWidth(320)
		scroll:SetScrollChild(content)
		panel.content, panel.scroll = content, scroll
	end
	for _, row in ipairs(rows) do
		row:Hide()
	end
	local world, items = PlayerWorld(), {}
	if key then
		items[1] = { label = L["Back"], back = true }
		local titles = {}
		for _, place in ipairs(index[key] or {}) do
			if world and place.world.map == world.map and place.specialty then
				titles[place.specialty] = true
			end
		end
		local names = {}
		for title in pairs(titles) do
			names[#names + 1] = title
		end
		table.sort(names)
		for _, title in ipairs(names) do
			items[#items + 1] = { label = title, key = key, specialty = title }
		end
	else
		for _, service in ipairs(SERVICES) do
			items[#items + 1] = service
		end
	end
	for i, item in ipairs(items) do
		local row = rows[i]
		if not row then
			row = CreateFrame("Button", nil, panel.content, "UIPanelButtonTemplate")
			row:SetSize(320, 26)
			rows[i] = row
		end
		row:SetPoint("TOPLEFT", 0, -(i - 1) * 30)
		local place = world and Nearest(item.key, world, item.specialty)
		local text = item.label
		if state == "building" then
			text = L["%s — loading QuestieDB"]:format(text)
		elseif not item.back and not place then
			text = L["%s — unavailable here"]:format(text)
		end
		row:SetText(text)
		row:SetEnabled(item.back or (state == "ready" and place ~= nil))
		row:SetScript("OnClick", function()
			if item.back then
				Open()
			elseif not item.specialty and (item.key == "trainer" or item.key == "vendor") then
				Open(item.key)
			elseif Navigate(item.key, place) then
				panel:Hide()
			end
		end)
		row:Show()
	end
	panel.content:SetHeight(math.max(1, #items * 30))
	panel.scroll:SetVerticalScroll(0)
	panel:Show()
end
---@class SPFNearbyServices
---@field Build fun()
---@field Nearest fun(key: string, world: SPFPoint, specialty?: string): SPFNearbyPlace?
---@field Navigate fun(key: string, place: SPFNearbyPlace?): boolean
---@field Index fun(): table<string, SPFNearbyPlace[]>
---@field State fun(): string
---@field Services table[]
---@class SPFNearbyPlace
---@field id integer
---@field name string
---@field specialty? string
---@field map integer
---@field x number
---@field y number
---@field world SPFPoint
ns.NearbyServices = {
	Build = Build,
	Nearest = Nearest,
	Navigate = Navigate,
	Services = SERVICES,
	Index = function()
		return index
	end,
	State = function()
		return state
	end,
}
ns.OpenNearby = Open
ns.Init(function()
	SLASH_SPFNEAR1 = "/spfnear"
	SlashCmdList.SPFNEAR = function(message)
		local key = string.lower((message or ""):match("^%s*(.-)%s*$"))
		local world = PlayerWorld()
		if key ~= "" and state == "ready" and world then
			for _, service in ipairs(SERVICES) do
				if service.key == key then
					Navigate(key, Nearest(key, world))
					return
				end
			end
		end
		Open()
	end
end)

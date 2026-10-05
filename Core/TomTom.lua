---@class SPFNamespace
local ns = select(2, ...)

-- Guides such as Questie, Zygor and All The Things set waypoints through TomTom's API. While TomTom is not
-- installed, this shim answers those calls by starting a Shortest Path journey, so a guide's pin plans real
-- travel. It is never defined when TomTom is installed or loads later, and the player can turn it off in
-- settings. Every waypoint belongs to one owner, so a second one replaces the journey rather than queueing.

-- The journey this shim started, so a guide can remove the waypoint it set.
local OWNER = "TomTom"
local API = ShortestPathForever.API

---@param value any
local function Number(value)
	return canaccessvalue(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

---@param value any
local function Text(value)
	return value == nil or (canaccessvalue(value) and type(value) == "string")
end

---@param value any
local function Flag(value)
	return value == nil or (canaccessvalue(value) and type(value) == "boolean")
end

-- A map the client knows. Modern callers pass a uiMapID; the old continent and zone indices have no client
-- mapping on this build, so the zone wins when it names a map and the continent is only a fallback.
---@param continent any
---@param zone any
---@return integer?
local function MapID(continent, zone)
	local function Known(id)
		return Number(id) and id > 0 and id % 1 == 0 and C_Map.GetMapInfo(id) ~= nil
	end
	if Known(zone) then
		return zone
	end
	if Known(continent) then
		return continent
	end
end

---@param map integer
---@param x number
---@param y number
---@param title string?
local function Key(map, x, y, title)
	return string.format("%d:%.17g:%.17g:%s", map, x, y, title or "")
end

-- The waypoint table a guide keeps, shaped like TomTom's: map, x and y by index, the title and its author by name.
---@type table<integer, table<string, TomTomWaypoint>>
local waypoints = {}
---@type TomTomWaypoint?
local current
local active = false

---@param uid TomTomWaypoint
---@param opts table?
---@return boolean
local function Fill(uid, opts)
	if opts == nil then
		return true
	end
	if type(opts) ~= "table" or not (Text(opts.title) and Text(opts.from)) then
		return false
	end
	for key, value in pairs(opts) do
		if uid[key] == nil then
			uid[key] = value
		end
	end
	return true
end

local function Forget()
	for map in pairs(waypoints) do
		waypoints[map] = nil
	end
end

---@param a any
---@param b TomTomWaypoint?
---@return boolean
local function Same(a, b)
	return type(a) == "table" and b ~= nil and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a.title == b.title
end

-- Both the waypoint and the journey start together: a refused journey leaves no waypoint for a guide to remove.
---@param map integer
---@param x number
---@param y number
---@param title string?
---@param opts table?
---@return TomTomWaypoint?
local function Start(map, x, y, title, opts)
	if not (active and API and ns.db) then
		return nil
	end
	---@type TomTomWaypoint
	local uid = { map, x, y, title = title }
	if not Fill(uid, opts) or not API.Navigate(OWNER, map, x, y, title) then
		return nil
	end
	current = uid
	Forget()
	waypoints[map] = { [Key(map, x, y, title)] = uid }
	return uid
end

local shim = {}
shim.waypoints = waypoints

---@param map integer
---@param x number
---@param y number
---@param opts? TomTomWaypointOptions
---@return TomTomWaypoint?
function shim.AddWaypoint(_, map, x, y, opts)
	if opts ~= nil and type(opts) ~= "table" then
		return nil
	end
	return Start(map, x, y, opts and opts.title, opts)
end

-- The map, its floor (this client has no floors) and the same point AddWaypoint takes.
---@param map integer
---@param floor number?
---@param x number
---@param y number
---@param opts? TomTomWaypointOptions
---@return TomTomWaypoint?
function shim.AddMFWaypoint(_, map, floor, x, y, opts)
	if floor ~= nil and not Number(floor) then
		return nil
	end
	return Start(map, x, y, opts and opts.title, opts)
end

-- The old continent and zone form, with coordinates on a 0-100 scale.
---@param continent any
---@param zone any
---@param x number
---@param y number
---@param desc? string
---@param persistent? boolean
---@param minimap? boolean
---@param world? boolean
---@param callbacks? table|false
---@param silent? boolean
---@param crazy? boolean
---@return TomTomWaypoint?
function shim.AddZWaypoint(_, continent, zone, x, y, desc, persistent, minimap, world, callbacks, silent, crazy)
	if not (Number(x) and Number(y)) then
		return nil
	end
	if not (Text(desc) and Flag(persistent) and Flag(minimap) and Flag(world) and Flag(silent) and Flag(crazy)) then
		return nil
	end
	if callbacks ~= nil and callbacks ~= false and type(callbacks) ~= "table" then
		return nil
	end
	local map = MapID(continent, zone)
	if not map then
		return nil
	end
	return Start(map, x / 100, y / 100, desc, {
		crazy = crazy,
		persistent = persistent,
		minimap = minimap,
		world = world,
		callbacks = callbacks,
		silent = silent,
	})
end

---@param waypoint TomTomWaypoint
---@return boolean
function shim.RemoveWaypoint(_, waypoint)
	if not Same(waypoint, current) then
		return false
	end
	if API then
		API.Cancel(OWNER)
	end
	current = nil
	Forget()
	return true
end

-- TomTom owns this global; another addon's TomTom, or one that loads later, is left alone.
---@return boolean
local function Installed()
	if TomTom ~= nil and TomTom ~= shim then
		return true
	end
	if C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("TomTom") then
		return true
	end
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("TomTom") or false
end

local function StandDown()
	if not active then
		return
	end
	active = false
	if API and API.CurrentStop(OWNER) then
		API.Cancel(OWNER)
	end
	current = nil
	Forget()
	if TomTom == shim then
		TomTom = nil
	end
end

-- The settings checkbox and the addon's own load both call this.
function ns.RefreshTomTom()
	if not (ns.db and ns.db.tomtom) or Installed() then
		StandDown()
		return
	end
	if not active then
		active = true
		TomTom = shim
	end
end

-- A journey that ends, or is replaced by the player or another addon, leaves no waypoint behind.
hooksecurefunc(ns, "JourneyChanged", function()
	if active and not API.CurrentStop(OWNER) then
		current = nil
		Forget()
	end
end)

ns.Init(function()
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:SetScript("OnEvent", function(self, _, name)
		if name == "TomTom" then
			StandDown()
			self:UnregisterEvent("ADDON_LOADED")
		end
	end)
	ns.RefreshTomTom()
end)

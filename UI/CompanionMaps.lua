---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

local Maps = {}
ns.CompanionMaps = Maps

---@class SPFCompanionPin : Frame
---@field isLeaMapsPin? boolean
---@field data? table
---@field u? number
---@field v? number
---@field look? table
---@field node? number
---@field kind? string

---@type {kind: string, x: number, y: number, key: string}[]
local pins = {}
local signature, nextScan = "", 0
-- The string Scan returns, built only when the pins or the journey it stands for change: UI/Canvas.lua reads it every
-- frame the map is shown, and joining a fresh string there is work done once a frame for nothing (WFA-13, #784).
local key, keySignature, keyPlan, keyCurrent

local function Signature()
	local plan, current = ns.JourneyPlan()
	if keySignature ~= signature or keyPlan ~= plan or keyCurrent ~= current then
		keySignature, keyPlan, keyCurrent = signature, plan, current
		key = signature .. ":" .. tostring(plan) .. ":" .. tostring(current)
	end
	return key
end

-- Reuse scan storage as well as the final key. GetChildren returns multiple values, so
-- walking those values directly avoids a fresh child array at every level of a stitched map.
local scan = { used = 0 }
local entries, keys = {}, {}
local Visit
local function Children(recursive, ...)
	for index = 1, select("#", ...) do
		Visit(select(index, ...), recursive)
	end
end

Visit = function(child, recursive)
	if not child:IsVisible() then
		return
	end
	local kind
	if scan.lea and child.isLeaMapsPin and child.data then
		local category = child.data[1]
		kind = type(category) == "string"
				and (category:match("^Flight") and "flight" or category:match("^Travel") and "travel" or category:match(
					"^Portal"
				) and "portal")
			or nil
	elseif scan.open and child.u and child.v and child.look then
		kind = child.node and "flight" or (child.kind == "boat" or child.kind == "zeppelin") and child.kind or nil
	end
	if kind then
		local x, y = child:GetCenter()
		if x and scan.left and scan.top and scan.width > 0 and scan.height > 0 then
			local scale = child:GetEffectiveScale() / scan.canvas:GetEffectiveScale()
			x, y = (x * scale - scan.left) / scan.width, (scan.top - y * scale) / scan.height
			scan.used = scan.used + 1
			local entry = entries[scan.used]
			if not entry then
				entry = {}
				entries[scan.used] = entry
			end
			if entry.kind ~= kind or entry.x ~= x or entry.y ~= y then
				entry.kind, entry.x, entry.y = kind, x, y
				entry.key = string.format("%s:%.5f:%.5f", kind, x, y)
				scan.changed = true
			end
			pins[scan.used] = entry
		end
	elseif recursive then
		Children(true, child:GetChildren())
	end
end

-- Read visible pins, rather than private settings: coverage, faction and zoom rules belong to their producer.
---@param map SPFMapCanvas
---@return string
function Maps.Scan(map)
	local now = GetTime()
	if now < nextScan then
		return Signature()
	end
	nextScan = now + 0.25
	scan.lea = C_AddOns.IsAddOnLoaded("Leatrix_Maps")
	scan.open = C_AddOns.IsAddOnLoaded("OpenMap") and ns.OpenMapAddon.Stitched()
	if not scan.lea and not scan.open and #pins == 0 then
		return Signature()
	end
	local canvas = map:GetCanvas()
	scan.canvas, scan.width, scan.height = canvas, canvas:GetWidth(), canvas:GetHeight()
	scan.left, scan.top = canvas:GetLeft(), canvas:GetTop()
	scan.used, scan.changed = 0, false
	local previous = #pins
	if scan.lea then
		Children(false, canvas:GetChildren())
	end
	if scan.open then
		Children(true, (canvas:GetParent() or canvas):GetChildren())
	end
	for index = scan.used + 1, previous do
		pins[index] = nil
	end
	if scan.changed or scan.used ~= previous then
		for index, pin in ipairs(pins) do
			keys[index] = pin.key
		end
		for index = #pins + 1, #keys do
			keys[index] = nil
		end
		table.sort(keys)
		signature = table.concat(keys, ";")
	end
	return Signature()
end

---@param kind string
---@param x number
---@param y number
---@param placeKind? SPFKind
---@param placeID? number
---@return boolean
function Maps.Suppresses(kind, x, y, placeKind, placeID)
	local plan, current = ns.JourneyPlan()
	if plan and placeID then
		for index = current, #plan.legs do
			local leg = plan.legs[index]
			if
				leg.from.kind == placeKind and leg.from.id == placeID
				or leg.to.kind == placeKind and leg.to.id == placeID
			then
				return false
			end
		end
	end
	for _, pin in ipairs(pins) do
		local matching = pin.kind == kind
			or pin.kind == "travel" and (kind == "boat" or kind == "zeppelin" or kind == "tram")
		if matching and math.abs(pin.x - x) < 0.008 and math.abs(pin.y - y) < 0.008 then
			return true
		end
	end
	return false
end

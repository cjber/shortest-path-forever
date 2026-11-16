---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local APIKit = assert(ForeverCore.APIKit)

-- The public API's arguments: what a caller may send, and what the addon answers while it has nothing to say. The
-- API and the walk estimates share one set of checks, so a place, an owner or a reason reads the same everywhere.
---@class SPFAPIInput
local Input = {}
ns.APIInput = Input

---@param value any
---@return boolean
function Input.Number(value)
	return canaccessvalue(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

---@param map any
---@param x any
---@param y any
---@return SPFPoint?
function Input.Point(map, x, y)
	if
		not Input.Number(map)
		or map <= 0
		or map % 1 ~= 0
		or not Input.Number(x)
		or not Input.Number(y)
		or x < 0
		or x > 1
		or y < 0
		or y > 1
	then
		return nil
	end
	return ns.WorldPoint(map, x, y)
end

-- A world point as this API names places: the uiMapID C_Map projects it onto and 0-1 fractions there. It is the
-- reverse of Point, so a caller reads back the same shape it sent and never one of ns's own world points.
---@param point SPFPoint?
---@return SPFAPIPlace?
function Input.Place(point)
	if not point then
		return nil
	end
	local uiMap, position = C_Map.GetMapPosFromWorldPos(point.map, CreateVector2D(point.x, point.y))
	if not (uiMap and position and Input.Number(uiMap) and uiMap > 0 and uiMap % 1 == 0) then
		return nil
	end
	local x, y = position:GetXY()
	if not (Input.Number(x) and Input.Number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
		return nil
	end
	return { map = uiMap, x = x, y = y }
end

-- A positive whole number: a quest or NPC id.
---@param value any
---@return boolean
function Input.ID(value)
	return Input.Number(value) and value % 1 == 0 and value >= 1
end

-- A stop's detail is one string with one line per quest (Adventure Guide joins its quest lines with newlines).
-- Split it here so every stop keeps its own lines for the pin tooltip (UI/StopPin.lua).
---@param text? string
---@return string[]?
function Input.DetailLines(text)
	if not text then
		return nil
	end
	local lines = {}
	for line in text:gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	return lines[1] and lines or nil
end

-- An objective area list: one or more places on a map, each with a yard radius. Every entry must be one this
-- client can place.
---@param shapes table
---@return boolean
function Input.Shapes(shapes)
	local count = #shapes
	if count < 1 then
		return false
	end
	for key, shape in pairs(shapes) do
		if not Input.Number(key) or key % 1 ~= 0 or key < 1 or key > count then
			return false
		end
		if
			type(shape) ~= "table"
			or not Input.Point(shape.map, shape.x, shape.y)
			or not Input.Number(shape.radius)
			or shape.radius < 0
		then
			return false
		end
	end
	return true
end

-- The quests a held area stands for: one or more quest IDs, in order.
---@param quests table
---@return boolean
function Input.Quests(quests)
	local count = #quests
	if count < 1 then
		return false
	end
	for key, questID in pairs(quests) do
		if not Input.Number(key) or key % 1 ~= 0 or key < 1 or key > count or not Input.ID(questID) then
			return false
		end
	end
	return true
end

---@return boolean
function Input.Loaded()
	return ns.db ~= nil and ns.charDB ~= nil
end

---@return boolean
function Input.Ready()
	return Input.Loaded() and not InCombatLockdown()
end

---@return nil, "loading"
function Input.Loading()
	local _, answer = APIKit.NotReady("loading")
	return nil, answer --[[@as "loading"]]
end

---@return nil, "none"
function Input.None()
	local _, answer = APIKit.NotReady("none")
	return nil, answer --[[@as "none"]]
end

---@param owner any
---@return boolean
function Input.Owner(owner)
	return canaccessvalue(owner) and type(owner) == "string" and owner:find("%S") ~= nil
end

---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local symbols = {}
for i = 1, #alphabet do
	symbols[alphabet:byte(i)] = i - 1
end
local floor = math.floor

local function readUnsigned(text, pos)
	local value, place = 0, 1
	while true do
		local digit = symbols[text:byte(pos)]
		pos = pos + 1
		value = value + (digit % 32) * place
		if digit < 32 then
			return value, pos
		end
		place = place * 32
	end
end

-- Each record is a node-key delta followed by an absolute height and its source bit. The least significant
-- five bits of each base64 symbol carry the integer, with bit 5 set when another symbol follows.
---@param text string
---@return table<number, number>
function ns.DecodePathCeilings(text)
	local ceilings = {}
	local key, pos = -1, 1
	while pos <= #text do
		local delta, value
		delta, pos = readUnsigned(text, pos)
		value, pos = readUnsigned(text, pos)
		key = key + delta
		ceilings[key] = value
	end
	return ceilings
end

---@param ceilings table<number, number>
---@param cell number
---@param layer number
---@return number? height
---@return "terrain"|"structure"|nil kind
function ns.PathCeilingAt(ceilings, cell, layer)
	local record = ceilings[cell * 64 + layer]
	if not record then
		return nil
	end
	local height = floor(record / 2)
	local eighths = height % 2 == 0 and height / 2 or -(height + 1) / 2
	return eighths / 8, record % 2 == 0 and "terrain" or "structure"
end

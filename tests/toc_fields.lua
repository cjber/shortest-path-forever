-- One addon TOC's `## Key: value` fields, as C_AddOns.GetAddOnMetadata reports them to the addon in game. The specs
-- stub the client call with this, so a value the addon reads at load is the one its TOC declares.
local M = {}

---@param path string
---@return table<string, string>
function M.read(path)
	local fields = {}
	local file = assert(io.open(path, "r"))
	for line in file:lines() do
		local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
		if key then
			fields[key] = value
		end
	end
	file:close()
	return fields
end

return M

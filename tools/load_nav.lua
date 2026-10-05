-- Offline tools load bundled terrain through the same XML order as the client.
local map, root, env, compressed = ...
local directory = (root or ".") .. "/"
local target = env or _G
local encoding = assert(loadfile(directory .. "tools/nav_encoding.lua"))()
target.C_EncodingUtil = encoding
target.Enum = target.Enum or {}
target.Enum.CompressionMethod = { Zlib = 1 }
for line in io.lines(directory .. "Nav/Nav.xml") do
	local file = line:match('file="([^"]+)"')
	if file and file:match("^Nav" .. map .. "[_.]") then
		local chunk = assert(loadfile(directory .. "Nav/" .. file))
		if env then
			setfenv(chunk, env)
		end
		chunk()
	end
end
if not compressed then
	local data = target.ShortestPathForeverPathData[tonumber(map)]
	for field, entries in pairs(data.packed or {}) do
		for key, blocks in pairs(entries) do
			local chunks = {}
			for i, block in ipairs(blocks) do
				chunks[i] = assert(encoding.DecompressString(assert(encoding.DecodeBase64(block))))
			end
			data[field][key] = table.concat(chunks)
		end
	end
	data.packed = nil
end

-- Offline implementation of the client's native encoding APIs for navigation tools and specs.
local ffi = require("ffi")
ffi.cdef(
	[[int uncompress(unsigned char *dest, unsigned long *destLen, const unsigned char *source, unsigned long sourceLen);]]
)
local zlib = ffi.load("z")
local alphabet, codes = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", {}
for i = 1, #alphabet do
	codes[alphabet:byte(i)] = i - 1
end
-- Each group of four characters holds 24 bits: codes shifted into place, read back a byte at a time.
local high, middle, low, chars = {}, {}, {}, {}
for byte, code in pairs(codes) do
	high[byte], middle[byte], low[byte] = code * 262144, code * 4096, code * 64
end
for i = 0, 255 do
	chars[i] = string.char(i)
end
return {
	DecodeBase64 = function(source)
		if source:find("[^%w+/]") then
			if source:find("[^%w+/=]") then
				return nil
			end
			source = source:gsub("=", "")
		end
		local n, out, size = #source, {}, 0
		for i = 1, n - 3, 4 do
			local a, b, c, d = source:byte(i, i + 3)
			local v = high[a] + middle[b] + low[c] + codes[d]
			local third = v % 256
			local second = (v - third) / 256 % 256
			out[size + 1], out[size + 2], out[size + 3] =
				chars[(v - second * 256 - third) / 65536], chars[second], chars[third]
			size = size + 3
		end
		local a, b, c = source:byte(n - n % 4 + 1, n)
		if c then
			local v = high[a] + middle[b] + low[c]
			out[size + 1], out[size + 2] = chars[math.floor(v / 65536)], chars[math.floor(v / 256) % 256]
		elseif b then
			out[size + 1] = chars[math.floor((high[a] + middle[b]) / 65536)]
		end
		return table.concat(out)
	end,
	DecompressString = function(source)
		local buffer, size = ffi.new("unsigned char[16384]"), ffi.new("unsigned long[1]", 16384)
		if zlib.uncompress(buffer, size, source, #source) ~= 0 then
			return nil
		end
		return ffi.string(buffer, tonumber(size[0]))
	end,
}

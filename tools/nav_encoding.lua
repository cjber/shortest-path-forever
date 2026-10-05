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
return {
	DecodeBase64 = function(source)
		local out, value, bits = {}, 0, 0
		for i = 1, #source do
			local code = codes[source:byte(i)]
			if code then
				value, bits = value * 64 + code, bits + 6
				if bits >= 8 then
					bits = bits - 8
					out[#out + 1] = string.char(math.floor(value / 2 ^ bits))
					value = value % 2 ^ bits
				end
			elseif source:sub(i, i) ~= "=" then
				return nil
			end
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

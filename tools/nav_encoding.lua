-- Offline implementation of the client's native encoding APIs for navigation tools and specs.
local ffi = require("ffi")
ffi.cdef([[
int uncompress(unsigned char *dest, unsigned long *destLen, const unsigned char *source, unsigned long sourceLen);
int EVP_DecodeBlock(unsigned char *t, const unsigned char *f, int n);
]])
local zlib = ffi.load("z")
-- The client decodes in C; a Lua loop here made the specs and benches scale with the size of the maps.
local crypto = ffi.load("libcrypto.so.3")
return {
	DecodeBase64 = function(source)
		if source:find("=", 1, true) then
			source = source:gsub("=", "")
		end
		-- A lone trailing character holds under one byte, so it decodes to nothing once checked.
		if #source % 4 == 1 then
			if not source:find("^[%w+/]", #source) then
				return nil
			end
			source = source:sub(1, -2)
		end
		-- EVP_DecodeBlock takes whole quads, counts the bytes a padding character stands for and rejects any
		-- character outside the alphabet. It skips whitespace at either end, which the client does not, so a short
		-- result is a rejection too.
		local pad = (4 - #source % 4) % 4
		source = source .. string.rep("=", pad)
		local length = #source / 4 * 3
		local buffer = ffi.new("unsigned char[?]", length)
		if crypto.EVP_DecodeBlock(buffer, source, #source) ~= length then
			return nil
		end
		return ffi.string(buffer, length - pad)
	end,
	DecompressString = function(source)
		local buffer, size = ffi.new("unsigned char[16384]"), ffi.new("unsigned long[1]", 16384)
		if zlib.uncompress(buffer, size, source, #source) ~= 0 then
			return nil
		end
		return ffi.string(buffer, tonumber(size[0]))
	end,
}

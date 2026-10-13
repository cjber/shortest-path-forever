-- Run from the repository root: luajit tests/position_guard_spec.lua
-- The player's position is read once, through ns.JourneyPosition, which refuses a missing or secret sample before
-- any arithmetic. Every other file the client loads goes through it rather than calling UnitPosition itself.
local secret = setmetatable({}, {
	__sub = function()
		error("secret position used")
	end,
})
local sample
local env = setmetatable({
	UnitPosition = function()
		return sample[1], sample[2], sample[3], sample[4]
	end,
	canaccessvalue = function(value)
		return value ~= secret
	end,
}, { __index = _G })

-- Only the definition itself in Journey/Journey.lua, extracted from the file the client loads.
local file = assert(io.open("Journey/Journey.lua"))
local journey = file:read("*a")
file:close()
local definition = assert(journey:match("\n(function ns%.JourneyPosition%(%).-\nend)\n"), "ns.JourneyPosition")
local ns = {}
setfenv(assert(loadstring("local ns = ...\n" .. definition)), env)(ns)
for _, case in ipairs({
	{ secret, 2, 0, 1 },
	{ 1, secret, 0, 1 },
	{ 1, 2, 0, secret },
	{ nil, nil, nil, nil },
}) do
	sample = case
	assert(ns.JourneyPosition() == nil, "a secret or missing sample reads as no position")
end
sample = { 1, 2, 0, 3 }
local x, y, z, map = ns.JourneyPosition()
assert(x == 1 and y == 2 and z == nil and map == 3, "a readable sample passes, without the placeholder height")

local toc = assert(io.open("ShortestPathForever.toc"))
local checked = 0
for line in toc:lines() do
	local path = line:match("^([%w_\\/]+%.lua)%s*$")
	if path then
		path = path:gsub("\\", "/")
		local source = assert(io.open(path))
		local number = 0
		for text in source:lines() do
			number = number + 1
			local code = text:gsub("%-%-.*$", "")
			if code:find("UnitPosition%s*%(") and path ~= "Journey/Journey.lua" then
				error(("%s:%d reads UnitPosition directly; use ns.JourneyPosition()"):format(path, number))
			end
		end
		source:close()
		checked = checked + 1
	end
end
toc:close()
assert(checked > 40, "the TOC's Lua files were read")
print("position_guard_spec: ok")

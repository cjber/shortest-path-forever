-- Offline tools follow the shipped load order so split maps have the same contents as in game.
local map, root, env, addon = ...
local function load(name)
	local directory = (root or ".") .. "/" .. name .. "/"
	for line in io.lines(directory .. name .. ".toc") do
		local file = line:match("^%s*(.-)%s*$")
		if file:sub(1, 1) ~= "#" and file:match("%.lua$") then
			local chunk = assert(loadfile(directory .. file))
			if env then
				setfenv(chunk, env)
			end
			chunk()
		end
	end
end
local base = "ShortestPathForever_Nav" .. map
load(addon or base)
if not addon then
	local data = (env or _G).ShortestPathForeverPathData[tonumber(map)]
	local parts = {}
	for _, part in pairs(data.parts or {}) do
		parts[part] = true
	end
	for part = 1, #parts do
		load(base .. "_" .. part)
	end
end

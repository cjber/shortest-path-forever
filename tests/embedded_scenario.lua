-- luacheck: read globals scenario
-- Runs only on the package (tools/check_package.py), where the embed step has put ForeverCore inside the addon at
-- Libs/ForeverCore/. With no standalone ForeverCore loaded, the embedded copy is elected at login, the addon's files
-- run then, and the addon works as it does beside the standalone. The checks read the loader only after the exercise:
-- a scenario's own call into addon code taints the exercise that follows it (cjber/forever-core#813).
---@param sim table
---@param when string
local function check(sim, when)
	local G = sim.G
	local loader = assert(G.ForeverCoreLoader, when .. ": the embedded loader registered")
	local selected = assert(loader.Selected(), when .. ": a copy was selected: " .. tostring(loader.Error()))
	assert(selected.mode == "elected", when .. ": mode " .. tostring(selected.mode))
	assert(selected.folder == "ShortestPathForever", when .. ": folder " .. tostring(selected.folder))
	assert(G.ForeverCore ~= nil, when .. ": the facade is published")
	assert(loader.CallbackError() == nil, when .. ": " .. tostring(loader.CallbackError()))
	-- The addon's own files ran on the elected copy: its public API exists only once Core/API.lua has run.
	local addon = G.ShortestPathForever
	assert(type(addon) == "table" and type(addon.API) == "table", when .. ": the addon's files ran")
	local db = G.ShortestPathForeverDB
	assert(type(db) == "table" and type(db.ForeverCoreStore) == "table", when .. ": core's settings mirror")
end

scenario("embedded ForeverCore boots without the standalone addon", function(sim)
	sim:login()
	-- exercise drives the addon on this client, then on a fresh one after /reload, and returns that one.
	local reloaded = sim:exercise()
	check(sim, "login")
	check(reloaded, "after reload")
end)

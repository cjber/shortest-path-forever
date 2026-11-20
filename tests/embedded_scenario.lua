-- luacheck: read globals scenario
-- Runs only on the package (tools/check_package.py), where the embed step has put ForeverCore inside the addon at
-- Libs/ForeverCore/. With no standalone ForeverCore loaded, the embedded copy is elected at login, the addon's files
-- run then, and the addon works as it does beside the standalone. The checks read the loader only after the exercise:
-- a scenario's own call into addon code taints the exercise that follows it (cjber/forever-core#813).
scenario("embedded ForeverCore boots without the standalone addon", function(sim)
	sim:login()
	sim:exercise()
	local G = sim.G
	local loader = assert(G.ForeverCoreLoader, "the embedded loader registered")
	local selected = assert(loader.Selected(), "a copy was selected: " .. tostring(loader.Error()))
	assert(selected.mode == "elected", "mode " .. tostring(selected.mode))
	assert(selected.folder == "ShortestPathForever", "folder " .. tostring(selected.folder))
	assert(G.ForeverCore ~= nil, "the facade is published")
	assert(loader.CallbackError() == nil, tostring(loader.CallbackError()))
	assert(
		type(G.ShortestPathForeverDB) == "table" and type(G.ShortestPathForeverDB.ForeverCoreStore) == "table",
		"mirror"
	)
	sim:reload()
	assert(sim.G.ForeverCoreLoader.Selected().mode == "elected", "elected after reload")
end)

-- luacheck: read globals scenario ADDON
-- Opening Combat Text in the settings panel refreshes every canvas page, including the shared Forever addons page.
-- That page builds Blizzard template controls, whose `$parent` names come from the nearest named frame. Built under
-- an unnamed page they collapsed to bare globals such as `Text`, and this addon wrote them while Blizzard's settings
-- code ran. A client name shared with the addon then carries this addon's taint into whatever reads it next, which is
-- how the Combat Text path could compare a secret with execution tainted by Shortest Path (#457).
scenario("the combat text settings keep this addon out of bare globals", function(sim)
	local G = sim.G
	sim:login()
	G.C_AddOns.LoadAddOn("Blizzard_Settings")
	G.C_AddOns.LoadAddOn("Blizzard_SettingsDefinitions_Frame")

	local combat
	for _, category in ipairs(G.SettingsPanel:GetAllCategories()) do
		if category:GetName() == "Combat" then
			combat = category
		end
	end
	assert(combat, "the Combat settings category exists")
	G.SettingsPanel:OpenToCategory(combat:GetID())
	sim:advance(0.2)

	assert(G.Text == nil, "the settings page leaves the client's Text name alone")
	assert(sim.taint.globalTaint.Text == nil, "and never taints it")
	-- The shared page may still name its own controls, but every name it writes belongs to this addon.
	for name, addon in pairs(sim.taint.globalTaint) do
		if addon == ADDON and name:match("Text$") then
			assert(
				name:find("ShortestPathForever", 1, true),
				"a template control's global name is this addon's: " .. name
			)
		end
	end
end)

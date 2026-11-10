-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")
-- Opening Combat Text in the settings panel refreshes every canvas page, including ForeverCore's Forever addons page.
-- That page builds Blizzard template controls, whose `$parent` names come from the nearest named frame. Built under
-- an unnamed page they collapse to bare globals such as `Text`. A client name shared with an addon then carries that
-- addon's taint into whatever reads it next, which is how the Combat Text path could compare a secret with execution
-- tainted by Shortest Path (#457). The page is ForeverCore's now; this addon must write no such name itself.
scenario(
	"the combat text settings keep this addon out of bare globals",
	{ addons = ForeverCore.addons() },
	function(sim)
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

		assert(
			sim.taint.globalTaint.Text ~= ADDON,
			"the settings page never taints the client's Text name with this addon"
		)
		-- The shared page may still name its own controls, but every name it writes belongs to this addon.
		for name, addon in pairs(sim.taint.globalTaint) do
			if addon == ADDON and name:match("Text$") then
				assert(
					name:find("ShortestPathForever", 1, true),
					"a template control's global name is this addon's: " .. name
				)
			end
		end
	end
)

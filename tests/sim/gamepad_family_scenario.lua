-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")
-- With the gamepad interface on, the Forever addons page is the client's own vertical rows, so the Options
-- navigation can enter it (cjber/tweaks-forever#382).
scenario(
	"the Forever addons settings page can be entered with a gamepad",
	{ addons = ForeverCore.addons() },
	function(sim)
		local G = sim.G
		-- The client opens the panel itself: a C function that calls SettingsPanel:OpenToCategory.
		sim.impl["C_SettingsUtil.OpenSettingsPanel"] = function(categoryID, scrollTo)
			G.SettingsPanel:OpenToCategory(categoryID, scrollTo)
		end
		sim:setGamepad(true)
		sim:login()
		local ns
		for _, entry in ipairs(sim.loader.addons) do
			if entry.name == ADDON then
				ns = entry.ns
			end
		end
		assert(ns, "the addon namespace loaded")
		local category
		for _, c in ipairs(G.SettingsPanel:GetAllCategories()) do
			if c:GetName() == "Shortest Path Forever" then
				category = c
			end
		end
		assert(category, "Shortest Path Forever is under Options > AddOns")
		local sub
		for _, s in ipairs(category:GetSubcategories()) do
			if s:GetName() == ns.L["Forever addons"] then
				sub = s
			end
		end
		assert(sub, ns.L["Forever addons"] .. " is one of its subpages")
		assert(
			G.SettingsPanel:GetLayout(sub):IsVerticalLayout(),
			"Forever addons is a canvas page, which the gamepad cursor cannot enter (cjber/tweaks-forever#382)"
		)
		sim:input(function()
			G.Settings.OpenToCategory(category:GetID())
		end)
		sim:input(function()
			G.SettingsPanel:SelectCategory(sub)
		end)
		sim:advance(0.1)
		local first = G.SettingsPanel:GetFirstSmartNavFocusableSettingFrame()
		assert(first, "the gamepad cursor has a row to land on")
		assert(first:IsVisible(), "the first row the cursor lands on is visible")
		sim:expectNoErrors(ADDON)
	end
)

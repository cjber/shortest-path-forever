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
		local guidance
		for _, child in ipairs(category:GetSubcategories()) do
			if child:GetName() == ns.L["Guidance"] then
				guidance = child
			end
		end
		assert(guidance, "Guidance is a native settings page")
		sim:input(function()
			G.SettingsPanel:SelectCategory(guidance)
			G.SettingsPanel:FocusContainer()
		end)
		assert(G.SmartNavigation.activeInfo, "Settings has active smart navigation")
		local initializers = G.SettingsPanel:GetLayout(guidance):GetInitializers()
		assert(#initializers > 0, "Guidance has settings to navigate")
		local scrollBox = G.SettingsPanel:GetSettingsList().ScrollBox
		for _, initializer in ipairs(initializers) do
			sim:input(function()
				scrollBox:ScrollToElementData(initializer, G.ScrollBoxConstants.AlignBegin)
			end)
			sim:advance(0.1)
			local row = assert(scrollBox:FindFrame(initializer), "Guidance row scrolled into view")
			sim:input(function()
				G.SmartNavigation:SelectButton(row.smartNavigationProxyTarget or row)
				assert(
					G.SmartNavigation:GetCurrentButton() == (row.smartNavigationProxyTarget or row),
					"gamepad selects each Guidance row"
				)
			end)
			for key, binding in pairs(G.GamepadSharedUtility.InputBindingManager.activeBindings) do
				assert(
					G.issecurevariable(binding, "isActive"),
					"Guidance tainted " .. key .. " for " .. initializer:GetName()
				)
			end
			sim:gamepadNavigate()
			sim:expectNoGamepadTaint(ADDON)
		end
		sim:input(function()
			G.SmartNavigation:AttemptClose()
			G.SettingsPanel:Hide()
		end)
		sim:gamepadNavigate()
		sim:expectNoGamepadTaint(ADDON)
		sim:input(function()
			G.Settings.OpenToCategory(sub:GetID())
		end)
		sim:advance(0.1)
		local first = G.SettingsPanel:GetFirstSmartNavFocusableSettingFrame()
		assert(first, "the gamepad cursor has a row to land on")
		assert(first:IsVisible(), "the first row the cursor lands on is visible")
		sim:input(function()
			G.SmartNavigation:AttemptClose()
			G.SettingsPanel:Hide()
		end)
		sim:gamepadNavigate()
		sim:expectNoGamepadTaint(ADDON)
		sim:expectNoErrors(ADDON)
	end
)

scenario("Guidance renders its native groups in order", { addons = ForeverCore.addons() }, function(sim)
	local G = sim.G
	sim:login()
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	local category
	for _, entry in ipairs(G.SettingsPanel:GetAllCategories()) do
		if entry:GetName() == "Shortest Path Forever" then
			category = entry
		end
	end
	assert(category and ns)
	-- Scroll each heading and control of the dense native list into view.
	local guidance
	for _, child in ipairs(category:GetSubcategories()) do
		if child:GetName() == ns.L["Guidance"] then
			guidance = child
		end
	end
	assert(guidance, "Guidance is a native subpage")
	sim:input(function()
		G.SettingsPanel:OpenToCategory(guidance:GetID())
	end)
	sim:advance(0.1)
	local box = G.SettingsPanel:GetSettingsList().ScrollBox
	local headings = { "Tracker", "Planning", "Destination", "Guides", "Route choices", "Map" }
	local heading = 0
	assert(box:GetDataProvider():GetSize() == 38, "all six headings and 32 controls render")
	for index = 1, box:GetDataProvider():GetSize() do
		local row
		sim:input(function()
			box:ScrollToElementDataIndex(index, nil, nil, true)
			row = box:FindFrame(box:GetDataProvider():Find(index))
			assert(row, "the native row renders")
		end)
		sim:advance(0.05)
		assert(row:GetHeight() > 0, "native rows reserve layout height")
		local nextRow = box:FindFrame(box:GetDataProvider():Find(index + 1))
		if nextRow and nextRow:IsVisible() then
			assert(row:GetBottom() >= nextRow:GetTop(), "adjacent native rows do not overlap")
		end
		if row.Title and row.Title:GetText() == ns.L[headings[heading + 1]] then
			heading = heading + 1
		end
	end
	assert(heading == #headings, "all localized headings render in order")
	sim:input(function()
		G.SettingsPanel:Close()
	end)
	sim:advance(0.1)
	-- Selecting this page's rows with gamepad navigation taints the binding stack through the journey key dropdown,
	-- with or without the headings (#943); its fix adds that walk and sim:expectNoGamepadTaint(ADDON).
	sim:expectNoErrors(ADDON)
end)

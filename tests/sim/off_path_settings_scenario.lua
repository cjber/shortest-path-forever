-- luacheck: read globals scenario ADDON
local ForeverCore = dofile("tests/forever_core.lua")

scenario("Guidance saves off-path tolerance from an older saved file", { addons = ForeverCore.addons() }, function(sim)
	local variable = "ShortestPathForever_offPathTolerance"
	sim.impl["C_SettingsUtil.OpenSettingsPanel"] = function(id, element)
		return sim.G.SettingsPanel:OpenToCategory(id, element)
	end
	sim:login({ savedVariables = { ShortestPathForeverDB = { arrivalDistance = 25 } } })
	local settings = sim.G.Settings
	assert(settings.GetSetting(variable):GetValue() == 15, "older saves start with 15 yards")
	for index, gamepad in ipairs({ false, true }) do
		local tolerance = index * 10 + 20
		sim:setGamepad(gamepad)
		sim:slash("/path")
		local root
		for _, category in ipairs(sim.G.SettingsPanel:GetAllCategories()) do
			if category:GetName() == "Shortest Path Forever" then
				root = category
				break
			end
		end
		assert(root, "the addon settings category is available")
		local guidance
		for _, page in ipairs(root:GetSubcategories()) do
			if page:GetName() == "Guidance" then
				guidance = page
				break
			end
		end
		assert(guidance, "the Guidance category is available")
		local setting = settings.GetSetting(variable)
		sim:input(function()
			sim.G.ForeverCore.OpenSettingsPanel(guidance:GetID(), setting:GetName())
		end)
		sim:advance(0.2)
		local box = sim.G.SettingsPanel:GetSettingsList().ScrollBox
		local row = assert(
			box:FindFrameByPredicate(function(_, initializer)
				return initializer:GetSetting() == setting
			end),
			"the off-path tolerance row is visible"
		)
		sim:input(function()
			row.SliderWithSteppers.Slider:SetValue(tolerance, true)
		end)
		assert(sim.G.ShortestPathForeverDB.offPathTolerance == tolerance, "the slider writes the saved distance")
		sim:pressEscape()
	end
	sim:expectNoErrors(ADDON)
	local reloaded = sim:reload()
	assert(reloaded.G.Settings.GetSetting(variable):GetValue() == 40, "the chosen tolerance survives reload")
	assert(reloaded.G.ShortestPathForeverDB.arrivalDistance == 25, "the arrival distance is independent")
	reloaded:expectNoErrors(ADDON)
end)

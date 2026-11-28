-- Route policy controls keep their declarations and invalidate travel when their values change.
local h = dofile("tests/settings_spec.lua")
local function Row(key)
	for _, row in ipairs(h.rows) do
		if row.initializer.setting.key == key then
			return row.initializer
		end
	end
	assert(false, "missing settings row: " .. key)
end

local waterWalking = Row("useWaterWalking")
assert(waterWalking.kind == "checkbox", "water walking uses a native Settings checkbox initializer")
assert(waterWalking.setting.default == true, "water walking stays enabled by default")
assert(waterWalking.setting.category.name == "Guidance", "water walking belongs to Guidance")
assert(waterWalking.tooltip:find("may still cross water", 1, true), "the tooltip does not promise a dry route")
local policies = h.getPolicyChanged()
waterWalking.setting:SetValue(false)
waterWalking.setting:SetValue(true)
assert(h.getPolicyChanged() == policies + 2, "both checkbox transitions invalidate travel policy")

local roadDetour = Row("roadDetour")
assert(roadDetour.kind == "slider" and roadDetour.setting.default == 50, "the road allowance preserves 50%")
assert(roadDetour.setting.variable == "ShortestPathForever_roadDetour", "the allowance is saved")
assert(roadDetour.setting.category.name == "Guidance", "the allowance belongs beside Follow roads")
assert(roadDetour.options.minValue == 0 and roadDetour.options.maxValue == 200 and roadDetour.options.step == 25)
assert(roadDetour.options.format(0) == "0%" and roadDetour.options.format(200) == "200%")
assert(roadDetour.tooltip:find("not a limit on the whole walk", 1, true), "the preference is no hard detour cap")
local roadPolicies = h.getPolicyChanged()
roadDetour.setting:SetValue(200)
assert(h.getPolicyChanged() == roadPolicies + 1, "changing the allowance replans the current journey")
local flightAllowance = Row("flightAllowance")
assert(flightAllowance.kind == "slider" and flightAllowance.setting.default == 0)
assert(flightAllowance.options.minValue == 0 and flightAllowance.options.maxValue == 10)
assert(flightAllowance.options.step == 1 and flightAllowance.options.format(3) == "3 min")
local flightPolicies = h.getPolicyChanged()
flightAllowance.setting:SetValue(3)
assert(h.getPolicyChanged() == flightPolicies + 1, "changing the flight allowance replans the current journey")
print("settings: route policy controls passed")

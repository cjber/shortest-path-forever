-- Malformed QuestieDB zone tables fail once and leave the Nearby menu with its explicit read error.
local h = dofile("tests/nearby_spec.lua")
local broken = setmetatable({}, { __index = h.lib })
for _, private in ipairs({
	{ areaIdToUiMapId = { [10] = 100 }, subZoneToParentZone = "return {[11]=10}" },
	{ areaIdToUiMapId = "return {[10]=100}", subZoneToParentZone = "return {" },
	{ areaIdToUiMapId = "error('gone')", subZoneToParentZone = "return {[11]=10}" },
}) do
	broken.Support = {
		Get = function()
			return { private = private }
		end,
	}
	assert(h.fresh(broken).NearbyServices.State() == "failed")
end
print("nearby: malformed QuestieDB zone data reports a failed catalogue read: ok")

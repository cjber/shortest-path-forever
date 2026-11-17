-- Settings layout beyond the rows: the Guidance headings in order, and the same pages from a ForeverCore without
-- section headings or a client without secure delegates. Runs on the settings_spec harness.
local h = dofile("tests/settings_spec.lua")
local env, ns = h.env, h.ns
local rows, buttons, settings, registered = h.rows, h.buttons, h.settings, h.registered
local function clear(...)
	for _, t in ipairs({ ... }) do
		for k in pairs(t) do
			t[k] = nil
		end
	end
end

-- Check every Guidance initializer, including the resume buttons, between the native headings.
local expected = {
	"#Tracker",
	"trackerAttached",
	"trackerLocked",
	"journeyTracker",
	"resumeJourney",
	"#Planning",
	"journey",
	"journeyKey",
	"focusedQuest",
	"#Destination",
	"destinationPin",
	"destinationPinSize",
	"arrivalPin",
	"arrivalDistance",
	"npcArrows",
	"#Guides",
	"tomtom",
	"tomtomFollow",
	"restedxp",
	"restedxpHideArrow",
	"guidelime",
	"dugi",
	"@RestedXP guide",
	"@Guidelime",
	"@Dugi Guides",
	"#Route choices",
	"avoidHighZones",
	"followRoads",
	"roadDetour",
	"useWaterWalking",
	"useHearthstone",
	"hearthMinimumSavings",
	"teleports",
	"teleportMinimumSavings",
	"#Map",
	"guideStops",
	"taxiRoute",
	"corpse",
}
local actual = {}
for _, entry in ipairs(registered) do
	if entry.target.name == "Guidance" then
		local row = entry.initializer
		actual[#actual + 1] = row.kind == "section" and "#" .. row.name
			or row.kind == "button" and "@" .. row.name
			or row.setting.key
	end
end
assert(table.concat(actual, ",") == table.concat(expected, ","), "Guidance headings and controls stay in order")

-- Rebuild with an older core: all controls still register and retain their declarations.
local previousRows = { unpack(rows) }
clear(rows, settings, buttons, registered)
env.ForeverCore.SettingsSections = nil
setfenv(assert(loadfile("UI/Settings.lua")), env)("ShortestPathForever", ns)
assert(#rows == #previousRows, "an older core keeps every control")
for index, entry in ipairs(rows) do
	local before, after = previousRows[index].initializer, entry.initializer
	assert(after.setting.key == before.setting.key and after.setting.default == before.setting.default)
	assert(after.kind == before.kind and after.tooltip == before.tooltip)
end
for _, entry in ipairs(registered) do
	assert(entry.initializer.kind ~= "section", "an older core omits headings")
end
print("settings sections: ok")
-- The probe client omits CreateSecureDelegate and must still register every settings page.
local expectedRows, expectedButtons = #rows, #buttons
local expectedPages = {}
for _, button in ipairs(buttons) do
	expectedPages[button.initializer.name] = true
end
env.CreateSecureDelegate = nil
clear(rows, buttons, settings)
h.clearFamilyPage()
setfenv(assert(loadfile("UI/Settings.lua")), env)("ShortestPathForever", ns)
assert(#rows == expectedRows, "every settings row registers without secure delegates")
assert(#buttons == expectedButtons, "every settings page registers without secure delegates")
for _, button in ipairs(buttons) do
	assert(expectedPages[button.initializer.name], "the same settings pages register without secure delegates")
	expectedPages[button.initializer.name] = nil
end
assert(next(expectedPages) == nil, "no settings page is missing without secure delegates")
assert(h.familyPage(), "the Forever addons page registers without secure delegates")
print("settings layout: ok")
